import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/zns/domain/zns_operation.dart';

const _scope = ZnsScope(
  zcashNetwork: 'mainnet',
  chainId: 8453,
  registry: '0x1111111111111111111111111111111111111111',
  owner: '0x2222222222222222222222222222222222222222',
);

Map<String, dynamic> _record() => ZnsOperation(
  scope: _scope,
  name: 'alice',
  unifiedAddress: 'u1synthetic',
  positionId: BigInt.zero,
  secret: '0x${'33' * 32}',
  commitment: '0x${'44' * 32}',
  kind: 'register',
  maxZatoshi: BigInt.from(100),
  maxEthWei: BigInt.from(1000),
  requiredTokenUnits: BigInt.from(500),
  registrationQuote: ZnsRegistrationQuote(
    minimumDeposit: BigInt.from(500),
    usdTarget: BigInt.from(100),
    pricingMode: 0,
    priceUpdatedAt: BigInt.from(900),
  ),
  maxGasFeeWei: BigInt.from(100),
  createdAt: DateTime.utc(2026, 9, 8),
).toJson();

Map<String, dynamic> _transaction({bool settled = false}) => {
  'kind': 'commit',
  'hash': '0x${'55' * 32}',
  'nonce': '0',
  'value': '0',
  'feeCeiling': '10',
  if (settled) ...{
    'confirmed': true,
    'success': true,
    'blockNumber': '100',
    'blockHash': '0x${'66' * 32}',
  },
};

Map<String, dynamic> _funding() => {
  'maxZatoshi': '42',
  'zecFee': '2',
  'attempted': true,
  'plan': {
    'requiredWei': '500',
    'depositZatoshi': '40',
    'receiveAmount': '0.0000000000000005 ETH',
    'minimumReceiveAmount': '0.000000000000000500 ETH',
  },
};

ZnsOperation _decode(Map<String, dynamic> record) =>
    ZnsOperation.decode(jsonEncode(record), _scope);

