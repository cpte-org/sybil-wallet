import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import 'contact_exchange_test_support.dart';

/// Plaintext presentation examples only. No keys, signatures, persisted wallet
/// data, or live addresses are loaded to build these widget fixtures.
abstract final class ContactExchangeFixtures {
  static const identity = 'ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  static const oldAddress = 'u1old-contact-address-presentation-fixture';
  static const newAddress = 'u1new-contact-address-presentation-fixture';
  static const requestJson = '{"presentation":"contact-request"}';
  static const responseJson = '{"presentation":"contact-response"}';

  static const alice = VerifiedContact(
    id: 'alice',
    label: 'Alice',
    identity: identity,
    address: oldAddress,
    sequence: 1,
    revision: 1,
  );
  static final suspendedAlice = alice.copyWith(
    status: ContactTrustStatus.suspended,
  );
  static final restoredAlice = alice.copyWith(
    status: ContactTrustStatus.restored,
  );
  static final expiry = contactTestNow.add(const Duration(minutes: 10));
  static final request = ContactRequestView(
    json: requestJson,
    expiresAt: expiry,
  );
  static final candidate = ContactCandidateView(
    identity: identity,
    address: newAddress,
    sequence: 1,
    expiresAt: expiry,
  );
  static final update = ContactCandidateView(
    identity: identity,
    address: newAddress,
    previousAddress: oldAddress,
    label: 'Alice',
    sequence: 2,
    expiresAt: expiry,
  );
  static final share = ContactShareReview(
    identity: identity,
    address: newAddress,
    audience: 'ed25519:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
    expiresAt: expiry,
  );
  static final shareUpdate = ContactShareReview(
    identity: identity,
    address: newAddress,
    audience: 'ed25519:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
    previousAddress: oldAddress,
    expiresAt: expiry,
  );
  static const unavailable = ContactExchangeState(
    unavailableReason: 'This account cannot use experimental contact exchange.',
  );
  static final newContact = ContactExchangeState(
    available: true,
    request: request,
    candidate: candidate,
  );
  static final updateContact = ContactExchangeState(
    available: true,
    contacts: const [alice],
    request: ContactRequestView(
      json: requestJson,
      expiresAt: expiry,
      contactId: alice.id,
      label: alice.label,
    ),
    candidate: update,
  );
  static final sharing = ContactExchangeState(
    available: true,
    shareReview: share,
  );
  static final response = ContactExchangeState(
    available: true,
    response: responseJson,
  );
}
