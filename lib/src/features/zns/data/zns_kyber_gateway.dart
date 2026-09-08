import 'dart:convert';
import 'zns_abi.dart';
import 'zns_http_transport.dart';
import 'zns_network_config.dart';
import 'zns_rpc_client.dart';

class ZnsSwapRoute {
  const ZnsSwapRoute({
    required this.owner,
    required this.amountInWei,
    required this.expectedOutput,
    required this.minimumOutput,
    required this.requiredOutput,
    required this.slippageBps,
    required this.expiresAt,
    required this.router,
    required this.routeSummary,
  });
  final String owner, router;
  final BigInt amountInWei, expectedOutput, minimumOutput, requiredOutput;
  final int slippageBps;
  final DateTime expiresAt;
  final Map<String, Object?> routeSummary;
}

class ZnsSwapCall {
  const ZnsSwapCall({
    required this.call,
    required this.minimumOutput,
    required this.expectedOutput,
    required this.deadline,
    required this.executor,
  });
  final ZnsCall call;
  final BigInt minimumOutput, expectedOutput;
  final DateTime deadline;
  final String executor;

  /// The supported executor carries opaque packed routing data. The registry's
  /// atomic executor MUST enforce deadline on chain. A standalone swap only has
  /// local pre-broadcast expiry plus the router-enforced amount/minimum bounds.
  bool get routerDeadlineVerified => false;
  Map<String, Object?> toOperationJson() => {
    'kind': 'swap',
    'data': call.data,
    'value': call.value.toString(),
    'minimumOutput': minimumOutput.toString(),
  };
}

class ZnsKyberGateway {
  ZnsKyberGateway(
    this.config, {
    ZnsHttpTransport? transport,
    DateTime Function()? now,
    Set<String> allowedExecutors = const {
      '0x8f10b468b06c6fd214b65f87778827f7d113f996',
    },
  }) : _transport = transport ?? ZnsPolicyHttpTransport(),
       _now = now ?? DateTime.now,
       _allowedExecutors = allowedExecutors.map(znsAddress).toSet();
  final ZnsNetworkConfig config;
  final ZnsHttpTransport _transport;
  final DateTime Function() _now;
  final Set<String> _allowedExecutors;
  void close() => _transport.close();
  Uri _endpoint(String path, [Map<String, String>? query]) => Uri.parse(
    '${config.kyberBaseUri.toString().replaceFirst(RegExp(r'/+$'), '')}$path',
  ).replace(queryParameters: query);
  Map<String, Object?> _data(Object? value) {
    final body = znsObject(value);
    if (body['code'] != 0) {
      throw const ZnsDataException(
        'No usable ETH to cbZEC route is currently available',
      );
    }
    return znsObject(body['data']);
  }

  BigInt _amount(Object? value) => znsDecimalUnits(value as String, 0);

  Future<ZnsSwapRoute> quoteExactInput({
    required String owner,
    required BigInt amountInWei,
    required BigInt requiredTokenUnits,
    int slippageBps = 100,
  }) async {
    owner = znsAddress(owner);
    if (amountInWei <= BigInt.zero ||
        requiredTokenUnits <= BigInt.zero ||
        slippageBps < 0 ||
        slippageBps > 300) {
      throw ArgumentError('Invalid cbZEC swap amount or slippage');
    }
    final data = _data(
      await _transport.request(
        'GET',
        _endpoint('/api/v1/routes', {
          'tokenIn': ZnsNetworkConfig.nativeEth,
          'tokenOut': config.tokenAddress,
          'amountIn': amountInWei.toString(),
        }),
      ),
    );
    final router = znsAddress(data['routerAddress'] as String);
    if (router != config.kyberRouterAddress) {
      throw const ZnsDataException('Kyber returned an unapproved router');
    }
    final summary = znsObject(data['routeSummary']);
    if (znsAddress(summary['tokenIn'] as String) !=
            ZnsNetworkConfig.nativeEth ||
        znsAddress(summary['tokenOut'] as String) != config.tokenAddress ||
        _amount(summary['amountIn']) != amountInWei) {
      throw const ZnsDataException(
        'Kyber route does not match the requested native ETH to cbZEC swap',
      );
    }
    final fee = summary['extraFee'];
    if (fee != null) {
      final amount = znsObject(fee)['feeAmount'];
      if (amount != null && amount != '' && amount != '0') {
        throw const ZnsDataException('Unexpected extra swap fee');
      }
    }
    final expected = _amount(summary['amountOut']);
    if (expected <= BigInt.zero) {
      throw const ZnsDataException('Kyber returned zero cbZEC output');
    }
    final minimum =
        expected * BigInt.from(10000 - slippageBps) ~/ BigInt.from(10000);
    return ZnsSwapRoute(
      owner: owner,
      amountInWei: amountInWei,
      expectedOutput: expected,
      minimumOutput: minimum,
      requiredOutput: requiredTokenUnits,
      slippageBps: slippageBps,
      expiresAt: _now().toUtc().add(const Duration(minutes: 2)),
      router: router,
      routeSummary: Map<String, Object?>.unmodifiable(
        jsonDecode(jsonEncode(summary)) as Map<String, dynamic>,
      ),
    );
  }

