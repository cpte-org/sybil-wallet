import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/zns/application/zns_engine.dart';
import 'package:zcash_wallet/src/features/zns/application/zns_journal.dart';
import 'package:zcash_wallet/src/features/zns/domain/zns_operation.dart';

const scope = ZnsScope(
  zcashNetwork: 'mainnet',
  chainId: 8453,
  registry: '0x1111111111111111111111111111111111111111',
  owner: '0x2222222222222222222222222222222222222222',
);
final secret = '0x${'33' * 32}';
final commitment = '0x${'44' * 32}';

class MemoryJournal implements ZnsJournalStorage {
  final values = <String, String>{};
  final writes = <String>[];
  String? failKey;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (key == failKey) throw StateError('Storage is unavailable');
    writes.add(key);
    values[key] = value;
  }
}

class Gateway implements ZnsEngineGateway {
  int now = 1000, commitAt = 900, minAge = 60, maxAge = 86400;
  BigInt eth = BigInt.from(10000), token = BigInt.from(500);
  BigInt allowance = BigInt.from(500), claimable = BigInt.zero;
  BigInt swapValue = BigInt.from(1000), fundingZatoshi = BigInt.from(100);
  ZnsRecord? owned, occupied;
  @override
  bool supportsAtomic = false;
  final signs = <Map<String, dynamic>>[];
  final broadcasts = <String>[];
  final receipts = <String, Map<String, dynamic>>{};
  final swapLimits = <BigInt?>[];
  int fundingSends = 0, liveQuotes = 0;
  int broadcastFailures = 0;
  bool fundingTimeout = false, fundingNotSent = false;
  Map<String, dynamic>? currentExitPreview;
  Map<String, dynamic> fundingState = {'complete': false};
  Completer<void>? signWait, fundingWait;
  void Function()? beforeFunding, beforeBroadcast;

  @override
  Future<ZnsChainView> snapshot(String? commitment) async => ZnsChainView(
    timestamp: now,
    deposit: BigInt.from(500),
    eth: eth,
    token: token,
    allowance: allowance,
    claimablePrincipal: claimable,
    claimableRewardsScaled: BigInt.zero,
    minAge: minAge,
    maxAge: maxAge,
    commitAt: commitAt,
    position: owned,
  );
  @override
  Future<ZnsRecord?> lookup(String name) async => occupied;
  @override
  Future<Map<String, dynamic>> exitPreview(BigInt positionId) async =>
      currentExitPreview == null
      ? {
          'early': now < (owned?.maturityAt ?? 0),
          'principalReturned': now < (owned?.maturityAt ?? 0) ? '0' : '500',
          'rewardsReturned': '0',
          'principalForfeited': now < (owned?.maturityAt ?? 0) ? '500' : '0',
          'rewardsForfeitedScaled': '0',
        }
      : {...currentExitPreview!};
  @override
  Future<Map<String, dynamic>> swapQuote(
    BigInt neededToken,
    BigInt? maxWei,
  ) async {
    swapLimits.add(maxWei);
    if (maxWei != null && swapValue > maxWei) {
      throw StateError('Swap exceeds reviewed ETH budget');
    }
    return {
      'value': swapValue.toString(),
      'minimumOutput': neededToken.toString(),
      'data': '0x1234',
    };
  }

  @override
  Future<Map<String, dynamic>> fundingQuote(
    BigInt requiredWei, {
    required bool dry,
  }) async {
    if (!dry) liveQuotes++;
    return {
      'maxZatoshi': fundingZatoshi.toString(),
      'deposit': 't1synthetic',
      'requiredWei': requiredWei.toString(),
    };
  }

  @override
  Future<String?> sendFunding(
    Map<String, dynamic> quote, {
    required void Function() ensureAuthorized,
  }) async {
    if (fundingWait != null) await fundingWait!.future;
    ensureAuthorized();
    if (fundingNotSent) {
      throw const ZnsFundingNotSent('Funding quote expired before signing');
    }
    beforeFunding?.call();
    fundingSends++;
    if (fundingTimeout) throw TimeoutException('Deposit submission uncertain');
    return 'zec-hash';
  }

