@Tags(['contact-native'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_exchange_controller.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_introduction_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_gateway.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_introduction_gateway.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_introduction_repository.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_introduction_models.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as native_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as native_wallet;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import 'support/file_contact_storage.dart';

const _libraryPath = String.fromEnvironment('CONTACT_NATIVE_LIBRARY');
const _password = 'IntroductionCheck1!';
// Public BIP39 test vector. Separate public passphrases produce three disposable
// wallet accounts; this test never contacts a server or sends a transaction.
const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_libraryPath.isEmpty || !File(_libraryPath).uri.isAbsolute) {
      throw StateError(
        'Pass an absolute CONTACT_NATIVE_LIBRARY path to the built wallet library.',
      );
    }
    await RustLib.init(externalLibrary: ExternalLibrary.open(_libraryPath));
  });
  tearDownAll(RustLib.dispose);

  test(
    'three disposable wallets introduce, persist, reopen and update through real Rust',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'zcash-introduction-native-',
      );
      final actors = <_Actor>[];
      final clock = _Clock();
      try {
        final alice = await _Actor.create(root, 'alice', clock);
        actors.add(alice);
        final bob = await _Actor.create(root, 'bob', clock);
        actors.add(bob);
        final carol = await _Actor.create(root, 'carol', clock);
        actors.add(carol);
        expect(actors.map((a) => a.scope.accountUuid).toSet(), hasLength(3));

        // Set up four direct, separately signed relationships, using the actual
        // native request/sign/verify path and encrypted signing records. These
        // deterministic comparisons simulate the independent human check.
        final aliceAtCarol = await alice.shareWith(carol, 'Alice');
        final carolAtAlice = await carol.shareWith(alice, 'Carol');
        final aliceAtBob = await alice.shareWith(bob, 'Alice');
        final bobAtAlice = await bob.shareWith(alice, 'Bob');
        final oldIdentities = {
          aliceAtCarol.identity,
          carolAtAlice.identity,
          aliceAtBob.identity,
          bobAtAlice.identity,
        };
        expect(oldIdentities, hasLength(4));
        await alice.associate(carolAtAlice, aliceAtCarol.identity);
        await carol.associate(aliceAtCarol, carolAtAlice.identity);
        await alice.associate(bobAtAlice, aliceAtBob.identity);
        await bob.associate(aliceAtBob, bobAtAlice.identity);

        await expectLater(
          carol.introductions.createRequest(aliceAtCarol.id, consent: false),
          throwsA(isA<ContactFailure>()),
        );
        final ask = await carol.introductions.createRequest(
          aliceAtCarol.id,
          consent: true,
        );
        // The invitation can wait while people are offline. Later approvals
        // and the final address proof use the current clock, not fixture time.
        clock.now = clock.now.add(const Duration(days: 1));
        final askReview = await alice.introductions.reviewAsk(
          carolAtAlice.id,
          bobAtAlice.id,
          ask,
          suggestedRecipient: 'Carol',
        );
        final offer = await alice.introductions.confirmOffer(
          askReview,
          consent: true,
        );
        final offerReview = await bob.introductions.reviewOffer(
          aliceAtBob.id,
          offer,
        );
        final freshIdentity = offerReview.identity!;
        final freshAddress = offerReview.address!;
        expect(oldIdentities.contains(freshIdentity), isFalse);
        expect(
          {
            aliceAtCarol.address,
            carolAtAlice.address,
            aliceAtBob.address,
            bobAtAlice.address,
          }.contains(freshAddress),
          isFalse,
        );
        expect(
          await bob.gateway.validateAddress(bob.scope, freshAddress),
          isTrue,
        );
        final beforeConsent = await bob.repository.loadSigner(
          bob.scope,
          freshIdentity,
        );
        try {
          expect(beforeConsent, isNull);
        } finally {
          beforeConsent?.clear();
        }
        await expectLater(
          bob.introductions.confirmConsent(offerReview, consent: false),
          throwsA(isA<ContactFailure>()),
        );
        final consent = await bob.introductions.confirmConsent(
          offerReview,
          consent: true,
        );
        final consentReview = await alice.introductions.reviewConsent(
          consent,
          suggestedContact: 'Bob',
        );
        expect(consentReview.identity, freshIdentity);
        expect(consentReview.address, freshAddress);
        final delivery = await alice.introductions.confirmDelivery(
          consentReview,
          consent: true,
        );
        // Reopening Alice may recover an already signed delivery for explicit
        // export. Native verification checks her outgoing Carol key as signer.
        await alice.reopen();
        final savedDeliveryReview = await alice.introductions
            .reviewSavedDelivery(askReview.wire.requestHash);
        expect(savedDeliveryReview.retry, isTrue);
        expect(savedDeliveryReview.identity, freshIdentity);
        expect(savedDeliveryReview.address, freshAddress);
        expect(savedDeliveryReview.suggestion, 'Bob');
        await expectLater(
          alice.introductions.confirmDelivery(
            savedDeliveryReview,
            consent: false,
          ),
          throwsA(isA<ContactFailure>()),
        );
        expect(
          await alice.introductions.confirmDelivery(
            savedDeliveryReview,
            consent: true,
          ),
          delivery,
        );
        final pendingInvitation =
            (await carol.introductions.overview()).pendingRequests.single;
        await carol.reopen();
        await carol.introductions.resumeRequest(pendingInvitation.hash);
        final deliveryReview = await carol.introductions.reviewDelivery(
          delivery,
        );
        expect(deliveryReview.identity, freshIdentity);
        expect(deliveryReview.address, freshAddress);
        expect(deliveryReview.suggestion, 'Bob');
        expect(deliveryReview.wire.requestHash, askReview.wire.requestHash);

        // None of the reviews/exports create the introduced incoming contact.
        expect(await alice.repository.load(alice.scope), hasLength(2));
        expect(await bob.repository.load(bob.scope), hasLength(1));
        expect(
          (await carol.repository.load(carol.scope)).map((c) => c.identity),
          [aliceAtCarol.identity],
        );
        await expectLater(
          carol.introductions.acceptDelivery(
            deliveryReview,
            label: 'Robert',
            consent: false,
          ),
          throwsA(isA<ContactFailure>()),
        );
        expect(await carol.repository.load(carol.scope), hasLength(1));
        final freshness = await carol.introductions.createAcceptanceRequest(
          deliveryReview,
          consent: true,
        );
        final relationshipSigner = await bob.repository.loadSigner(
          bob.scope,
          freshIdentity,
        );
        expect(relationshipSigner, isNotNull);
        late String freshResponse;
        try {
          freshResponse = await bob.gateway.sign(
            bob.scope,
            freshness.json,
            relationshipSigner!,
            clock.now,
          );
          final replacement = await carol.introductions.createAcceptanceRequest(
            deliveryReview,
            consent: true,
          );
          await expectLater(
            carol.introductions.acceptDelivery(
              deliveryReview,
              label: 'Robert',
              consent: true,
              freshResponse: freshResponse,
            ),
            throwsA(anything),
          );
          freshResponse = await bob.gateway.sign(
            bob.scope,
            replacement.json,
            relationshipSigner,
            clock.now,
          );
        } finally {
          relationshipSigner?.clear();
        }
        final accepted = await carol.introductions.acceptDelivery(
          deliveryReview,
          label: 'Robert', // A local choice, distinct from the suggestion.
          consent: true,
          freshResponse: freshResponse,
        );
        expect(accepted.identity, freshIdentity);
        expect(accepted.address, freshAddress);
        expect(accepted.label, 'Robert');
        expect(accepted.sequence, 1);
        expect(accepted.status, ContactTrustStatus.accepted);

        // Acceptance, consumed request and provenance share one encrypted book.
        late String acceptedProvenance;
        await carol.inspectBook((book) {
          expect(book.contacts, hasLength(2));
          expect(book.signers, isEmpty);
          final consumed = book.sessions.single;
          expect(consumed.role, ContactIntroductionRole.requester);
          expect(consumed.phase, ContactIntroductionPhase.accepted);
          expect(consumed.contactId, accepted.id);
          expect(consumed.requestHash, askReview.wire.requestHash);
          expect(consumed.inputPacket, delivery);
          final provenance = book.provenance.single;
          expect(provenance.introducedContactId, accepted.id);
          expect(provenance.introducerContactId, aliceAtCarol.id);
          expect(provenance.introducerIdentity, aliceAtCarol.identity);
          expect(provenance.requestHash, deliveryReview.wire.requestHash);
          expect(provenance.endpointHash, deliveryReview.wire.endpointHash);
          expect(
            provenance.attestationHash,
            deliveryReview.wire.endorsementHash,
          );
          expect(provenance.suggestion, 'Bob');
          acceptedProvenance = jsonEncode(provenance.toJson());
        });
        await bob.inspectBook((book) {
          expect(book.contacts, hasLength(1));
          expect(book.signers.single.identity, freshIdentity);
          expect(book.signers.single.address, freshAddress);
          expect(book.sessions.single.outputPacket, consent);
        });
        final rawCarol = await carol.storageFile.readAsString();
        final rawBob = await bob.storageFile.readAsString();
        for (final raw in [rawCarol, rawBob]) {
          expect(raw.contains(freshIdentity), isFalse);
          expect(raw.contains(freshAddress), isFalse);
          expect(raw.contains(askReview.wire.requestHash), isFalse);
          expect(raw.contains('"label":"Robert"'), isFalse);
        }
        await expectLater(
          carol.introductions.reviewDelivery(delivery),
          throwsA(isA<ContactFailure>()),
        );

        // A second fully valid delivery remains unaccepted. Reopening may read
        // its replay record, but must never reactivate the live pending request.
        final secondAsk = await carol.introductions.createRequest(
          aliceAtCarol.id,
          consent: true,
        );
        final secondOffer = await alice.introductions.confirmOffer(
          await alice.introductions.reviewAsk(
            carolAtAlice.id,
            bobAtAlice.id,
            secondAsk,
            suggestedRecipient: 'Carol',
          ),
          consent: true,
        );
        final secondConsent = await bob.introductions.confirmConsent(
          await bob.introductions.reviewOffer(aliceAtBob.id, secondOffer),
          consent: true,
        );
        final secondDelivery = await alice.introductions.confirmDelivery(
          await alice.introductions.reviewConsent(
            secondConsent,
            suggestedContact: 'Bob',
          ),
          consent: true,
        );
        final pendingReview = await carol.introductions.reviewDelivery(
          secondDelivery,
        );
        expect(pendingReview.identity, isNot(freshIdentity));
        for (final actor in actors) {
          await actor.reopen();
        }
        await expectLater(
          carol.introductions.reviewDelivery(secondDelivery),
          throwsA(
            isA<ContactFailure>().having(
              (e) => e.message,
              'message',
              contains('No live introduction is pending'),
            ),
          ),
        );
        expect(await carol.repository.load(carol.scope), hasLength(2));
        await carol.inspectBook((book) {
          expect(book.sessions, hasLength(2));
          expect(
            book.sessions.where(
              (s) => s.phase == ContactIntroductionPhase.accepted,
            ),
            hasLength(1),
          );
          expect(
            book.sessions
                .where((s) => s.requestHash == pendingReview.wire.requestHash)
                .single
                .phase,
            ContactIntroductionPhase.published,
          );
          expect(
            jsonEncode(book.provenance.single.toJson()),
            acceptedProvenance,
          );
        });
        final persisted = await bob.repository.loadSigner(
          bob.scope,
          freshIdentity,
        );
        expect(persisted, isNotNull);
        try {
          expect(persisted!.identity, freshIdentity);
          expect(persisted.address, freshAddress);
          expect(persisted.sequence, 1);
        } finally {
          persisted?.clear();
        }

        // Use the existing direct controller to update Bob's introduced key.
        // The same key now signs revision 2 for a newly allocated wallet UA.
        await carol.direct.startRequest(contactId: accepted.id);
        expect(carol.state.error, isNull);
        await bob.direct.prepareShare(carol.state.request!.json);
        expect(bob.state.error, isNull);
        final update = bob.state.shareReview!;
        expect(update.identity, freshIdentity);
        expect(update.previousAddress, freshAddress);
        expect(update.address, isNot(freshAddress));
        await bob.direct.confirmShare(consent: true);
        expect(bob.state.error, isNull);
        await carol.direct.previewResponse(bob.state.response!);
        expect(carol.state.error, isNull);
        expect(carol.state.candidate!.identity, freshIdentity);
        expect(carol.state.candidate!.sequence, 2);
        await carol.direct.acceptResponse(
          label: 'Robert',
          independentlyVerified: true,
        );
        expect(carol.state.error, isNull);
        final updated = carol.state.contacts.singleWhere(
          (c) => c.id == accepted.id,
        );
        expect(updated.identity, freshIdentity);
        expect(updated.address, update.address);
        expect(updated.sequence, 2);
        await bob.reopen();
        await carol.reopen();
        final updatedSigner = await bob.repository.loadSigner(
          bob.scope,
          freshIdentity,
        );
        try {
          expect(updatedSigner, isNotNull);
          expect(updatedSigner!.identity, freshIdentity);
          expect(updatedSigner.address, update.address);
          expect(updatedSigner.sequence, 2);
        } finally {
          updatedSigner?.clear();
        }
        await carol.inspectBook((book) {
          expect(
            book.contacts.singleWhere((c) => c.id == accepted.id).sequence,
            2,
          );
          expect(
            jsonEncode(book.provenance.single.toJson()),
            acceptedProvenance,
          );
          expect(
            book.sessions.singleWhere((s) => s.contactId == accepted.id).phase,
            ContactIntroductionPhase.accepted,
          );
        });
      } finally {
        for (final actor in actors) {
          actor.close();
        }
        // This test owns only the freshly created disposable directory.
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _Clock {
  DateTime now = DateTime.utc(2026, 9, 10, 12);
}

class _DatabaseGateway extends RustContactGateway {
  _DatabaseGateway(this.dbPath);
  final String dbPath;

  @override
  Future<String> freshAddress(ContactScope scope) =>
      native_sync.getNextAvailableAddress(
        dbPath: dbPath,
        network: scope.network,
        accountUuid: scope.accountUuid,
        addressRequest: 'orchard',
      );
}

class _Actor {
  _Actor(this.name, this.scope, this.storageFile, this.gateway, this.clock);
  final String name;
  final ContactScope scope;
  final File storageFile;
  final _DatabaseGateway gateway;
  final _Clock clock;
  final introGateway = RustContactIntroductionGateway();
  late AppSecureStore store;
  late SecureContactRepository repository;
  late SecureContactIntroductionRepository books;
  ContactIntroductionCoordinator? _introductions;
  ProviderContainer? _container;
  ContactIntroductionCoordinator get introductions => _introductions!;
  ContactExchangeController get direct =>
      _container!.read(contactExchangeProvider.notifier);
  ContactExchangeState get state => _container!.read(contactExchangeProvider);

  static Future<_Actor> create(
    Directory root,
    String name,
    _Clock clock,
  ) async {
    final dbPath = '${root.path}/$name.sqlite';
    final account = await native_wallet.importWallet(
      mnemonic: _mnemonic,
      bip39Passphrase: 'public-introduction-check-$name',
      network: 'test',
      dbPath: dbPath,
      birthdayHeight: BigInt.from(2000000),
      accountName: name,
    );
    await native_sync.updateChainTip(
      dbPath: dbPath,
      network: 'test',
      height: BigInt.from(2500000),
    );
    final actor = _Actor(
      name,
      ContactScope(accountUuid: account.accountUuid, network: 'test'),
      File('${root.path}/$name-secrets.json'),
      _DatabaseGateway(dbPath),
      clock,
    );
    try {
      await actor.reopen(first: true);
      return actor;
    } catch (_) {
      actor.close();
      rethrow;
    }
  }

  Future<void> reopen({bool first = false}) async {
    _introductions?.dispose();
    _container?.dispose();
    _container = null;
    if (!first) store.clearSessionPassword();
    store = AppSecureStore.testing(
      storage: FileBackedContactSecureStorage(storageFile),
    );
    if (first) {
      await store.configurePassword(_password);
    } else {
      expect(await store.verifyPassword(_password), isTrue);
    }
    repository = SecureContactRepository(store: store);
    books = SecureContactIntroductionRepository(store: store);
    _introductions = ContactIntroductionCoordinator(
      scope: () => scope,
      repository: books,
      directRepository: repository,
      gateway: introGateway,
      directGateway: gateway,
      clock: () => clock.now,
    );
    final container = ProviderContainer(
      overrides: [
        contactScopeProvider.overrideWithValue(scope),
        contactRepositoryProvider.overrideWithValue(repository),
        contactGatewayProvider.overrideWithValue(gateway),
        contactClockProvider.overrideWithValue(() => clock.now),
      ],
    );
    _container = container;
    final ready = Completer<void>();
    final subscription = container.listen(contactExchangeProvider, (_, next) {
      if (!next.loading && !ready.isCompleted) ready.complete();
    }, fireImmediately: true);
    try {
      await ready.future.timeout(const Duration(seconds: 30));
    } finally {
      subscription.close();
    }
    expect(state.error, isNull);
  }

  Future<VerifiedContact> shareWith(_Actor peer, String label) async {
    final fresh = await gateway.createIdentity();
    ContactSigner? signer;
    try {
      final address = await gateway.freshAddress(scope);
      signer = ContactSigner(
        identity: fresh.identity,
        secret: Uint8List.fromList(fresh.secret),
        address: address,
        sequence: 1,
      );
      final request = await peer.gateway.createRequest(
        peer.scope,
        null,
        clock.now,
      );
      final response = await gateway.sign(
        scope,
        request.json,
        signer,
        clock.now,
      );
      final endpoint = await peer.gateway.verify(
        peer.scope,
        request.json,
        response,
        clock.now,
      );
      expect(endpoint.identity, signer.identity);
      expect(endpoint.address, signer.address);
      await repository.saveSigner(scope, signer);
      final contact = VerifiedContact(
        id: '$name-at-${peer.name}',
        label: label,
        identity: endpoint.identity,
        address: endpoint.address,
        sequence: endpoint.sequence,
        revision: 1,
      );
      await peer.repository.save(peer.scope, [
        ...await peer.repository.load(peer.scope),
        contact,
      ]);
      return contact;
    } finally {
      fresh.clear();
      signer?.clear();
    }
  }

  Future<void> associate(VerifiedContact peer, String outgoingIdentity) async {
    final review = await introductions.reviewAssociation(
      peer.id,
      outgoingIdentity,
    );
    expect(review.peer.identity, peer.identity);
    expect(review.outgoingIdentity, outgoingIdentity);
    await expectLater(
      introductions.confirmAssociation(review, independentlyVerified: false),
      throwsA(isA<ContactFailure>()),
    );
    await introductions.confirmAssociation(review, independentlyVerified: true);
  }

  Future<void> inspectBook(void Function(ContactBook) inspect) async {
    final book = await books.loadBook(scope);
    try {
      inspect(book);
    } finally {
      book.clearSecrets();
    }
  }

  void close() {
    _introductions?.dispose();
    _container?.dispose();
    _container = null;
    store.clearSessionPassword();
  }
}