  /// Bounded integer-only sizing: re-quotes each candidate so a proportional
  /// estimate can never masquerade as a guaranteed output or funding amount.
  Future<ZnsSwapRoute> quoteForTokenOutput({
    required String owner,
    required BigInt requiredTokenUnits,
    required BigInt maximumWei,
    int slippageBps = 100,
  }) async {
    if (maximumWei <= BigInt.zero) {
      throw ArgumentError('A positive swap spending cap is required');
    }
    var candidate = maximumWei < BigInt.from(100000000000000)
        ? maximumWei
        : BigInt.from(100000000000000);
    for (var attempt = 0; attempt < 6; attempt++) {
      final route = await quoteExactInput(
        owner: owner,
        amountInWei: candidate,
        requiredTokenUnits: requiredTokenUnits,
        slippageBps: slippageBps,
      );
      if (route.minimumOutput >= requiredTokenUnits) {
        if (attempt < 5 &&
            route.minimumOutput * BigInt.from(100) >
                requiredTokenUnits * BigInt.from(101)) {
          final smaller =
              (candidate * requiredTokenUnits * BigInt.from(10050) +
                  route.minimumOutput * BigInt.from(10000) -
                  BigInt.one) ~/
              (route.minimumOutput * BigInt.from(10000));
          if (smaller > BigInt.zero && smaller < candidate) {
            candidate = smaller;
            continue;
          }
        }
        return route;
      }
      if (candidate >= maximumWei || route.minimumOutput == BigInt.zero) break;
      // Small headroom accounts for integer rounding and movement between
      // successive quotes. It is still capped and then verified by re-quote.
      final next =
          (candidate * requiredTokenUnits * BigInt.from(10050) +
              route.minimumOutput * BigInt.from(10000) -
              BigInt.one) ~/
          (route.minimumOutput * BigInt.from(10000));
      candidate = next > maximumWei ? maximumWei : next;
    }
    throw const ZnsDataException(
      'The approved ETH spending cap cannot currently buy enough cbZEC',
    );
  }