  @override
  Future<Map<String, dynamic>> fundingStatus(
    Map<String, dynamic> quote,
  ) async => fundingState;
  @override
  Future<Map<String, dynamic>> sign(
    ZnsOperation intent,
    Map<String, dynamic> operation, {
    required void Function() ensureAuthorized,
  }) async {
    ensureAuthorized();
    signs.add({...operation});
    if (signWait != null) await signWait!.future;
    ensureAuthorized();
    return {
      'raw': 'raw-${signs.length}',
      'hash': 'hash-${signs.length}',
      'value': operation['value'] ?? '0',
      'feeCeiling': '10',
    };
  }

  @override
  Future<void> broadcast(String rawTransaction, String expectedHash) async {
    beforeBroadcast?.call();
    broadcasts.add(rawTransaction);
    if (broadcastFailures > 0) {
      broadcastFailures--;
      throw TimeoutException('RPC response lost');
    }
  }

  @override
  Future<Map<String, dynamic>?> receipt(String hash) async => receipts[hash];
  @override
  Future<BigInt> gasBudget(String kind) async => BigInt.from(100);
  @override
  Future<String> secret() async => '0x${'33' * 32}';
  @override
  Future<String> commitment(String name, String ua, String secret) async =>
      '0x${'44' * 32}';
}

ZnsOperation intent({String kind = 'register', String? salt}) => ZnsOperation(
  scope: scope,
  name: 'alice',
  unifiedAddress: 'u1synthetic',
  positionId: ['register', 'withdrawClaims'].contains(kind)
      ? BigInt.zero
      : BigInt.one,
  secret: salt ?? secret,
  commitment: commitment,
  kind: kind,
  maxZatoshi: BigInt.from(100),
  maxEthWei: BigInt.from(1150),
  requiredTokenUnits: kind == 'register' ? BigInt.from(500) : BigInt.zero,
  maxGasFeeWei: BigInt.from(100),
  createdAt: DateTime.utc(2026, 9, 8),
  exitPreview: kind == 'release'
      ? {
          'early': false,
          'principalReturned': '500',
          'rewardsReturned': '0',
          'principalForfeited': '0',
          'rewardsForfeitedScaled': '0',
        }
      : null,
  baselineExpiry: 100000,
);

ZnsRecord record({
  String owner = '0x2222222222222222222222222222222222222222',
  String ua = 'u1synthetic',
  int expiry = 100000,
  int id = 1,
  int maturity = 1500,
  bool participating = true,
  bool retired = false,
}) => ZnsRecord(
  name: 'alice',
  owner: owner,
  unifiedAddress: ua,
  expiresAt: expiry,
  deposit: BigInt.from(500),
  positionId: BigInt.from(id),
  maturityAt: maturity,
  refreshDueAt: expiry - 90,
  participating: participating,
  retired: retired,
  rewardCreditScaled: BigInt.zero,
);

Map<String, dynamic> mined({bool success = true, String block = 'block-a'}) => {
  'confirmed': true,
  'success': success,
  'blockHash': block,
};

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 50; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected asynchronous boundary was not reached');
}

