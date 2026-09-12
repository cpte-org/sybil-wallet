import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import 'contact_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'renaming preserves authority and updates payment labels after save',
    () async {
      final original = testContact();
      final h = ContactHarness(repository: FakeContactRepository([original]));
      await h.ready();
      final recipient = h.controller.recipientFor(original.id);
      await h.controller.startRequest(contactId: original.id);
      h.repository.saveGate = Completer<void>();
      final pending = h.controller.renameContact(original.id, ' Alice café ');
      await pumpEventQueue();
      expect(() => h.validate(recipient), throwsA(isA<ContactFailure>()));
      expect(
        () => h.controller.recipientFor(original.id),
        throwsA(isA<ContactFailure>()),
      );
      h.repository.saveGate!.complete();
      await pending;
      final renamed = h.repository.contacts.single;
      expect(renamed.label, 'Alice café');
      expect(renamed.identity, original.identity);
      expect(renamed.address, original.address);
      expect(renamed.sequence, original.sequence);
      expect(renamed.status, original.status);
      expect(renamed.revision, original.revision + 1);
      expect(h.state.request, isNull);
      expect(h.controller.recipientFor(original.id).label, 'Alice café');
    },
  );

  test(
    'rename never makes restored, suspended or retired contacts payable',
    () async {
      for (final status in ContactTrustStatus.values.where(
        (s) => s != ContactTrustStatus.accepted,
      )) {
        final original = testContact(status: status);
        final h = ContactHarness(repository: FakeContactRepository([original]));
        await h.ready();
        await h.controller.renameContact(original.id, 'A private name');
        expect(h.repository.contacts.single.status, status);
        expect(h.repository.contacts.single.label, 'A private name');
        expect(
          () => h.controller.recipientFor(original.id),
          throwsA(isA<ContactFailure>()),
        );
      }
    },
  );

  test('rename rejects collisions and invalid names without saving', () async {
    final h = ContactHarness(
      repository: FakeContactRepository([
        testContact(),
        testContact(id: 'bob', label: 'Bob', identityByte: 2),
      ]),
    );
    await h.ready();
    for (final label in ['bob', '', 'bad\nname', 'a' * 21]) {
      await h.controller.renameContact('alice', label);
      expect(h.state.error, isNotNull);
      expect(h.repository.saves, 0);
      expect(h.repository.contacts.first.label, 'Alice');
    }
  });

  test(
    'scope loss during rename cannot publish or allow a stale payment',
    () async {
      final h = ContactHarness(
        repository: FakeContactRepository([testContact()]),
      );
      await h.ready();
      final recipient = h.controller.recipientFor('alice');
      h.repository.loadGate = Completer<List<VerifiedContact>>();
      final pending = h.controller.renameContact('alice', 'A new label');
      await pumpEventQueue();
      await h.scope(null);
      h.repository.loadGate!.complete([testContact()]);
      await pending;
      expect(h.repository.saves, 0);
      expect(h.state.contacts, isEmpty);
      expect(() => h.validate(recipient), throwsA(isA<ContactFailure>()));
    },
  );
}
