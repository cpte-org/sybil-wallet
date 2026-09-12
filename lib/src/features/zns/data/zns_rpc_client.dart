import 'zns_abi.dart';
import '../domain/zns_operation.dart';
import 'zns_http_transport.dart';
import 'zns_network_config.dart';

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
  ZnsRpcClient(this.config, {ZnsHttpTransport? transport})
    : _transport = transport ?? ZnsPolicyHttpTransport();
  final ZnsNetworkConfig config;
  final ZnsHttpTransport _transport;
  var _id = 0;
  void close() => _transport.close();

  Future<Object?> request(String method, List<Object?> params) async {
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
      // Do not propagate provider text: it can contain calldata and addresses.
      throw ZnsDataException(
        'Base RPC $method failed. Refresh before retrying.',
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

  Future<BigInt> _uint(String to, String data, String tag) async {
    final result = ZnsAbi(await _call(to, data, tag));
    if (result.bytes.length != 32) {
      throw const ZnsDataException('Invalid registry integer response');
    }
    return result.word(0);
  }

  Future<void> _canonical(ZnsBlock expected) async {
    if ((await block(znsQuantity(expected.number))).hash != expected.hash) {
      throw const ZnsDataException(
        'Base reorganized during the read. Refresh before continuing.',
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
    final values = await Future.wait([
      _uint(registry, '0x2e4f692a', tag),
      _uint(registry, '0x8ccb9ea6', tag),
      request('eth_getBalance', [owner, tag]).then(znsParseQuantity),
      _uint(token, '0x70a08231$ownerWord', tag),
      _uint(token, '0xdd62ed3e$ownerWord${ZnsAbi.addressWord(registry)}', tag),
      _uint(registry, '0x70a08231$ownerWord', tag),
      commitment == null
          ? Future.value(BigInt.zero)
          : _uint(
              registry,
              '0x8b1592b5$ownerWord${znsHex(commitment, bytes: 32).substring(2)}',
              tag,
            ),
    ]);
    final claims = ZnsAbi(await _call(registry, '0x8903ab9d$ownerWord', tag));
    if (claims.bytes.length != 64) {
      throw const ZnsDataException('Malformed claimable funds response');
    }
    // Bound discovery to twenty owned NFTs, all from one canonical block.
    final total = values[5];
    final start = BigInt.from(offset) >= total ? 0 : offset;
    final count = (total - BigInt.from(start)) > BigInt.from(20)
        ? 20
        : (total - BigInt.from(start)).toInt();
    final ids = await Future.wait(
      List.generate(
        count,
        (i) => _uint(
          registry,
          '0x2f745c59$ownerWord${ZnsAbi.uintWord(BigInt.from(start + i))}',
          tag,
        ),
      ),
    );
    if (ids.toSet().length != ids.length) {
      throw const ZnsDataException('Duplicate registry inventory');
    }
    final positions = await Future.wait(ids.map((id) => _positionInfo(id, at)));
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
    if (values[0] <= BigInt.zero || values[1] <= values[0]) {
      throw const ZnsDataException('Invalid registry commitment window');
    }
    return ZnsRegistrySnapshot(
      block: at,
      owner: owner,
      token: token,
      tokenDecimals: decimals.toInt(),
      registrationQuote: quote,
      minimumCommitmentAge: values[0],
      maximumCommitmentAge: values[1],
      nativeBalance: values[2],
      tokenBalance: values[3],
      allowance: values[4],
      selectedPosition: position,
      positions: positions,
      totalPositions: total,
      positionOffset: start,
      claimablePrincipal: claims.word(0),
      claimableRewardsScaled: claims.word(32),
      commitmentTimestamp: values[6],
    );
  }

  Future<ZnsPosition> _positionInfo(BigInt id, ZnsBlock at) async {
    if (id <= BigInt.zero) {
      throw const FormatException('Position id must be positive');
    }
    final result = ZnsAbi(
      await _call(
        config.registryAddress,
        '0x89097a6a${ZnsAbi.uintWord(id)}',
        znsQuantity(at.number),
      ),
    );
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

  Future<ZnsRegistrationQuote> quoteRegistration(String name) async {
    final at = await block();
    await verifyProtocol(at: at);
    final quote = await _registrationQuote(name, at);
    await _canonical(at);
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
    if (!RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(name)) {
      throw const FormatException('Invalid normalized ZNS name');
    }
    final at = await block();
    await verifyProtocol(at: at);
    final tag = znsQuantity(at.number);
    final result = ZnsAbi(
      await _call(
        config.registryAddress,
        ZnsAbi.stringCall('0x8ee9065d', name),
        tag,
      ),
    );
    final id = await _uint(
      config.registryAddress,
      ZnsAbi.stringCall('0xef6bc988', name),
      tag,
    );
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
