import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_abi.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_http_transport.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_network_config.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_rpc_client.dart';

String nested(String selector, {int offset = 64, int length = 4}) =>
    '0x5c0dee5d${ZnsAbi.uintWord(BigInt.from(2))}'
    '${ZnsAbi.uintWord(BigInt.from(offset))}'
    '${ZnsAbi.uintWord(BigInt.from(length))}'
    '${selector.substring(2).padRight(64, '0')}';

class _RevertTransport implements ZnsHttpTransport {
  _RevertTransport(this.data);
  final Object? data;
  int calls = 0;
  @override
  void close() {}
  @override
  Future<Object?> request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    calls++;
    return {
      'jsonrpc': '2.0',
      'id': body!['id'],
      'error': {
        'code': 3,
        'message': 'Private provider URL and calldata must never appear.',
        'data': data,
      },
    };
  }
}

void main() {
  Future<void> expectFailure(
    Object? data,
    String expected, {
    String method = 'eth_call',
  }) async {
    final transport = _RevertTransport(data);
    final rpc = ZnsRpcClient(
      ZnsNetworkConfig(
        chainId: 8453,
        rpcUri: Uri.parse('https://rpc.example/private-api-key'),
        registryAddress: '0x1111111111111111111111111111111111111111',
      ),
      transport: transport,
      requestSpacing: Duration.zero,
    );
    addTearDown(rpc.close);
    await expectLater(
      rpc.request(method, const []),
      throwsA(
        isA<ZnsDataException>().having(
          (e) => e.message,
          'safe message',
          expected,
        ),
      ),
    );
    expect(
      transport.calls,
      1,
      reason: 'Contract reverts never retry automatically.',
    );
  }

  const pricing =
      'Registration pricing changed. Review the updated bond and pricing mode before continuing.';
  const limit =
      'The required registration bond exceeds the reviewed limit. Review the updated bond before continuing.';
  const generic = 'Base RPC eth_call failed. Refresh before retrying.';

  test(
    'direct and batch-wrapped pricing changes require fresh review',
    () async {
      await expectFailure('0x02f378dc', pricing);
      await expectFailure(nested('0x02f378dc'), pricing);
      await expectFailure(
        nested('0x02f378dc'),
        pricing,
        method: 'eth_estimateGas',
      );
    },
  );

  test(
    'bond limit, quote expiry and oracle gas failures use fixed safe messages',
    () async {
      await expectFailure('0x6adf7e28', limit);
      await expectFailure(nested('0x6adf7e28'), limit);
      await expectFailure(
        '0x8727a7f9',
        'The registration quote expired. Review again before continuing.',
      );
      await expectFailure(
        nested('0x8730528d'),
        'The name service could not verify pricing with the available gas. Review again before continuing.',
      );
    },
  );

  test(
    'unknown, nested again or malformed reasons stay generic without provider content',
    () async {
      for (final data in <Object?>[
        null,
        '0xdeadbeef',
        '0x02f378dc00',
        '0x5c0dee5d',
        nested('0x02f378dc', offset: 32),
        nested('0x02f378dc', length: 8),
        '${nested('0x02f378dc').substring(0, 264)}ff',
        nested('0x5c0dee5d'),
        '0x${'ab' * 5000}',
        {'data': '0x02f378dc', 'message': 'Private provider text'},
      ]) {
        await expectFailure(data, generic);
      }
    },
  );

  test(
    'signed submission errors are not reinterpreted as safe preflight failures',
    () async {
      await expectFailure(
        nested('0x02f378dc'),
        'Base RPC eth_sendRawTransaction failed. Refresh before retrying.',
        method: 'eth_sendRawTransaction',
      );
    },
  );
}
