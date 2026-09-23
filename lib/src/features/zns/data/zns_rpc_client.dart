import 'package:flutter/foundation.dart' show visibleForTesting;

import 'zns_abi.dart';
import '../domain/zns_operation.dart';
import 'zns_http_transport.dart';
import 'zns_multicall.dart';
import 'zns_network_config.dart';

/// Decode only fixed, argument-free errors from the reviewed contracts. Never
/// display provider prose, arbitrary revert strings, calldata or addresses.
String? _knownRevertMessage(Object? data) {
  if (data is! String ||
      data.length > 266 ||
      !RegExp(r'^0x(?:[0-9a-fA-F]{2})+$').hasMatch(data)) {
    return null;
  }
  var reason = data.toLowerCase();
  // ZnsBatchAccount.CallFailed(uint256,bytes), with exactly one four-byte
  // nested reason, canonical offset/length and zero ABI padding.
  if (reason.startsWith('0x5c0dee5d')) {
    if (reason.length != 266) return null;
    final wrapped = ZnsAbi('0x${reason.substring(10)}');
    if (wrapped.word(32) != BigInt.from(64) ||
        wrapped.word(64) != BigInt.from(4) ||
        reason.substring(210) != '0' * 56) {
      return null;
    }
    reason = '0x${reason.substring(202, 210)}';
  }
  return const {
    '0x02f378dc':
        'Registration pricing changed. Review the updated bond and pricing mode before continuing.',
    '0x6adf7e28':
        'The required registration bond exceeds the reviewed limit. Review the updated bond before continuing.',
    '0x8727a7f9':
        'The registration quote expired. Review again before continuing.',
    '0x8730528d':
        'The name service could not verify pricing with the available gas. Review again before continuing.',
  }[reason];
}

/// Only canonical batch ABI is recognized. The payload is never retained.
class ZnsRpcRevert extends ZnsDataException {
  const ZnsRpcRevert(
    super.message, {
    super.code,
    this.batchStep,
    this.revertSelector,
  });
  final int? batchStep;
  final String? revertSelector;
}

int? _batchFailureStep(Object? data) {
  if (data is! String ||
      data.length < 202 ||
      data.length > 16586 ||
      !RegExp(r'^0x5c0dee5d[0-9a-fA-F]+$').hasMatch(data) ||
      (data.length - 10) % 64 != 0) {
    return null;
  }
  final abi = ZnsAbi('0x${data.substring(10)}');
  final length = abi.word(64);
  if (abi.word(0) > BigInt.from(2) ||
      abi.word(32) != BigInt.from(64) ||
      length > BigInt.from(8192)) {
    return null;
  }
  final bytes = length.toInt();
  final padded = ((bytes + 31) ~/ 32) * 64;
  if (data.length != 202 + padded ||
      data.substring(202 + bytes * 2) != '0' * (padded - bytes * 2)) {
    return null;
  }
  return abi.word(0).toInt();
}

// Called only after the canonical batch envelope has been validated.
String? _safeBatchSelector(String data) {
  if (data.length < 210) return null;
  final selector = '0x${data.substring(202, 210).toLowerCase()}';
  return const {
        '0x02f378dc', // PricingModeChanged
        '0x6adf7e28', // DepositLimitExceeded
        '0x8727a7f9', // QuoteExpired
        '0x8730528d', // InsufficientOracleGas
        '0x7c9c6e8f', // Uniswap v4 PriceLimitAlreadyExceeded
      }.contains(selector)
      ? selector
      : null;
}

/// One reverted call becomes one reviewed message, whether it arrived as a
/// JSON-RPC error or as a failed sub-call inside a batch.
ZnsDataException _callFailure(String method, Object? data, {int? code}) {
  final revertable = method == 'eth_call' || method == 'eth_estimateGas';
  final knownRevert = revertable ? _knownRevertMessage(data) : null;
  final batchStep = revertable ? _batchFailureStep(data) : null;
  if (batchStep != null) {
    return ZnsRpcRevert(
      knownRevert ?? 'Base RPC $method failed. Refresh before retrying.',
      code: code,
      batchStep: batchStep,
      revertSelector: _safeBatchSelector(data as String),
    );
  }
  return ZnsDataException(
    knownRevert ?? 'Base RPC $method failed. Refresh before retrying.',
    code: code,
  );
}

