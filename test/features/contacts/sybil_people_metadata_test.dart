import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_exchange_controller.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_lifecycle.dart';
import 'package:zcash_wallet/src/features/contacts/application/sybil_people_metadata_provider.dart';
import 'package:zcash_wallet/src/features/contacts/data/sybil_people_metadata_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import 'contact_test_fakes.dart';

class _SecretStore extends Fake implements AppSecureStore {
  final values = <String, String>{};
  final unlockedReads = <bool>[];
  final strictReads = <bool>[];
  Completer<void>? writeGate;

  @override
  Future<String?> readSecretStringWithOptions(
    String key, {
    bool requireUnlockedSession = false,
    bool rejectInvalidEnvelope = false,
  }) async {
    unlockedReads.add(requireUnlockedSession);
    strictReads.add(rejectInvalidEnvelope);
    return values[key];
  }

  @override
  Future<void> writeSecretString(String key, String value) async {
    await writeGate?.future;
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('notes and pins use strict encrypted account/network storage', () async {
    final store = _SecretStore();
    final repository = SybilPeopleMetadataRepository(store: store);
    final identity = testIdentity(1);
    await repository.save(testContactScope, {
      identity: const SybilPersonMetadata(
        notes: 'Met at the café.\nPrefers mornings.',
        pinned: true,
      ),
    }, beforeWrite: () {});
    expect(
      store.values.keys.single,
      startsWith(testContactScope.storagePrefix),
    );
    final loaded = await SybilPeopleMetadataRepository(
      store: store,
    ).load(testContactScope);
    expect(loaded[identity]!.notes, contains('café'));
    expect(loaded[identity]!.pinned, isTrue);
    expect(() => loaded.clear(), throwsUnsupportedError);
    expect(store.unlockedReads, everyElement(true));
    expect(store.strictReads, everyElement(true));
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
  });

  test(
    'foreign scopes, unknown fields and excessive notes fail closed',
    () async {
      final store = _SecretStore();
      final repository = SybilPeopleMetadataRepository(store: store);
      await repository.save(testContactScope, {
        testIdentity(1): const SybilPersonMetadata(notes: 'Private'),
      }, beforeWrite: () {});
      final key = store.values.keys.single;
      final original = store.values[key]!;
      for (final change in <void Function(Map<String, dynamic>)>[
        (map) => map['account'] = 'foreign',
        (map) => map['network'] = 'regtest',
        (map) => map['extra'] = 'unsupported',
        (map) => (map['people'] as Map)[testIdentity(1)]['notes'] = 'n' * 2001,
        (map) => (map['people'] as Map)[testIdentity(1)]['pinned'] = 'true',
      ]) {
        final map = jsonDecode(original) as Map<String, dynamic>;
        change(map);
        store.values[key] = jsonEncode(map);
        await expectLater(
          repository.load(testContactScope),
          throwsA(isA<ContactFailure>()),
        );
      }
      await expectLater(
        repository.save(testContactScope, {
          testIdentity(1): const SybilPersonMetadata(notes: 'Bad\u0000note'),
        }, beforeWrite: () {}),
        throwsA(isA<ContactFailure>()),
      );
    },
  );

  test(
    'pending metadata save drains on account removal and never republishes after scope loss',
    () async {
      final store = _SecretStore();
      final person = testContact();
      final container = ProviderContainer(
        overrides: [
          contactScopeProvider.overrideWith(
            (ref) => ref.watch(testContactScopeProvider),
          ),
          contactRepositoryProvider.overrideWithValue(
            FakeContactRepository([person]),
          ),
          contactGatewayProvider.overrideWithValue(FakeContactGateway()),
          sybilPeopleMetadataRepositoryProvider.overrideWithValue(
            SybilPeopleMetadataRepository(store: store),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(
        () => ContactLifecycle.resume(account: testContactScope.accountUuid),
      );
      container.read(contactExchangeProvider);
      await pumpEventQueue();
      await container.read(sybilPeopleMetadataProvider.future);
      store.writeGate = Completer<void>();
      final operation = container
          .read(sybilPeopleMetadataProvider.notifier)
          .save(
            person,
            const SybilPersonMetadata(notes: 'Local only', pinned: true),
          );
      final rejected = expectLater(operation, throwsA(isA<ContactFailure>()));
      await pumpEventQueue();
      var drained = false;
      final quiescence = ContactLifecycle.quiesce(
        account: testContactScope.accountUuid,
      ).then((_) => drained = true);
      container.read(testContactScopeProvider.notifier).change(null);
      await pumpEventQueue();
      expect(drained, isFalse);
      store.writeGate!.complete();
      await rejected;
      await quiescence;
      expect(drained, isTrue);
      expect(await container.read(sybilPeopleMetadataProvider.future), isEmpty);
    },
  );
}
