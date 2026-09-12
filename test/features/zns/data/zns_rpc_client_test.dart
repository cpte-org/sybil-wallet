import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_abi.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_http_transport.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_network_config.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_rpc_client.dart';

const owner = '0x2222222222222222222222222222222222222222';
const registry = '0x1111111111111111111111111111111111111111';
final blockHash = '0x${'33' * 32}';
final transactionHash = '0x${'44' * 32}';
ZnsNetworkConfig configuration() => ZnsNetworkConfig(
  chainId: 8453,
  rpcUri: Uri.parse('https://rpc.example'),
  registryAddress: registry,
);
String word(int value) => ZnsAbi.uintWord(BigInt.from(value));
String tuple(List<Object> values) {
  var tail = '';
  final heads = <String>[];
  for (final value in values) {
    if (value is String && !value.startsWith('0x')) {
      final bytes = utf8.encode(value);
      heads.add(word(values.length * 32 + tail.length ~/ 2));
      tail +=
          word(bytes.length) +
          bytes
              .map((v) => v.toRadixString(16).padLeft(2, '0'))
              .join()
              .padRight(((bytes.length + 31) ~/ 32) * 64, '0');
    } else if (value is String) {
      heads.add(value.substring(2).padLeft(64, '0'));
    } else if (value is BigInt) {
      heads.add(ZnsAbi.uintWord(value));
    } else {
      heads.add(word(value as int));
    }
  }
  return '0x${heads.join()}$tail';
}

class RpcFixture implements ZnsHttpTransport {
  final selectors = <String>[];
  final readTags = <String>[];
  bool incompatible = false,
      reorganize = false,
      wrongToken = false,
      wrongId = false,
      receiptReorg = false;
  int receiptReads = 0;
  int inventorySize = 1, lookupId = 42;
  bool enumerate = false;
  Object? overridePosition;
  @override
  void close() {}
  @override
  Future<Object?> request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    final rpc = body!['method'] as String;
    final params = body['params'] as List;
    Object? result;
    switch (rpc) {
      case 'eth_chainId':
        result = '0x2105';
      case 'eth_getCode':
        result = '0x6000';
        readTags.add(params[1] as String);
      case 'eth_getBlockByNumber':
        result = {
          'number': '0xa',
          'hash': reorganize && params[0] != 'latest'
              ? '0x${'55' * 32}'
              : blockHash,
          'timestamp': '0x72',
          'baseFeePerGas': '0x7',
        };
      case 'eth_getBalance':
        result = '0x123';
        readTags.add(params[1] as String);
      case 'eth_getTransactionReceipt':
        receiptReads++;
        result = receiptReorg && receiptReads > 1
            ? null
            : {
                'transactionHash': transactionHash,
                'blockNumber': '0x9',
                'blockHash': blockHash,
                'status': '0x1',
                'from': owner,
                'to': registry,
              };
      case 'eth_call':
        readTags.add(params[1] as String);
        final selector = (params[0] as Map)['data'].toString().substring(0, 10);
        selectors.add(selector);
        result = switch (selector) {
          '0xda1f12ab' =>
            incompatible ? '0x${word(0)}' : ZnsNetworkConfig.protocolId,
          '0x1caa5109' => tuple([
            wrongToken ? owner : ZnsNetworkConfig.canonicalCbZec,
          ]),
          '0x313ce567' => tuple([8]),
          '0xe57a4675' => tuple([500, 100, 0, 100]),
          '0x2e4f692a' => tuple([60]),
          '0x8ccb9ea6' => tuple([86400]),
          '0x70a08231' => tuple([
            (params[0] as Map)['to'] == registry ? inventorySize : 200,
          ]),
          '0xdd62ed3e' => tuple([500]),
          '0x2f745c59' => tuple([
            enumerate
                ? 1 +
                      int.parse(
                        (params[0] as Map)['data'].toString().substring(74),
                        radix: 16,
                      )
                : 42,
          ]),
          '0x8903ab9d' => tuple([
            25,
            ZnsNetworkConfig.rewardScale + BigInt.one,
          ]),
          '0x89097a6a' =>
            overridePosition ??
                tuple([
                  owner,
                  'alice',
                  'u1publicfixture',
                  100,
                  115,
                  110,
                  120,
                  1,
                  0,
                  ZnsNetworkConfig.rewardScale + BigInt.from(7),
                  750,
                ]),
          '0xee0611eb' => tuple([
            1,
            0,
            0,
            500,
            ZnsNetworkConfig.rewardScale + BigInt.from(7),
          ]),
          '0x8ee9065d' => tuple([owner, 'u1publicfixture', 120, 1]),
          '0xef6bc988' => tuple([lookupId]),
          _ => throw StateError('Unexpected selector $selector'),
        };
      default:
        throw StateError('Unexpected RPC $rpc');
    }
    return {
      'jsonrpc': '2.0',
      'id': wrongId ? -1 : body['id'],
      'result': result,
    };
  }
}