class ZnsCall {
  ZnsCall({
    required String from,
    required String to,
    required String data,
    BigInt? value,
    this.authorizationList,
  }) : from = znsAddress(from),
       to = znsAddress(to),
       data = znsHex(data, allowEmpty: true),
       value = value ?? BigInt.zero {
    znsQuantity(this.value);
  }
  final String from, to, data;
  final BigInt value;
  final List<Map<String, Object?>>? authorizationList;
  Map<String, Object?> toJson() => {
    'from': from,
    'to': to,
    'data': data,
    'value': znsQuantity(value),
    if (authorizationList != null) 'authorizationList': authorizationList,
  };
}

class ZnsBlock {
  const ZnsBlock({
    required this.number,
    required this.hash,
    required this.timestamp,
    this.baseFeePerGas,
  });
  final BigInt number, timestamp;
  final String hash;
  final BigInt? baseFeePerGas;
}

class ZnsRegistrySnapshot {
  const ZnsRegistrySnapshot({
    required this.block,
    required this.owner,
    required this.token,
    required this.tokenDecimals,
    required this.registrationQuote,
    required this.minimumCommitmentAge,
    required this.maximumCommitmentAge,
    required this.nativeBalance,
    required this.tokenBalance,
    required this.allowance,
    required this.claimablePrincipal,
    required this.claimableRewardsScaled,
    required this.selectedPosition,
    required this.commitmentTimestamp,
    required this.positions,
    required this.totalPositions,
    required this.positionOffset,
  });
  final ZnsBlock block;
  final String owner, token;
  final int tokenDecimals;
  final ZnsRegistrationQuote? registrationQuote;
  final BigInt minimumCommitmentAge,
      maximumCommitmentAge,
      nativeBalance,
      tokenBalance,
      allowance,
      claimablePrincipal,
      claimableRewardsScaled,
      commitmentTimestamp;
  final ZnsPosition? selectedPosition;
  final List<ZnsPosition> positions;
  final BigInt totalPositions;
  final int positionOffset;
  String get activeName =>
      selectedPosition?.participating == true ? selectedPosition!.name : '';
}

class ZnsPosition {
  const ZnsPosition({
    required this.positionId,
    required this.owner,
    required this.name,
    required this.unifiedAddress,
    required this.registeredAt,
    required this.maturityAt,
    required this.refreshDueAt,
    required this.graceEndsAt,
    required this.participating,
    required this.retired,
    required this.rewardCreditScaled,
    required this.principal,
    required this.block,
  });
  final BigInt positionId,
      registeredAt,
      maturityAt,
      refreshDueAt,
      graceEndsAt,
      rewardCreditScaled,
      principal;
  final String owner, name, unifiedAddress;
  final bool participating, retired;
  final ZnsBlock block;
  bool get mature => block.timestamp >= maturityAt;
  bool get inGrace => participating && block.timestamp >= refreshDueAt;
}

class ZnsExitPreview {
  const ZnsExitPreview({
    required this.early,
    required this.principalReturned,
    required this.rewardsReturned,
    required this.principalForfeited,
    required this.rewardsForfeitedScaled,
    required this.block,
  });
  final bool early;
  final BigInt principalReturned,
      rewardsReturned,
      principalForfeited,
      rewardsForfeitedScaled;
  final ZnsBlock block;
}

class ZnsNameRecord {
  const ZnsNameRecord({
    required this.name,
    required this.owner,
    required this.unifiedAddress,
    required this.expiresAt,
    required this.active,
    required this.positionId,
    required this.block,
  });
  final String name, owner, unifiedAddress;
  final BigInt expiresAt, positionId;
  final bool active;
  final ZnsBlock block;
}

class ZnsReceipt {
  const ZnsReceipt({
    required this.transactionHash,
    required this.blockNumber,
    required this.blockHash,
    required this.succeeded,
    required this.canonical,
    required this.confirmations,
    required this.requiredConfirmations,
    required this.from,
    required this.to,
  });
  final String transactionHash, blockHash, from;
  final String? to;
  final BigInt blockNumber, confirmations;
  final int requiredConfirmations;
  final bool succeeded, canonical;
  bool get confirmed =>
      canonical && confirmations >= BigInt.from(requiredConfirmations);
}

class ZnsFeeQuote {
  const ZnsFeeQuote({
    required this.maxFeePerGas,
    required this.maxPriorityFeePerGas,
  });
  final BigInt maxFeePerGas, maxPriorityFeePerGas;

