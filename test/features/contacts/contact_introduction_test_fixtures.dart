import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_introduction_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_mutation_gate.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_introduction_gateway.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_gateway.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_introduction_repository.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_introduction_models.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import 'contact_test_fakes.dart';

// Deliberately fake signatures/addresses: these tests isolate state transitions.
// The separate native lane exercises the same coordinator with real Rust crypto.
String _hash(int n) => base64Url.encode(List.filled(32, n)).replaceAll('=', '');

class _Store extends Fake implements AppSecureStore {
  final values = <String, String>{};
  Completer<void>? writeGate, writeEntered;
  bool failBeforeWrite = false, failAfterWrite = false;
  int writes = 0;
  @override
  Future<String?> readSecretStringWithOptions(
    String key, {
    bool requireUnlockedSession = false,
    bool rejectInvalidEnvelope = false,
  }) async => values[key];
  @override
  Future<void> writeSecretString(String key, String value) async {
    writes++;
    if (writeEntered?.isCompleted == false) writeEntered!.complete();
    if (writeGate != null) await writeGate!.future;
    if (failBeforeWrite) throw StateError('simulated write failure');
    values[key] = value;
    if (failAfterWrite) throw StateError('simulated uncertain acknowledgement');
  }
}

class IntroductionObservedRepository
    extends SecureContactIntroductionRepository {
  IntroductionObservedRepository({required super.store});
  final loaded = <ContactBook>[];
  final submitted = <ContactBook>[];
  @override
  Future<ContactBook> loadBook(ContactScope scope) async {
    final book = await super.loadBook(scope);
    loaded.add(book);
    return book;
  }

  @override
  Future<void> saveBook(ContactScope scope, ContactBook book) {
    submitted.add(book);
    return super.saveBook(scope, book);
  }
}

class IntroductionTestDirect extends FakeContactGateway {
  IntroductionTestDirect(this.actor);
  final String actor;
  @override
  Future<ContactSigner> createIdentity() async {
    final n = 50 + identityCreates++;
    final signer = ContactSigner(
      identity: testIdentity(n),
      secret: Uint8List.fromList(List.filled(32, n)),
      address: '',
      sequence: 1,
    );
    createdSigners.add(signer);
    return signer;
  }

  @override
  Future<String> freshAddress(ContactScope scope) async {
    addressAllocations++;
    return addressGate == null
        ? 'fresh-$actor-$addressAllocations'
        : await addressGate!.future;
  }
}

class _Wire implements ContactIntroductionGateway {
  static int counter = 1;
  Completer<void>? verifyGate,
      verifyEntered,
      associationGate,
      associationEntered;
  final loans = <ContactSigner>[];
  int signatures = 0;
  @override
  Future<bool> validateAssociation(
    ContactScope scope,
    String peer,
    ContactSigner own,
  ) async {
    loans.add(own);
    if (associationEntered?.isCompleted == false) {
      associationEntered!.complete();
    }
    if (associationGate != null) await associationGate!.future;
    final raw = base64Url.decode(
      base64Url.normalize(own.identity.substring(8)),
    );
    return peer != own.identity && own.secret.every((b) => b == raw.first);
  }

  IntroductionWireResult _result(Map<String, dynamic> m) =>
      IntroductionWireResult(
        packet: jsonEncode(m),
        request: m['request'],
        requestHash: m['hash'],
        expiresAt: DateTime.fromMillisecondsSinceEpoch(m['expires']),
        offer: m['kind'] == 'offer' ? jsonEncode(m) : m['offer'],
        endpoint: m['identity'] == null
            ? null
            : jsonEncode(['endpoint', m['identity'], m['address']]),
        identity: m['identity'],
        address: m['address'],
        sequence: m['identity'] == null ? null : 1,
        suggestion: m['suggestion'],
        endpointHash: m['identity'] == null ? null : _hash(200),
        endorsementHash: m['kind'] == 'delivery' ? _hash(201) : null,
      );
  @override
  Future<IntroductionWireResult> verify(
    ContactScope scope,
    IntroductionWireStage stage,
    String peer,
    String own,
    String packet,
    DateTime now, {
    String? request,
    String? offer,
  }) async {
    if (verifyEntered?.isCompleted == false) verifyEntered!.complete();
    if (verifyGate != null) await verifyGate!.future;
    final m = jsonDecode(packet) as Map<String, dynamic>;
    if (m['kind'] != stage.name ||
        m['sender'] != peer ||
        m['target'] != own ||
        (request != null && m['request'] != request) ||
        (offer != null && m['offer'] != offer) ||
        now.millisecondsSinceEpoch >= m['expires']) {
      throw const ContactFailure('Invalid test transcript.');
    }
    return _result(m);
  }

  @override
  Future<IntroductionWireResult> ask(
    ContactScope scope,
    String peer,
    ContactSigner own,
    DateTime now,
  ) async {
    signatures++;
    final hash = _hash(counter++);
    return _result({
      'kind': 'ask',
      'request': jsonEncode(['R', hash]),
      'hash': hash,
      'sender': own.identity,
      'target': peer,
      'expires': now.add(const Duration(minutes: 15)).millisecondsSinceEpoch,
    });
  }

  @override
  Future<IntroductionWireResult> offer(
    ContactScope scope,
    String request,
    String peer,
    ContactSigner own,
    String suggestion,
    DateTime now,
  ) async {
    signatures++;
    return _result({
      'kind': 'offer',
      'request': request,
      'hash': jsonDecode(request)[1],
      'sender': own.identity,
      'target': peer,
      'suggestion': suggestion,
      'expires': now.add(const Duration(minutes: 15)).millisecondsSinceEpoch,
    });
  }