void main() {
  late MemoryJournal storage;
  late Gateway gateway;
  late ZnsEngine engine;
  var signable = true;
  final engines = <ZnsEngine>[];
  ZnsEngine makeEngine({String uuid = 'uuid-a'}) {
    final result = ZnsEngine(
      accountUuid: uuid,
      scope: scope,
      gateway: gateway,
      journal: ZnsJournal(storage),
      canSign: () => signable,
      onChange: () {},
    );
    engines.add(result);
    return result;
  }

  setUp(() {
    signable = true;
    storage = MemoryJournal();
    gateway = Gateway();
    engine = makeEngine();
  });
  tearDown(() {
    for (final item in engines) {
      item.dispose();
    }
    engines.clear();
  });

  test('secret and signed bytes are durable before first broadcast', () async {
    gateway.commitAt = 0;
    gateway.beforeBroadcast = () {
      final saved = ZnsOperation.decode(storage.values[scope.key]!, scope);
      expect(saved.secret, secret);
      expect(saved.pending!['raw'], 'raw-1');
      expect(saved.pending!['kind'], 'commit');
    };
    await engine.authorize(intent());
    expect(gateway.signs.single['kind'], 'commit');
    expect(gateway.broadcasts, ['raw-1']);
  });

  test(
    'uncertain broadcast reload replays identical raw bytes without resigning',
    () async {
      gateway.commitAt = 0;
      gateway.broadcastFailures = 1;
      await engine.authorize(intent());
      expect(engine.authorized, isFalse);
      expect(engine.operation!.pending, isNotNull);
      engine.dispose();
      final restored = makeEngine(uuid: 'restored-uuid');
      await restored.load();
      expect(restored.authorized, isFalse);
      expect(gateway.signs, hasLength(1));
      await restored.advance();
      expect(gateway.broadcasts, ['raw-1']);
      await restored.authorize(restored.operation!);
      expect(gateway.broadcasts, ['raw-1', 'raw-1']);
      expect(gateway.signs, hasLength(1));
      expect(gateway.fundingSends, 0);
    },
  );

  test(
    'uncertain Zcash funding is attempted once across restart and review',
    () async {
      gateway.eth = BigInt.zero;
      gateway.fundingTimeout = true;
      gateway.beforeFunding = () {
        final saved = ZnsOperation.decode(storage.values[scope.key]!, scope);
        expect(saved.funding!['attempted'], isTrue);
      };
      await engine.authorize(intent());
      expect(gateway.fundingSends, 1);
      expect(engine.authorized, isFalse);
      engine.dispose();
      final restored = makeEngine();
      await restored.load();
      await restored.authorize(restored.operation!);
      await restored.advance();
      expect(gateway.fundingSends, 1);
      expect(gateway.liveQuotes, 1);
      expect(gateway.signs, isEmpty);
      expect(restored.operation!.phase, 'funding');
    },
  );

  test(
    'proven unsent funding clears the durable attempt and permits a fresh reviewed quote',
    () async {
      gateway.eth = BigInt.zero;
      gateway.fundingNotSent = true;
      await engine.authorize(intent());
      expect(engine.authorized, isFalse);
      expect(engine.error, contains('expired before signing'));
      expect(engine.operation!.funding, isNull);
      expect((await ZnsJournal(storage).load(scope))!.funding, isNull);
      expect(gateway.fundingSends, 0);
      expect(gateway.signs, isEmpty);
      engine.dispose();
      final restored = makeEngine(uuid: 'restored-software-account');
      await restored.load();
      expect(restored.authorized, isFalse);
      gateway.fundingNotSent = false;
      await restored.authorize(restored.operation!);
      expect(gateway.liveQuotes, 2);
      expect(gateway.fundingSends, 1);
      expect(restored.operation!.funding!['attempted'], isTrue);
      expect(restored.operation!.funding!['txHash'], 'zec-hash');
      await restored.advance();
      expect(gateway.fundingSends, 1);
      expect(gateway.signs, isEmpty);
    },
  );

  test(
    'canonical receipt replaces forged historical kind, value and fee before another swap budget',
    () async {
      gateway.token = BigInt.from(400);
      final op = intent()
        ..transactions = [
          {
            'hash': 'actual-swap',
            'raw': 'preserved-signed-bytes',
            'kind': 'register',
            'value': '0',
            'feeCeiling': '0',
            ...mined(),
          },
        ];
      gateway.receipts['actual-swap'] = {
        ...mined(),
        'verifiedIntent': true,
        'kind': 'swap',
        'value': '1000',
        'feeCeiling': '75',
      };
      await engine.authorize(op);
      expect(op.transactions.single['kind'], 'swap');
      expect(op.transactions.single['value'], '1000');
      expect(op.transactions.single['feeCeiling'], '75');
      expect(op.transactions.single['raw'], 'preserved-signed-bytes');
      expect(gateway.swapLimits, [BigInt.from(50)]);
      expect(engine.error, contains('reviewed ETH budget'));
      expect(engine.authorized, isFalse);
      expect(op.isComplete, isFalse);
      expect(gateway.signs, isEmpty);
      expect(gateway.fundingSends, 0);
      final saved = (await ZnsJournal(storage).load(scope))!;
      expect(saved.transactions.single['feeCeiling'], '75');
      expect(saved.transactions.single['value'], '1000');
      expect(saved.transactions.single['kind'], 'swap');
    },
  );

  test(
    'canonical failure replaces imported success before a matching record can claim completion',
    () async {
      gateway.owned = record();
      final op = intent()
        ..transactions = [
          {
            'hash': 'failed-final',
            'kind': 'register',
            'value': '0',
            'feeCeiling': '0',
            ...mined(),
          },
        ];
      gateway.receipts['failed-final'] = {
        ...mined(success: false),
        'verifiedIntent': true,
        'kind': 'register',
        'name': op.name,
        'unifiedAddress': op.unifiedAddress,
        'secret': op.secret,
        'value': '0',
        'feeCeiling': '80',
      };
      await engine.authorize(op);
      expect(op.transactions.single['success'], isFalse);
      expect(op.transactions.single['feeCeiling'], '80');
      expect(op.isComplete, isFalse);
      expect(engine.authorized, isFalse);
      expect(gateway.signs, isEmpty);
      expect(engine.error, contains('before your reveal'));
    },
  );

  for (final historical in [false, true]) {
    test(
      'wrong actual commitment in ${historical ? 'history' : 'pending transaction'} pauses before any new spend',
      () async {
        gateway.eth = BigInt.zero;
        final op = intent();
        final saved = <String, dynamic>{
          'hash': 'wrong-commit',
          'kind': 'commit',
          'raw': 'preserved',
          ...mined(),
        };
        if (historical) {
          op.transactions = [saved];
        } else {
          op.pending = saved;
        }
        gateway.receipts['wrong-commit'] = {
          ...mined(),
          'verifiedIntent': true,
          'kind': 'commit',
          'commitment': '0x${'99' * 32}',
          'value': '0',
          'feeCeiling': '10',
        };
        await engine.authorize(op);
        expect(
          engine.error,
          contains('does not match this registration intent'),
        );
        expect(engine.authorized, isFalse);
        expect(gateway.signs, isEmpty);
        expect(gateway.broadcasts, isEmpty);
        expect(gateway.fundingSends, 0);
        expect(op.secret, secret);
        if (historical) {
          expect(op.transactions.single['raw'], 'preserved');
        } else {
          expect(op.pending!['raw'], 'preserved');
          expect(op.transactions, isEmpty);
        }
      },
    );
  }

  test(
    'canonical management receipt for another position cannot complete or repeat the requested action',
    () async {
      gateway.owned = record(expiry: 100000 + 31536000);
      final op = intent(kind: 'refresh')
        ..pending = {
          'hash': 'other-position',
          'kind': 'refresh',
          'raw': 'preserved',
        };
      gateway.receipts['other-position'] = {
        ...mined(),
        'verifiedIntent': true,
        'kind': 'refresh',
        'positionId': '2',
        'value': '0',
        'feeCeiling': '10',
      };
      await engine.authorize(op);
      expect(engine.error, contains('different name operation'));
      expect(op.isComplete, isFalse);
      expect(op.pending, isNotNull);
      expect(engine.authorized, isFalse);
      expect(gateway.signs, isEmpty);
      expect(gateway.broadcasts, isEmpty);
    },
  );

  for (final maturityChanged in [false, true]) {
    test(
      'changed ${maturityChanged ? 'maturity' : 'unvested reward'} exit preview pauses until the updated amounts are reviewed',
      () async {
        gateway.owned = record();
        final reviewed = await engine.prepare(
          name: 'alice',
          ua: 'u1synthetic',
          kind: 'release',
        );
        final originalPreview = {...reviewed.exitPreview!};
        if (maturityChanged) {
          gateway.now = 1500;
        } else {
          gateway.currentExitPreview = {
            ...originalPreview,
            'rewardsForfeitedScaled': '123456789',
          };
        }
        await engine.authorize(reviewed);
        expect(engine.error, contains('changed'));
        expect(engine.authorized, isFalse);
        expect(gateway.signs, isEmpty);
        expect(gateway.broadcasts, isEmpty);
        expect(reviewed.pending, isNull);
        expect(
          reviewed.exitPreview,
          originalPreview,
          reason: 'The engine cannot silently expand approved forfeitures',
        );
        // Explicitly accepting a refreshed review updates the saved display data,
        // as the controller does; no new secret, position or spending cap appears.
        final freshPreview = await gateway.exitPreview(reviewed.positionId);
        reviewed.exitPreview!
          ..clear()
          ..addAll(freshPreview);
        await engine.authorize(reviewed);
        expect(gateway.signs.single, {'kind': 'release', 'positionId': '1'});
        expect(gateway.broadcasts, ['raw-1']);
        expect(reviewed.secret, secret);
        expect(
          (await ZnsJournal(storage).load(scope))!.exitPreview,
          freshPreview,
        );
      },
    );
  }

  test(
    'manual pause during funding preparation stops the deposit signer',
    () async {
      gateway.eth = BigInt.zero;
      gateway.fundingWait = Completer<void>();
      final work = engine.authorize(intent());
      await until(() => engine.operation?.funding != null);
      engine.pause();
      gateway.fundingWait!.complete();
      await work;
      expect(gateway.fundingSends, 0);
      expect(gateway.signs, isEmpty);
      expect(engine.authorized, isFalse);
      expect(engine.operation!.funding!['attempted'], isTrue);
    },
  );

  for (final manualPause in [true, false]) {
    test(
      '${manualPause ? 'pause' : 'account switch'} while signing prevents broadcast',
      () async {
        gateway.signWait = Completer<void>();
        final work = engine.authorize(intent());
        await until(() => gateway.signs.isNotEmpty);
        if (manualPause) {
          engine.pause();
        } else {
          signable = false;
        }
        gateway.signWait!.complete();
        await work;
        expect(gateway.broadcasts, isEmpty);
        expect(engine.operation!.pending, isNull);
        expect(engine.authorized, isFalse);
      },
    );
  }

  test('persistence failure prevents funding and signing', () async {
    storage.failKey = scope.key;
    gateway.eth = BigInt.zero;
    await expectLater(engine.authorize(intent()), throwsStateError);
    expect(gateway.fundingSends, 0);
    expect(gateway.signs, isEmpty);
    expect(await ZnsJournal(storage).hasAccountRecords('uuid-a'), isTrue);
  });

  test(
    'unconfirmed receipt does not broadcast or advance a second transaction',
    () async {
      final op = intent()
        ..pending = {'raw': 'existing-raw', 'hash': 'old', 'kind': 'commit'};
      gateway.receipts['old'] = {
        'confirmed': false,
        'success': true,
        'blockHash': 'b',
      };
      await engine.authorize(op);
      expect(gateway.signs, isEmpty);
      expect(gateway.broadcasts, isEmpty);
      expect(op.pending, isNotNull);
    },
  );

  test(
    'reverted transaction pauses and retains receipt without automatic retry',
    () async {
      final op = intent()
        ..pending = {
          'raw': 'existing-raw',
          'hash': 'old',
          'kind': 'register',
          'feeCeiling': '10',
        };
      gateway.receipts['old'] = mined(success: false);
      await engine.authorize(op);
      await engine.advance();
      expect(op.pending, isNull);
      expect(op.transactions.single['success'], isFalse);
      expect(gateway.signs, isEmpty);
      expect(engine.authorized, isFalse);
      expect(engine.error, contains('reverted'));
    },
  );

  test(
    'earlier receipt reorg pauses and preserves secret and signed history',
    () async {
      final op = intent()
        ..transactions = [
          {'hash': 'old', 'raw': 'old-raw', 'kind': 'commit', ...mined()},
        ];
      gateway.receipts['old'] = mined(block: 'replacement-block');
      await engine.authorize(op);
      expect(engine.error, contains('reorganization'));
      expect(gateway.signs, isEmpty);
      expect(
        (await ZnsJournal(storage).load(scope))!.transactions.single['raw'],
        'old-raw',
      );
    },
  );

  test('commitment is eligible at exact minimum and maximum age', () async {
    gateway.commitAt = 1000;
    gateway.now = 1059;
    await engine.authorize(intent());
    expect(engine.operation!.phase, 'waiting');
    expect(gateway.signs, isEmpty);
    gateway.now = 1060;
    await engine.advance();
    expect(gateway.signs.single['kind'], 'register');
    engine.dispose();
    final edge = makeEngine();
    gateway.signs.clear();
    gateway.now = 1000 + gateway.maxAge;
    await edge.authorize(intent());
    expect(gateway.signs.single['kind'], 'register');
  });

  test(
    'expired commitment can be archived before explicit fresh review',
    () async {
      gateway.now = gateway.commitAt + gateway.maxAge + 1;
      await engine.authorize(intent());
      expect(engine.error, contains('expired'));
      expect(gateway.signs, isEmpty);
      await engine.archive();
      expect(engine.operation, isNull);
      expect(await ZnsJournal(storage).load(scope), isNull);
      final history =
          jsonDecode(storage.values['${scope.key}:history']!) as List;
      expect(history.single['secret'], secret);
      gateway.commitAt = 0;
      final fresh = await engine.prepare(
        name: 'alice',
        ua: 'u1synthetic',
        maxZatoshi: BigInt.from(100),
      );
      expect(fresh.kind, 'register');
    },
  );

  test('name conflict stops before funding or reveal', () async {
    gateway.occupied = record(
      owner: '0x9999999999999999999999999999999999999999',
    );
    gateway.eth = BigInt.zero;
    await engine.authorize(intent());
    expect(engine.error, contains('before your reveal'));
    expect(gateway.signs, isEmpty);
    expect(gateway.fundingSends, 0);
  });

  test('fresh funding quote cannot expand reviewed ZEC budget', () async {
    gateway.eth = BigInt.zero;
    gateway.fundingZatoshi = BigInt.from(101);
    await engine.authorize(intent());
    expect(engine.error, contains('approved ZEC budget'));
    expect(gateway.fundingSends, 0);
    expect(engine.operation!.funding, isNull);
  });

  test(
    'prepare rejects unaffordable funding and includes bounded ETH margin',
    () async {
      gateway.token = BigInt.zero;
      gateway.eth = BigInt.zero;
      await expectLater(
        engine.prepare(
          name: 'alice',
          ua: 'u1synthetic',
          maxZatoshi: BigInt.from(99),
        ),
        throwsStateError,
      );
      final review = await engine.prepare(
        name: 'alice',
        ua: 'u1synthetic',
        maxZatoshi: BigInt.from(100),
      );
      expect(review.requiredTokenUnits, BigInt.from(500));
      expect(review.maxEthWei, BigInt.from(1150));
      expect(review.maxGasFeeWei, BigInt.from(100));
      expect(gateway.fundingSends, 0);
      expect(gateway.signs, isEmpty);
    },
  );

  test('a second swap uses only unspent approved ETH budget', () async {
    gateway.token = BigInt.zero;
    await engine.authorize(intent());
    expect(gateway.signs.single['kind'], 'swap');
    gateway.receipts['hash-1'] = mined();
    gateway.token = BigInt.from(400);
    await engine.advance();
    expect(gateway.swapLimits, [BigInt.from(1050), BigInt.from(50)]);
    expect(gateway.signs, hasLength(1));
    expect(engine.authorized, isFalse);
  });

  for (final kind in ['refresh', 'update']) {
    test(
      'successful $kind with stale read cannot issue a second final transaction',
      () async {
        gateway.owned = record(
          ua: kind == 'update' ? 'u1previous' : 'u1synthetic',
          expiry: 99999,
        );
        final op = intent(kind: kind)
          ..pending = {'raw': 'old-raw', 'hash': 'old', 'kind': kind};
        gateway.receipts['old'] = mined();
        await engine.authorize(op);
        await engine.advance();
        expect(gateway.signs, isEmpty);
        expect(engine.authorized, isFalse);
        expect(engine.error, contains('will not be sent again'));
        expect(op.isComplete, isFalse);
      },
    );
  }

  test(
    'registration completion needs both matching state and confirmed final receipt',
    () async {
      gateway.owned = record();
      gateway.occupied = gateway.owned;
      final op = intent()
        ..pending = {'raw': 'old-raw', 'hash': 'old', 'kind': 'register'};
      gateway.receipts['old'] = mined();
      await engine.authorize(op);
      expect(op.isComplete, isTrue);
      expect(op.phase, 'complete');
      expect(engine.authorized, isFalse);
      expect(gateway.signs, isEmpty);
      expect((await ZnsJournal(storage).load(scope))!.secret, secret);
    },
  );

  test(
    'refresh and release complete from their own final receipt and chain effects',
    () async {
      gateway.owned = record(expiry: 100000 + 31536000);
      final renewed = intent(kind: 'refresh')
        ..pending = {'raw': 'renew-raw', 'hash': 'renew', 'kind': 'refresh'};
      gateway.receipts['renew'] = mined();
      await engine.authorize(renewed);
      expect(renewed.isComplete, isTrue);
      gateway.owned = null;
      gateway.claimable = BigInt.zero;
      final withdrawn = intent(kind: 'release', salt: '0x${'55' * 32}')
        ..pending = {
          'raw': 'withdraw-raw',
          'hash': 'withdraw',
          'kind': 'release',
        };
      gateway.receipts['withdraw'] = mined();
      await engine.authorize(withdrawn);
      expect(withdrawn.isComplete, isTrue);
      final history =
          jsonDecode(storage.values['${scope.key}:history']!) as List;
      expect(history.single['kind'], 'refresh');
      expect(history.single['secret'], secret);
    },
  );

  test(
    'archive rejects possibly live Base transaction and nonterminal ZEC funding',
    () async {
      engine.operation = intent()
        ..pending = {'raw': 'raw', 'hash': 'unknown', 'kind': 'register'};
      await expectLater(engine.archive(), throwsStateError);
      expect(engine.operation, isNotNull);
      engine.operation = intent()..funding = {'attempted': true};
      await expectLater(engine.archive(), throwsStateError);
      gateway.fundingState = {'failed': true, 'complete': false};
      await engine.archive();
      expect(engine.operation, isNull);
    },
  );

  test('journal corruption and scope mismatch fail closed', () async {
    storage.values[scope.key] = '{broken';
    await expectLater(engine.load(), throwsFormatException);
    final raw = intent().toJson();
    (raw['scope'] as Map)['chainId'] = 84532;
    storage.values[scope.key] = jsonEncode(raw);
    await expectLater(engine.load(), throwsFormatException);
    expect(gateway.signs, isEmpty);
    expect(gateway.fundingSends, 0);
  });

  test(
    'archive persistence failure preserves active recovery record',
    () async {
      final op = intent();
      await ZnsJournal(storage).save(op, 'uuid-a');
      storage.failKey = '${scope.key}:history';
      await expectLater(ZnsJournal(storage).archive(op), throwsStateError);
      expect((await ZnsJournal(storage).load(scope))!.secret, secret);
    },
  );

  test(
    'release review binds the registration and discloses the full early forfeiture',
    () async {
      gateway.owned = record();
      final reviewed = await engine.prepare(
        name: 'alice',
        ua: 'u1synthetic',
        kind: 'release',
      );
      expect(reviewed.positionId, BigInt.one);
      expect(reviewed.requiredTokenUnits, BigInt.zero);
      expect(reviewed.maturityAt, 1500);
      expect(reviewed.exitPreview!['principalForfeited'], '500');
      expect(reviewed.exitPreview!['early'], isTrue);
      await engine.authorize(reviewed);
      expect(gateway.signs.single, {'kind': 'release', 'positionId': '1'});
    },
  );

  test(
    'a replaced registration cannot be released by a stale review',
    () async {
      gateway.owned = record(id: 2);
      await engine.authorize(intent(kind: 'release'));
      expect(gateway.signs, isEmpty);
      expect(engine.error, contains('changed or expired'));
    },
  );

  test('old claims withdrawal preserves a participating name', () async {
    gateway.owned = record();
    gateway.claimable = BigInt.from(50);
    final reviewed = await engine.prepare(
      name: '',
      ua: '',
      kind: 'withdrawClaims',
    );
    await engine.authorize(reviewed);
    expect(gateway.signs.single, {'kind': 'withdrawClaims'});
    gateway.claimable = BigInt.zero;
    gateway.receipts['hash-1'] = mined();
    await engine.advance();
    expect(reviewed.isComplete, isTrue);
    expect(gateway.owned!.positionId, BigInt.one);
  });

  test(
    'reward claim requires original maturity and participating ownership',
    () async {
      gateway.owned = record();
      await expectLater(
        engine.prepare(name: 'alice', ua: 'u1synthetic', kind: 'claimRewards'),
        throwsStateError,
      );
      gateway.now = 1500;
      final reviewed = await engine.prepare(
        name: 'alice',
        ua: 'u1synthetic',
        kind: 'claimRewards',
      );
      expect(reviewed.maturityAt, 1500);
      expect(reviewed.requiredTokenUnits, BigInt.zero);
      gateway.owned = record(participating: false);
      await engine.authorize(reviewed);
      expect(gateway.signs, isEmpty);
    },
  );

  test(
    'prototype duration authorization cannot be imported under deposit rules',
    () {
      final old = intent().toJson()..remove('policy');
      old['years'] = 1;
      expect(
        () => ZnsOperation.decode(jsonEncode(old), scope),
        throwsFormatException,
      );
    },
  );
}