  /// L2 execution ceiling only. Base also charges an L1 data fee: reserve and
  /// review it separately rather than claiming this is a complete fee.
  BigInt executionCeiling(BigInt gasLimit) => gasLimit * maxFeePerGas;
}

class ZnsRpcClient {
  ZnsRpcClient(
    this.config, {
    ZnsHttpTransport? transport,
    Duration? requestSpacing,
    Future<void> Function(Duration)? wait,
    DateTime Function()? now,
  }) : _transport = transport ?? ZnsPolicyHttpTransport(),
       requestSpacing =
           requestSpacing ??
           (_isPacedPublicEndpoint(config.rpcUri)
               ? const Duration(milliseconds: 1100)
               : const Duration(milliseconds: 250)),
       _sharedPublicPacing =
           requestSpacing == null && _isPacedPublicEndpoint(config.rpcUri),
       _wait = wait ?? Future<void>.delayed,
       _now = now ?? DateTime.now {
    if (this.requestSpacing.isNegative) {
      throw ArgumentError('Negative RPC spacing');
    }
  }
  final ZnsNetworkConfig config;
  final ZnsHttpTransport _transport;
  final Duration requestSpacing;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _now;
  final bool _sharedPublicPacing;
  static Future<void> _pacedPublicStartQueue = Future<void>.value();
  static DateTime? _pacedPublicLastStart;
  Future<void> _queue = Future<void>.value();
  DateTime? _lastRequestAt, _rateLimitedUntil;
  bool _closed = false;
  var _id = 0;

