import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_introduction_repository.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_introduction_models.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import 'contact_test_fixtures.dart';

class _DelayedSecretStore extends Fake implements AppSecureStore {
  final values = <String, String>{};
  final writes = <String>[];
  final bookKey = '${testContactScope.storagePrefix}book';
  Completer<void>? bookReadEntered, bookReadGate;

  void delayNextBookRead() {
    bookReadEntered = Completer<void>();
    bookReadGate = Completer<void>();
  }

  @override
  Future<String?> readSecretStringWithOptions(
    String key, {
    bool requireUnlockedSession = false,
    bool rejectInvalidEnvelope = false,
  }) async {
    expect(requireUnlockedSession, isTrue);
    expect(rejectInvalidEnvelope, isTrue);
    final gate = bookReadGate;
    if (key == bookKey && gate != null) {
      bookReadGate = null;
      bookReadEntered!.complete();
      await gate.future;
    }
    return values[key];
  }

  @override
  Future<void> writeSecretString(String key, String value) async {
    values[key] = value;
    writes.add(key);
  }
}

String _hash(int byte) =>
    base64Url.encode(List.filled(32, byte)).replaceAll('=', '');

ContactSigner _signer({int sequence = 3, String address = 'old-own-address'}) =>
    ContactSigner(
      identity: testIdentity(9),
      secret: Uint8List.fromList(List.filled(32, 7)),
      address: address,
      sequence: sequence,
    );

ContactBook _book({required bool introductionSigner}) => ContactBook(
  contacts: [
    testContact(),
    testContact(id: 'bob', label: 'Bob', identityByte: 2),
  ],
  associations: [
    ContactPeerAssociation(
      incomingContactId: 'alice',
      incomingIdentity: testIdentity(1),
      outgoingIdentity: testIdentity(3),
      independentlyConfirmedAt: testContactNow,
    ),
  ],
  sessions: [
    ContactIntroductionSession(
      role: ContactIntroductionRole.requester,
      requestHash: _hash(1),
      requestJson: '["exact-request"]',
      expiresAt: testContactNow.add(const Duration(minutes: 15)),
      phase: ContactIntroductionPhase.accepted,
      pins: [
        ContactIntroductionPin(
          contactId: 'alice',
          identity: testIdentity(1),
          outgoingIdentity: testIdentity(3),
        ),
      ],
      outputPacket: '["exact-ask"]',
      inputPacket: '["exact-delivery"]',
      endpointJson: '["exact-endpoint"]',
      contactId: 'bob',
    ),
  ],
  provenance: [
    ContactIntroductionProvenance(
      introducedContactId: 'bob',
      introducerContactId: 'alice',
      introducerIdentity: testIdentity(1),
      requestHash: _hash(1),
      endpointHash: _hash(2),
      attestationHash: _hash(3),
      acceptedAt: testContactNow,
      suggestion: 'Public suggestion',
    ),
  ],
  signers: introductionSigner
      ? [
          IntroductionStoredSigner(
            identity: testIdentity(9),
            secret: Uint8List.fromList(List.filled(32, 7)),
            address: 'old-own-address',
            sequence: 3,
          ),
        ]
      : [],
);

Future<void> _seed(
  _DelayedSecretStore store, {
  required bool introductionSigner,
}) async {
  final book = _book(introductionSigner: introductionSigner);
  try {
    await SecureContactIntroductionRepository(
      store: store,
    ).saveBook(testContactScope, book);
  } finally {
    book.clearSecrets();
  }
  if (!introductionSigner) {
    final signer = _signer();
    try {
      await SecureContactRepository(
        store: store,
      ).saveSigner(testContactScope, signer);
    } finally {
      signer.clear();
    }
  }
  store.writes.clear();
}

Future<void> _expectStoredSigner(
  SecureContactRepository repository, {
  required int sequence,
  required String address,
}) async {
  final signer = (await repository.loadSigner(
    testContactScope,
    testIdentity(9),
  ))!;
  expect(signer.identity, testIdentity(9));
  expect(signer.sequence, sequence);
  expect(signer.address, address);
  expect(signer.secret, everyElement(7));
  signer.clear();
  expect(signer.secret, everyElement(0));
  final reloaded = (await repository.loadSigner(
    testContactScope,
    testIdentity(9),
  ))!;
  expect(reloaded.secret, everyElement(7));
  reloaded.clear();
}