void main() {
  test('floor-aware recovery rejects the preceding tiered policy', () {
    final old = _record()
      ..['policy'] =
          'tieredUSD-fixedFallback-deposit365-refresh365-grace90-linearFee10-linearRewards-weighted-reserveCarry-erc721-multiName-clearUA';
    expect(() => _decode(old), throwsFormatException);
    expect(_decode(_record()).registrationQuote!.pricingMode, 0);
  });

  test('floor disclosure uses the quoted minimum before optional extra', () {
    for (final (target, floor) in [
      (2000, 2000000),
      (500, 500000),
      (200, 200000),
      (100, 100000),
      (50, 50000),
    ]) {
      ZnsRegistrationQuote quote(int units, int mode) => ZnsRegistrationQuote(
        minimumDeposit: BigInt.from(units),
        usdTarget: BigInt.from(target),
        pricingMode: mode,
        priceUpdatedAt: BigInt.from(900),
      );
      expect(quote(floor, 0).minimumBondFloor, BigInt.from(floor));
      expect(quote(floor, 0).minimumFloorApplies, isTrue);
      expect(quote(floor + 1, 0).minimumFloorApplies, isFalse);
      expect(quote(floor, 1).minimumFloorApplies, isFalse);
    }
  });

  test('recovery never invents registration pricing or extra-bond authority', () {
    for (final key in [
      'minimumDeposit',
      'extraDeposit',
      'usdTarget',
      'expectedPricingMode',
      'priceUpdatedAt',
    ]) {
      final missing = _record()..remove(key);
      expect(() => _decode(missing), throwsFormatException);
    }
    expect(
      () => _decode(_record()..['expectedPricingMode'] = 2),
      throwsFormatException,
    );
    expect(
      () => _decode(_record()..['extraDeposit'] = '1'),
      throwsFormatException,
    );
    expect(
      () => _decode(
        _record()
          ..['policy'] =
              'deposit365-refresh365-grace90-earlyFee10-forfeitRewards-reserveCarry-erc721-multiName-clearUA',
      ),
      throwsFormatException,
    );
  });

  test(
    'NFT recovery binds the recipient and rejects the old economic policy',
    () {
      final record = _record()
        ..['kind'] = 'transfer'
        ..['requiredTokenUnits'] = '0'
        ..['positionId'] = '42'
        ..['recipient'] = '0x3333333333333333333333333333333333333333';
      expect(_decode(record).recipient, record['recipient']);
      for (final recipient in [
        '',
        _scope.owner,
        _scope.registry,
        '0x${'0' * 40}',
      ]) {
        expect(
          () => _decode({...record, 'recipient': recipient}),
          throwsFormatException,
        );
      }
      expect(
        () => _decode({
          ...record,
          'policy': 'deposit365-refresh365-grace90-forfeitAll-reserveCarry',
        }),
        throwsFormatException,
      );
    },
  );

  test('valid pending funding recovery retains exact integer amounts', () {
    final record = _record()
      ..['pending'] = _transaction()
      ..['transactions'] = [_transaction(settled: true)]
      ..['funding'] = _funding();
    final decoded = _decode(record);
    expect(decoded.maxEthWei, BigInt.from(1000));
    expect(decoded.pending!['feeCeiling'], '10');
    expect(decoded.transactions.single['value'], '0');
    expect(decoded.funding!['plan']['requiredWei'], '500');
  });

  test('top-level amounts reject alternate signed and oversized encodings', () {
    for (final key in [
      'positionId',
      'maxZatoshi',
      'maxEthWei',
      'requiredTokenUnits',
      'maxGasFeeWei',
    ]) {
      for (final bad in ['-1', '-0', '+1', '01', ' 1', '0x10', '1e2', 1]) {
        expect(
          () => _decode(_record()..[key] = bad),
          throwsFormatException,
          reason: '$key must reject $bad',
        );
      }
    }
    expect(
      () => _decode(_record()..['maxEthWei'] = (BigInt.one << 256).toString()),
      throwsFormatException,
    );
    expect(
      () => _decode(_record()..['maxZatoshi'] = '2100000000000001'),
      throwsFormatException,
    );
  });

  test('imported negative fees and values cannot create spend credit', () {
    for (final container in ['pending', 'transactions']) {
      for (final key in ['value', 'feeCeiling']) {
        final tx = _transaction(settled: container == 'transactions')
          ..[key] = '-999999999999999999';
        final record = _record()
          ..[container] = container == 'pending' ? tx : [tx];
        expect(() => _decode(record), throwsFormatException);
      }
    }
  });

  test('each saved nonce and gas amount uses bounded unsigned integers', () {
    for (final key in [
      'nonce',
      'authorizationNonce',
      'blockNumber',
      'gasLimit',
      'gasUsed',
      'maxFeePerGas',
      'maxPriorityFeePerGas',
      'effectiveGasPrice',
      'l1FeeWei',
      'operatorFeeWei',
    ]) {
      expect(
        () => _decode(_record()..['pending'] = (_transaction()..[key] = '-1')),
        throwsFormatException,
      );
    }
    expect(
      () => _decode(
        _record()
          ..['pending'] = (_transaction()
            ..['nonce'] = (BigInt.one << 64).toString()),
      ),
      throwsFormatException,
    );
  });

  test('gas and native reservations include pending and confirmed steps', () {
    for (final key in ['value', 'feeCeiling']) {
      final overHalf = key == 'value' ? '500' : '60';
      final record = _record()
        ..['pending'] = (_transaction()..[key] = overHalf)
        ..['transactions'] = [_transaction(settled: true)..[key] = overHalf];
      expect(() => _decode(record), throwsFormatException);
    }
    final reverted = _transaction(settled: true)
      ..['success'] = false
      ..['value'] = '900';
    expect(
      _decode(_record()..['transactions'] = [reverted]).transactions,
      hasLength(1),
    );
    reverted['feeCeiling'] = '101';
    expect(
      () => _decode(_record()..['transactions'] = [reverted]),
      throwsFormatException,
    );
  });

  test('gas detail cannot understate its saved fee ceiling', () {
    for (final detail in [
      {'gasLimit': '4', 'maxFeePerGas': '3'},
      {'gasLimit': '3', 'maxFeePerGas': '3', 'l1FeeWei': '2'},
      {'maxFeePerGas': '1', 'maxPriorityFeePerGas': '2'},
      {'gasLimit': '3', 'gasUsed': '4'},
    ]) {
      expect(
        () => _decode(_record()..['pending'] = {..._transaction(), ...detail}),
        throwsFormatException,
      );
    }
  });

  test('funding validates quote sums and reviewed ZEC and ETH bounds', () {
    for (final change in [
      {'maxZatoshi': '-1'},
      {'maxZatoshi': '101'},
      {'zecFee': '3'},
    ]) {
      expect(
        () => _decode(_record()..['funding'] = {..._funding(), ...change}),
        throwsFormatException,
      );
    }
    for (final change in [
      {'requiredWei': '1001'},
      {'depositZatoshi': '41'},
      {'depositZatoshi': '-1'},
      {'receiveAmount': '1e-15 ETH'},
      {'minimumReceiveAmount': '-0.1 ETH'},
      {'minimumReceiveAmount': '0.000000000000000499 ETH'},
      {'minimumReceiveAmount': '0.000000000000000501 ETH'},
    ]) {
      final funding = _funding();
      funding['plan'] = {...funding['plan'] as Map, ...change};
      expect(
        () => _decode(_record()..['funding'] = funding),
        throwsFormatException,
      );
    }
  });

  test(
    'management recovery cannot request a token purchase or other action',
    () {
      final record = _record()
        ..['kind'] = 'refresh'
        ..['positionId'] = '7';
      expect(() => _decode(record), throwsFormatException);
      record['requiredTokenUnits'] = '0';
      expect(_decode(record).positionId, BigInt.from(7));
      record['pending'] = _transaction();
      expect(() => _decode(record), throwsFormatException);
      expect(
        () => _decode(_record()..['maxGasFeeWei'] = '1001'),
        throwsFormatException,
      );
    },
  );

  test('release preview rejects noncanonical forfeiture amounts', () {
    final record = _record()
      ..['kind'] = 'release'
      ..['positionId'] = '7'
      ..['requiredTokenUnits'] = '0'
      ..['exitPreview'] = {
        'early': true,
        'principalReturned': '450',
        'rewardsReturned': '0',
        'principalForfeited': '50',
        'rewardsForfeitedScaled': '01',
      };
    expect(() => _decode(record), throwsFormatException);
    record['exitPreview']['rewardsForfeitedScaled'] = '1';
    expect(_decode(record).exitPreview!['early'], isTrue);
  });

  test(
    'hash-only recovery remains available for authoritative reconciliation',
    () {
      final record = _record()
        ..['pending'] = {'kind': 'commit', 'hash': '0x${'55' * 32}'};
      final decoded = _decode(record);
      expect(decoded.pending!.containsKey('feeCeiling'), isFalse);
      expect(decoded.pending!.containsKey('value'), isFalse);
    },
  );
}
