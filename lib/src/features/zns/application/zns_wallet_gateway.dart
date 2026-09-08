import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/storage/app_secure_store.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../rust/api/zns.dart' as rust;
import '../../swap/domain/swap_intent_status.dart';
import '../../swap/providers/swap_deposit_sender.dart';
import '../../swap/providers/swap_zec_staging_address_service.dart';
import '../data/zns_abi.dart';
import '../data/zns_network_config.dart';
import '../data/zns_rpc_client.dart';
import '../data/zns_http_transport.dart';
import '../data/zns_funding_gateway.dart';
import '../data/zns_kyber_gateway.dart';
import '../domain/zns_operation.dart';
import 'zns_batch_bytecode.dart';
import 'zns_engine.dart';
import 'zns_confirmed_transaction.dart';

class ZnsWalletGateway implements ZnsEngineGateway {
  ZnsWalletGateway({
    required this.ref,
    required this.config,
    required this.scope,
    required this.accountUuid,
    this.delegate = '',
    this.recordHoldings = true,
  }) : rpc = ZnsRpcClient(config),
       kyber = ZnsKyberGateway(config) {
    funding = ZnsFundingGateway(
      config: config,
      staging: ref.read(swapZecStagingAddressServiceProvider),
      sender: RustSwapDepositSender(
        ref,
        beforeSoftwareSign: (feeZatoshi) {
          final guard = _fundingGuard;
          if (guard == null) {
            throw StateError('Funding authorization is not active.');
          }
          guard();
          final limit = _fundingFeeLimit;
          if (limit == null || feeZatoshi.isNegative || feeZatoshi > limit) {
            throw const ZnsFundingNotSent(
              'The actual ZEC transaction fee exceeds the reviewed funding quote. No payment was signed. Review a fresh quote.',
            );
          }
        },
      ),
    );
  }
  final Ref ref;
  final ZnsNetworkConfig config;
  final ZnsScope scope;
  final String accountUuid, delegate;
  final bool recordHoldings;
  final ZnsRpcClient rpc;
  final ZnsKyberGateway kyber;
  late final ZnsFundingGateway funding;
  void Function()? _fundingGuard;
  BigInt? _fundingFeeLimit;
  ZnsRegistrySnapshot? lastSnapshot;
  @override
  bool get supportsAtomic => delegate.isNotEmpty;
  void close() {
    rpc.close();
    kyber.close();
  }