void main() {
  test(
    'inventory pages are bounded and operation identity is independent of the page',
    () async {
      final transport = RpcFixture()
        ..inventorySize = 23
        ..enumerate = true;
      final rpc = ZnsRpcClient(configuration(), transport: transport);
      final first = await rpc.registrySnapshot(owner);
      expect(first.positions, hasLength(20));
      expect(first.totalPositions, BigInt.from(23));
      expect(
        transport.selectors.where((s) => s == '0x2f745c59'),
        hasLength(20),
      );
      final second = await rpc.registrySnapshot(
        owner,
        offset: 20,
        positionId: BigInt.one,
      );
      expect(second.positions.map((p) => p.positionId), [
        BigInt.from(21),
        BigInt.from(22),
        BigInt.from(23),
      ]);
      expect(second.selectedPosition!.positionId, BigInt.one);
      transport.lookupId = 77;
      final registering = await rpc.registrySnapshot(
        owner,
        registrationName: 'bob',
      );
      expect(registering.selectedPosition!.positionId, BigInt.from(77));
      transport.lookupId = 0;
      expect(
        (await rpc.registrySnapshot(
          owner,
          registrationName: 'bob',
        )).selectedPosition,
        isNull,
      );
      expect((await rpc.registrySnapshot(owner, offset: 40)).positionOffset, 0);
      expect(transport.readTags.every((tag) => tag == '0xa'), isTrue);
    },
  );
  test(
    'duplicate inventory entries and foreign owners are rejected; empty address is valid',
    () async {
      final duplicate = RpcFixture()..inventorySize = 2;
      await expectLater(
        ZnsRpcClient(
          configuration(),
          transport: duplicate,
        ).registrySnapshot(owner),
        throwsA(isA<ZnsDataException>()),
      );
      final foreign = RpcFixture()
        ..overridePosition = tuple([
          registry,
          'alice',
          '',
          100,
          115,
          110,
          120,
          1,
          0,
          BigInt.zero,
          750,
        ]);
      await expectLater(
        ZnsRpcClient(
          configuration(),
          transport: foreign,
        ).registrySnapshot(owner),
        throwsA(isA<ZnsDataException>()),
      );
      final received = RpcFixture()
        ..overridePosition = tuple([
          owner,
          'alice',
          '',
          100,
          115,
          110,
          120,
          1,
          0,
          BigInt.zero,
          750,
        ]);
      expect(
        (await ZnsRpcClient(
          configuration(),
          transport: received,
        ).registrySnapshot(owner)).selectedPosition!.unifiedAddress,
        '',
      );
    },
  );

  test(
    'snapshot reads name quote, actual principal and scaled claims at one canonical block',
    () async {
      final transport = RpcFixture();
      final snapshot = await ZnsRpcClient(
        configuration(),
        transport: transport,
      ).registrySnapshot(owner, registrationName: 'alice');
      expect(snapshot.registrationQuote!.minimumDeposit, BigInt.from(500));
      expect(snapshot.registrationQuote!.usdTarget, BigInt.from(100));
      expect(snapshot.registrationQuote!.pricingMode, 0);
      expect(snapshot.selectedPosition!.principal, BigInt.from(750));
      expect(snapshot.claimablePrincipal, BigInt.from(25));
      expect(
        snapshot.claimableRewardsScaled,
        ZnsNetworkConfig.rewardScale + BigInt.one,
      );
      expect(snapshot.selectedPosition!.maturityAt, BigInt.from(115));
      expect(snapshot.selectedPosition!.refreshDueAt, BigInt.from(110));
      expect(snapshot.selectedPosition!.inGrace, isTrue);
      expect(snapshot.selectedPosition!.mature, isFalse);
      expect(snapshot.activeName, 'alice');
      expect(transport.readTags.every((tag) => tag == '0xa'), isTrue);
      expect(transport.selectors, isNot(contains('0x1dfda2e7')));
      expect(transport.selectors, isNot(contains('0xf76e947b')));
    },
  );
  test('name lookup binds the stable position id during grace', () async {
    final result = await ZnsRpcClient(
      configuration(),
      transport: RpcFixture(),
    ).lookupName('alice');
    expect(result.positionId, BigInt.from(42));
    expect(result.active, isTrue);
    expect(result.expiresAt, BigInt.from(120));
  });
  test('release preview preserves full fractional forfeiture', () async {
    final result = await ZnsRpcClient(
      configuration(),
      transport: RpcFixture(),
    ).exitPreview(BigInt.from(42));
    expect(result.early, isTrue);
    expect(result.principalReturned, BigInt.zero);
    expect(result.principalForfeited, BigInt.from(500));
    expect(
      result.rewardsForfeitedScaled,
      ZnsNetworkConfig.rewardScale + BigInt.from(7),
    );
  });
  test(
    'incompatible protocol and wrong token stop reads before funding',
    () async {
      final bad = RpcFixture()..incompatible = true;
      await expectLater(
        ZnsRpcClient(configuration(), transport: bad).registrySnapshot(owner),
        throwsA(isA<ZnsDataException>()),
      );
      expect(bad.selectors, ['0xda1f12ab']);
      await expectLater(
        ZnsRpcClient(
          configuration(),
          transport: RpcFixture()..wrongToken = true,
        ).registrySnapshot(owner),
        throwsA(isA<ZnsDataException>()),
      );
    },
  );
  test(
    'reorganization and mismatched RPC ids cannot create usable snapshots',
    () async {
      for (final transport in [
        RpcFixture()..reorganize = true,
        RpcFixture()..wrongId = true,
      ]) {
        await expectLater(
          ZnsRpcClient(
            configuration(),
            transport: transport,
          ).registrySnapshot(owner),
          throwsA(isA<ZnsDataException>()),
        );
      }
    },
  );
  test('malformed position boolean is rejected', () async {
    final transport = RpcFixture()
      ..overridePosition = tuple([
        owner,
        'alice',
        'u1publicfixture',
        100,
        115,
        110,
        120,
        2,
        0,
        BigInt.zero,
      ]);
    await expectLater(
      ZnsRpcClient(
        configuration(),
        transport: transport,
      ).positionInfo(BigInt.from(42)),
      throwsA(isA<ZnsDataException>()),
    );
  });
  test('receipt needs depth and a stable second canonical read', () async {
    final client = ZnsRpcClient(configuration(), transport: RpcFixture());
    final receipt = (await client.transactionReceipt(transactionHash))!;
    expect(receipt.confirmed, isTrue);
    expect(receipt.confirmations, BigInt.two);
    final moved = await ZnsRpcClient(
      configuration(),
      transport: RpcFixture()..receiptReorg = true,
    ).transactionReceipt(transactionHash);
    expect(moved!.confirmed, isFalse);
    expect(moved.canonical, isFalse);
  });
  test('config and quantities reject unsafe or ambiguous input', () {
    expect(
      () => ZnsNetworkConfig(
        chainId: 8453,
        rpcUri: Uri.parse('http://rpc.example'),
        registryAddress: registry,
      ),
      throwsArgumentError,
    );
    expect(
      () => ZnsNetworkConfig(
        chainId: 8453,
        rpcUri: Uri.parse('https://rpc.example'),
        registryAddress: registry,
        tokenDecimals: 18,
      ),
      throwsArgumentError,
    );
    expect(() => znsParseQuantity('0x00'), throwsFormatException);
    expect(() => znsDecimalUnits('0.000000001', 8), throwsFormatException);
    expect(znsDecimalUnits('0.00000001', 8), BigInt.one);
  });
}
