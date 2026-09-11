import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_binding_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_binding_repository.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_delivery_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_connection_binding.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_delivery.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'contact_test_fakes.dart';

const scope = ContactScope(accountUuid: 'binding-test', network: 'regtest');

class MemoryBindings implements ContactBindingRepository {
  List<ContactConnectionBinding> values = [];
  @override
  Future<List<ContactConnectionBinding>> load(ContactScope scope) async =>
      values.map((b) => ContactConnectionBinding.decode(b.toJson())).toList();
  @override
  Future<void> save(
    ContactScope scope,
    List<ContactConnectionBinding> bindings,
  ) async {
    values = bindings;
  }
}

class _Journal implements ContactDeliveryRepository {
  String? raw;
  @override
  Future<ContactDeliveryJournal> load(ContactScope scope) async => raw == null
      ? ContactDeliveryJournal()
      : ContactDeliveryJournal.decode(raw!, scope);
  @override
  Future<void> save(ContactScope scope, ContactDeliveryJournal j) async {
    raw = j.encode(scope);
  }
}

class Channel implements ContactPacketTransport, ContactChannelTransport {
  @override
  ContactScope get scope =>
      const ContactScope(accountUuid: 'binding-test', network: 'regtest');
  String code = '123456789012345678901234567890';
  int sends = 0;
  bool fail = false;
  Completer<String>? codeGate;
  @override
  Future<String> securityCode(String peer) async =>
      codeGate == null ? code : await codeGate!.future;
  @override
  Future<void> submit(String peer, String id, String packet) async {
    sends++;
    if (fail) throw StateError('ambiguous network');
  }
}

void main() {
  late MemoryBindings repository;
  late FakeContactRepository contacts;
  late ContactBindingCoordinator bindings;
  late Channel channel;
  setUp(() {
    repository = MemoryBindings();
    contacts = FakeContactRepository([
      testContact(id: 'alice', label: 'Alice', identityByte: 7),
    ]);
    bindings = ContactBindingCoordinator(
      scope: () => scope,
      repository: repository,
      contacts: contacts,
    );
    channel = Channel();
  });
  Future<ContactConnectionBinding> bind() async {
    final review = await bindings.prepare('alice', '1', channel);
    await bindings.confirm(review, channel, independentlyVerified: true);
    return repository.values.single;
  }

  test(
    'comparison approval is required; code and contact are rechecked before saving',
    () async {
      final review = await bindings.prepare('alice', '1', channel);
      await expectLater(
        bindings.confirm(review, channel, independentlyVerified: false),
        throwsA(isA<ContactFailure>()),
      );
      expect(repository.values, isEmpty);
      channel.code = '999999999999999999999999999999';
      await expectLater(
        bindings.confirm(review, channel, independentlyVerified: true),
        throwsA(isA<ContactFailure>()),
      );
      expect(repository.values, isEmpty);
      await bind();
      expect((await bindings.resolve('alice', channel))!.code, channel.code);
    },
  );
  test('two contacts cannot claim the same checked connection', () async {
    await bind();
    contacts.contacts.add(
      testContact(id: 'bob', label: 'Bob', identityByte: 8),
    );
    final review = await bindings.prepare('bob', '1', channel);
    await expectLater(
      bindings.confirm(review, channel, independentlyVerified: true),
      throwsA(isA<ContactFailure>()),
    );
    expect(repository.values, hasLength(1));
  });
  test(
    'automatic routing cannot replace the identity pinned by the review',
    () async {
      await bind();
      await expectLater(
        bindings.resolve('alice', channel, expectedIdentity: testIdentity(9)),
        throwsA(isA<ContactFailure>()),
      );
    },
  );
  test(
    'invalidation while reading the code cannot publish a binding review',
    () async {
      channel.codeGate = Completer<String>();
      final pending = bindings.prepare('alice', '1', channel);
      await pumpEventQueue();
      bindings.invalidate();
      final rejected = expectLater(pending, throwsA(isA<ContactFailure>()));
      channel.codeGate!.complete(channel.code);
      await rejected;
      expect(repository.values, isEmpty);
    },
  );
  for (final change in ['code', 'forgotten', 'suspended', 'identity']) {
    test('persisted retry stops after $change changes', () async {
      final binding = await bind();
      final journal = _Journal();
      var delivery = ContactDeliveryCoordinator(
        scope: () => scope,
        repository: journal,
        validateBinding: bindings.checkForSend,
      );
      final id = await delivery.enqueue(
        '1',
        'approved packet',
        binding: binding,
      );
      channel.fail = true;
      await expectLater(delivery.submit(id, channel), throwsStateError);
      expect(channel.sends, 1);
      delivery = ContactDeliveryCoordinator(
        scope: () => scope,
        repository: journal,
        validateBinding: bindings.checkForSend,
      );
      switch (change) {
        case 'code':
          channel.code = '999999999999999999999999999999';
        case 'forgotten':
          await bindings.forget('alice');
        case 'suspended':
          contacts.contacts[0] = contacts.contacts[0].copyWith(
            status: ContactTrustStatus.suspended,
          );
        case 'identity':
          contacts.contacts[0] = testContact(
            id: 'alice',
            label: 'Alice',
            identityByte: 9,
          );
      }
      channel.fail = false;
      await expectLater(
        delivery.submit(id, channel),
        throwsA(isA<ContactFailure>()),
      );
      expect(channel.sends, 1);
      expect(
        (await delivery.overview()).single.state,
        ContactDeliveryState.queued,
      );
    });
  }
  test(
    'bound journal cannot silently downgrade when the checker is absent',
    () async {
      final binding = await bind(), journal = _Journal();
      final delivery = ContactDeliveryCoordinator(
        scope: () => scope,
        repository: journal,
      );
      final id = await delivery.enqueue(
        '1',
        'approved packet',
        binding: binding,
      );
      await expectLater(
        delivery.submit(id, channel),
        throwsA(isA<ContactFailure>()),
      );
      expect(channel.sends, 0);
    },
  );
}
