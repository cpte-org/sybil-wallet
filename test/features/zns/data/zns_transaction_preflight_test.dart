import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_abi.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_http_transport.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_network_config.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_rpc_client.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_transaction_preflight.dart';

String word(int n) => ZnsAbi.uintWord(BigInt.from(n));
const owner = '0x2222222222222222222222222222222222222222';
const registry = '0x1111111111111111111111111111111111111111';

class Fixture implements ZnsHttpTransport {
  final requests = <Map<String, Object?>>[];
  bool reorg = false, pendingRead = false;
  int time = 1000;
  int? failedStep;
  void Function()? afterSimulation;
  Map? simulation;
  @override
  void close() {}
  @override
  Future<Object?> request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    requests.add(body!);
    final params = body['params'] as List;
    if (params.contains('pending')) pendingRead = true;
    final rpc = body['method'];
    Object? result;
    switch (rpc) {
      case 'eth_chainId':
        result = '0x2105';
      case 'eth_getBlockByNumber':
        result = {
          'number': '0xa',
          'hash': '0x${(reorg && params[0] != 'latest' ? '44' : '33') * 32}',
          'timestamp': znsQuantity(BigInt.from(time)),
          'baseFeePerGas': '0x7',
        };
      case 'eth_getCode':
        result = '0x6000';
      case 'eth_call' || 'eth_estimateGas':
        final call = params[0] as Map;
        final data = call['data'] as String;
        if (data == '0xda1f12ab') {
          result = ZnsNetworkConfig.protocolId;
        } else if (data.startsWith('0xe57a4675')) {
          // Model the incident: pending state + older context gives fallback.
          result =
              '0x${word(500)}${word(100)}${word(params[1] == 'pending' ? 1 : 0)}${word(time)}';
        } else {
          simulation = call;
          afterSimulation?.call();
          if (failedStep != null) {
            return {
              'jsonrpc': '2.0',
              'id': body['id'],
              'error': {
                'code': 3,
                'message': 'DO NOT LOG PROVIDER CONTENT',
                'data':
                    '0x5c0dee5d${word(failedStep!)}${word(64)}${word(4)}${'7c9c6e8f'.padRight(64, '0')}',
              },
            };
          }
          result = rpc == 'eth_estimateGas' ? '0x10000' : '0x';
        }
      default:
        throw StateError('Unexpected $rpc');
    }
    return {'jsonrpc': '2.0', 'id': body['id'], 'result': result};
  }
}

void main() {
  late Fixture fixture;
  late ZnsTransactionPreflight preflight;
  late List<Map<String, Object?>> events;
  var authorized = true;
  void guard() {
    if (!authorized) throw StateError('Wallet locked');
  }

  setUp(() {
    fixture = Fixture();
    events = [];
    authorized = true;
    final rpc = ZnsRpcClient(
      ZnsNetworkConfig(
        chainId: 8453,
        rpcUri: Uri.parse('https://rpc.example/SECRET'),
        registryAddress: registry,
      ),
      transport: fixture,
      requestSpacing: Duration.zero,
      now: () => DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
    );
    addTearDown(rpc.close);
    preflight = ZnsTransactionPreflight(rpc, diagnostic: events.add);
  });
  Future<BigInt?> run({bool finalCall = false, bool swap = true}) =>
      preflight.run(
        call: ZnsCall(from: owner, to: owner, data: '0xabcdef01'),
        ensureAuthorized: guard,
        hasAtomicSwap: swap,
        registrationName: 'alice',
        checkQuote: (q) => expect(q.pricingMode, 0),
        overrides: {
          owner: {'code': '0x6000'},
        },
        gasLimit: finalCall ? BigInt.from(90000) : null,
        fees: finalCall
            ? ZnsFeeQuote(
                maxFeePerGas: BigInt.from(20),
                maxPriorityFeePerGas: BigInt.two,
              )
            : null,
      );

  test(
    'quote, estimate and exact final call use coherent canonical blocks, never pending',
    () async {
      expect(await run(), BigInt.from(65536));
      await run(finalCall: true);
      expect(fixture.pendingRead, isFalse);
      for (final request in fixture.requests.where(
        (r) => [
          'eth_call',
          'eth_estimateGas',
          'eth_getCode',
        ].contains(r['method']),
      )) {
        expect((request['params'] as List)[1], '0xa');
      }
      expect(fixture.simulation!['gas'], '0x15f90');
      expect(fixture.simulation!['maxFeePerGas'], '0x14');
      expect(fixture.simulation!['maxPriorityFeePerGas'], '0x2');
      final log = jsonEncode(events);
      for (final sensitive in [
        'alice',
        owner,
        'abcdef01',
        'SECRET',
        'PROVIDER CONTENT',
      ]) {
        expect(log, isNot(contains(sensitive)));
      }
      expect(events.last['blockTimestamp'], '1000');
    },
  );

  test('canonical hash changing after simulation rejects the result', () async {
    fixture.afterSimulation = () => fixture.reorg = true;
    await expectLater(run(finalCall: true), throwsA(isA<ZnsDataException>()));
    expect(events.last['outcome'], 'rejected');
  });
  for (final timestamp in [939, 1006]) {
    test(
      'stale or future timestamp $timestamp cannot authorize signing',
      () async {
        fixture.time = timestamp;
        await expectLater(
          run(finalCall: true),
          throwsA(isA<ZnsDataException>()),
        );
      },
    );
  }
  test('locking while simulation is in flight rejects its result', () async {
    fixture.afterSimulation = () => authorized = false;
    await expectLater(run(finalCall: true), throwsStateError);
  });
  test('only swap step zero qualifies for unsigned route refresh', () async {
    fixture.failedStep = 0;
    await expectLater(run(), throwsA(isA<ZnsUnsignedSwapRejected>()));
    await expectLater(run(swap: false), throwsA(isA<ZnsRpcRevert>()));
    fixture.failedStep = 2;
    await expectLater(run(), throwsA(isA<ZnsRpcRevert>()));
  });
}
