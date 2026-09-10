import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import 'contact_test_fixtures.dart';

class _SecretStore extends Fake implements AppSecureStore {
  final values = <String, String>{};
  final unlockedReads = <bool>[];
  final strictEnvelopeReads = <bool>[];
  @override
  Future<String?> readSecretStringWithOptions(
    String key, {
    bool requireUnlockedSession = false,
    bool rejectInvalidEnvelope = false,
  }) async {
    unlockedReads.add(requireUnlockedSession);
    strictEnvelopeReads.add(rejectInvalidEnvelope);
    return values[key];
  }

  @override
  Future<void> writeSecretString(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test(
    'contact book uses account/network-scoped encrypted storage and immutable loaded lists',
    () async {
      final store = _SecretStore();
      final repository = SecureContactRepository(store: store);
      final contacts = [testContact()];
      await repository.save(testContactScope, contacts);
      expect(store.values.keys.single, '${testContactScope.storagePrefix}book');
      final book =
          jsonDecode(store.values.values.single) as Map<String, dynamic>;
      expect(book['domain'], 'zcash-contact/book');
      expect(book['account'], testContactScope.accountUuid);
      expect(book['network'], 'test');
      final loaded = await repository.load(testContactScope);
      expect(loaded.single.toJson(), contacts.single.toJson());
      expect(() => loaded.add(testContact()), throwsUnsupportedError);
      expect(store.unlockedReads, isNotEmpty);
      expect(store.unlockedReads, everyElement(true));
      expect(store.strictEnvelopeReads, everyElement(true));
      expect(
        await repository.load(
          const ContactScope(accountUuid: 'other', network: 'test'),
        ),
        isEmpty,
      );
      expect(
        await repository.load(
          const ContactScope(
            accountUuid: 'contact-test-account',
            network: 'regtest',
          ),
        ),
        isEmpty,
      );
    },
  );

  test(
    'whole-book decode rejects malformed schemas, foreign scopes and partial bad records',
    () async {
      final store = _SecretStore();
      final repository = SecureContactRepository(store: store);
      final key = '${testContactScope.storagePrefix}book';
      await repository.save(testContactScope, [testContact()]);
      final original = store.values[key]!;
      final mutations = <void Function(Map<String, dynamic>)>[
        (m) => m['domain'] = 'legacy-address-book',
        (m) => m['account'] = 'foreign-account',
        (m) => m['network'] = 'regtest',
        (m) => m['extra'] = 'unsupported',
        (m) => m.remove('network'),
        (m) => m['contacts'] = {},
        (m) => (m['contacts'] as List).add({'malformed': true}),
        (m) => (m['contacts'] as List).add((m['contacts'] as List).first),
        (m) => (m['contacts'] as List).add(testContact(id: 'other').toJson()),
        (m) => m['contacts'] = List.generate(
          101,
          (i) => testContact(id: '$i', identityByte: i).toJson(),
        ),
        (m) => (m['contacts'] as List).first['address'] = ' whitespace ',
        (m) => (m['contacts'] as List).first['sequence'] = 0,
        (m) => (m['contacts'] as List).first['revision'] = 1.0,
        (m) => (m['contacts'] as List).first['status'] = 'unknown',
        (m) =>
            (m['contacts'] as List).first['identity'] = '${testIdentity(1)}=',
      ];
      for (final mutate in mutations) {
        final book = jsonDecode(original) as Map<String, dynamic>;
        mutate(book);
        store.values[key] = jsonEncode(book);
        await expectLater(
          repository.load(testContactScope),
          throwsA(isA<ContactFailure>()),
        );
      }
      for (final raw in ['{not-json', '[]', 'null', ' ' * 131073]) {
        store.values[key] = raw;
        await expectLater(
          repository.load(testContactScope),
          throwsA(isA<ContactFailure>()),
        );
      }
    },
  );

  test(
    'saved book cannot reintroduce ambiguous case-insensitive local labels',
    () async {
      final store = _SecretStore();
      final repository = SecureContactRepository(store: store);
      await expectLater(
        repository.save(testContactScope, [
          testContact(),
          testContact(id: 'other', identityByte: 2, label: 'alice'),
        ]),
        throwsA(isA<ContactFailure>()),
      );
      expect(store.values, isEmpty);
    },
  );

  test(
    'signer storage retains exact key/address/counter and zeroing a loaded key preserves storage',
    () async {
      final store = _SecretStore();
      final repository = SecureContactRepository(store: store);
      final signer = ContactSigner(
        identity: testIdentity(3),
        secret: Uint8List.fromList(List.filled(32, 7)),
        address: 'test-address',
        sequence: 12,
      );
      await repository.saveSigner(testContactScope, signer);
      signer.clear();
      expect(signer.secret, everyElement(0));
      final loaded = (await repository.loadSigner(
        testContactScope,
        signer.identity,
      ))!;
      expect(loaded.identity, signer.identity);
      expect(loaded.address, 'test-address');
      expect(loaded.sequence, 12);
      expect(loaded.secret, everyElement(7));
      loaded.clear();
      final reloaded = (await repository.loadSigner(
        testContactScope,
        signer.identity,
      ))!;
      expect(reloaded.secret, everyElement(7));
      reloaded.clear();
      expect(store.unlockedReads, everyElement(true));
      expect(store.strictEnvelopeReads, everyElement(true));
      expect(
        await repository.loadSigner(testContactScope, testIdentity(4)),
        isNull,
      );
    },
  );

  test(
    'signer decode rejects foreign scope, wrong identity, bad counters and secret encodings',
    () async {
      final store = _SecretStore();
      final repository = SecureContactRepository(store: store);
      final signer = ContactSigner(
        identity: testIdentity(3),
        secret: Uint8List.fromList(List.filled(32, 7)),
        address: 'test-address',
        sequence: 12,
      );
      await repository.saveSigner(testContactScope, signer);
      signer.clear();
      final key = store.values.keys.single,
          original = store.values.values.single;
      for (final entry in <String, Object?>{
        'domain': 'other',
        'account': 'foreign',
        'network': 'regtest',
        'identity': testIdentity(4),
        'sequence': 0,
        'secret': base64Encode(List.filled(31, 7)),
        'extra': 'unsupported',
      }.entries) {
        final record = jsonDecode(original) as Map<String, dynamic>;
        record[entry.key] = entry.value;
        store.values[key] = jsonEncode(record);
        await expectLater(
          repository.loadSigner(testContactScope, signer.identity),
          throwsA(isA<ContactFailure>()),
        );
      }
      store.values[key] = 'x' * 4097;
      await expectLater(
        repository.loadSigner(testContactScope, signer.identity),
        throwsA(isA<ContactFailure>()),
      );
    },
  );
}