  @override
  Future<IntroductionWireResult> consent(
    ContactScope scope,
    String peer,
    ContactSigner own,
    ContactSigner fresh,
    String offerPacket,
    DateTime now,
  ) async {
    signatures++;
    final offer = jsonDecode(offerPacket) as Map<String, dynamic>;
    return _result({
      ...offer,
      'kind': 'consent',
      'sender': own.identity,
      'target': peer,
      'offer': offerPacket,
      'identity': fresh.identity,
      'address': fresh.address,
    });
  }

  @override
  Future<IntroductionWireResult> delivery(
    ContactScope scope,
    String peerBob,
    String ownBob,
    String peerCarol,
    ContactSigner ownCarol,
    String request,
    String offer,
    String consentPacket,
    String suggestion,
    DateTime now,
  ) async {
    signatures++;
    final consent = jsonDecode(consentPacket) as Map<String, dynamic>;
    return _result({
      ...consent,
      'kind': 'delivery',
      'sender': ownCarol.identity,
      'target': peerCarol,
      'suggestion': suggestion,
    });
  }
}

int _actorNumber = 0;

class IntroductionTestActor {
  IntroductionTestActor(String name)
    : fixed = ContactScope(
        accountUuid: '$name-${_actorNumber++}',
        network: 'test',
      ),
      direct = IntroductionTestDirect(name) {
    current = fixed;
    repo = IntroductionObservedRepository(store: store);
    directRepo = SecureContactRepository(store: store);
    reopen();
    addTearDown(() => coordinator.dispose());
  }
  final ContactScope fixed;
  ContactScope? current;
  final store = _Store();
  final IntroductionTestDirect direct;
  final wire = _Wire();
  DateTime now = testContactNow;
  late final IntroductionObservedRepository repo;
  late final SecureContactRepository directRepo;
  late ContactIntroductionCoordinator coordinator;
  void reopen() {
    coordinator = ContactIntroductionCoordinator(
      scope: () => current,
      repository: repo,
      directRepository: directRepo,
      gateway: wire,
      directGateway: direct,
      clock: () => now,
    );
  }

  Future<void> peer(
    String label,
    int incoming,
    int outgoing, {
    bool paired = true,
  }) async {
    final book = await repo.loadBook(fixed);
    try {
      final contact = testContact(
        id: label,
        label: label,
        identityByte: incoming,
        address: 'address-$label-$incoming',
      );
      await repo.saveBook(
        fixed,
        book.copyWith(
          contacts: [...book.contacts, contact],
          associations: [
            ...book.associations,
            if (paired)
              ContactPeerAssociation(
                incomingContactId: label,
                incomingIdentity: contact.identity,
                outgoingIdentity: testIdentity(outgoing),
                independentlyConfirmedAt: now,
              ),
          ],
        ),
      );
      final signer = ContactSigner(
        identity: testIdentity(outgoing),
        secret: Uint8List.fromList(List.filled(32, outgoing)),
        address: 'own-$label-$outgoing',
        sequence: 1,
      );
      try {
        await directRepo.saveSigner(fixed, signer);
      } finally {
        signer.clear();
      }
    } finally {
      book.clearSecrets();
    }
  }

  Future<void> suspend(String id) => ContactMutationGate.run(fixed, () async {
    final book = await repo.loadBook(fixed);
    try {
      await repo.saveBook(
        fixed,
        book.copyWith(
          contacts: [
            for (final c in book.contacts)
              if (c.id == id)
                c.copyWith(
                  status: ContactTrustStatus.suspended,
                  revision: c.revision + 1,
                )
              else
                c,
          ],
        ),
      );
    } finally {
      book.clearSecrets();
    }
  }, mutation: true);
  Future<ContactBook> book() => repo.loadBook(fixed);

  void configureFreshResponse(IntroductionReview review) {
    direct.expiry = now.add(const Duration(minutes: 5));
    direct.endpoint = ContactWireEndpoint(
      identity: review.identity!,
      address: review.address!,
      sequence: review.wire.sequence!,
      expiresAt: direct.expiry,
    );
  }

  Future<String> prepareFreshCheck(IntroductionReview review) async {
    configureFreshResponse(review);
    await coordinator.createAcceptanceRequest(review, consent: true);
    return 'fake-fresh-response';
  }
}

class IntroductionTestCeremony {
  final alice = IntroductionTestActor('alice'),
      bob = IntroductionTestActor('bob'),
      carol = IntroductionTestActor('carol');
  late String ask, offer, consent, delivery;
  Future<void> setup() async {
    await alice.peer('Carol', 12, 11);
    await carol.peer('Alice', 11, 12);
    await alice.peer('Bob', 22, 21);
    await bob.peer('Alice', 21, 22);
  }

  Future<void> throughOffer() async {
    await setup();
    ask = await carol.coordinator.createRequest('Alice', consent: true);
    final review = await alice.coordinator.reviewAsk(
      'Carol',
      'Bob',
      ask,
      suggestedRecipient: 'Carol',
    );
    offer = await alice.coordinator.confirmOffer(review, consent: true);
  }

  Future<void> throughConsent() async {
    await throughOffer();
    final review = await bob.coordinator.reviewOffer('Alice', offer);
    consent = await bob.coordinator.confirmConsent(review, consent: true);
  }

  Future<void> throughDelivery() async {
    await throughConsent();
    final review = await alice.coordinator.reviewConsent(
      consent,
      suggestedContact: 'Bob',
    );
    delivery = await alice.coordinator.confirmDelivery(review, consent: true);
  }
}
