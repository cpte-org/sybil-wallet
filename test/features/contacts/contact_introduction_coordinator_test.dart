import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_exchange_controller.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_lifecycle.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_mutation_gate.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_introduction_models.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import 'contact_test_fakes.dart';

import 'contact_introduction_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reciprocal setup requires exact independently approved pair and cannot reuse an outgoing key',
    () async {
      final a = IntroductionTestActor('pairing');
      await a.peer('Alice', 11, 12, paired: false);
      await expectLater(
        a.coordinator.createRequest('Alice', consent: true),
        throwsA(isA<ContactFailure>()),
      );
      final review = await a.coordinator.reviewAssociation(
        'Alice',
        testIdentity(12),
      );
      expect(review.peer.identity, testIdentity(11));
      expect(review.outgoingIdentity, testIdentity(12));
      await expectLater(
        a.coordinator.confirmAssociation(review, independentlyVerified: false),
        throwsA(isA<ContactFailure>()),
      );
      await a.coordinator.confirmAssociation(
        review,
        independentlyVerified: true,
      );
      final book = await a.book();
      expect(book.associations.single.incomingContactId, 'Alice');
      book.clearSecrets();
      await a.peer('Other', 31, 32, paired: false);
      final other = await a.coordinator.reviewAssociation(
        'Other',
        testIdentity(12),
      );
      await expectLater(
        a.coordinator.confirmAssociation(other, independentlyVerified: true),
        throwsA(isA<ContactFailure>()),
      );
    },
  );

  test(
    'three-party consent remains explicit and acceptance consumes request with provenance in one write',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughOffer();
      final bobReview = await c.bob.coordinator.reviewOffer('Alice', c.offer);
      await expectLater(
        c.bob.coordinator.confirmConsent(bobReview, consent: false),
        throwsA(isA<ContactFailure>()),
      );
      expect((await c.bob.book()).signers, isEmpty);
      c.consent = await c.bob.coordinator.confirmConsent(
        bobReview,
        consent: true,
      );
      final aliceReview = await c.alice.coordinator.reviewConsent(
        c.consent,
        suggestedContact: 'Bob',
      );
      await expectLater(
        c.alice.coordinator.confirmDelivery(aliceReview, consent: false),
        throwsA(isA<ContactFailure>()),
      );
      c.delivery = await c.alice.coordinator.confirmDelivery(
        aliceReview,
        consent: true,
      );
      final review = await c.carol.coordinator.reviewDelivery(c.delivery);
      expect((await c.carol.book()).contacts.length, 1);
      await expectLater(
        c.carol.coordinator.acceptDelivery(
          review,
          label: 'Bob',
          consent: false,
        ),
        throwsA(isA<ContactFailure>()),
      );
      final writes = c.carol.store.writes;
      final accepted = await c.carol.coordinator.acceptDelivery(
        review,
        label: 'Bob',
        consent: true,
      );
      expect(c.carol.store.writes, writes + 1);
      final book = await c.carol.book();
      expect(book.contacts.last.toJson(), accepted.toJson());
      expect(book.sessions.single.phase, ContactIntroductionPhase.accepted);
      expect(book.provenance.single.introducedContactId, accepted.id);
      expect(book.provenance.single.introducerIdentity, testIdentity(11));
      book.clearSecrets();
      await expectLater(
        c.carol.coordinator.reviewDelivery(c.delivery),
        throwsA(isA<ContactFailure>()),
      );
    },
  );

  test(
    'subject retries use the same published reply and key after reopen, never a new allocation',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughConsent();
      final identityCreates = c.bob.direct.identityCreates,
          signatures = c.bob.wire.signatures;
      c.bob.coordinator.dispose();
      c.bob.reopen();
      final review = await c.bob.coordinator.reviewOffer('Alice', c.offer);
      expect(review.retry, isTrue);
      expect(
        await c.bob.coordinator.confirmConsent(review, consent: true),
        c.consent,
      );
      expect(c.bob.direct.identityCreates, identityCreates);
      expect(c.bob.wire.signatures, signatures);
      final book = await c.bob.book();
      expect(book.signers.length, 1);
      book.clearSecrets();
    },
  );

  test(
    'an introducer can explicitly review and resend the same saved endorsement after restart',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughDelivery();
      final before = c.alice.wire.signatures;
      final book = await c.alice.book();
      final hash = book.sessions.single.requestHash;
      book.clearSecrets();
      c.alice.coordinator.dispose();
      c.alice.reopen();
      await expectLater(
        c.alice.coordinator.reviewConsent(c.consent, suggestedContact: 'Bob'),
        throwsA(isA<ContactFailure>()),
      );
      final review = await c.alice.coordinator.reviewSavedDelivery(hash);
      expect(review.retry, isTrue);
      await expectLater(
        c.alice.coordinator.confirmDelivery(review, consent: false),
        throwsA(isA<ContactFailure>()),
      );
      expect(
        await c.alice.coordinator.confirmDelivery(review, consent: true),
        c.delivery,
      );
      expect(c.alice.wire.signatures, before);
      await c.alice.coordinator.cancel();
      await expectLater(
        c.alice.coordinator.reviewSavedDelivery(hash),
        throwsA(isA<ContactFailure>()),
      );
    },
  );

  test(
    'same request with changed offer details is a conflict even if its signature verifies',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughConsent();
      final altered = jsonDecode(c.offer) as Map<String, dynamic>;
      altered['suggestion'] = 'Someone else';
      await expectLater(
        c.bob.coordinator.reviewOffer('Alice', jsonEncode(altered)),
        throwsA(isA<ContactFailure>()),
      );
      expect(c.bob.direct.identityCreates, 1);
    },
  );

  test(
    'restart, cancellation and expiry never restore a pending requester',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughDelivery();
      c.carol.coordinator.dispose();
      c.carol.reopen();
      await expectLater(
        c.carol.coordinator.reviewDelivery(c.delivery),
        throwsA(isA<ContactFailure>()),
      );
      final fresh = await c.carol.coordinator.createRequest(
        'Alice',
        consent: true,
      );
      expect(fresh, isNot(c.ask));
      await c.carol.coordinator.cancel();
      final book = await c.carol.book();
      expect(book.sessions.last.phase, ContactIntroductionPhase.cancelled);
      book.clearSecrets();
      await expectLater(
        c.carol.coordinator.reviewDelivery(c.delivery),
        throwsA(isA<ContactFailure>()),
      );
      c.bob.now = c.bob.now.add(const Duration(minutes: 16));
      await expectLater(
        c.bob.coordinator.reviewOffer('Alice', c.offer),
        throwsA(isA<ContactFailure>()),
      );
    },
  );

  test(
    'cancelled unpublished subject review leaves a durable tombstone and clears the fresh key',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughOffer();
      await c.bob.coordinator.reviewOffer('Alice', c.offer);
      await c.bob.coordinator.cancel();
      final book = await c.bob.book();
      expect(book.sessions.single.phase, ContactIntroductionPhase.cancelled);
      expect(book.signers, isEmpty);
      book.clearSecrets();
      c.bob.coordinator.dispose();
      c.bob.reopen();
      await expectLater(
        c.bob.coordinator.reviewOffer('Alice', c.offer),
        throwsA(isA<ContactFailure>()),
      );
    },
  );

  test(
    'pause clears both freshly allocated and loaded relationship key buffers before pending work resolves',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughOffer();
      final gate = Completer<String>();
      c.bob.direct.addressGate = gate;
      final preparing = c.bob.coordinator.reviewOffer('Alice', c.offer);
      await pumpEventQueue();
      expect(c.bob.direct.createdSigners.single.secret, contains(isNonZero));
      c.bob.coordinator.pauseReview();
      expect(c.bob.direct.createdSigners.single.secret, everyElement(0));
      final rejected = expectLater(preparing, throwsA(isA<ContactFailure>()));
      gate.complete('fresh-bob');
      await rejected;
      c.bob.direct.addressGate = null;
      final validation = Completer<void>();
      c.bob.wire.associationGate = validation;
      c.bob.wire.associationEntered = Completer<void>();
      final pairing = c.bob.coordinator.reviewAssociation(
        'Alice',
        testIdentity(22),
      );
      await c.bob.wire.associationEntered!.future;
      c.bob.coordinator.pauseReview();
      expect(c.bob.wire.loans.last.secret, everyElement(0));
      final rejectedPair = expectLater(pairing, throwsA(isA<ContactFailure>()));
      validation.complete();
      await rejectedPair;
    },
  );

  test(
    'pause clears decoded durable signer buffers while a verification is still pending',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughConsent();
      c.bob.wire.verifyGate = Completer<void>();
      c.bob.wire.verifyEntered = Completer<void>();
      final pending = c.bob.coordinator.reviewOffer('Alice', c.offer);
      await c.bob.wire.verifyEntered!.future;
      final loaded = c.bob.repo.loaded.last;
      expect(loaded.signers.single.secret, everyElement(50));
      c.bob.coordinator.pauseReview();
      expect(loaded.signers.single.secret, everyElement(0));
      final rejected = expectLater(pending, throwsA(isA<ContactFailure>()));
      c.bob.wire.verifyGate!.complete();
      await rejected;
      final saved = await c.bob.book();
      expect(saved.signers.single.secret, everyElement(50));
      saved.clearSecrets();
    },
  );

  test(
    'pause clears a newly copied signer while its durable publication is pending',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughOffer();
      final review = await c.bob.coordinator.reviewOffer('Alice', c.offer);
      c.bob.store.writeGate = Completer<void>();
      c.bob.store.writeEntered = Completer<void>();
      final pending = c.bob.coordinator.confirmConsent(review, consent: true);
      await c.bob.store.writeEntered!.future;
      final submitted = c.bob.repo.submitted.last;
      expect(submitted.signers.single.secret, everyElement(50));
      c.bob.coordinator.pauseReview();
      expect(submitted.signers.single.secret, everyElement(0));
      final rejected = expectLater(pending, throwsA(isA<ContactFailure>()));
      c.bob.store.writeGate!.complete();
      await rejected;
      c.bob.store.writeGate = null;
      final saved = await c.bob.book();
      expect(saved.signers.single.secret, everyElement(50));
      expect(saved.sessions.single.phase, ContactIntroductionPhase.published);
      final packet = saved.sessions.single.outputPacket;
      saved.clearSecrets();
      final retry = await c.bob.coordinator.reviewOffer('Alice', c.offer);
      expect(
        await c.bob.coordinator.confirmConsent(retry, consent: true),
        packet,
      );
      expect(c.bob.direct.identityCreates, 1);
    },
  );

  test(
    'uncertain subject write exposes no reply and later reconciles the exact stored key and packet',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughOffer();
      final review = await c.bob.coordinator.reviewOffer('Alice', c.offer);
      c.bob.store.failAfterWrite = true;
      await expectLater(
        c.bob.coordinator.confirmConsent(review, consent: true),
        throwsStateError,
      );
      c.bob.store.failAfterWrite = false;
      final book = await c.bob.book();
      final saved = book.sessions.single.outputPacket;
      expect(book.signers.single.identity, review.identity);
      book.clearSecrets();
      c.bob.coordinator.dispose();
      c.bob.reopen();
      final retry = await c.bob.coordinator.reviewOffer('Alice', c.offer);
      expect(
        await c.bob.coordinator.confirmConsent(retry, consent: true),
        saved,
      );
      expect(c.bob.direct.identityCreates, 1);
    },
  );

  test(
    'cancelling during initial request write suppresses export and tombstones the newly persisted request',
    () async {
      final a = IntroductionTestActor('cancel-create');
      await a.peer('Alice', 11, 12);
      a.store.writeGate = Completer<void>();
      a.store.writeEntered = Completer<void>();
      final request = a.coordinator.createRequest('Alice', consent: true);
      await a.store.writeEntered!.future;
      final cancelled = a.coordinator.cancel();
      final rejected = expectLater(request, throwsA(isA<ContactFailure>()));
      a.store.writeGate!.complete();
      await rejected;
      await cancelled;
      final book = await a.book();
      expect(book.sessions.single.phase, ContactIntroductionPhase.cancelled);
      book.clearSecrets();
    },
  );

  test(
    'trust changes during review block acceptance and old identities cannot be reintroduced',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughDelivery();
      final review = await c.carol.coordinator.reviewDelivery(c.delivery);
      await c.carol.suspend('Alice');
      await expectLater(
        c.carol.coordinator.acceptDelivery(review, label: 'Bob', consent: true),
        throwsA(isA<ContactFailure>()),
      );
      final book = await c.carol.book();
      expect(book.contacts.length, 1);
      book.clearSecrets();
      final other = IntroductionTestCeremony();
      await other.throughConsent();
      final b = await other.alice.book();
      final endpoint = jsonDecode(other.consent) as Map<String, dynamic>;
      await other.alice.repo.saveBook(
        other.alice.fixed,
        b.copyWith(
          contacts: [
            ...b.contacts,
            testContact(
              id: 'old',
              label: 'Old',
              identityByte: 50,
              status: ContactTrustStatus.retired,
            ),
          ],
        ),
      );
      b.clearSecrets();
      expect(endpoint['identity'], testIdentity(50));
      await expectLater(
        other.alice.coordinator.reviewConsent(
          other.consent,
          suggestedContact: 'Bob',
        ),
        throwsA(isA<ContactFailure>()),
      );
    },
  );

  test(
    'scope changes and clock rollback invalidate work crossing an asynchronous verification boundary',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughDelivery();
      c.carol.wire.verifyGate = Completer<void>();
      c.carol.wire.verifyEntered = Completer<void>();
      final pending = c.carol.coordinator.reviewDelivery(c.delivery);
      await c.carol.wire.verifyEntered!.future;
      c.carol.current = null;
      c.carol.coordinator.invalidate();
      c.carol.current = c.carol.fixed;
      final rejected = expectLater(pending, throwsA(isA<ContactFailure>()));
      c.carol.wire.verifyGate!.complete();
      await rejected;
      c.carol.wire.verifyGate = null;
      c.carol.now = c.carol.now.subtract(const Duration(seconds: 1));
      await expectLater(
        c.carol.coordinator.createRequest('Alice', consent: true),
        throwsA(isA<ContactFailure>()),
      );
    },
  );

  test(
    'a queued direct suspension preserves the newly accepted contact and invalidates stale payment snapshots',
    () async {
      final c = IntroductionTestCeremony();
      await c.throughDelivery();
      final container = ProviderContainer(
        overrides: [
          contactScopeProvider.overrideWith((_) => c.carol.current),
          contactRepositoryProvider.overrideWithValue(c.carol.directRepo),
          contactGatewayProvider.overrideWithValue(c.carol.direct),
          contactClockProvider.overrideWithValue(() => c.carol.now),
        ],
      );
      addTearDown(container.dispose);
      final direct = container.read(contactExchangeProvider.notifier);
      await pumpEventQueue();
      final old = direct.recipientFor('Alice');
      final review = await c.carol.coordinator.reviewDelivery(c.delivery);
      c.carol.wire.verifyGate = Completer<void>();
      c.carol.wire.verifyEntered = Completer<void>();
      final acceptance = c.carol.coordinator.acceptDelivery(
        review,
        label: 'Bob',
        consent: true,
      );
      await c.carol.wire.verifyEntered!.future;
      final suspension = direct.suspendContact('Alice');
      expect(
        () => direct.validateRecipient(
          old,
          address: old.address,
          accountUuid: old.scope.accountUuid,
          network: old.scope.network,
        ),
        throwsA(isA<ContactFailure>()),
      );
      c.carol.wire.verifyGate!.complete();
      await acceptance;
      await suspension;
      await pumpEventQueue();
      final book = await c.carol.book();
      expect(book.contacts.length, 2);
      expect(
        book.contacts.firstWhere((x) => x.id == 'Alice').status,
        ContactTrustStatus.suspended,
      );
      expect(book.provenance.length, 1);
      book.clearSecrets();
    },
  );

  test(
    'lifecycle quiescence drains queued writes and nested owners cannot resume each other',
    () async {
      final a = IntroductionTestActor('drain');
      await a.peer('Alice', 11, 12);
      final gate = Completer<void>();
      final entered = Completer<void>();
      final running = ContactMutationGate.run(a.fixed, () {
        entered.complete();
        return gate.future;
      }, mutation: true);
      await entered.future;
      final first = ContactLifecycle.quiesce(account: a.fixed.accountUuid);
      final second = ContactLifecycle.quiesce(account: a.fixed.accountUuid);
      await expectLater(
        a.coordinator.createRequest('Alice', consent: true),
        throwsA(isA<ContactFailure>()),
      );
      gate.complete();
      await running;
      await first;
      await second;
      ContactLifecycle.resume(account: a.fixed.accountUuid);
      expect(ContactLifecycle.allowed(a.fixed.accountUuid), isFalse);
      ContactLifecycle.resume(account: a.fixed.accountUuid);
      expect(ContactLifecycle.allowed(a.fixed.accountUuid), isTrue);
    },
  );
}
