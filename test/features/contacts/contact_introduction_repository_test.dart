import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_introduction_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_introduction_models.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import 'contact_test_fixtures.dart';

class _SecretStore extends Fake implements AppSecureStore {
  final values = <String, String>{};
  final reads = <({String key, bool unlocked, bool strict})>[];
  final writes = <({String key, String value})>[];
  Object? writeFailure;
  Object? readFailure;

  @override
  Future<String?> readSecretStringWithOptions(
    String key, {
    bool requireUnlockedSession = false,
    bool rejectInvalidEnvelope = false,
  }) async {
    reads.add((
      key: key,
      unlocked: requireUnlockedSession,
      strict: rejectInvalidEnvelope,
    ));
    if (readFailure != null) throw readFailure!;
    return values[key];
  }

  @override
  Future<void> writeSecretString(String key, String value) async {
    if (writeFailure != null) throw writeFailure!;
    values[key] = value;
    writes.add((key: key, value: value));
  }
}

String _hash(int byte) =>
    base64Url.encode(List.filled(32, byte)).replaceAll('=', '');

ContactIntroductionSession _session({
  ContactIntroductionRole role = ContactIntroductionRole.requester,
  ContactIntroductionPhase phase = ContactIntroductionPhase.published,
  int hashByte = 1,
  String? contactId,
}) => ContactIntroductionSession(
  role: role,
  requestHash: _hash(hashByte),
  requestJson: '["exact-request",1]',
  expiresAt: testContactNow.add(const Duration(minutes: 15)),
  phase: phase,
  pins: [
    ContactIntroductionPin(
      contactId: 'alice',
      identity: testIdentity(1),
      outgoingIdentity: testIdentity(3),
    ),
  ],
  inputPacket: '["exact-input"]',
  outputPacket: '["exact-output"]',
  consentPacket: '["exact-consent"]',
  offerJson: '["exact-offer"]',
  endpointJson: '["exact-endpoint"]',
  suggestion: 'A public suggestion',
  contactId: contactId,
);

ContactBook _book() => ContactBook(
  contacts: [testContact()],
  associations: [
    ContactPeerAssociation(
      incomingContactId: 'alice',
      incomingIdentity: testIdentity(1),
      outgoingIdentity: testIdentity(3),
      independentlyConfirmedAt: testContactNow,
    ),
  ],
  sessions: [_session()],
  signers: [
    IntroductionStoredSigner(
      identity: testIdentity(9),
      secret: Uint8List.fromList(List.filled(32, 7)),
      address: 'test-address-fresh',
      sequence: 1,
    ),
  ],
);

Map<String, dynamic> _json(ContactBook book) =>
    jsonDecode(jsonEncode(book.toJson(testContactScope)))
        as Map<String, dynamic>;

ContactIntroductionProvenance _provenance() => ContactIntroductionProvenance(
  introducedContactId: 'bob',
  introducerContactId: 'alice',
  introducerIdentity: testIdentity(1),
  requestHash: _hash(1),
  endpointHash: _hash(2),
  attestationHash: _hash(3),
  acceptedAt: testContactNow,
  suggestion: 'Bob suggestion',
);