  Future<ZnsSwapCall> build(
    ZnsSwapRoute route, {
    required BigInt maximumWei,
    DateTime? deadline,
  }) async {
    final now = _now().toUtc();
    final expires = (deadline ?? now.add(const Duration(minutes: 10))).toUtc();
    if (!route.expiresAt.isAfter(now) ||
        !expires.isAfter(now) ||
        expires.isAfter(now.add(const Duration(minutes: 20))) ||
        route.amountInWei > maximumWei ||
        route.minimumOutput < route.requiredOutput) {
      throw const ZnsDataException('Refresh the cbZEC quote before continuing');
    }
    final data = _data(
      await _transport.request(
        'POST',
        _endpoint('/api/v1/route/build'),
        body: {
          'routeSummary': route.routeSummary,
          'sender': route.owner,
          'recipient': route.owner,
          'slippageTolerance': route.slippageBps,
          'deadline': expires.millisecondsSinceEpoch ~/ 1000,
          'enableGasEstimation': false,
          'source': 'vizor-zns',
        },
      ),
    );
    final router = znsAddress(data['routerAddress'] as String);
    if (router != route.router ||
        router != config.kyberRouterAddress ||
        _amount(data['amountIn']) != route.amountInWei) {
      throw const ZnsDataException(
        'Kyber build changed the approved router or ETH amount',
      );
    }
    final expected = _amount(data['amountOut']);
    final floor =
        expected * BigInt.from(10000 - route.slippageBps) ~/ BigInt.from(10000);
    if (floor < route.requiredOutput) {
      throw const ZnsDataException(
        'The updated swap output is below the registration cost',
      );
    }
    final call = ZnsCall(
      from: route.owner,
      to: router,
      data: data['data'] as String,
      value: route.amountInWei,
    );
    final decoded = validateSwapCall(
      call,
      requiredOutput: route.requiredOutput,
      maximumWei: maximumWei,
      minimumSlippageOutput: floor,
      expectedOutput: expected,
    );
    if (!_now().toUtc().isBefore(expires)) {
      throw const ZnsDataException('The swap quote expired while building');
    }
    return ZnsSwapCall(
      call: call,
      minimumOutput: decoded.minimumOutput,
      expectedOutput: expected,
      deadline: expires,
      executor: decoded.executor,
    );
  }

  /// Validates the on-chain enforced outer description, not provider metadata.
  /// Source: issuer-verified MetaAggregationRouterV2 on BaseScan; native value
  /// equals desc.amount and _checkReturnAmount verifies destination balance delta.
  ({BigInt minimumOutput, String executor}) validateSwapCall(
    ZnsCall call, {
    required BigInt requiredOutput,
    required BigInt maximumWei,
    required BigInt minimumSlippageOutput,
    required BigInt expectedOutput,
  }) {
    if (call.to != config.kyberRouterAddress ||
        call.value <= BigInt.zero ||
        call.value > maximumWei ||
        !call.data.startsWith('0xe21fd0e9') ||
        call.data.length > 131074) {
      throw const ZnsDataException(
        'Unsupported swap target, selector or ETH amount',
      );
    }
    final abi = ZnsAbi('0x${call.data.substring(10)}');
    final execution = abi.offset(0, 0, minimum: 32);
    final executor = abi.address(execution);
    if (!_allowedExecutors.contains(executor) ||
        abi.address(execution + 32) != ZnsNetworkConfig.zeroAddress) {
      throw const ZnsDataException(
        'Unsupported Kyber executor or additional approval target',
      );
    }
    final target = abi.dynamicBytes(abi.offset(execution, 2, minimum: 160));
    if (target.isEmpty) {
      throw const ZnsDataException('Missing swap execution data');
    }
    final desc = abi.offset(execution, 3, minimum: 160);
    if (abi.address(desc) != ZnsNetworkConfig.nativeEth ||
        abi.address(desc + 32) != config.tokenAddress ||
        abi.address(desc + 192) != call.from ||
        abi.word(desc + 224) != call.value) {
      throw const ZnsDataException(
        'Swap calldata changed the token, recipient or amount',
      );
    }
    for (final index in [2, 3, 4, 5]) {
      if (abi.word(abi.offset(desc, index, minimum: 352)) != BigInt.zero) {
        throw const ZnsDataException(
          'Unexpected swap source distribution or fee recipients',
        );
      }
    }
    final flags = abi.word(desc + 288);
    if (flags != BigInt.zero && flags != BigInt.from(512)) {
      throw const ZnsDataException('Unsupported swap flags');
    }
    if (abi.dynamicBytes(abi.offset(desc, 10, minimum: 352)).isNotEmpty) {
      throw const ZnsDataException('Unexpected token permit');
    }
    final minimum = abi.word(desc + 256);
    if (minimum < requiredOutput ||
        minimum < minimumSlippageOutput ||
        minimum > expectedOutput ||
        minimum <= BigInt.zero) {
      throw const ZnsDataException(
        'Swap calldata does not guarantee enough cbZEC',
      );
    }
    // Also bound the final dynamic field so malformed offsets do not reach the
    // signer even when economically relevant fields happen to look correct.
    abi.dynamicBytes(abi.offset(execution, 4, minimum: 160));
    return (minimumOutput: minimum, executor: executor);
  }
}