  static Future<Map<String, dynamic>> account(
    Ref ref,
    String uuid,
    String network,
  ) async {
    final bytes = await _secretBytes(ref, uuid);
    try {
      return jsonDecode(
            await rust.znsAccount(
              dbPath: await getWalletDbPath(),
              network: network,
              accountUuid: uuid,
              secretBytes: bytes,
            ),
          )
          as Map<String, dynamic>;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static Future<Uint8List> _secretBytes(Ref ref, String uuid) async {
    if (ref.read(appSecurityProvider).requiresUnlock ||
        ref.read(accountProvider).value?.activeAccountUuid != uuid) {
      throw StateError('Unlock the selected account.');
    }
    final bytes = await ref
        .read(accountProvider.notifier)
        .getMnemonicBytesForAccount(uuid);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Software signing is unavailable for this account.');
    }
    return bytes;
  }

  @override
  Future<ZnsChainView> snapshot(String? commitment) async {
    final s = await rpc.registrySnapshot(scope.owner, commitment: commitment);
    lastSnapshot = s;
    final p = s.latestPosition;
    final record = p == null
        ? null
        : ZnsRecord(
            name: p.name,
            owner: p.owner,
            unifiedAddress: p.unifiedAddress,
            expiresAt: p.graceEndsAt.toInt(),
            deposit: s.fixedDeposit,
            positionId: p.positionId,
            maturityAt: p.maturityAt.toInt(),
            refreshDueAt: p.refreshDueAt.toInt(),
            participating: p.participating,
            retired: p.retired,
            rewardCreditScaled: p.rewardCreditScaled,
          );
    if (recordHoldings) {
      await AppSecureStore.instance.writeString(
        'zns:holdings:$accountUuid',
        jsonEncode({
          'eth': s.nativeBalance.toString(),
          'token': s.tokenBalance.toString(),
          'claimable':
              (s.claimablePrincipal +
                      s.claimableRewardsScaled ~/ znsRewardScale)
                  .toString(),
          'name': s.activeName,
          'chainId': config.chainId,
          'owner': scope.owner,
        }),
      );
    }
    return ZnsChainView(
      timestamp: s.block.timestamp.toInt(),
      deposit: s.fixedDeposit,
      eth: s.nativeBalance,
      token: s.tokenBalance,
      allowance: s.allowance,
      claimablePrincipal: s.claimablePrincipal,
      claimableRewardsScaled: s.claimableRewardsScaled,
      minAge: s.minimumCommitmentAge.toInt(),
      maxAge: s.maximumCommitmentAge.toInt(),
      commitAt: s.commitmentTimestamp.toInt(),
      position: record,
    );
  }

  @override
  Future<ZnsRecord?> lookup(String name) async {
    final r = await rpc.lookupName(name);
    if (r.owner == ZnsNetworkConfig.zeroAddress) return null;
    return ZnsRecord(
      name: name,
      owner: r.owner,
      unifiedAddress: r.unifiedAddress,
      expiresAt: r.expiresAt.toInt(),
      deposit: lastSnapshot?.fixedDeposit ?? BigInt.zero,
      positionId: r.positionId,
      maturityAt: 0,
      refreshDueAt: 0,
      participating: r.active,
      retired: false,
      rewardCreditScaled: BigInt.zero,
    );
  }

  @override
  Future<Map<String, dynamic>> exitPreview(BigInt positionId) async {
    final p = await rpc.exitPreview(positionId);
    return {
      'early': p.early,
      'principalReturned': p.principalReturned.toString(),
      'rewardsReturned': p.rewardsReturned.toString(),
      'principalForfeited': p.principalForfeited.toString(),
      'rewardsForfeitedScaled': p.rewardsForfeitedScaled.toString(),
    };
  }

  @override
  Future<Map<String, dynamic>> swapQuote(
    BigInt neededToken,
    BigInt? maxWei,
  ) async {
    await rpc.verifyProtocol();
    if (config.chainId != 8453) {
      throw StateError(
        'Fund this test account with the configured test token. Live swaps require Base mainnet.',
      );
    }
    final route = await kyber.quoteForTokenOutput(
      owner: scope.owner,
      requiredTokenUnits: neededToken,
      maximumWei: maxWei ?? BigInt.from(10).pow(18),
    );
    final call = await kyber.build(
      route,
      maximumWei: maxWei ?? route.amountInWei,
    );
    final data = Map<String, dynamic>.from(call.toOperationJson())
      ..remove('kind');
    // This is local workflow metadata, never a field in the Rust swap ABI.
    data['_quoteExpiresAt'] =
        (route.expiresAt.isBefore(call.deadline)
                ? route.expiresAt
                : call.deadline)
            .toUtc()
            .toIso8601String();
    return data;
  }

  @override
  Future<Map<String, dynamic>> fundingQuote(
    BigInt requiredWei, {
    required bool dry,
  }) async {
    await rpc.verifyProtocol();
    if (scope.zcashNetwork != 'mainnet' || config.chainId != 8453) {
      throw StateError(
        'Live ZEC funding requires Zcash and Base mainnet. Fund the test account separately.',
      );
    }
    final plan = await funding.quoteExactOutput(
      accountUuid: accountUuid,
      baseOwner: scope.owner,
      requiredWei: requiredWei,
      dryRun: dry,
    );
    final fee = await funding.estimateDepositFee(plan);
    return {
      'plan': plan.toJson(),
      'maxZatoshi': (plan.depositZatoshi + fee).toString(),
      'zecFee': fee.toString(),
    };
  }

  ZnsFundingQuote _plan(Map<String, dynamic> quote) {
    final p = ZnsFundingQuote.fromJson(
      Map<String, Object?>.from(quote['plan'] as Map),
    );
    if (p.owner.toLowerCase() != scope.owner.toLowerCase() ||
        p.accountUuid != accountUuid ||
        p.chainId != config.chainId ||
        p.registryAddress.toLowerCase() !=
            config.registryAddress.toLowerCase() ||
        p.protocolId != ZnsNetworkConfig.protocolId) {
      throw StateError('Funding recovery belongs to a different account.');
    }
    return p;
  }

  @override
  Future<String?> sendFunding(
    Map<String, dynamic> quote, {
    required void Function() ensureAuthorized,
  }) async {
    final plan = _plan(quote);
    final feeLimit = BigInt.parse(quote['zecFee'] as String);
    final totalLimit = BigInt.parse(quote['maxZatoshi'] as String);
    if (feeLimit.isNegative || plan.depositZatoshi + feeLimit > totalLimit) {
      throw const ZnsFundingNotSent('Invalid reviewed ZEC funding limits.');
    }
    ensureAuthorized();
    await funding.start(plan);
    ensureAuthorized();
    if (ref.read(appSecurityProvider).requiresUnlock ||
        ref.read(accountProvider).value?.activeAccountUuid != accountUuid) {
      throw StateError(
        'Funding paused before signing. Inspect the saved quote before retrying.',
      );
    }
    _fundingGuard = ensureAuthorized;
    _fundingFeeLimit = feeLimit;
    late final String txHash;
    try {
      txHash = (await funding.sendDeposit(plan)).txHash;
    } finally {
      _fundingGuard = null;
      _fundingFeeLimit = null;
    }
    // Notification failure is not a failed payment. Polling the durable deposit
    // address still recovers the provider's observed transaction.
    try {
      await funding.submitDeposit(plan: plan, txHash: txHash);
    } catch (_) {}
    return txHash;
  }

  @override
  Future<Map<String, dynamic>> fundingStatus(Map<String, dynamic> quote) async {
    final status = await funding.status(_plan(quote));
    return {
      'complete': status.status == SwapIntentStatus.complete,
      'failed': [
        SwapIntentStatus.failed,
        SwapIntentStatus.refunded,
        SwapIntentStatus.expired,
      ].contains(status.status),
      'providerStatus': status.status.name,
      'message': status.nextAction,
    };
  }

  Map<String, dynamic> _config({
    ZnsOperation? intent,
    BigInt? gasRemaining,
  }) => {
    'chainId': config.chainId,
    'allowTestChain': config.chainId != 8453,
    'protocolId': ZnsNetworkConfig.protocolId,
    'registry': config.registryAddress,
    'token': config.tokenAddress,
    'router': config.kyberRouterAddress,
    if (delegate.isNotEmpty) 'delegate': delegate,
    'maxValueWei': (intent?.maxEthWei ?? BigInt.from(10).pow(18)).toString(),
    'maxGasLimit': '3000000',
    'maxFeePerGasWei': '100000000000',
    'maxTotalFeeWei':
        (gasRemaining ?? intent?.maxGasFeeWei ?? BigInt.from(10).pow(18))
            .toString(),
    'maxTokenAmount': (intent?.requiredTokenUnits ?? BigInt.from(10).pow(30))
        .toString(),
  };
  @override
  Future<String> secret() => rust.znsRandomSecret();
  @override
  Future<String> commitment(String name, String ua, String secret) async {
    final result =
        jsonDecode(
              await rust.znsPrepare(
                network: scope.zcashNetwork,
                configJson: jsonEncode(_config()),
                owner: scope.owner,
                operationJson: jsonEncode({
                  'kind': 'commit',
                  'name': name,
                  'unifiedAddress': ua,
                  'secret': secret,
                }),
              ),
            )
            as Map<String, dynamic>;
    return result['commitment'] as String;
  }

  Future<BigInt> _extraFee(int size, BigInt gas) async {
    if (config.chainId == 31337) return BigInt.zero;
    const oracle = '0x420000000000000000000000000000000000000f';
    Future<BigInt> call(String selector, BigInt value) async => ZnsAbi(
      await rpc.request('eth_call', [
            {'to': oracle, 'data': '$selector${ZnsAbi.uintWord(value)}'},
            'latest',
          ])
          as String,
    ).word(0);
    final l1 = await call('0xf1c7a58b', BigInt.from(size));
    final operator = await call('0x275aedd2', gas);
    // Provider estimates are refreshed for each signature. These fields cannot
    // impose a consensus-level ceiling on Base publication/operator fees.
    return (l1 + operator) * BigInt.from(120) ~/ BigInt.from(100);
  }

  @override
  Future<BigInt> gasBudget(String kind) async {
    await rpc.verifyProtocol();
    final accountCode = await rpc.code(scope.owner);
    if (delegate.isNotEmpty &&
        (await rpc.code(delegate)).toLowerCase() !=
            znsBatchRuntime.toLowerCase()) {
      throw StateError(
        'The configured batch account does not match the reviewed implementation.',
      );
    }
    if (accountCode != '0x' &&
        (delegate.isEmpty ||
            accountCode != '0xef0100${delegate.substring(2).toLowerCase()}')) {
      throw StateError(
        'This Base account already uses different delegated code. Resolve its ownership before funding registration.',
      );
    }
    final fee = await rpc.feeQuote();
    // Allow headroom for a long registry record plus a destination swap in the
    // atomic transaction. The exact estimate and total reviewed fee still bind.
    final gas = BigInt.from(3000000);
    return (fee.executionCeiling(gas) + await _extraFee(16000, gas)) *
        BigInt.from(kind == 'register' ? 4 : 1);
  }

  @override
  Future<Map<String, dynamic>> sign(
    ZnsOperation intent,
    Map<String, dynamic> operation, {
    required void Function() ensureAuthorized,
  }) async {
    ensureAuthorized();
    final signingOperation = Map<String, dynamic>.from(operation);
    Map<String, dynamic>? swap;
    if (signingOperation['kind'] == 'swap') {
      swap = signingOperation;
    } else if (signingOperation['kind'] == 'atomicRegister' &&
        signingOperation['swap'] != null) {
      swap = Map<String, dynamic>.from(signingOperation['swap'] as Map);
      signingOperation['swap'] = swap;
    }
    DateTime? quoteExpiresAt;
    if (swap != null) {
      final rawExpiry = swap.remove('_quoteExpiresAt');
      quoteExpiresAt = rawExpiry is String
          ? DateTime.tryParse(rawExpiry)?.toUtc()
          : null;
      if (quoteExpiresAt == null) {
        throw StateError(
          'The swap quote is missing its local expiry. Request a fresh quote.',
        );
      }
    }
    void ensureQuoteFresh() {
      final expiry = quoteExpiresAt;
      if (expiry != null && !DateTime.now().toUtc().isBefore(expiry)) {
        throw StateError(
          'The swap quote expired. Review again to request a fresh route.',
        );
      }
    }

    ensureQuoteFresh();
    await rpc.verifyProtocol();
    final previouslyReserved = intent.transactions.fold(
      BigInt.zero,
      (sum, tx) => sum + BigInt.parse(tx['feeCeiling'] as String? ?? '0'),
    );
    final gasRemaining = intent.maxGasFeeWei - previouslyReserved;
    if (gasRemaining <= BigInt.zero) {
      throw StateError('The reviewed gas budget is exhausted.');
    }
    final bounds = _config(intent: intent, gasRemaining: gasRemaining);
    final prepared =
        jsonDecode(
              await rust.znsPrepare(
                network: scope.zcashNetwork,
                configJson: jsonEncode(bounds),
                owner: scope.owner,
                operationJson: jsonEncode(signingOperation),
              ),
            )
            as Map<String, dynamic>;
    final isAtomic = operation['kind'] == 'atomicRegister';
    final code = await rpc.code(scope.owner);
    Map<String, Object?>? overrides;
    if (isAtomic) {
      if (delegate.isEmpty ||
          (await rpc.code(delegate)).toLowerCase() !=
              znsBatchRuntime.toLowerCase()) {
        throw StateError(
          'The configured batch account does not match the reviewed wallet implementation.',
        );
      }
      if (code != '0x' &&
          code != '0xef0100${delegate.substring(2).toLowerCase()}') {
        throw StateError(
          'This Base account already delegates to different code.',
        );
      }
      overrides = {
        scope.owner: {'code': znsBatchRuntime},
      };
    } else if (code != '0x' &&
        (delegate.isEmpty ||
            code != '0xef0100${delegate.substring(2).toLowerCase()}')) {
      throw StateError('This Base account has an unrecognized delegation.');
    }
    final call = ZnsCall(
      from: scope.owner,
      to: prepared['to'] as String,
      data: prepared['data'] as String,
      value: BigInt.parse(prepared['value'] as String),
    );
    await rpc.verifyChain();
    await rpc.request('eth_call', [call.toJson(), 'pending', ?overrides]);
    final estimate = znsParseQuantity(
      await rpc.request('eth_estimateGas', [
        call.toJson(),
        'pending',
        ?overrides,
      ]),
    );
    final gas =
        estimate * BigInt.from(120) ~/ BigInt.from(100) +
        BigInt.from(isAtomic ? 25000 : 0);
    final fees = await rpc.feeQuote();
    final extra = await _extraFee(call.data.length ~/ 2 + 512, gas);
    final ceiling = fees.executionCeiling(gas) + extra;
    if (ceiling > gasRemaining) {
      throw StateError('Current network fees exceed your reviewed gas budget.');
    }
    final balance = znsParseQuantity(
      await rpc.request('eth_getBalance', [scope.owner, 'pending']),
    );
    if (balance < call.value + ceiling) {
      throw StateError(
        'The Base account needs more ETH for this step and gas.',
      );
    }
    final nonce = await rpc.pendingNonce(scope.owner);
    if (operation['kind'] == 'release' &&
        !znsSameExitPreview(
          intent.exitPreview,
          await exitPreview(intent.positionId),
        )) {
      throw StateError(
        'The release refund or forfeiture changed. Review the updated release amounts before continuing.',
      );
    }
    ensureAuthorized();
    final bytes = await _secretBytes(ref, accountUuid);
    try {
      final dbPath = await getWalletDbPath();
      ensureAuthorized();
      ensureQuoteFresh();
      final signed =
          jsonDecode(
                await rust.znsSign(
                  dbPath: dbPath,
                  network: scope.zcashNetwork,
                  accountUuid: accountUuid,
                  secretBytes: bytes,
                  configJson: jsonEncode(bounds),
                  operationJson: jsonEncode(signingOperation),
                  transactionJson: jsonEncode({
                    'nonce': nonce.toString(),
                    'gasLimit': gas.toString(),
                    'maxFeePerGas': fees.maxFeePerGas.toString(),
                    'maxPriorityFeePerGas': fees.maxPriorityFeePerGas
                        .toString(),
                    'l1FeeWei': extra.toString(),
                  }),
                ),
              )
              as Map<String, dynamic>;
      ensureAuthorized();
      ensureQuoteFresh();
      return {
        'raw': signed['rawTransaction'],
        'hash': signed['transactionHash'],
        'nonce': nonce.toString(),
        'value': call.value.toString(),
        'to': call.to,
        'data': call.data,
        'feeCeiling': ceiling.toString(),
      };
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<void> broadcast(String rawTransaction, String expectedHash) async {
    try {
      await rpc.broadcastSignedRaw(rawTransaction, expectedHash: expectedHash);
    } catch (_) {
      // An already-known/mined transaction is successful submission evidence,
      // not permission to sign a replacement. Unknown errors remain ambiguous.
      final known = await rpc.request('eth_getTransactionByHash', [
        expectedHash,
      ]);
      if (known == null) rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> receipt(String hash) async {
    final r = await rpc.transactionReceipt(hash);
    if (r == null) return null;
    if (r.from.toLowerCase() != scope.owner.toLowerCase()) {
      throw StateError('The transaction receipt has the wrong sender.');
    }
    if (!r.confirmed) return {'confirmed': false};
    final tx = await rpc.request('eth_getTransactionByHash', [hash]);
    final rawReceipt = await rpc.request('eth_getTransactionReceipt', [hash]);
    if (tx == null || rawReceipt == null) return null;
    final receiptJson = znsObject(rawReceipt);
    if (receiptJson['blockHash'] != r.blockHash ||
        receiptJson['transactionHash'] != hash ||
        (await rpc.block(znsQuantity(r.blockNumber))).hash != r.blockHash) {
      return {'confirmed': false};
    }
    final accounted = znsConfirmedTransaction(
      transaction: znsObject(tx),
      config: config,
      owner: scope.owner,
      expectedHash: hash,
      expectedBlockHash: r.blockHash,
      expectedBlockNumber: r.blockNumber,
    );
    var extra = BigInt.zero;
    if (config.chainId != 31337) {
      // Use the mined receipt's L1 fee and the historical fee oracle, not
      // editable recovery metadata or today's operator fee parameters.
      final l1 = znsParseQuantity(receiptJson['l1Fee']);
      final operator = ZnsAbi(
        await rpc.request('eth_call', [
              {
                'to': '0x420000000000000000000000000000000000000f',
                'data':
                    '0x275aedd2${ZnsAbi.uintWord(BigInt.parse(accounted['gasLimit'] as String))}',
              },
              znsQuantity(r.blockNumber),
            ])
            as String,
      ).word(0);
      extra = l1 + operator;
    }
    if ((await rpc.block(znsQuantity(r.blockNumber))).hash != r.blockHash) {
      return {'confirmed': false};
    }
    return {
      ...accounted,
      'feeCeiling':
          (BigInt.parse(accounted['executionFeeCeiling'] as String) + extra)
              .toString(),
      'confirmed': r.confirmed,
      'success': r.succeeded,
      'blockHash': r.blockHash,
      'blockNumber': r.blockNumber.toString(),
    };
  }
}
