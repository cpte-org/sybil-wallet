import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_lifecycle.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_gateway.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import 'contact_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(
    () => ContactLifecycle.resume(account: testContactScope.accountUuid),
  );

  test(
    'direct acceptance requires an independent check and consumes the request only after save',
    () async {
      final h = ContactHarness();
      await h.ready();
      await h.candidate();
      await h.controller.acceptResponse(
        label: 'Alice',
        independentlyVerified: false,
      );
      expect(h.repository.saves, 0);
      expect(h.state.candidate, isNotNull);
      expect(h.state.error, contains('trusted exchange'));
      await h.controller.acceptResponse(
        label: ' Alice ',
        independentlyVerified: true,
      );
      expect(h.gateway.verifications, 2);
      expect(h.repository.contacts.single.label, 'Alice');
      expect(h.state.request, isNull);
      expect(h.state.candidate, isNull);
      final recipient = h.controller.recipientFor(h.state.contacts.single.id);
      expect(() => h.validate(recipient), returnsNormally);
      await h.controller.previewResponse('signed-response');
      expect(h.state.error, contains('request first'));
      expect(h.repository.saves, 1);
      await h.controller.startRequest();
      await h.controller.previewResponse('signed-response');
      expect(h.state.error, contains('already recorded'));
      expect(h.state.candidate, isNull);
    },
  );

  test('new contact label collisions are local and case insensitive', () async {
    final h = ContactHarness(
      repository: FakeContactRepository([testContact(identityByte: 2)]),
    );
    await h.ready();
    await h.candidate();
    await h.controller.acceptResponse(
      label: 'alice',
      independentlyVerified: true,
    );
    expect(h.repository.saves, 0);
    expect(h.state.error, contains('distinguishes'));
    await h.controller.acceptResponse(
      label: 'Alice café',
      independentlyVerified: true,
    );
    expect(h.repository.contacts, hasLength(2));
  });

  test(
    'higher same-identity revision updates the existing contact after explicit acceptance',
    () async {
      final original = testContact();
      final h = ContactHarness(repository: FakeContactRepository([original]));
      await h.ready();
      final stale = h.controller.recipientFor(original.id);
      await h.candidate(contactId: original.id);
      expect(h.gateway.requestedSubject, original.identity);
      expect(h.state.candidate!.previousAddress, original.address);
      expect(h.repository.contacts.single.address, original.address);
      await h.controller.acceptResponse(
        label: original.label,
        independentlyVerified: true,
      );
      final updated = h.repository.contacts.single;
      expect(updated.id, original.id);
      expect(updated.identity, original.identity);
      expect(updated.label, original.label);
      expect(updated.address, 'test-address-new');
      expect(updated.sequence, 6);
      expect(updated.revision, original.revision + 1);
      expect(() => h.validate(stale), throwsA(isA<ContactFailure>()));
    },
  );

  test(
    'rollback, equal-revision address conflict, and different identity are rejected',
    () async {
      for (final endpoint in [
        ContactWireEndpoint(
          identity: testIdentity(1),
          address: 'test-address-new',
          sequence: 4,
          expiresAt: testContactNow.add(const Duration(minutes: 5)),
        ),
        ContactWireEndpoint(
          identity: testIdentity(1),
          address: 'test-address-new',
          sequence: 5,
          expiresAt: testContactNow.add(const Duration(minutes: 5)),
        ),
        ContactWireEndpoint(
          identity: testIdentity(2),
          address: 'test-address-new',
          sequence: 6,
          expiresAt: testContactNow.add(const Duration(minutes: 5)),
        ),
      ]) {
        final h = ContactHarness(
          repository: FakeContactRepository([testContact()]),
        );
        await h.ready();
        h.gateway.endpoint = endpoint;
        await h.controller.startRequest(contactId: 'alice');
        await h.controller.previewResponse('response');
        expect(h.state.candidate, isNull);
        expect(h.state.error, isNotNull);
        expect(h.repository.saves, 0);
      }
    },
  );

  test(
    'equal revision with the same accepted address may be confirmed',
    () async {
      final original = testContact();
      final h = ContactHarness(repository: FakeContactRepository([original]));
      await h.ready();
      h.gateway.endpoint = ContactWireEndpoint(
        identity: original.identity,
        address: original.address,
        sequence: original.sequence,
        expiresAt: h.gateway.expiry,
      );
      await h.candidate(contactId: original.id);
      await h.controller.acceptResponse(
        label: original.label,
        independentlyVerified: true,
      );
      expect(h.repository.contacts.single.sequence, original.sequence);
      expect(h.repository.contacts.single.revision, original.revision + 1);
    },
  );

  test(
    'suspension invalidates prepared recipients before persistence finishes',
    () async {
      final h = ContactHarness(
        repository: FakeContactRepository([testContact()]),
      );
      await h.ready();
      final snapshot = h.controller.recipientFor('alice');
      h.repository.saveGate = Completer<void>();
      final operation = h.controller.suspendContact('alice');
      await pumpEventQueue();
      expect(() => h.validate(snapshot), throwsA(isA<ContactFailure>()));
      expect(
        () => h.controller.recipientFor('alice'),
        throwsA(isA<ContactFailure>()),
      );
      h.repository.saveGate!.complete();
      await operation;
      expect(h.repository.contacts.single.status, ContactTrustStatus.suspended);
      await h.controller.startRequest(contactId: 'alice');
      expect(h.state.request, isNull);
      expect(h.state.error, contains('suspended'));
    },
  );

  test('retired contacts cannot pay or authorize updates', () async {
    for (final status in [ContactTrustStatus.retired]) {
      final h = ContactHarness(
        repository: FakeContactRepository([testContact(status: status)]),
      );
      await h.ready();
      expect(
        () => h.controller.recipientFor('alice'),
        throwsA(isA<ContactFailure>()),
      );
      await h.controller.startRequest(contactId: 'alice');
      expect(h.state.request, isNull);
      expect(h.gateway.requestedSubject, isNull);
    }
  });

  test(
    'restored contact requires a fresh response and explicit recovery check',
    () async {
      final h = ContactHarness(
        repository: FakeContactRepository([
          testContact(status: ContactTrustStatus.restored),
        ]),
      );
      await h.ready();
      expect(
        () => h.controller.recipientFor('alice'),
        throwsA(isA<ContactFailure>()),
      );
      await h.controller.startRequest(contactId: 'alice');
      await h.controller.previewResponse('fixture-response');
      expect(h.state.candidate?.requiresRecoveryCheck, isTrue);
      await h.controller.acceptResponse(
        label: 'Alice',
        independentlyVerified: false,
      );
      expect(h.repository.contacts.single.canPay, isFalse);
      await h.controller.acceptResponse(
        label: 'Alice',
        independentlyVerified: true,
      );
      expect(h.repository.contacts.single.canPay, isTrue);
      expect(h.repository.contacts.single.address, 'test-address-new');
    },
  );

  test(
    'storage load failure and invalid saved addresses block contact payments',
    () async {
      final broken = FakeContactRepository([testContact()])
        ..loadError = StateError('test storage failure');
      final h = ContactHarness(repository: broken);
      await h.ready();
      expect(h.state.error, contains('storage'));
      expect(h.state.contacts, isEmpty);
      expect(
        () => h.controller.recipientFor('alice'),
        throwsA(isA<ContactFailure>()),
      );
      final other = ContactHarness(
        repository: FakeContactRepository([testContact()]),
        gateway: FakeContactGateway()..invalidAddresses.add('test-address-old'),
      );
      await other.ready();
      expect(other.state.error, contains('addresses'));
      expect(other.state.contacts, isEmpty);
    },
  );

  test(
    'failed contact save invalidates existing recipients until explicit reload',
    () async {
      final h = ContactHarness(
        repository: FakeContactRepository([testContact()]),
      );
      await h.ready();
      final snapshot = h.controller.recipientFor('alice');
      h.repository.saveError = StateError('save failed');
      await h.controller.suspendContact('alice');
      expect(h.repository.contacts.single.status, ContactTrustStatus.accepted);
      expect(() => h.validate(snapshot), throwsA(isA<ContactFailure>()));
      expect(
        () => h.controller.recipientFor('alice'),
        throwsA(isA<ContactFailure>()),
      );
      h.repository.saveError = null;
      await h.controller.reload();
      expect(() => h.controller.recipientFor('alice'), returnsNormally);
      expect(() => h.validate(snapshot), throwsA(isA<ContactFailure>()));
    },
  );

  test(
    'cancel and scope loss during verification cannot install late candidates',
    () async {
      for (final changeScope in [false, true]) {
        final h = ContactHarness();
        await h.ready();
        await h.controller.startRequest();
        h.gateway.verifyGate = Completer<ContactWireEndpoint>();
        final operation = h.controller.previewResponse('response');
        await pumpEventQueue();
        if (changeScope) {
          await h.scope(null);
        } else {
          h.controller.cancelTransient();
        }
        h.gateway.verifyGate!.complete(h.gateway.endpoint);
        await operation;
        expect(h.state.candidate, isNull);
        expect(h.state.request, isNull);
        expect(h.repository.saves, 0);
      }
    },
  );

  test(
    'scope change during acceptance verification rejects the late mutation',
    () async {
      final h = ContactHarness();
      await h.ready();
      await h.candidate();
      h.gateway.verifyGate = Completer<ContactWireEndpoint>();
      final operation = h.controller.acceptResponse(
        label: 'Alice',
        independentlyVerified: true,
      );
      await pumpEventQueue();
      await h.scope(
        const ContactScope(accountUuid: 'other', network: 'regtest'),
      );
      h.gateway.verifyGate!.complete(h.gateway.endpoint);
      await operation;
      expect(h.repository.saves, 0);
      expect(h.state.contacts, isEmpty);
    },
  );

  test(
    'response acceptance rechecks expiry after verification awaits',
    () async {
      final h = ContactHarness();
      await h.ready();
      await h.candidate();
      h.gateway.verifyGate = Completer<ContactWireEndpoint>();
      final operation = h.controller.acceptResponse(
        label: 'Alice',
        independentlyVerified: true,
      );
      await pumpEventQueue();
      h.now = h.gateway.expiry;
      h.gateway.verifyGate!.complete(h.gateway.endpoint);
      await operation;
      expect(h.repository.saves, 0);
      expect(h.state.error, contains('expired'));
    },
  );

  test(
    'share consent and persisted signer counter precede response release',
    () async {
      final h = ContactHarness();
      await h.ready();
      await h.controller.prepareShare('request');
      final signer = h.gateway.createdSigners.single;
      await h.controller.confirmShare(consent: false);
      expect(h.gateway.signatures, 0);
      h.repository.signerSaveGate = Completer<void>();
      final operation = h.controller.confirmShare(consent: true);
      await pumpEventQueue();
      expect(h.state.response, isNull);
      expect(h.repository.events, ['save-start']);
      h.repository.signerSaveGate!.complete();
      await operation;
      expect(h.repository.events, ['save-start', 'save-complete']);
      expect(h.repository.signers[signer.identity]!.sequence, 1);
      expect(h.state.response, 'signed-contact-response');
      expect(signer.secret, everyElement(0));
      h.gateway.incomingSubject = signer.identity;
      await h.controller.prepareShare('update-request');
      expect(h.state.shareReview!.previousAddress, 'test-address-fresh');
      await h.controller.confirmShare(consent: true);
      expect(h.repository.signers[signer.identity]!.sequence, 2);
      expect(h.repository.loadedSigners.single.secret, everyElement(0));
    },
  );

  test(
    'unknown relationship key never silently creates a new identity or resets its counter',
    () async {
      final h = ContactHarness();
      await h.ready();
      h.gateway.incomingSubject = testIdentity(9);
      await h.controller.prepareShare('update-request');
      expect(h.gateway.identityCreates, 0);
      expect(h.gateway.addressAllocations, 0);
      expect(h.state.shareReview, isNull);
      expect(h.state.error, contains('unavailable'));
    },
  );

  test(
    'failed signer persistence releases no response and cancellation clears key material',
    () async {
      final h = ContactHarness();
      await h.ready();
      await h.controller.prepareShare('request');
      h.repository.signerSaveError = StateError('storage failed');
      await h.controller.confirmShare(consent: true);
      expect(h.state.response, isNull);
      expect(h.repository.signers, isEmpty);
      h.controller.cancelTransient();
      expect(h.gateway.createdSigners.single.secret, everyElement(0));
    },
  );

  test(
    'cancellation during signing clears retained key and rejects late response',
    () async {
      final h = ContactHarness();
      await h.ready();
      await h.controller.prepareShare('request');
      h.gateway.signGate = Completer<String>();
      final operation = h.controller.confirmShare(consent: true);
      await pumpEventQueue();
      h.controller.cancelTransient();
      expect(h.gateway.createdSigners.single.secret, everyElement(0));
      h.gateway.signGate!.complete('late-signed-response');
      await operation;
      expect(h.repository.signerSaves, 0);
      expect(h.state.response, isNull);
    },
  );

  test(
    'cancellation during address allocation immediately clears in-flight signing key',
    () async {
      final h = ContactHarness();
      await h.ready();
      h.gateway.addressGate = Completer<String>();
      final operation = h.controller.prepareShare('request');
      await pumpEventQueue();
      final signer = h.gateway.createdSigners.single;
      h.controller.cancelTransient();
      try {
        expect(signer.secret, everyElement(0));
      } finally {
        h.gateway.addressGate!.complete('late-address');
        await operation;
      }
      expect(h.state.shareReview, isNull);
      expect(signer.secret, everyElement(0));
    },
  );

  test(
    'late identity creation after lock is cleared and never allocates an address',
    () async {
      final h = ContactHarness();
      await h.ready();
      h.gateway.identityGate = Completer<ContactSigner>();
      final operation = h.controller.prepareShare('request');
      await pumpEventQueue();
      await h.scope(null);
      final signer = ContactSigner(
        identity: testIdentity(3),
        secret: Uint8List.fromList(List.filled(32, 9)),
        address: '',
        sequence: 1,
      );
      h.gateway.identityGate!.complete(signer);
      await operation;
      expect(signer.secret, everyElement(0));
      expect(h.gateway.addressAllocations, 0);
      expect(h.state.shareReview, isNull);
    },
  );

  test(
    'lock during initial book load cannot hydrate late trusted contacts',
    () async {
      final repository = FakeContactRepository()
        ..loadGate = Completer<List<VerifiedContact>>();
      final h = ContactHarness(repository: repository);
      await pumpEventQueue();
      expect(h.state.loading, isTrue);
      await h.scope(null);
      repository.loadGate!.complete([testContact()]);
      await pumpEventQueue();
      expect(h.state.available, isFalse);
      expect(h.state.contacts, isEmpty);
      expect(
        () => h.controller.recipientFor('alice'),
        throwsA(isA<ContactFailure>()),
      );
    },
  );

  test(
    'cancel during signer persistence preserves the reserved counter without releasing a response',
    () async {
      final h = ContactHarness();
      await h.ready();
      await h.controller.prepareShare('request');
      final signer = h.gateway.createdSigners.single;
      h.repository.signerSaveGate = Completer<void>();
      final operation = h.controller.confirmShare(consent: true);
      await pumpEventQueue();
      expect(h.repository.signerSaves, 1);
      h.controller.cancelTransient();
      expect(signer.secret, everyElement(0));
      h.repository.signerSaveGate!.complete();
      await operation;
      expect(h.state.response, isNull);
      expect(h.repository.signers[signer.identity]!.sequence, 1);
      h.gateway.incomingSubject = signer.identity;
      await h.controller.prepareShare('update-request');
      await h.controller.confirmShare(consent: true);
      expect(h.repository.signers[signer.identity]!.sequence, 2);
      expect(h.state.response, 'signed-contact-response');
    },
  );

  test(
    'destructive quiescence cancels preparation immediately and waits for address allocation to drain',
    () async {
      final h = ContactHarness(
        repository: FakeContactRepository([testContact()]),
      );
      await h.ready();
      final snapshot = h.controller.recipientFor('alice');
      h.gateway.addressGate = Completer<String>();
      final preparation = h.controller.prepareShare('request');
      await pumpEventQueue();
      final signer = h.gateway.createdSigners.single;
      var drained = false;
      final quiescence = ContactLifecycle.quiesce(
        account: testContactScope.accountUuid,
      ).then((_) => drained = true);
      await pumpEventQueue();
      expect(signer.secret, everyElement(0));
      expect(drained, isFalse);
      expect(() => h.validate(snapshot), throwsA(isA<ContactFailure>()));
      h.gateway.addressGate!.complete('allocated-before-removal');
      await preparation;
      await quiescence;
      expect(drained, isTrue);
      expect(h.state.shareReview, isNull);
      expect(h.state.response, isNull);
      ContactLifecycle.resume(account: testContactScope.accountUuid);
      await pumpEventQueue();
      expect(() => h.controller.recipientFor('alice'), returnsNormally);
      expect(() => h.validate(snapshot), throwsA(isA<ContactFailure>()));
    },
  );

  test(
    'destructive quiescence drains a pending contact save before removal can proceed',
    () async {
      final h = ContactHarness();
      await h.ready();
      await h.candidate();
      h.repository.saveGate = Completer<void>();
      final acceptance = h.controller.acceptResponse(
        label: 'Alice',
        independentlyVerified: true,
      );
      await pumpEventQueue();
      expect(h.repository.saves, 1);
      var drained = false;
      final quiescence = ContactLifecycle.quiesce(
        account: testContactScope.accountUuid,
      ).then((_) => drained = true);
      await pumpEventQueue();
      expect(drained, isFalse);
      h.repository.saveGate!.complete();
      await acceptance;
      await quiescence;
      expect(drained, isTrue);
      expect(h.state.contacts, isEmpty);
      expect(h.state.request, isNull);
      expect(
        () => h.controller.recipientFor(h.repository.contacts.single.id),
        throwsA(isA<ContactFailure>()),
      );
    },
  );

  test(
    'background pause preserves only the pending public request and rejects late review completion',
    () async {
      final h = ContactHarness();
      await h.ready();
      await h.controller.startRequest();
      final request = h.state.request;
      h.gateway.verifyGate = Completer<ContactWireEndpoint>();
      final verification = h.controller.previewResponse('response');
      await pumpEventQueue();
      h.controller.pauseExchange();
      expect(h.state.request, same(request));
      expect(h.state.candidate, isNull);
      h.gateway.verifyGate!.complete(h.gateway.endpoint);
      await verification;
      expect(h.state.request, same(request));
      expect(h.state.candidate, isNull);
      h.gateway.verifyGate = null;
      await h.controller.previewResponse('response');
      expect(h.state.candidate, isNotNull);
      h.controller.pauseExchange();
      expect(h.state.candidate, isNull);
      expect(h.state.request, same(request));
      await h.scope(null);
      expect(h.state.request, isNull);
    },
  );

  test(
    'background pause clears share consent and keys during address preparation',
    () async {
      final h = ContactHarness();
      await h.ready();
      h.gateway.addressGate = Completer<String>();
      final preparation = h.controller.prepareShare('request');
      await pumpEventQueue();
      h.controller.pauseExchange();
      expect(h.gateway.createdSigners.single.secret, everyElement(0));
      expect(h.state.shareReview, isNull);
      h.gateway.addressGate!.complete('late-address');
      await preparation;
      expect(h.state.shareReview, isNull);
      expect(h.state.response, isNull);
    },
  );

  test('background pause never restores an expired pending request', () async {
    final h = ContactHarness();
    await h.ready();
    await h.controller.startRequest();
    h.now = h.gateway.expiry;
    h.controller.pauseExchange();
    expect(h.state.request, isNull);
    await h.controller.previewResponse('response');
    expect(h.state.candidate, isNull);
  });

  test(
    'accepted offline recipient remains usable after its exchange validity expires',
    () async {
      final h = ContactHarness();
      await h.ready();
      await h.candidate();
      await h.controller.acceptResponse(
        label: 'Alice',
        independentlyVerified: true,
      );
      final snapshot = h.controller.recipientFor(h.state.contacts.single.id);
      h.now = h.gateway.expiry.add(const Duration(days: 30));
      expect(() => h.validate(snapshot), returnsNormally);
      expect(
        () => h.controller.recipientFor(snapshot.contact.id),
        returnsNormally,
      );
    },
  );

  test(
    'recipient guard rejects changed address, account, network and substituted contact object',
    () async {
      final h = ContactHarness(
        repository: FakeContactRepository([testContact()]),
      );
      await h.ready();
      final snapshot = h.controller.recipientFor('alice');
      for (final (address, account, network) in [
        ('other-address', testContactScope.accountUuid, 'test'),
        (snapshot.address, 'other-account', 'test'),
        (snapshot.address, testContactScope.accountUuid, 'regtest'),
      ]) {
        expect(
          () => h.controller.validateRecipient(
            snapshot,
            address: address,
            accountUuid: account,
            network: network,
          ),
          throwsA(isA<ContactFailure>()),
        );
      }
      final forged = ContactRecipientSnapshot(
        scope: snapshot.scope,
        bookInstance: snapshot.bookInstance,
        generation: snapshot.generation,
        contact: snapshot.contact.copyWith(address: 'other-address'),
      );
      expect(() => h.validate(forged), throwsA(isA<ContactFailure>()));
    },
  );
}
