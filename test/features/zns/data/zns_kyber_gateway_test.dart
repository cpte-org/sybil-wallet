import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_abi.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_http_transport.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_kyber_gateway.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_network_config.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_rpc_client.dart';
import 'zns_rpc_client_test.dart' show configuration, owner;

class RouteTransport implements ZnsHttpTransport {
  final inputs = <BigInt>[];
  bool wrongRouter = false, wrongToken = false;
  @override
  void close() {}
  @override
  Future<Object?> request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    final amount = BigInt.parse(uri.queryParameters['amountIn']!);
    inputs.add(amount);
    return {
      'code': 0,
      'data': {
        'routerAddress': wrongRouter
            ? owner
            : ZnsNetworkConfig.canonicalKyberRouter,
        'routeSummary': {
          'tokenIn': ZnsNetworkConfig.nativeEth,
          'tokenOut': wrongToken ? owner : ZnsNetworkConfig.canonicalCbZec,
          'amountIn': amount.toString(),
          'amountOut': (amount ~/ BigInt.from(1000000000)).toString(),
          'extraFee': {'feeAmount': ''},
        },
      },
    };
  }
}

void main() {
  test(
    'token shortfall sizing shrinks oversized first estimate and re-quotes',
    () async {
      final transport = RouteTransport();
      final route = await ZnsKyberGateway(configuration(), transport: transport)
          .quoteForTokenOutput(
            owner: owner,
            requiredTokenUnits: BigInt.from(100),
            maximumWei: BigInt.from(1000000000000000),
          );
      expect(transport.inputs.length, greaterThan(1));
      expect(transport.inputs.last, lessThan(transport.inputs.first));
      expect(route.minimumOutput, greaterThanOrEqualTo(BigInt.from(100)));
      expect(route.minimumOutput, lessThanOrEqualTo(BigInt.from(101)));
      expect(transport.inputs.length, lessThanOrEqualTo(6));
    },
  );
  test(
    'route refuses a changed router, token, or inadequate spending cap',
    () async {
      for (final transport in [
        RouteTransport()..wrongRouter = true,
        RouteTransport()..wrongToken = true,
        RouteTransport(),
      ]) {
        await expectLater(
          ZnsKyberGateway(
            configuration(),
            transport: transport,
          ).quoteForTokenOutput(
            owner: owner,
            requiredTokenUnits: BigInt.from(10000),
            maximumWei: BigInt.from(100),
          ),
          throwsA(isA<Exception>()),
        );
      }
    },
  );
  test(
    'independent provider calldata verifies outer recipient value and min output',
    () {
      final fixture =
          jsonDecode(
                File(
                  'rust/zns-core/tests/fixtures/kyber-native-cbzec.json',
                ).readAsStringSync(),
              )
              as Map;
      final gateway = ZnsKyberGateway(
        configuration(),
        transport: RouteTransport(),
      );
      final value = BigInt.parse(fixture['value'] as String),
          recipient = fixture['owner'] as String;
      final data = fixture['data'] as String;
      ZnsCall call({String? from, String? encoded, BigInt? amount}) => ZnsCall(
        from: from ?? recipient,
        to: configuration().kyberRouterAddress,
        data: encoded ?? data,
        value: amount ?? value,
      );
      validate(ZnsCall call) => gateway.validateSwapCall(
        call,
        requiredOutput: BigInt.from(210000),
        maximumWei: value,
        minimumSlippageOutput: BigInt.from(210000),
        expectedOutput: BigInt.from(218300),
      );
      expect(
        validate(call()).minimumOutput,
        greaterThanOrEqualTo(BigInt.from(210000)),
      );
      expect(() => validate(call(from: owner)), throwsA(isA<Exception>()));
      expect(
        () => validate(call(amount: value + BigInt.one)),
        throwsA(isA<Exception>()),
      );
      final abi = ZnsAbi('0x${data.substring(10)}');
      final execution = abi.offset(0, 0, minimum: 32),
          desc = abi.offset(32, 3, minimum: 160);
      for (final offset in [execution + 32, desc + 256, desc + 288]) {
        final start = 10 + offset * 2;
        final altered = data.replaceRange(
          start,
          start + 64,
          ZnsAbi.uintWord(BigInt.one),
        );
        expect(
          () => validate(call(encoded: altered)),
          throwsA(isA<Exception>()),
        );
      }
    },
  );
}