void main() {
  for (final introductionSigner in [false, true]) {
    final branch = introductionSigner ? 'introduction-backed' : 'legacy';

    test('$branch persistence snapshots before a delayed book read', () async {
      final store = _DelayedSecretStore();
      final repository = SecureContactRepository(store: store);
      await _seed(store, introductionSigner: introductionSigner);
      final originalBook = store.values[store.bookKey]!;
      store.delayNextBookRead();
      final readGate = store.bookReadGate!;
      final next = _signer(sequence: 4, address: 'new-own-address');
      final saving = repository.saveSigner(testContactScope, next);
      await store.bookReadEntered!.future;
      next.clear(); // The controller does this synchronously on pause/lock.
      expect(next.secret, everyElement(0));
      expect(store.writes, isEmpty);
      readGate.complete();
      await saving;
      expect(store.writes, hasLength(1));
      expect(
        store.writes.single,
        introductionSigner
            ? store.bookKey
            : '${testContactScope.storagePrefix}signer_${testIdentity(9).substring(8)}',
      );
      if (!introductionSigner) {
        expect(store.values[store.bookKey], originalBook);
      }
      await _expectStoredSigner(
        repository,
        sequence: 4,
        address: 'new-own-address',
      );
    });

    test('$branch lifecycle guard blocks writes after the book read', () async {
      final store = _DelayedSecretStore();
      final repository = SecureContactRepository(store: store);
      await _seed(store, introductionSigner: introductionSigner);
      final originalValues = Map.of(store.values);
      store.delayNextBookRead();
      final readGate = store.bookReadGate!;
      final next = _signer(sequence: 4, address: 'new-own-address');
      var paused = false;
      var guardCalls = 0;
      final saving = repository.saveSigner(
        testContactScope,
        next,
        beforeWrite: () {
          guardCalls++;
          if (paused) throw const ContactFailure('Contact review paused.');
        },
      );
      await store.bookReadEntered!.future;
      expect(guardCalls, 0);
      paused = true;
      next.clear();
      final rejected = expectLater(saving, throwsA(isA<ContactFailure>()));
      readGate.complete();
      await rejected;
      expect(guardCalls, 1);
      expect(store.writes, isEmpty);
      expect(store.values, originalValues);
      await _expectStoredSigner(
        repository,
        sequence: 3,
        address: 'old-own-address',
      );
    });
  }

  test(
    'direct contact save preserves every introduction field and signer',
    () async {
      final store = _DelayedSecretStore();
      final repository = SecureContactRepository(store: store);
      final books = SecureContactIntroductionRepository(store: store);
      await _seed(store, introductionSigner: true);
      final before =
          jsonDecode(store.values[store.bookKey]!) as Map<String, dynamic>;
      final contacts = await repository.load(testContactScope);
      final replacement = [
        for (final contact in contacts)
          contact.id == 'alice'
              ? contact.copyWith(
                  status: ContactTrustStatus.suspended,
                  revision: 3,
                )
              : contact,
      ];
      await repository.save(testContactScope, replacement);
      final after =
          jsonDecode(store.values[store.bookKey]!) as Map<String, dynamic>;
      expect(store.writes, [store.bookKey]);
      expect(after['contacts'], [
        for (final contact in replacement) contact.toJson(),
      ]);
      for (final field in [
        'domain',
        'account',
        'network',
        'associations',
        'introductionSessions',
        'introductionSigners',
        'provenance',
      ]) {
        expect(after[field], before[field], reason: field);
      }
      final loaded = await books.loadBook(testContactScope);
      expect(loaded.sessions.single.phase, ContactIntroductionPhase.accepted);
      expect(loaded.provenance.single.introducedContactId, 'bob');
      loaded.clearSecrets();
      await _expectStoredSigner(
        repository,
        sequence: 3,
        address: 'old-own-address',
      );
    },
  );

  test(
    'introduction signer update preserves contacts and exact transcripts',
    () async {
      final store = _DelayedSecretStore();
      final repository = SecureContactRepository(store: store);
      await _seed(store, introductionSigner: true);
      final before =
          jsonDecode(store.values[store.bookKey]!) as Map<String, dynamic>;
      final next = _signer(sequence: 4, address: 'new-own-address');
      try {
        await repository.saveSigner(testContactScope, next);
      } finally {
        next.clear();
      }
      final after =
          jsonDecode(store.values[store.bookKey]!) as Map<String, dynamic>;
      expect(store.writes, [store.bookKey]);
      for (final field in [
        'domain',
        'account',
        'network',
        'contacts',
        'associations',
        'introductionSessions',
        'provenance',
      ]) {
        expect(after[field], before[field], reason: field);
      }
      final stored = (after['introductionSigners'] as List).single;
      expect(stored['sequence'], 4);
      expect(stored['address'], 'new-own-address');
      expect(base64Decode(stored['secret'] as String), everyElement(7));
      await _expectStoredSigner(
        repository,
        sequence: 4,
        address: 'new-own-address',
      );
    },
  );
}