  /// Conservatively pace shared endpoints across clients in this process,
  /// including the Sybil gateway. Custom endpoints retain their own pacing.
  static bool _isPacedPublicEndpoint(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      ((uri.host == 'api.sybil.cash' && uri.path == '/api/base/rpc') ||
          (const {'mainnet.base.org', 'base.drpc.org'}.contains(uri.host) &&
              (uri.path.isEmpty || uri.path == '/'))) &&
      !uri.hasQuery &&
      uri.userInfo.isEmpty;

  Future<void> _waitForRequestStart() async {
    if (!_sharedPublicPacing) {
      final last = _lastRequestAt;
      if (last != null) {
        final remaining = requestSpacing - _now().difference(last);
        if (remaining > Duration.zero) await _wait(remaining);
      }
      return;
    }
    // Reserve actual starts across Names clients, including an endpoint editor
    // and a reopened controller. This gate holds no network request or wallet
    // state; explicit spacing overrides opt out for controlled diagnostics.
    final turn = _pacedPublicStartQueue.then((_) async {
      _checkOpen();
      final last = _pacedPublicLastStart;
      if (last != null) {
        final remaining = requestSpacing - _now().difference(last);
        if (remaining > Duration.zero) await _wait(remaining);
      }
      _checkOpen();
      _pacedPublicLastStart = _now();
    });
    _pacedPublicStartQueue = turn.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    await turn;
  }

  void close() {
    _closed = true;
    _transport.close();
  }

  // A registry snapshot fans out many reads. Serialize/pause them at the RPC
  // boundary so a single screen cannot burst through a public endpoint's quota.
  // Failed reads do not poison the queue; closing cancels queued work as well.
  Future<Object?> request(String method, List<Object?> params) {
    final result = _queue.then((_) => _requestWithBackoff(method, params));
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _checkOpen() {
    if (_closed) {
      throw const ZnsDataException('Name service request cancelled.');
    }
  }

  Future<Object?> _requestWithBackoff(
    String method,
    List<Object?> params,
  ) async {
    _checkOpen();
    final cooldown = _rateLimitedUntil;
    if (cooldown != null && _now().isBefore(cooldown)) {
      throw ZnsRateLimitException(
        retryAfter: cooldown.difference(_now()),
        rpcMethod: method,
      );
    }
    const readMethods = {
      'eth_chainId',
      'eth_getBlockByNumber',
      'eth_getCode',
      'eth_call',
      'eth_getBalance',
      'eth_getTransactionCount',
      'eth_estimateGas',
      'eth_maxPriorityFeePerGas',
      'eth_getTransactionReceipt',
    };
    for (var attempt = 0; ; attempt++) {
      _checkOpen();
      await _waitForRequestStart();
      _checkOpen();
      _lastRequestAt = _now();
      try {
        final result = await _requestOnce(method, params);
        _checkOpen();
        return result;
      } on ZnsRateLimitException catch (error) {
        final backoff = Duration(seconds: 1 << attempt.clamp(0, 2));
        final retryAfter = error.retryAfter;
        final delay = retryAfter != null && retryAfter > backoff
            ? retryAfter
            : backoff;
        // Never retry a signed transaction here: the engine owns its durable
        // journal and ambiguous-broadcast reconciliation. Long Retry-After
        // values also fail promptly, without retrying before the stated time.
        if (!readMethods.contains(method) ||
            attempt >= 2 ||
            delay > const Duration(seconds: 5)) {
          _rateLimitedUntil = _now().add(delay);
          throw ZnsRateLimitException(
            retryAfter: error.retryAfter,
            rpcMethod: method,
          );
        }
        await _wait(delay);
      } on ZnsDataException catch (error) {
        if (error.code == 401 || error.code == 403) {
          // Never expose the provider's response body or echo a URL that may
          // contain credentials. Access denial is not a connectivity failure.
          throw ZnsDataException(
            'The selected Base RPC endpoint rejected access (${error.code}). '
            'Saved progress is retained. Choose a different endpoint in '
            'Settings → Base RPC endpoint.',
            code: error.code,
          );
        }
        rethrow;
      }
    }
  }

  Future<Object?> _requestOnce(String method, List<Object?> params) async {
    final id = ++_id;
    final response = znsObject(
      await _transport.request(
        'POST',
        config.rpcUri,
        body: {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params},
      ),
    );
    if (response['id'] != id || response['jsonrpc'] != '2.0') {
      throw const ZnsDataException('Mismatched Base RPC response');
    }
    if (response['error'] != null) {
      final error = znsObject(response['error']);
      if (error['code'] == 429 ||
          error['code'] == -32005 ||
          error['code'] == -32016) {
        throw const ZnsRateLimitException();
      }
      // Do not propagate provider text: it can contain calldata and addresses.
      throw _callFailure(
        method,
        error['data'],
        code: error['code'] is int ? error['code'] as int : null,
      );
    }
    if (!response.containsKey('result')) {
      throw const ZnsDataException('Base RPC result is missing');
    }
    return response['result'];
  }

  Future<void> verifyChain() async {
    if (znsParseQuantity(await request('eth_chainId', [])) !=
        BigInt.from(config.chainId)) {
      throw const ZnsDataException(
        'The RPC network does not match the ZNS deployment',
      );
    }
  }

  Future<ZnsBlock> block([String tag = 'latest']) async {
    final value = znsObject(
      await request('eth_getBlockByNumber', [tag, false]),
    );
    return ZnsBlock(
      number: znsParseQuantity(value['number']),
      hash: znsHex(value['hash'] as String, bytes: 32),
      timestamp: znsParseQuantity(value['timestamp']),
      baseFeePerGas: value['baseFeePerGas'] == null
          ? null
          : znsParseQuantity(value['baseFeePerGas']),
    );
  }

  Future<String> code(String address, {String blockTag = 'latest'}) async =>
      znsHex(
        await request('eth_getCode', [znsAddress(address), blockTag]) as String,
        allowEmpty: true,
      );

  Future<String> _call(String to, String data, String blockTag) async => znsHex(
    await request('eth_call', [
          {'to': to, 'data': data},
          blockTag,
        ])
        as String,
    allowEmpty: true,
  );

  Future<BigInt> _uint(String to, String data, String tag) async =>
      _uintResult(await _call(to, data, tag));

  static BigInt _uintResult(String payload) {
    final result = ZnsAbi(payload);
    if (result.bytes.length != 32) {
      throw const ZnsDataException('Invalid registry integer response');
    }
    return result.word(0);
  }

  /// Reads many contracts at one block in a single call. An endpoint whose chain
  /// has no deployed Multicall3 keeps working through serialized reads.
  Future<List<String>> multiCall(
    List<ZnsReadRequest> calls,
    String blockTag,
  ) async {
    if (calls.isEmpty) return const [];
    if (!await _multicallAvailable(blockTag)) {
      final fallback = <String>[];
      for (final call in calls) {
        fallback.add(await _call(call.to, call.data, blockTag));
      }
      return fallback;
    }
    final payload = await _call(
      znsMulticall3Address,
      znsAggregate3Calldata(calls),
      blockTag,
    );
    final results = znsDecodeAggregate3(payload);
    if (results.length != calls.length) {
      throw const ZnsDataException('Malformed batch read response');
    }
    final values = <String>[];
    for (final result in results) {
      if (!result.success) throw _callFailure('eth_call', result.returnData);
      values.add(znsHex(result.returnData, allowEmpty: true));
    }
    return values;
  }

  static final Map<String, bool> _multicallDeployments = {};

  /// Deployment is a property of the chain and endpoint, so one probe serves
  /// every client until the process restarts.
  Future<bool> _multicallAvailable(String blockTag) async {
    final key = '${config.chainId}|${config.rpcUri}';
    final cached = _multicallDeployments[key];
    if (cached != null) return cached;
    final deployed =
        await code(znsMulticall3Address, blockTag: blockTag) != '0x';
    _multicallDeployments[key] = deployed;
    return deployed;
  }

  @visibleForTesting
  static void resetMulticallSupport() => _multicallDeployments.clear();

  Future<void> _canonical(ZnsBlock expected) async {
    if ((await block(znsQuantity(expected.number))).hash != expected.hash) {
      throw const ZnsDataException(
        'Base reorganized during the read. Refresh before continuing.',
      );
    }
  }

  /// Reject stale execution contexts and reorgs before a signature is created.
  Future<void> checkFreshCanonical(ZnsBlock at) async {
    await _canonical(at);
    final age =
        BigInt.from(_now().toUtc().millisecondsSinceEpoch ~/ 1000) -
        at.timestamp;
    if (age > BigInt.from(60) || age < BigInt.from(-5)) {
      throw const ZnsDataException(
        'The Base RPC endpoint returned an outdated block or your device clock is incorrect. '
        'Check the clock or change the Base RPC endpoint in Settings. No transaction was signed.',
      );
    }
  }

  /// Must succeed before quotes, authorization, and signing. The offline signer
  /// additionally requires the same protocol id in its bounded configuration.
  Future<void> verifyProtocol({ZnsBlock? at}) async {
    await verifyChain();
    final snapshot = at ?? await block();
    final tag = znsQuantity(snapshot.number);
    if (await code(config.registryAddress, blockTag: tag) == '0x') {
      throw const ZnsDataException(
        'No ZNS contract exists at the configured address',
      );
    }
    final id = await _call(config.registryAddress, '0xda1f12ab', tag);
    if (id != ZnsNetworkConfig.protocolId) {
      throw const ZnsDataException(
        'The registry does not implement the expected ZNS deposit and reward '
        'policy. Saved commitments and Base assets are safe. Check for a '
        'wallet update, or verify the registry address in wallet Settings → '
        'Names.',
      );
    }
    if (at == null) await _canonical(snapshot);
  }

  Future<ZnsRegistrySnapshot> registrySnapshot(
    String owner, {
    String? commitment,
    BigInt? positionId,
    String? registrationName,
    int offset = 0,
  }) async {
    if (offset < 0) throw const FormatException("Invalid inventory offset");
    owner = znsAddress(owner);
    final at = await block();
    await verifyProtocol(at: at);
    final tag = znsQuantity(at.number), registry = config.registryAddress;
    final tokenAbi = ZnsAbi(await _call(registry, '0x1caa5109', tag));
    if (tokenAbi.bytes.length != 32 ||
        tokenAbi.address(0) != config.tokenAddress) {
      throw const ZnsDataException(
        'The registry payment token does not match this deployment',
      );
    }
    final token = config.tokenAddress;
    if (await code(token, blockTag: tag) == '0x') {
      throw const ZnsDataException('The payment token contract is missing');
    }
    final decimals = await _uint(token, '0x313ce567', tag);
    if (decimals != BigInt.from(config.tokenDecimals)) {
      throw const ZnsDataException(
        'The payment token decimals do not match this deployment',
      );
    }
    final ownerWord = ZnsAbi.addressWord(owner);
    // One batch per block instead of one request per read: public endpoints
    // throttle bursts, and the per-account reads below share this block tag.
    final reads = await multiCall([
      ZnsReadRequest(registry, '0x2e4f692a'),
      ZnsReadRequest(registry, '0x8ccb9ea6'),
      ZnsReadRequest(token, '0x70a08231$ownerWord'),
      ZnsReadRequest(
        token,
        '0xdd62ed3e$ownerWord${ZnsAbi.addressWord(registry)}',
      ),
      ZnsReadRequest(registry, '0x70a08231$ownerWord'),
      ZnsReadRequest(registry, '0x8903ab9d$ownerWord'),
      if (commitment != null)
        ZnsReadRequest(
          registry,
          '0x8b1592b5$ownerWord${znsHex(commitment, bytes: 32).substring(2)}',
        ),
    ], tag);
    final nativeBalance = znsParseQuantity(
      await request('eth_getBalance', [owner, tag]),
    );
    final claims = ZnsAbi(reads[5]);
    if (claims.bytes.length != 64) {
      throw const ZnsDataException('Malformed claimable funds response');
    }
    final minCommitmentAge = _uintResult(reads[0]);
    final maxCommitmentAge = _uintResult(reads[1]);
    final commitmentTimestamp = commitment == null
        ? BigInt.zero
        : _uintResult(reads[6]);
    // Bound discovery to twenty owned NFTs, all from one canonical block.
    final total = _uintResult(reads[4]);
    final start = BigInt.from(offset) >= total ? 0 : offset;
    final count = (total - BigInt.from(start)) > BigInt.from(20)
        ? 20
        : (total - BigInt.from(start)).toInt();
    final ids = [
      for (final value in await multiCall([
        for (var i = 0; i < count; i++)
          ZnsReadRequest(
            registry,
            '0x2f745c59$ownerWord${ZnsAbi.uintWord(BigInt.from(start + i))}',
          ),
      ], tag))
        _uintResult(value),
    ];
    if (ids.toSet().length != ids.length) {
      throw const ZnsDataException('Duplicate registry inventory');
    }
    final decodings = await multiCall([
      for (final id in ids)
        ZnsReadRequest(registry, '0x89097a6a${ZnsAbi.uintWord(id)}'),
    ], tag);
    final positions = <ZnsPosition>[];
    for (var i = 0; i < ids.length; i++) {
      positions.add(_positionFrom(ids[i], ZnsAbi(decodings[i]), at));
    }
    if (positions.any((p) => p.owner != owner || p.retired)) {
      throw const ZnsDataException('Invalid registry NFT inventory');
    }
    var selectedId = positionId;
    if (registrationName != null) {
      selectedId = await _uint(
        registry,
        ZnsAbi.stringCall('0xef6bc988', registrationName),
        tag,
      );
    }
    final ZnsPosition? position;
    if (selectedId != null) {
      position = selectedId == BigInt.zero
          ? null
          : await _positionInfo(selectedId, at);
    } else {
      position = positions.isEmpty ? null : positions.first;
    }
    final quote = registrationName == null
        ? null
        : await _registrationQuote(registrationName, at);
    await _canonical(at);
    if (minCommitmentAge <= BigInt.zero ||
        maxCommitmentAge <= minCommitmentAge) {
      throw const ZnsDataException('Invalid registry commitment window');
    }
    return ZnsRegistrySnapshot(
      block: at,
      owner: owner,
      token: token,
      tokenDecimals: decimals.toInt(),
      registrationQuote: quote,
      minimumCommitmentAge: minCommitmentAge,
      maximumCommitmentAge: maxCommitmentAge,
      nativeBalance: nativeBalance,
      tokenBalance: _uintResult(reads[2]),
      allowance: _uintResult(reads[3]),
      selectedPosition: position,
      positions: positions,
      totalPositions: total,
      positionOffset: start,
      claimablePrincipal: claims.word(0),
      claimableRewardsScaled: claims.word(32),
      commitmentTimestamp: commitmentTimestamp,
    );
  }

  Future<ZnsPosition> _positionInfo(BigInt id, ZnsBlock at) async {
    if (id <= BigInt.zero) {
      throw const FormatException('Position id must be positive');
    }
    return _positionFrom(
      id,
      ZnsAbi(
        await _call(
          config.registryAddress,
          '0x89097a6a${ZnsAbi.uintWord(id)}',
          znsQuantity(at.number),
        ),
      ),
      at,
    );
  }

  ZnsPosition _positionFrom(BigInt id, ZnsAbi result, ZnsBlock at) {
    if (id <= BigInt.zero) {
      throw const FormatException('Position id must be positive');
    }
    final participating = result.word(224), retired = result.word(256);
    final owner = result.address(0),
        registered = result.word(96),
        maturity = result.word(128),
        refresh = result.word(160),
        grace = result.word(192);
    if (participating > BigInt.one ||
        retired > BigInt.one ||
        owner == ZnsNetworkConfig.zeroAddress ||
        registered > maturity ||
        refresh > grace ||
        (participating == BigInt.one && retired == BigInt.one)) {
      throw const ZnsDataException('Invalid ZNS position response');
    }
    return ZnsPosition(
      positionId: id,
      owner: owner,
      name: result.stringAt(0, 1, minimum: 352, maximum: 63),
      unifiedAddress: result.stringAt(0, 2, minimum: 352),
      registeredAt: registered,
      maturityAt: maturity,
      refreshDueAt: refresh,
      graceEndsAt: grace,
      participating: participating == BigInt.one,
      retired: retired == BigInt.one,
      rewardCreditScaled: result.word(288),
      principal: result.word(320),
      block: at,
    );
  }

  Future<ZnsRegistrationQuote> _registrationQuote(
    String name,
    ZnsBlock at,
  ) async {
    znsValidateLabel(name);
    final result = ZnsAbi(
      await _call(
        config.registryAddress,
        ZnsAbi.stringCall('0xe57a4675', name),
        znsQuantity(at.number),
      ),
    );
    if (result.bytes.length != 128 ||
        result.word(0) == BigInt.zero ||
        result.word(32) == BigInt.zero ||
        result.word(64) > BigInt.one) {
      throw const ZnsDataException('Invalid registration quote');
    }
    return ZnsRegistrationQuote(
      minimumDeposit: result.word(0),
      usdTarget: result.word(32),
      pricingMode: result.word(64).toInt(),
      priceUpdatedAt: result.word(96),
    );
  }

  Future<ZnsRegistrationQuote> quoteRegistration(
    String name, {
    ZnsBlock? at,
  }) async {
    final snapshot = at ?? await block();
    if (at == null) await verifyProtocol(at: snapshot);
    final quote = await _registrationQuote(name, snapshot);
    if (at == null) await _canonical(snapshot);
    return quote;
  }

  Future<ZnsPosition> positionInfo(BigInt id) async {
    final at = await block();
    await verifyProtocol(at: at);
    final result = await _positionInfo(id, at);
    await _canonical(at);
    return result;
  }

  Future<ZnsExitPreview> exitPreview(BigInt id) async {
    if (id <= BigInt.zero) {
      throw const FormatException('Position id must be positive');
    }
    final at = await block();
    await verifyProtocol(at: at);
    final result = ZnsAbi(
      await _call(
        config.registryAddress,
        '0xee0611eb${ZnsAbi.uintWord(id)}',
        znsQuantity(at.number),
      ),
    );
    if (result.bytes.length != 160 || result.word(0) > BigInt.one) {
      throw const ZnsDataException('Invalid release preview');
    }
    await _canonical(at);
    return ZnsExitPreview(
      early: result.word(0) == BigInt.one,
      principalReturned: result.word(32),
      rewardsReturned: result.word(64),
      principalForfeited: result.word(96),
      rewardsForfeitedScaled: result.word(128),
      block: at,
    );
  }

  Future<ZnsNameRecord> lookupName(String name) async {
    return _readNameRecord(name, requireRegistrationPolicy: true);
  }

  /// Resolves the public record without loading an owner or checking the
  /// registration economics. Chain, deployed code and canonical reads still
  /// apply; the caller must validate activity, expiry and the Zcash address.
  Future<ZnsNameRecord> readNameRecord(String name) async {
    return _readNameRecord(name, requireRegistrationPolicy: false);
  }

  Future<ZnsNameRecord> _readNameRecord(
    String name, {
    required bool requireRegistrationPolicy,
  }) async {
    if (!RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(name)) {
      throw const FormatException('Invalid normalized ZNS name');
    }
    final at = await block();
    if (requireRegistrationPolicy) {
      await verifyProtocol(at: at);
    } else {
      await verifyChain();
      if (await code(
            config.registryAddress,
            blockTag: znsQuantity(at.number),
          ) ==
          '0x') {
        throw const ZnsDataException(
          'No names registry exists at the configured address.',
        );
      }
    }
    final tag = znsQuantity(at.number);
    final reads = await multiCall([
      ZnsReadRequest(
        config.registryAddress,
        ZnsAbi.stringCall('0x8ee9065d', name),
      ),
      ZnsReadRequest(
        config.registryAddress,
        ZnsAbi.stringCall('0xef6bc988', name),
      ),
    ], tag);
    final result = ZnsAbi(reads[0]);
    final id = _uintResult(reads[1]);
    final owner = result.address(0),
        expiry = result.word(64),
        active = result.word(96);
    if (active > BigInt.one) {
      throw const ZnsDataException('Invalid registry record status');
    }
    final address = result.stringAt(0, 1, minimum: 128);
    await _canonical(at);
    return ZnsNameRecord(
      name: name,
      owner: owner,
      unifiedAddress: address,
      expiresAt: expiry,
      positionId: id,
      active: active == BigInt.one,
      block: at,
    );
  }

  Future<String> simulateCall(ZnsCall call) async {
    await verifyProtocol();
    return znsHex(
      await request('eth_call', [call.toJson(), 'pending']) as String,
      allowEmpty: true,
    );
  }

  Future<BigInt> estimateGas(ZnsCall call) async {
    await verifyChain();
    final gas = znsParseQuantity(
      await request('eth_estimateGas', [call.toJson()]),
    );
    if (gas <= BigInt.zero) {
      throw const ZnsDataException('Base returned an invalid gas estimate');
    }
    return gas;
  }

  Future<BigInt> pendingNonce(String owner) async {
    await verifyChain();
    return znsParseQuantity(
      await request('eth_getTransactionCount', [znsAddress(owner), 'pending']),
    );
  }

  Future<ZnsFeeQuote> feeQuote() async {
    await verifyChain();
    final latest = await block();
    final baseFee = latest.baseFeePerGas;
    if (baseFee == null) {
      throw const ZnsDataException('Base did not report an EIP-1559 base fee');
    }
    final priority = znsParseQuantity(
      await request('eth_maxPriorityFeePerGas', []),
    );
    return ZnsFeeQuote(
      maxFeePerGas: baseFee * BigInt.two + priority,
      maxPriorityFeePerGas: priority,
    );
  }

  /// Caller must persist the locally computed transaction hash and exact signed
  /// bytes BEFORE invoking this method. A timeout is an ambiguous broadcast.
  Future<String> broadcastSignedRaw(
    String raw, {
    required String expectedHash,
  }) async {
    znsHex(raw);
    expectedHash = znsHex(expectedHash, bytes: 32);
    await verifyChain();
    final received = znsHex(
      await request('eth_sendRawTransaction', [raw]) as String,
      bytes: 32,
    );
    if (received != expectedHash) {
      throw const ZnsDataException(
        'Base returned a different transaction hash; reconcile the saved transaction before retrying',
      );
    }
    return received;
  }

  Future<ZnsReceipt?> transactionReceipt(
    String hash, {
    int confirmations = 2,
  }) async {
    if (confirmations < 1) {
      throw ArgumentError('At least one confirmation is required');
    }
    hash = znsHex(hash, bytes: 32);
    await verifyChain();
    final value = await request('eth_getTransactionReceipt', [hash]);
    if (value == null) return null;
    final json = znsObject(value);
    if (znsHex(json['transactionHash'] as String, bytes: 32) != hash) {
      throw const ZnsDataException('Mismatched transaction receipt');
    }
    final height = znsParseQuantity(json['blockNumber']);
    final blockHash = znsHex(json['blockHash'] as String, bytes: 32);
    final status = znsParseQuantity(json['status']);
    if (status > BigInt.one) {
      throw const ZnsDataException('Invalid transaction receipt status');
    }
    final tip = await block();
    final canonical =
        tip.number >= height &&
        (await block(znsQuantity(height))).hash == blockHash;
    // Re-read the receipt after canonical block verification to catch movement
    // between these reads. Short reorgs remain recoverable by subsequent polls.
    final checked = await request('eth_getTransactionReceipt', [hash]);
    final stable =
        checked != null && znsObject(checked)['blockHash'] == json['blockHash'];
    return ZnsReceipt(
      transactionHash: hash,
      blockNumber: height,
      blockHash: blockHash,
      succeeded: status == BigInt.one,
      canonical: canonical && stable,
      confirmations: canonical && stable
          ? tip.number - height + BigInt.one
          : BigInt.zero,
      requiredConfirmations: confirmations,
      from: znsAddress(json['from'] as String),
      to: json['to'] == null ? null : znsAddress(json['to'] as String),
    );
  }
}
