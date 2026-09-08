import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/app_secure_store.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/zns.dart' as rust;
import '../data/zns_network_config.dart';
import '../domain/zns_operation.dart';
import '../presentation/zns_view_data.dart';
import 'zns_engine.dart';
import 'zns_journal.dart';
import 'zns_wallet_gateway.dart';
import 'zns_lifecycle_guard.dart';

final znsControllerProvider = NotifierProvider<ZnsController, ZnsViewData>(
  ZnsController.new,
);

class ZnsRecipientChanged implements Exception {
  const ZnsRecipientChanged(this.name, this.address, this.fingerprint);
  final String name, address, fingerprint;
  @override
  String toString() =>
      'This name has a different registration. Confirm its current recipient before sending.';
}

class ZnsController extends Notifier<ZnsViewData> {
  ZnsEngine? _engine;
  ZnsWalletGateway? _gateway;
  ZnsConfigurationInput _config = const ZnsConfigurationInput();
  ZnsOperation? _review;
  ZnsLookupView? _lookup;
  ZnsRecord? _lookedUpRecord;
  String? _error;
  String? _notice;
  String _owner = '';
  bool _busy = false;
  bool _disposed = false;
  int _epoch = 0;

  @override
  ZnsViewData build() {
    ref.listen(accountProvider, (before, after) {
      if (before?.value?.activeAccountUuid != after.value?.activeAccountUuid ||
          before?.value?.activeAddress != after.value?.activeAddress) {
        unawaited(_initialize());
      }
    });
    ref.listen(appSecurityProvider, (before, after) {
      if (after.requiresUnlock) {
        _epoch++;
        _engine?.pause();
        _review = null;
        _publish();
      } else if (before?.requiresUnlock == true) {
        unawaited(_initialize());
      }
    });
    ref.listen(rpcEndpointFailoverProvider, (before, after) {
      if (before?.current.networkName != after.current.networkName) {
        unawaited(_initialize());
      }
    });
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
      _engine?.dispose();
      _gateway?.close();
    });
    scheduleMicrotask(_initialize);
    return const ZnsViewData();
  }

  bool get _unlocked =>
      !_disposed && !ref.read(appSecurityProvider).requiresUnlock;
  String get _uuid => ref.read(accountProvider).value?.activeAccountUuid ?? '';
  String get _network =>
      ref.read(rpcEndpointFailoverProvider).current.networkName;
  String get _ua => ref.read(accountProvider).value?.activeAddress ?? '';

  Future<void> _initialize() async {
    final epoch = ++_epoch;
    _engine?.dispose();
    _engine = null;
    _gateway?.close();
    _gateway = null;
    _review = null;
    _lookup = null;
    _lookedUpRecord = null;
    _owner = '';
    _error = null;
    _busy = true;
    _publish();
    try {
      if (!_unlocked || _uuid.isEmpty) return;
      final saved = await AppSecureStore.instance.readString(
        'zns:configuration:v1',
      );
      if (saved != null) {
        final c = jsonDecode(saved) as Map<String, dynamic>;
        _config = ZnsConfigurationInput(
          rpcUrl: c['rpcUrl'] as String,
          registryAddress: c['registryAddress'] as String,
          chainId: c['chainId'] as int,
          tokenAddress: c['tokenAddress'] as String,
          delegateAddress: c['delegateAddress'] as String? ?? '',
        );
      }
      if (ref.read(accountProvider).value?.activeAccount?.isHardware == true ||
          _config.registryAddress.isEmpty) {
        return;
      }
      final uuid = _uuid, network = _network;
      final identity = await ZnsWalletGateway.account(ref, uuid, network);
      if (epoch != _epoch || !_unlocked) return;
      _owner = identity['address'] as String;
      final scope = ZnsScope(
        zcashNetwork: network,
        chainId: _config.chainId,
        registry: _config.registryAddress,
        owner: _owner,
      );
      final config = _networkConfig(_config);
      final gateway = ZnsWalletGateway(
        ref: ref,
        config: config,
        scope: scope,
        accountUuid: uuid,
        delegate: _config.delegateAddress,
      );
      _gateway = gateway;
      _engine = ZnsEngine(
        accountUuid: uuid,
        scope: scope,
        gateway: gateway,
        journal: const ZnsJournal(ZnsSecureJournalStorage()),
        canSign: () =>
            epoch == _epoch &&
            _unlocked &&
            _uuid == uuid &&
            _network == network,
        onChange: _publish,
      );
      final engine = _engine!;
      ZnsLifecycleGuard.active[uuid] = () => engine.busy || engine.authorized;
      await _engine!.load();
    } catch (e) {
      if (epoch == _epoch) _error = e.toString();
    } finally {
      if (epoch == _epoch) {
        _busy = false;
        _publish();
      }
    }
  }

  ZnsNetworkConfig _networkConfig(ZnsConfigurationInput input) =>
      ZnsNetworkConfig(
        chainId: input.chainId,
        rpcUri: Uri.parse(input.rpcUrl),
        registryAddress: input.registryAddress,
        tokenAddress: input.tokenAddress,
        tokenDecimals: 8,
        allowLocalTestEndpoints:
            input.chainId == 31337 || input.chainId == 84532,
      );

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _disposed) return;
    _busy = true;
    _error = null;
    _notice = null;
    _publish();
    final epoch = _epoch;
    try {
      await action();
    } catch (e) {
      if (epoch == _epoch) _error = e.toString();
    } finally {
      if (!_disposed && epoch == _epoch) {
        _busy = false;
        _publish();
      }
    }
  }

  void lookup(String label) => unawaited(
    _run(() async {
      final epoch = _epoch;
      znsValidateLabel(label);
      if (_gateway == null) throw StateError('Configure a registry first.');
      final record = await _gateway!.lookup(label);
      final now = (await _gateway!.rpc.block()).timestamp.toInt();
      if (epoch != _epoch || !_unlocked) return;
      _lookedUpRecord = record;
      _lookup = record == null || record.expiresAt <= now
          ? ZnsLookupView(name: label, status: ZnsLookupStatus.available)
          : ZnsLookupView(
              name: label,
              status: ZnsLookupStatus.registered,
              unifiedAddress: record.unifiedAddress,
              expiresAt: _date(record.expiresAt),
            );
    }),
  );

  void prepare(ZnsRegistrationInput input) => unawaited(
    _run(() async {
      final epoch = _epoch, network = _network, ua = _ua;
      final engine = _engine;
      if (engine == null) {
        throw StateError(
          'Configure the registry and unlock your software account.',
        );
      }
      if (!await rust.znsValidateUnifiedAddress(
        network: network,
        address: ua,
      )) {
        throw StateError(
          'The wallet address is not a valid Unified Address for this Zcash network.',
        );
      }
      if (epoch != _epoch || !_unlocked) return;
      final review = await engine.prepare(name: input.name, ua: ua);
      if (epoch == _epoch && _unlocked) _review = review;
    }),
  );

  void confirm() => unawaited(
    _run(() async {
      final reviewed = _review;
      if (reviewed == null || _engine == null) {
        throw StateError('Review the operation first.');
      }
      _review = null;
      await _engine!.authorize(reviewed);
    }),
  );
  void cancelReview() {
    _review = null;
    _publish();
  }

  void pause() {
    _engine?.pause();
    _publish();
  }

  void resume() => unawaited(
    _run(() async {
      final epoch = _epoch, engine = _engine, gateway = _gateway;
      final operation = engine?.operation;
      if (operation == null || gateway == null || !_unlocked) return;
      await engine!.refresh();
      if (operation.kind == 'release') {
        final preview = await gateway.exitPreview(operation.positionId);
        if (epoch != _epoch || !_unlocked) return;
        operation.exitPreview!
          ..clear()
          ..addAll(preview);
      }
      if (epoch == _epoch && _unlocked) _review = operation;
    }),
  );

  void refresh() => unawaited(
    _run(() async {
      if (_engine != null) {
        await _engine!.refresh();
      } else {
        await _initialize();
      }
    }),
  );

  void manage(
    String kind, {
    String recipient = '',
    String? receivingAddress,
  }) => unawaited(
    _run(() async {
      final epoch = _epoch, network = _network, currentUa = _ua;
      final engine = _engine;
      if (engine == null) {
        throw StateError('Unlock and configure the wallet first.');
      }
      await engine.refresh();
      if (epoch != _epoch || !_unlocked) return;
      final position = engine.chain?.position;
      if (kind != 'withdrawClaims' && position == null) {
        throw StateError('There is no registration to manage.');
      }
      final ua = kind == 'update'
          ? (receivingAddress ?? currentUa).trim()
          : position?.unifiedAddress ?? '';
      if (kind == 'update' &&
          !await rust.znsValidateUnifiedAddress(
            network: network,
            address: ua,
          )) {
        throw StateError(
          'Select a valid Unified Address before updating your name.',
        );
      }
      // If Base gas needs funding, quote a bounded ZEC amount and show it before
      // authorization. Management never silently spends additional ZEC.
      if (epoch != _epoch || !_unlocked) return;
      final review = await engine.prepare(
        name: position?.name ?? '',
        ua: ua,
        kind: kind,
        recipient: recipient,
      );
      if (epoch == _epoch && _unlocked) _review = review;
    }),
  );

  void selectName(String id) => unawaited(
    _run(() async {
      final engine = _engine, gateway = _gateway;
      if (engine == null ||
          gateway == null ||
          _review != null ||
          (engine.operation != null && !engine.operation!.isComplete)) {
        return;
      }
      final value = BigInt.parse(id);
      if (!(gateway.lastSnapshot?.positions.any((p) => p.positionId == value) ??
          false)) {
        throw StateError(
          'Refresh the name inventory before selecting this registration.',
        );
      }
      if (engine.operation?.isComplete == true) await engine.archive();
      gateway.selectedPositionId = value;
      await engine.refresh();
    }),
  );

  void namesPage(int offset) => unawaited(
    _run(() async {
      final engine = _engine, gateway = _gateway;
      if (engine == null ||
          gateway == null ||
          offset < 0 ||
          _review != null ||
          (engine.operation != null && !engine.operation!.isComplete)) {
        return;
      }
      if (engine.operation?.isComplete == true) await engine.archive();
      gateway.inventoryOffset = offset;
      gateway.selectedPositionId = null;
      await engine.refresh();
    }),
  );

  void saveConfiguration(ZnsConfigurationInput input) => unawaited(
    _run(() async {
      final epoch = _epoch;
      if (!_unlocked) throw StateError('Unlock the wallet first.');
      if (_engine?.operation != null && !_engine!.operation!.isComplete) {
        throw StateError(
          'Finish or archive the saved operation before changing its deployment.',
        );
      }
      final config = _networkConfig(input);
      if (input.delegateAddress.isNotEmpty) znsAddress(input.delegateAddress);
      // A locally verified address is still user-configured deployment data, not
      // a declaration that the source has been independently audited.
      final check = ZnsWalletGateway(
        ref: ref,
        config: config,
        scope: ZnsScope(
          zcashNetwork: _network,
          chainId: input.chainId,
          registry: input.registryAddress,
          owner: _owner.isEmpty
              ? '0x0000000000000000000000000000000000000001'
              : _owner,
        ),
        accountUuid: _uuid,
        delegate: input.delegateAddress,
        recordHoldings: false,
      );
      try {
        await check.snapshot(null);
      } finally {
        check.close();
      }
      if (epoch != _epoch || !_unlocked) return;
      await AppSecureStore.instance.writeString(
        'zns:configuration:v1',
        jsonEncode({
          'rpcUrl': input.rpcUrl,
          'chainId': input.chainId,
          'registryAddress': input.registryAddress,
          'tokenAddress': input.tokenAddress,
          'delegateAddress': input.delegateAddress,
        }),
      );
      if (epoch != _epoch || !_unlocked) return;
      _config = input;
      await _initialize();
    }),
  );

  String exportRecovery() {
    if (!_unlocked || _engine?.operation == null) {
      throw StateError('No saved operation is available.');
    }
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(_engine!.operation!.toJson());
  }

  Future<void> archiveOperation() async {
    final epoch = _epoch;
    final engine = _engine;
    if (engine == null || !_unlocked) {
      throw StateError('Unlock the account first.');
    }
    await engine.archive();
    if (epoch != _epoch || !_unlocked) return;
    _review = null;
    _notice =
        'Operation archived locally. Existing Base assets and on-chain commitments remain under your control.';
    _publish();
  }

  Future<void> importRecovery(String raw) async {
    final epoch = _epoch, uuid = _uuid;
    final engine = _engine, gateway = _gateway;
    if (engine == null || gateway == null || !_unlocked) {
      throw StateError('Configure and unlock this software account first.');
    }
    if (engine.busy ||
        engine.authorized ||
        (engine.operation != null && !engine.operation!.isComplete)) {
      throw StateError(
        'Pause and archive the current operation before restoring another.',
      );
    }
    final op = ZnsOperation.decode(raw, engine.scope);
    if (op.kind == 'register' &&
        await gateway.commitment(op.name, op.unifiedAddress, op.secret) !=
            op.commitment) {
      throw StateError(
        'The recovery secret does not match the saved commitment.',
      );
    }
    if (op.kind == 'release') {
      final current = await gateway.exitPreview(op.positionId);
      op.exitPreview!
        ..clear()
        ..addAll(current);
    }
    // Imported bytes are not trusted as a signing/broadcast instruction. Keep
    // hashes for receipt reconciliation; locally persisted bytes remain intact.
    op.pending?.remove('raw');
    if (op.funding?['plan'] is Map) {
      final plan = Map<String, dynamic>.from(op.funding!['plan'] as Map);
      if ('${plan['owner']}'.toLowerCase() !=
          engine.scope.owner.toLowerCase()) {
        throw StateError('Funding recovery belongs to another Base owner.');
      }
      plan['accountUuid'] = uuid;
      op.funding = {...op.funding!, 'plan': plan, 'attempted': true};
    }
    if (epoch != _epoch || !_unlocked) {
      throw StateError(
        'Account changed. Restore recovery again after unlocking.',
      );
    }
    await engine.journal.save(op, uuid);
    if (epoch != _epoch || !_unlocked) return;
    await engine.load();
    if (epoch != _epoch || !_unlocked) return;
    _notice = 'Recovery restored. Review the saved intent before continuing.';
    _publish();
  }

  Future<String> resolvedAddressForSend({String? acceptedRecipient}) async {
    final epoch = _epoch;
    final label = _lookup?.name;
    if (label == null || _gateway == null) {
      throw StateError('Look up a name first.');
    }
    final record = await _gateway!.lookup(label);
    final block = await _gateway!.rpc.block();
    if (record == null ||
        !record.participating ||
        record.expiresAt <= block.timestamp.toInt() ||
        !await rust.znsValidateUnifiedAddress(
          network: _network,
          address: record.unifiedAddress,
        )) {
      throw StateError(
        'The current name does not resolve to a valid address for this Zcash network.',
      );
    }
    if (epoch != _epoch || !_unlocked) {
      throw StateError('Account changed. Look up the name again.');
    }
    final identity = '${record.positionId}:${record.owner.toLowerCase()}';
    final fingerprint = '$identity:${record.unifiedAddress}';
    final scope = _engine!.scope;
    final key =
        'zns:recipient:${scope.zcashNetwork}:${scope.chainId}:${scope.registry.toLowerCase()}:$label';
    final saved = await AppSecureStore.instance.readString(key);
    final observed = _lookedUpRecord;
    final observedIdentity = observed == null
        ? null
        : '${observed.positionId}:${observed.owner.toLowerCase()}';
    if (((saved != null && saved != identity) ||
            (observedIdentity != null && observedIdentity != identity)) &&
        acceptedRecipient != fingerprint) {
      throw ZnsRecipientChanged(label, record.unifiedAddress, fingerprint);
    }
    if (epoch != _epoch || !_unlocked) {
      throw StateError('Account changed. Look up the name again.');
    }
    await AppSecureStore.instance.writeString(key, identity);
    if (epoch != _epoch || !_unlocked) {
      throw StateError('Account changed. Look up the name again.');
    }
    _lookedUpRecord = record;
    return record.unifiedAddress;
  }

  ZnsCallbacks callbacks({
    void Function()? onShowRecovery,
    void Function(ZnsLookupView)? onSendToName,
  }) => ZnsCallbacks(
    onLookup: lookup,
    onPrepareRegistration: prepare,
    onConfirmRegistration: confirm,
    onCancelReview: cancelReview,
    onPause: pause,
    onResume: resume,
    onRefresh: refresh,
    onRefreshName: () => manage('refresh'),
    onClaimRewards: () => manage('claimRewards'),
    onWithdrawClaims: () => manage('withdrawClaims'),
    onUpdateAddress: (address) => manage('update', receivingAddress: address),
    onRelease: () => manage('release'),
    onTransfer: (recipient) => manage('transfer', recipient: recipient),
    onSelectName: selectName,
    onNamesPage: namesPage,
    onSaveConfiguration: saveConfiguration,
    onShowRecovery: onShowRecovery,
    onSendToName: onSendToName,
  );

  String _date(int seconds) => DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
  ).toLocal().toString().split('.').first;
  String _amount(BigInt value, int decimals) =>
      znsFormatAmount(value, decimals);
  String _reward(BigInt scaled) => _amount(scaled, 32);

  void _publish() {
    if (_disposed) return;
    final account = ref.read(accountProvider).value;
    final locked = !_unlocked;
    final chain = locked ? null : _engine?.chain;
    final op = locked ? null : _engine?.operation;
    final review = locked ? null : _review;
    final owned =
        chain?.position?.retired == false &&
            chain?.position?.owner.toLowerCase() == _owner.toLowerCase()
        ? chain?.position
        : null;
    final inventory = locked ? null : _gateway?.lastSnapshot;
    final phase = op?.phase ?? '';
    final registration = op?.kind == 'register';
    final phases = registration
        ? ['funding', 'commit', 'waiting', 'register', 'complete']
        : ['funding', op?.kind ?? 'ready', 'complete'];
    final action = switch (op?.kind) {
      'refresh' => 'Refresh name',
      'claimRewards' => 'Claim rewards',
      'update' => 'Update Zcash address',
      'release' => 'Release name',
      'transfer' => 'Transfer name',
      'withdrawClaims' => 'Withdraw old claims',
      _ => 'Register name',
    };
    final stepTitles = registration
        ? [
            'Fund registration',
            'Commit name',
            'Wait to register',
            'Deposit cbZEC and register',
            'Confirm ownership',
          ]
        : ['Fund network fee', action, 'Confirm action'];
    final phaseIndex = phases.indexOf(
      ['swap', 'approve', 'atomicRegister'].contains(phase)
          ? 'register'
          : phase,
    );
    final preview = review?.exitPreview;
    BigInt previewAmount(String key) =>
        BigInt.parse(preview?[key] as String? ?? '0');
    state = ZnsViewData(
      accountId: account?.activeAccountUuid ?? '',
      accountName: account?.activeAccount?.name ?? 'Your account',
      isConfigured: _config.registryAddress.isNotEmpty,
      isSoftwareAccount: account?.activeAccount?.isHardware != true,
      isLocked: locked,
      isBusy: _busy || (_engine?.busy ?? false),
      walletUnifiedAddress: locked ? '' : _ua,
      baseOwnerAddress: locked ? '' : _owner,
      baseRecoveryDescription:
          'Recovered from this wallet seed, BIP39 passphrase and account index. Keep your existing backup.',
      ethBalance: chain == null ? '—' : _amount(chain.eth, 18),
      cbZecBalance: chain == null ? '—' : _amount(chain.token, 8),
      claimablePrincipal: chain == null
          ? '—'
          : _amount(chain.claimablePrincipal, 8),
      claimableRewards: chain == null
          ? '—'
          : _amount(chain.claimableRewardsScaled ~/ znsRewardScale, 8),
      canWithdrawClaims:
          chain != null &&
          (chain.claimablePrincipal > BigInt.zero ||
              chain.claimableRewardsScaled >= znsRewardScale),
      configuration: _config,
      lookup: locked ? null : _lookup,
      error: locked ? null : _error ?? _engine?.error,
      notice: _notice,
      names:
          inventory?.positions
              .map(
                (p) => ZnsNameChoice(
                  p.positionId.toString(),
                  p.name,
                  expired: !p.participating,
                ),
              )
              .toList() ??
          const [],
      inventoryOffset: inventory?.positionOffset ?? 0,
      hasMoreNames:
          inventory != null &&
          BigInt.from(inventory.positionOffset + inventory.positions.length) <
              inventory.totalPositions,
      ownedName: owned == null
          ? null
          : ZnsOwnedNameView(
              name: owned.name,
              unifiedAddress: owned.unifiedAddress,
              positionId: owned.positionId.toString(),
              maturityAt: _date(owned.maturityAt),
              refreshDueAt: _date(owned.refreshDueAt),
              graceEndsAt: _date(owned.expiresAt),
              deposit: _amount(owned.deposit, 8),
              accruedRewards: _reward(owned.rewardCreditScaled),
              claimableRewards: chain!.timestamp >= owned.maturityAt
                  ? _amount(owned.rewardCreditScaled ~/ znsRewardScale, 8)
                  : '0',
              isMature: chain.timestamp >= owned.maturityAt,
              isInGrace:
                  owned.participating && chain.timestamp >= owned.refreshDueAt,
              canClaimRewards:
                  owned.participating &&
                  chain.timestamp >= owned.maturityAt &&
                  owned.rewardCreditScaled >= znsRewardScale,
              isExpired: !owned.participating,
            ),
      review: review == null
          ? null
          : ZnsReviewView(
              positionId: review.positionId.toString(),
              recipient: review.kind == 'transfer' ? review.recipient : null,
              name: review.name.isEmpty
                  ? 'Old deposits and rewards'
                  : review.name,
              unifiedAddress: review.unifiedAddress,
              maxZec: _amount(review.maxZatoshi, 8),
              estimatedZec: review.estimatedZatoshi == null
                  ? null
                  : _amount(review.estimatedZatoshi!, 8),
              conversionRate: review.rateZatoshi == null
                  ? null
                  : '1 cbZEC ≈ ${_amount(review.rateZatoshi!, 8)} ZEC',
              zcashFee: review.zcashFeeZatoshi == null
                  ? null
                  : _amount(review.zcashFeeZatoshi!, 8),
              deposit: _amount(
                review.kind == 'transfer'
                    ? chain?.deposit ?? BigInt.zero
                    : review.requiredTokenUnits,
                8,
              ),
              maturityAt: review.kind == 'register' || review.maturityAt == 0
                  ? null
                  : _date(review.maturityAt),
              refreshDueAt: review.kind == 'transfer'
                  ? (owned == null ? null : _date(owned.refreshDueAt))
                  : chain == null
                  ? null
                  : _date(chain.timestamp + znsHoldingSeconds),
              exitPreview: preview == null
                  ? null
                  : ZnsExitPreview(
                      early: preview['early'] == true,
                      principalReturned: _amount(
                        previewAmount('principalReturned'),
                        8,
                      ),
                      rewardsReturned: _amount(
                        previewAmount('rewardsReturned'),
                        8,
                      ),
                      principalForfeited: _amount(
                        previewAmount('principalForfeited'),
                        8,
                      ),
                      rewardsForfeited: _reward(
                        previewAmount('rewardsForfeitedScaled'),
                      ),
                    ),
              rewardsToClaim: review.kind == 'transfer'
                  ? _reward(owned?.rewardCreditScaled ?? BigInt.zero)
                  : _amount(
                      ((review.kind == 'withdrawClaims'
                                  ? chain?.claimableRewardsScaled
                                  : owned?.rewardCreditScaled) ??
                              BigInt.zero) ~/
                          znsRewardScale,
                      8,
                    ),
              gasReserve: _amount(review.maxGasFeeWei, 18),
              estimatedDuration: (chain?.eth ?? BigInt.zero) >= review.maxEthWei
                  ? (review.kind == 'register'
                        ? 'Commitment wait and Base confirmations'
                        : 'Base confirmations')
                  : 'Several minutes if ZEC funding is needed, then Base confirmations',
              maxBaseEth: _amount(review.maxEthWei, 18),
              existingCbZecSpend: _amount(
                (chain?.token ?? BigInt.zero) < review.requiredTokenUnits
                    ? chain?.token ?? BigInt.zero
                    : review.requiredTokenUnits,
                8,
              ),
              existingEthSpend: _amount(
                (chain?.eth ?? BigInt.zero) < review.maxEthWei
                    ? chain?.eth ?? BigInt.zero
                    : review.maxEthWei,
                18,
              ),
              kind: switch (review.kind) {
                'refresh' => ZnsReviewKind.refresh,
                'claimRewards' => ZnsReviewKind.claimRewards,
                'withdrawClaims' => ZnsReviewKind.withdrawClaims,
                'update' => ZnsReviewKind.addressUpdate,
                'release' => ZnsReviewKind.release,
                'transfer' => ZnsReviewKind.transfer,
                _ => ZnsReviewKind.registration,
              },
              canConfirm: !locked && !_busy,
            ),
      operation: op == null
          ? null
          : ZnsOperationView(
              name: op.name,
              title: op.isComplete
                  ? '$action confirmed'
                  : phase == 'waiting'
                  ? 'Waiting to register'
                  : '$action in progress',
              description: op.isComplete
                  ? 'The action is confirmed on Base.'
                  : registration
                  ? 'Progress is saved. Funding does not reserve the name; it becomes yours after registration confirms.'
                  : 'Progress and spending limits are saved. You can pause and resume after reviewing.',
              steps: [
                for (var i = 0; i < phases.length; i++)
                  ZnsProgressStep(
                    title: stepTitles[i],
                    status: op.isComplete || i < phaseIndex
                        ? ZnsStepStatus.complete
                        : i == phaseIndex
                        ? (_engine?.authorized == true
                              ? ZnsStepStatus.active
                              : ZnsStepStatus.paused)
                        : ZnsStepStatus.upcoming,
                  ),
              ],
              isPaused: _engine?.authorized != true && !op.isComplete,
              isComplete: op.isComplete,
              canPause: _engine?.authorized == true,
              canResume:
                  _engine?.authorized != true && !op.isComplete && !locked,
              remainingWait: chain != null && phase == 'waiting'
                  ? '${(chain.commitAt + chain.minAge - chain.timestamp).clamp(0, chain.minAge)} seconds at the latest block'
                  : null,
              transactionId:
                  op.pending?['hash'] as String? ??
                  op.funding?['txHash'] as String?,
              recoveryMessage: op.isComplete
                  ? null
                  : op.message ??
                        'Unlock and review to resume after restarting. Existing signed transactions can still confirm.',
            ),
    );
  }
}