void main() {
  test(
    'old four-field books remain readable; additions share the same key',
    () async {
      final store = _SecretStore();
      final repository = SecureContactIntroductionRepository(store: store);
      final key = '${testContactScope.storagePrefix}book';
      store.values[key] = jsonEncode({
        'domain': 'zcash-contact/book',
        'account': testContactScope.accountUuid,
        'network': testContactScope.network,
        'contacts': [testContact().toJson()],
      });
      final old = await repository.loadBook(testContactScope);
      expect(old.contacts.single.toJson(), testContact().toJson());
      expect(old.sessions, isEmpty);
      expect(old.associations, isEmpty);
      expect(old.signers, isEmpty);
      expect(old.provenance, isEmpty);
      final added = _book();
      await repository.saveBook(testContactScope, added);
      final loaded = await repository.loadBook(testContactScope);
      expect(loaded.toJson(testContactScope), added.toJson(testContactScope));
      expect(store.values.keys, [key]);
      expect(store.writes.single.key, key);
      expect(store.reads.every((read) => read.unlocked && read.strict), isTrue);
      expect(
        jsonDecode(store.writes.single.value)['domain'],
        'zcash-contact/book',
      );
      added.clearSecrets();
      loaded.clearSecrets();
    },
  );

  test('account and network use separate encrypted book keys', () async {
    final store = _SecretStore();
    final repository = SecureContactIntroductionRepository(store: store);
    final book = _book();
    await repository.saveBook(testContactScope, book);
    for (final scope in [
      const ContactScope(accountUuid: 'other-account', network: 'test'),
      const ContactScope(
        accountUuid: 'contact-test-account',
        network: 'regtest',
      ),
    ]) {
      expect((await repository.loadBook(scope)).contacts, isEmpty);
      store.values['${scope.storagePrefix}book'] = store.values.values.first;
      await expectLater(
        repository.loadBook(scope),
        throwsA(isA<ContactFailure>()),
      );
    }
    book.clearSecrets();
  });

  test('book and pin lists copy input lists and reject mutation', () {
    final contacts = [testContact()];
    final sessions = [_session()];
    final book = ContactBook(contacts: contacts, sessions: sessions);
    contacts.clear();
    sessions.clear();
    expect(book.contacts, hasLength(1));
    expect(book.sessions, hasLength(1));
    expect(() => book.contacts.clear(), throwsUnsupportedError);
    expect(() => book.associations.clear(), throwsUnsupportedError);
    expect(() => book.sessions.clear(), throwsUnsupportedError);
    expect(() => book.signers.clear(), throwsUnsupportedError);
    expect(() => book.provenance.clear(), throwsUnsupportedError);
    expect(() => book.sessions.single.pins.clear(), throwsUnsupportedError);
    final copy = book.copyWith(contacts: [testContact(label: 'New label')]);
    expect(copy.contacts.single.label, 'New label');
    expect(book.contacts.single.label, 'Alice');
    expect(copy.sessions.single.id, book.sessions.single.id);
  });

  test(
    'contact acceptance and consumed session are one backend write',
    () async {
      final store = _SecretStore();
      final repository = SecureContactIntroductionRepository(store: store);
      final initial = _book();
      await repository.saveBook(testContactScope, initial);
      final accepted = initial.copyWith(
        contacts: [
          testContact(),
          testContact(id: 'bob', label: 'Bob', identityByte: 9),
        ],
        sessions: [
          initial.sessions.single.copyWith(
            phase: ContactIntroductionPhase.accepted,
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
            suggestion: 'Bob suggestion',
          ),
        ],
      );
      final before = store.writes.length;
      await repository.saveBook(testContactScope, accepted);
      expect(store.writes.length - before, 1);
      final loaded = await repository.loadBook(testContactScope);
      expect(loaded.contacts.last.id, 'bob');
      expect(loaded.sessions.single.phase, ContactIntroductionPhase.accepted);
      expect(loaded.sessions.single.contactId, 'bob');
      expect(loaded.provenance.single.introducedContactId, 'bob');
      expect(
        loaded.sessions.single.requestJson,
        initial.sessions.single.requestJson,
      );
      expect(
        loaded.sessions.single.outputPacket,
        initial.sessions.single.outputPacket,
      );
      expect(loaded.sessions.single.consentPacket, '["exact-consent"]');
      expect(loaded.signers.single.secret, everyElement(7));
      initial.clearSecrets();
      loaded.clearSecrets();
    },
  );

  test(
    'fresh signer and consent packet persist in the same backend write',
    () async {
      final store = _SecretStore();
      final repository = SecureContactIntroductionRepository(store: store);
      final initial = _book();
      final consent = initial.copyWith(
        sessions: [_session(role: ContactIntroductionRole.subject)],
      );
      await repository.saveBook(testContactScope, consent);
      expect(store.writes, hasLength(1));
      consent.clearSecrets();
      final loaded = await repository.loadBook(testContactScope);
      expect(loaded.sessions.single.role, ContactIntroductionRole.subject);
      expect(loaded.sessions.single.outputPacket, '["exact-output"]');
      expect(loaded.signers.single.secret, everyElement(7));
      loaded.clearSecrets();
      expect(loaded.signers.single.secret, everyElement(0));
      final reloaded = await repository.loadBook(testContactScope);
      expect(reloaded.signers.single.secret, everyElement(7));
      reloaded.clearSecrets();
    },
  );

  test(
    'decode rejects unknown fields, malformed records and duplicate keys',
    () {
      final source = _book();
      final mutations = <void Function(Map<String, dynamic>)>[
        (m) => m['domain'] = 'other',
        (m) => m['account'] = 'other',
        (m) => m['network'] = 'regtest',
        (m) => m['extra'] = true,
        (m) => m.remove('contacts'),
        (m) => m['associations'] = null,
        (m) => m['introductionSessions'] = {},
        (m) => m['introductionSigners'] = 'bad',
        (m) => m['provenance'] = {},
        (m) => (m['contacts'] as List).add((m['contacts'] as List).first),
        (m) => (m['contacts'] as List).add(testContact(id: 'other').toJson()),
        (m) => (m['contacts'] as List).add(
          testContact(id: 'other', identityByte: 2, label: 'alice').toJson(),
        ),
        (m) => (m['contacts'] as List).add({'bad': true}),
        (m) => m['associations'][0]['privateLabel'] = 'secret local name',
        (m) => m['associations'][0]['independentlyConfirmedAt'] = 1.0,
        (m) => m['associations'][0]['incomingIdentity'] = 'wrong-key',
        (m) => (m['associations'] as List).add(m['associations'][0]),
        (m) => m['introductionSessions'][0]['label'] = 'private local label',
        (m) => m['introductionSessions'][0]['role'] = 'receiver',
        (m) => m['introductionSessions'][0]['phase'] = 'complete',
        (m) => m['introductionSessions'][0]['requestHash'] = '${_hash(1)}=',
        (m) =>
            m['introductionSessions'][0]['requestHash'] = _hash(1).substring(1),
        (m) => m['introductionSessions'][0]['expiresAt'] = 0,
        (m) => m['introductionSessions'][0]['expiresAt'] = 8640000000000001,
        (m) => m['introductionSessions'][0]['outputPacket'] = null,
        (m) => m['introductionSessions'][0]['consentPacket'] = null,
        (m) => m['introductionSessions'][0]['pins'][0]['extra'] = true,
        (m) => (m['introductionSessions'][0]['pins'] as List).add(
          m['introductionSessions'][0]['pins'][0],
        ),
        (m) => (m['introductionSessions'] as List).add(
          m['introductionSessions'][0],
        ),
        (m) => m['introductionSessions'][0]['suggestion'] = ' leading',
        (m) => m['introductionSessions'][0]['suggestion'] = 'nonasciié',
        (m) => m['introductionSigners'][0]['secret'] = base64Encode(
          List.filled(31, 7),
        ),
        (m) => m['introductionSigners'][0]['secret'] = base64Encode(
          List.filled(32, 7),
        ).replaceAll('=', ''),
        (m) => m['introductionSigners'][0]['sequence'] = 0,
        (m) => m['introductionSigners'][0]['address'] = ' padded ',
        (m) => m['introductionSigners'][0]['extra'] = true,
        (m) =>
            (m['introductionSigners'] as List).add(m['introductionSigners'][0]),
      ];
      for (var i = 0; i < mutations.length; i++) {
        final map = _json(source);
        mutations[i](map);
        expect(
          () => ContactBook.decode(map, testContactScope),
          throwsA(isA<ContactFailure>()),
          reason: 'mutation $i',
        );
      }
      source.clearSecrets();
    },
  );

  test(
    'session key includes role, and expiry never silently prunes records',
    () {
      final expired = _session().copyWith(
        phase: ContactIntroductionPhase.cancelled,
      );
      final book = ContactBook(
        sessions: [
          expired,
          _session(role: ContactIntroductionRole.introducer),
          _session(role: ContactIntroductionRole.subject),
        ],
      );
      final loaded = ContactBook.decode(_json(book), testContactScope);
      expect(loaded.sessions, hasLength(3));
      expect(loaded.sessions.first.phase, ContactIntroductionPhase.cancelled);
      expect(
        loaded.sessions.map((session) => session.id).toSet(),
        hasLength(3),
      );
    },
  );

  test('provenance rejects ambiguous keys and unrecognized saved metadata', () {
    final source = ContactBook(provenance: [_provenance()]);
    final mutations = <void Function(Map<String, dynamic>)>[
      (m) => m['provenance'][0]['privateLabel'] = 'local name',
      (m) => m['provenance'][0]['introducerIdentity'] = 'wrong-key',
      (m) => m['provenance'][0]['requestHash'] = '${_hash(1)}=',
      (m) => m['provenance'][0]['endpointHash'] = 'short',
      (m) => m['provenance'][0]['attestationHash'] = 42,
      (m) => m['provenance'][0]['suggestion'] = null,
      (m) => m['provenance'][0]['acceptedAt'] = 1.5,
      (m) => m['provenance'][0].remove('endpointHash'),
      (m) => (m['provenance'] as List).add(m['provenance'][0]),
      (m) => (m['provenance'] as List).add({
        ...m['provenance'][0],
        'introducedContactId': 'different-contact',
      }),
    ];
    for (var i = 0; i < mutations.length; i++) {
      final map = _json(source);
      mutations[i](map);
      expect(
        () => ContactBook.decode(map, testContactScope),
        throwsA(isA<ContactFailure>()),
        reason: 'provenance mutation $i',
      );
    }
  });

  test(
    'optional stage data is omitted and retained without wire normalization',
    () {
      final pending = ContactIntroductionSession(
        role: ContactIntroductionRole.requester,
        requestHash: _hash(1),
        requestJson: '["exact-request",1]',
        expiresAt: testContactNow,
        phase: ContactIntroductionPhase.prepared,
      );
      expect(pending.toJson().containsKey('outputPacket'), isFalse);
      expect(pending.toJson().containsKey('consentPacket'), isFalse);
      final book = ContactBook(sessions: [pending]);
      final decoded = ContactBook.decode(_json(book), testContactScope);
      expect(decoded.sessions.single.outputPacket, isNull);
      expect(decoded.sessions.single.consentPacket, isNull);
      final published = pending.copyWith(
        phase: ContactIntroductionPhase.published,
        outputPacket: '["exact-output"]',
        consentPacket: '["exact-consent"]',
      );
      expect(published.requestJson, pending.requestJson);
      expect(published.requestHash, pending.requestHash);
      expect(published.expiresAt, pending.expiresAt);
      expect(published.consentPacket, '["exact-consent"]');
    },
  );

  test('all record arrays are bounded without partial acceptance', () {
    final book = _book();
    for (final field in [
      'contacts',
      'associations',
      'introductionSessions',
      'introductionSigners',
      'provenance',
    ]) {
      final map = _json(book);
      map[field] = List.filled(101, null);
      expect(
        () => ContactBook.decode(map, testContactScope),
        throwsA(isA<ContactFailure>()),
        reason: field,
      );
    }
    book.clearSecrets();
  });

  test('malformed JSON and oversized UTF-8 plaintext fail closed', () async {
    final store = _SecretStore();
    final repository = SecureContactIntroductionRepository(store: store);
    final key = '${testContactScope.storagePrefix}book';
    for (final raw in ['{bad', '[]', 'null', ' ' * (contactBookMaxBytes + 1)]) {
      store.values[key] = raw;
      await expectLater(
        repository.loadBook(testContactScope),
        throwsA(isA<ContactFailure>()),
      );
    }
    // This JSON is under the UTF-16 code-unit cap but exceeds the UTF-8 byte cap.
    final tooLarge = ContactBook(
      sessions: List.generate(
        40,
        (i) => _session(hashByte: i).copyWith(inputPacket: 'é' * 14000),
      ),
    );
    final raw = jsonEncode(tooLarge.toJson(testContactScope));
    expect(raw.length, lessThan(contactBookMaxBytes));
    expect(utf8.encode(raw).length, greaterThan(contactBookMaxBytes));
    store.values[key] = raw;
    await expectLater(
      repository.loadBook(testContactScope),
      throwsA(isA<ContactFailure>()),
    );
    await expectLater(
      repository.saveBook(testContactScope, tooLarge),
      throwsA(isA<ContactFailure>()),
    );
    expect(store.writes, isEmpty);
    final packetTooLarge = ContactBook(
      sessions: [_session().copyWith(inputPacket: 'é' * 16385)],
    );
    await expectLater(
      repository.saveBook(testContactScope, packetTooLarge),
      throwsA(isA<ContactFailure>()),
    );
    expect(store.writes, isEmpty);
  });

  test('invalid programmatic records cannot overwrite a valid book', () async {
    final store = _SecretStore();
    final repository = SecureContactIntroductionRepository(store: store);
    final source = _book();
    await repository.saveBook(testContactScope, source);
    final old = store.values.values.single;
    await expectLater(
      repository.saveBook(
        testContactScope,
        source.copyWith(
          sessions: [source.sessions.single, source.sessions.single],
        ),
      ),
      throwsA(isA<ContactFailure>()),
    );
    expect(store.values.values.single, old);
    expect(store.writes, hasLength(1));
    source.clearSecrets();
  });

  test(
    'backend failures propagate without returning empty or published state',
    () async {
      final store = _SecretStore();
      final repository = SecureContactIntroductionRepository(store: store);
      final source = _book();
      await repository.saveBook(testContactScope, source);
      final old = store.values.values.single;
      store.writeFailure = StateError('storage unavailable');
      await expectLater(
        repository.saveBook(
          testContactScope,
          source.copyWith(
            sessions: [
              source.sessions.single.copyWith(
                phase: ContactIntroductionPhase.accepted,
                contactId: 'bob',
              ),
            ],
          ),
        ),
        throwsStateError,
      );
      expect(store.values.values.single, old);
      store.readFailure = StateError('locked');
      await expectLater(
        repository.loadBook(testContactScope),
        throwsStateError,
      );
      expect(store.writes, hasLength(1));
      expect(source.signers.single.secret, everyElement(7));
      source.clearSecrets();
    },
  );
}
