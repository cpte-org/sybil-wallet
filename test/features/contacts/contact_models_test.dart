import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import 'contact_test_fixtures.dart';

void main() {
  test(
    'local labels trim surrounding space and reject empty, overlong and control text',
    () {
      expect(contactLabel(' Alice café '), 'Alice café');
      for (final label in [
        '',
        '   ',
        'x' * 21,
        'Ali\nce',
        'Ali\u007fce',
        String.fromCharCode(0xd800),
      ]) {
        expect(() => contactLabel(label), throwsA(isA<ContactFailure>()));
      }
    },
  );

  test(
    'contact snapshots preserve immutable identity and accepted receiving fields',
    () {
      final original = testContact();
      final snapshot = ContactRecipientSnapshot(
        scope: testContactScope,
        bookInstance: 'book',
        generation: 1,
        contact: original,
      );
      final changed = original.copyWith(
        label: 'New label',
        address: 'new-address',
        revision: 3,
      );
      expect(snapshot.label, 'Alice');
      expect(snapshot.address, 'test-address-old');
      expect(snapshot.contact, same(original));
      expect(changed.identity, original.identity);
      expect(changed.id, original.id);
      expect(changed.label, 'New label');
      expect(snapshot.fingerprint, 'book:1:alice:2');
    },
  );

  test(
    'only accepted contacts can pay; restored contacts can request verification',
    () {
      for (final status in ContactTrustStatus.values) {
        final contact = testContact(status: status);
        expect(contact.canPay, status == ContactTrustStatus.accepted);
        expect(
          contact.canRequestUpdate,
          status == ContactTrustStatus.accepted ||
              status == ContactTrustStatus.restored,
        );
      }
    },
  );

  test(
    'saved contact schema rejects extra authority fields and noncanonical label or identity',
    () {
      expect(
        VerifiedContact.decode(testContact().toJson()).toJson(),
        testContact().toJson(),
      );
      for (final entry in <String, Object?>{
        'seed': 'not allowed',
        'label': ' Alice ',
        'identity': '${testIdentity(1)}=',
        'sequence': 9007199254740992,
        'revision': -1,
      }.entries) {
        final map = testContact().toJson();
        map[entry.key] = entry.value;
        expect(
          () => VerifiedContact.decode(map),
          throwsA(isA<ContactFailure>()),
        );
      }
      for (final value in [0, -1, 1.0, '1', null, 9007199254740992]) {
        expect(() => contactInteger(value), throwsA(isA<ContactFailure>()));
      }
      expect(contactInteger(9007199254740991), 9007199254740991);
    },
  );
}
