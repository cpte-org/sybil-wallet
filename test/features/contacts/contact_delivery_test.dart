import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_delivery_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_delivery.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

const alice = ContactScope(accountUuid: 'alice', network: 'regtest');
const bob = ContactScope(accountUuid: 'bob', network: 'regtest');
const id = 'abcdefghijklmnopqrstuvwx';

class MemoryJournal implements ContactDeliveryRepository {
  final values = <ContactScope, String>{};
  bool failSave = false;
  Completer<void>? readGate;
  @override
  Future<ContactDeliveryJournal> load(ContactScope scope) async {
    await readGate?.future;
    final raw = values[scope];
    return raw == null
        ? ContactDeliveryJournal()
        : ContactDeliveryJournal.decode(raw, scope);
  }

  @override
  Future<void> save(ContactScope scope, ContactDeliveryJournal journal) async {
    if (failSave) throw StateError('disk unavailable');
    values[scope] = journal.encode(scope);
  }
}

class FakeTransport implements ContactPacketTransport {
  FakeTransport(this.scope);
  @override
  final ContactScope scope;
  final sent = <(String, String, String)>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> submit(String peer, String id, String packet) async {
    sent.add((peer, id, packet));
    await gate?.future;
    if (fail) throw StateError('ambiguous network failure');
  }
}

void main() {
  late MemoryJournal store;
  late ContactScope? scope;
  late ContactDeliveryCoordinator coordinator;
  setUp(() {
    store = MemoryJournal();
    scope = alice;
    coordinator = ContactDeliveryCoordinator(
      scope: () => scope,
      repository: store,
    );
  });

  test('persist before send; restart retries exact id and bytes', () async {
    final key = await coordinator.enqueue('peer1', 'signed packet');
    final transport = FakeTransport(alice)..fail = true;
    await expectLater(coordinator.submit(key, transport), throwsStateError);
    coordinator = ContactDeliveryCoordinator(
      scope: () => scope,
      repository: store,
    );
    transport.fail = false;
    await coordinator.submit(key, transport);
    expect(transport.sent, [
      ('peer1', key, 'signed packet'),
      ('peer1', key, 'signed packet'),
    ]);
    expect(
      (await coordinator.overview()).single.state,
      ContactDeliveryState.submitted,
    );
    await coordinator.submit(key, transport);
    expect(transport.sent, hasLength(2));
  });

  test('failed persistence cannot create sendable work', () async {
    store.failSave = true;
    await expectLater(coordinator.enqueue('peer1', 'packet'), throwsStateError);
    store.failSave = false;
    expect(await coordinator.overview(), isEmpty);
  });

  test('same id on another peer is independent; conflicts reject', () async {
    expect(await coordinator.receive(alice, 'peer1', id, 'packet'), true);
    expect(await coordinator.receive(alice, 'peer1', id, 'packet'), false);
    expect(await coordinator.receive(alice, 'peer2', id, 'different'), true);
    await expectLater(
      coordinator.receive(alice, 'peer1', id, 'substitution'),
      throwsA(isA<ContactFailure>()),
    );
    await coordinator.dismiss('peer1', id);
    coordinator = ContactDeliveryCoordinator(
      scope: () => scope,
      repository: store,
    );
    expect(await coordinator.receive(alice, 'peer1', id, 'packet'), false);
    expect(
      (await coordinator.overview()).first.state,
      ContactDeliveryState.dismissed,
    );
  });

  test('lock during read prevents network action', () async {
    final key = await coordinator.enqueue('peer1', 'packet');
    store.readGate = Completer<void>();
    final transport = FakeTransport(alice);
    final work = coordinator.submit(key, transport);
    final rejected = expectLater(work, throwsA(isA<ContactFailure>()));
    await Future<void>.delayed(Duration.zero);
    scope = null;
    coordinator.invalidate();
    store.readGate!.complete();
    await rejected;
    expect(transport.sent, isEmpty);
  });

  test(
    'lock and unlock same account still invalidates an in-flight send',
    () async {
      final key = await coordinator.enqueue('peer1', 'packet');
      final transport = FakeTransport(alice)..gate = Completer<void>();
      final work = coordinator.submit(key, transport);
      final rejected = expectLater(work, throwsA(isA<ContactFailure>()));
      await Future<void>.delayed(Duration.zero);
      coordinator.invalidate();
      transport.gate!.complete();
      await rejected;
      expect(
        (await coordinator.overview()).single.state,
        ContactDeliveryState.queued,
      );
    },
  );

  test('wrong-scope transport and inbound callback reject', () async {
    final key = await coordinator.enqueue('peer1', 'packet');
    final transport = FakeTransport(bob);
    await expectLater(
      coordinator.submit(key, transport),
      throwsA(isA<ContactFailure>()),
    );
    await expectLater(
      coordinator.receive(bob, 'peer1', id, 'packet'),
      throwsA(isA<ContactFailure>()),
    );
    expect(transport.sent, isEmpty);
    scope = bob;
    expect(await coordinator.overview(), isEmpty);
  });

  test('concurrent deliveries do not lose writes', () async {
    await Future.wait([
      coordinator.receive(alice, 'peer1', id, 'one'),
      coordinator.receive(alice, 'peer2', id, 'two'),
    ]);
    expect(await coordinator.overview(), hasLength(2));
  });

  test('bounded journal retains replay tombstones and fails full', () async {
    for (var i = 0; i < contactDeliveryMaxRecords; i++) {
      await coordinator.receive(alice, 'peer$i', id, 'packet');
    }
    await coordinator.dismiss('peer0', id);
    await expectLater(
      coordinator.receive(alice, 'another', id, 'packet'),
      throwsA(isA<ContactFailure>()),
    );
    expect(await coordinator.receive(alice, 'peer0', id, 'packet'), false);
  });

  test('oversized UTF-8 and wrong-scope journals reject', () async {
    await expectLater(
      coordinator.enqueue('peer', 'é' * 10000),
      throwsA(isA<ContactFailure>()),
    );
    final raw = ContactDeliveryJournal().encode(alice);
    expect(
      () => ContactDeliveryJournal.decode(raw, bob),
      throwsA(isA<ContactFailure>()),
    );
  });
}
