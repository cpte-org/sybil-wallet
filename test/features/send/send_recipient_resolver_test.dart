// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_review_layout.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

import '../contacts/contact_test_fakes.dart';

const _address = 'u1selftransfertargetaddress0000000000000001';

AddressBookContact _contact(String label, String address) {
  return AddressBookContact(
    id: 'id-$label',
    label: label,
    network: AddressBookNetwork.zcash,
    address: address,
    profilePictureId: 'pfp-03',
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}

void main() {
  test(
    'selected contact label survives a conflicting legacy address label',
    () {
      final selected = ContactRecipientSnapshot(
        scope: testContactScope,
        bookInstance: 'test-contact-book',
        generation: 1,
        contact: testContact(label: 'Alice from the café', address: _address),
      );
      final recipient = sendReviewRecipientFor(
        contacts: [_contact('Another person', _address)],
        address: _address,
        contactRecipient: selected,
      );

      expect(
        recipient,
        isA<SendReviewContactRecipient>()
            .having(
              (r) => r.name,
              'captured local label',
              'Alice from the café',
            )
            .having((r) => r.address, 'selected address', _address),
      );
    },
  );

  test('a captured contact label is never displayed for another address', () {
    final selected = ContactRecipientSnapshot(
      scope: testContactScope,
      bookInstance: 'test-contact-book',
      generation: 1,
      contact: testContact(address: 'different-contact-address'),
    );

    final recipient = sendReviewRecipientFor(
      contacts: const [],
      address: _address,
      contactRecipient: selected,
    );

    expect(recipient, isA<SendReviewAddressRecipient>());
  });

  test('unknown address resolves to the raw-address variant', () {
    final recipient = sendReviewRecipientFor(
      contacts: const [],
      address: _address,
    );
    expect(recipient, isA<SendReviewAddressRecipient>());
  });

  test('own account resolves to the contact variant with the account name', () {
    final recipient = sendReviewRecipientFor(
      contacts: const [],
      address: _address,
      ownAccounts: {
        _address: const AccountInfo(
          uuid: 'uuid-1',
          name: 'Savings',
          profilePictureId: 'pfp-07',
          order: 0,
        ),
      },
    );
    expect(
      recipient,
      isA<SendReviewContactRecipient>()
          .having((r) => r.name, 'name', 'Savings')
          .having((r) => r.profilePictureId, 'pfp', 'pfp-07'),
    );
  });

  test('own-account match trims the recipient address', () {
    final recipient = sendReviewRecipientFor(
      contacts: const [],
      address: '  $_address  ',
      ownAccounts: {
        _address: const AccountInfo(uuid: 'uuid-1', name: 'Savings', order: 0),
      },
    );
    expect(recipient, isA<SendReviewContactRecipient>());
  });

  group('paymentRequestRecipientIdentityFor', _paymentRequestIdentityTests);

  test('a saved contact wins over the own-account match', () {
    final recipient = sendReviewRecipientFor(
      contacts: [_contact('Mike', _address)],
      address: _address,
      ownAccounts: {
        _address: const AccountInfo(uuid: 'uuid-1', name: 'Savings', order: 0),
      },
    );
    expect(
      recipient,
      isA<SendReviewContactRecipient>().having((r) => r.name, 'name', 'Mike'),
    );
  });
}

void _paymentRequestIdentityTests() {
  test('an unknown address gets no identity at all', () {
    expect(
      paymentRequestRecipientIdentityFor(contacts: const [], address: _address),
      isNull,
    );
  });

  test('a saved contact resolves to the contact identity', () {
    final identity = paymentRequestRecipientIdentityFor(
      contacts: [_contact('Mike', _address)],
      address: _address,
    );
    expect(
      identity,
      isA<PaymentRequestRecipientIdentity>()
          .having((i) => i.kind, 'kind', PaymentRequestRecipientKind.contact)
          .having((i) => i.name, 'name', 'Mike')
          .having((i) => i.profilePictureId, 'pfp', 'pfp-03')
          .having((i) => i.isOwnAccount, 'isOwnAccount', isFalse),
    );
  });

  test('an own account resolves to the own-account identity', () {
    final identity = paymentRequestRecipientIdentityFor(
      contacts: const [],
      address: _address,
      ownAccounts: {
        _address: const AccountInfo(
          uuid: 'uuid-1',
          name: 'Savings',
          profilePictureId: 'pfp-07',
          order: 0,
        ),
      },
    );
    expect(
      identity,
      isA<PaymentRequestRecipientIdentity>()
          .having((i) => i.kind, 'kind', PaymentRequestRecipientKind.ownAccount)
          .having((i) => i.name, 'name', 'Savings')
          .having((i) => i.profilePictureId, 'pfp', 'pfp-07')
          .having((i) => i.isOwnAccount, 'isOwnAccount', isTrue),
    );
  });

  test('a saved contact wins over the own-account match', () {
    // Same precedence as `sendReviewRecipientFor`: the card hands off to the
    // review screen for this address, and the two must not name it
    // differently.
    final identity = paymentRequestRecipientIdentityFor(
      contacts: [_contact('Mike', _address)],
      address: _address,
      ownAccounts: {
        _address: const AccountInfo(
          uuid: 'uuid-1',
          name: 'Savings',
          profilePictureId: 'pfp-07',
          order: 0,
        ),
      },
    );
    expect(identity!.isOwnAccount, isFalse);
    expect(identity.name, 'Mike');
  });

  test('the own-account match trims the recipient address', () {
    final identity = paymentRequestRecipientIdentityFor(
      contacts: const [],
      address: '  $_address  ',
      ownAccounts: {
        _address: const AccountInfo(uuid: 'uuid-1', name: 'Savings', order: 0),
      },
    );
    expect(identity?.isOwnAccount, isTrue);
  });

  test('a case-shifted address matches neither source', () {
    // Zcash addresses are case-sensitive; a near-miss is a different address.
    final shifted = _address.toUpperCase();
    expect(
      paymentRequestRecipientIdentityFor(
        contacts: [_contact('Mike', _address)],
        address: shifted,
        ownAccounts: {
          _address: const AccountInfo(
            uuid: 'uuid-1',
            name: 'Savings',
            order: 0,
          ),
        },
      ),
      isNull,
    );
  });

  test('a blank-labelled contact falls back to the own account', () {
    final identity = paymentRequestRecipientIdentityFor(
      contacts: [_contact('   ', _address)],
      address: _address,
      ownAccounts: {
        _address: const AccountInfo(uuid: 'uuid-1', name: 'Savings', order: 0),
      },
    );
    expect(identity!.isOwnAccount, isTrue);
    expect(identity.name, 'Savings');
  });

  test('a blank name is not an identity the card will render', () {
    const view = PaymentRequestView(
      source: PaymentRequestSource.link,
      address: _address,
      recipientIdentity: PaymentRequestRecipientIdentity.contact(
        name: '  ',
        profilePictureId: 'pfp-03',
      ),
    );
    expect(view.recipientIdentity, isNotNull);
    expect(view.displayRecipientIdentity, isNull);
  });
}
