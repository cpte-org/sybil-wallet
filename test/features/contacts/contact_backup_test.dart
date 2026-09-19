import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_exchange_controller.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_gateway.dart';
import 'contact_test_fakes.dart' show FakeContactGateway;
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_repository.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_backup_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_backup_store.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_introduction_models.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'contact_test_fixtures.dart';

const sourceScope = ContactScope(accountUuid: 'old-db-id', network: 'test');
const targetScope = ContactScope(accountUuid: 'new-db-id', network: 'test');

class MemoryBackupStore implements ContactBackupStore {
  ContactBook book = ContactBook();
  bool occupied = false;
  ContactBook copy(ContactBook b, ContactScope s) =>
      ContactBook.decode(jsonDecode(jsonEncode(b.toJson(s))), s);
  @override
  Future<ContactBook> snapshot(ContactScope scope) async => copy(book, scope);
  @override
  Future<void> restoreEmpty(
    ContactScope scope,
    ContactBook next,
    void Function() check,
  ) async {
    check();
    if (occupied) throw const ContactFailure('Existing data');
    book = copy(next, scope);
    occupied = true;
  }
}

// Only exercises snapshot policy; native encryption is tested separately.
class FixtureCrypto implements ContactBackupCrypto {
  Uint8List? lastPlain;
  Completer<void>? pause;
  @override
  Future<String> encrypt(ContactScope scope, Uint8List plain) async {
    lastPlain = plain;
    return utf8.decode(plain);
  }

  @override
  Future<Uint8List> decrypt(ContactScope scope, String archive) async {
    final plain = Uint8List.fromList(utf8.encode(archive));
    lastPlain = plain;
    if (pause != null) await pause!.future;
    return plain;
  }
}

class FixtureStore extends Fake implements AppSecureStore {
  final values = <String, String>{};
  @override
  Future<List<String>> storedKeysWithPrefix(String prefix) async =>
      values.keys.where((k) => k.startsWith(prefix)).toList();
  @override
  Future<String?> readSecretStringWithOptions(
    String key, {
    bool requireUnlockedSession = false,
    bool rejectInvalidEnvelope = false,
  }) async {
    expect(requireUnlockedSession, isTrue);
    expect(rejectInvalidEnvelope, isTrue);
    return values[key];
  }

  @override
  Future<void> writeSecretString(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryBackupStore source, target;
  late FixtureCrypto crypto;
  late ContactBackupCoordinator exporter, importer;
  setUp(() {
    source = MemoryBackupStore();
    target = MemoryBackupStore();
    crypto = FixtureCrypto();
    source.book = ContactBook(
      contacts: [testContact()],
      signers: [
        IntroductionStoredSigner(
          identity: testContact().identity,
          secret: Uint8List.fromList(List.filled(32, 7)),
          address: 'fixture-address',
          sequence: 3,
        ),
      ],
    );
    exporter = ContactBackupCoordinator(
      scope: () => sourceScope,
      store: source,
      crypto: crypto,
    );
    importer = ContactBackupCoordinator(
      scope: () => targetScope,
      store: target,
      crypto: crypto,
    );
  });
  tearDown(() {
    exporter.invalidate();
    importer.invalidate();
    source.book.clearSecrets();
    target.book.clearSecrets();
  });
  test(
    'secure restore keeps archived keys inaccessible to ordinary signing',
    () async {
      final storage = FixtureStore();
      final secure = SecureContactBackupStore(store: storage);
      final coordinator = ContactBackupCoordinator(
        scope: () => targetScope,
        store: secure,
        crypto: crypto,
      );
      final review = await coordinator.prepare(await exporter.export());
      await coordinator.restore(review, approved: true);
      final direct = SecureContactRepository(store: storage);
      await expectLater(
        direct.loadSigner(targetScope, testContact().identity),
        throwsA(isA<ContactFailure>()),
      );
      final oldSigner = ContactSigner(
        identity: testContact().identity,
        secret: Uint8List(32),
        address: 'fixture-address',
        sequence: 99,
      );
      await expectLater(
        direct.saveSigner(targetScope, oldSigner),
        throwsA(isA<ContactFailure>()),
      );
      oldSigner.clear();
      final next = await coordinator.prepare(await exporter.export());
      await expectLater(
        coordinator.restore(next, approved: true),
        throwsA(isA<ContactFailure>()),
      );
      coordinator.invalidate();
    },
  );
  test(
    'restored peer check completes without activating archived signing keys',
    () async {
      final storage = FixtureStore();
      final secure = SecureContactBackupStore(store: storage);
      final coordinator = ContactBackupCoordinator(
        scope: () => targetScope,
        store: secure,
        crypto: crypto,
      );
      addTearDown(coordinator.invalidate);
      final review = await coordinator.prepare(await exporter.export());
      await coordinator.restore(review, approved: true);
      final direct = SecureContactRepository(store: storage);
      final gateway = FakeContactGateway();
      final container = ProviderContainer(
        overrides: [
          contactScopeProvider.overrideWithValue(targetScope),
          contactRepositoryProvider.overrideWithValue(direct),
          contactGatewayProvider.overrideWithValue(gateway),
          contactClockProvider.overrideWithValue(() => testContactNow),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(contactExchangeProvider.notifier);
      await pumpEventQueue();
      expect(
        (await coordinator.recoveryProgress()).pendingContacts,
        hasLength(1),
      );
      await controller.startRequest(contactId: 'alice');
      // A validly signed but older revision must not complete recovery.
      gateway.endpoint = ContactWireEndpoint(
        identity: testContact().identity,
        address: 'older-address',
        sequence: 4,
        expiresAt: testContactNow.add(const Duration(minutes: 5)),
      );
      await controller.previewResponse('older-response');
      expect(container.read(contactExchangeProvider).candidate, isNull);
      expect(
        (await coordinator.recoveryProgress()).pendingContacts,
        hasLength(1),
      );
      gateway.endpoint = FakeContactGateway().endpoint;
      await controller.previewResponse('fresh-response');
      await controller.acceptResponse(
        label: 'Alice',
        independentlyVerified: false,
      );
      expect(
        (await coordinator.recoveryProgress()).pendingContacts,
        hasLength(1),
      );
      // An interrupted review cannot be accepted later.
      controller.cancelTransient();
      await controller.acceptResponse(
        label: 'Alice',
        independentlyVerified: true,
      );
      expect(
        (await coordinator.recoveryProgress()).pendingContacts,
        hasLength(1),
      );
      await controller.startRequest(contactId: 'alice');
      await controller.previewResponse('fresh-response');
      await controller.acceptResponse(
        label: 'Alice',
        independentlyVerified: true,
      );
      final progress = await coordinator.recoveryProgress();
      expect(progress.pendingContacts, isEmpty);
      expect(progress.inactiveKeyCount, 1);
      expect((await direct.load(targetScope)).single.canPay, isTrue);
      await expectLater(
        direct.loadSigner(targetScope, testContact().identity),
        throwsA(isA<ContactFailure>()),
      );
      // The consumed proof has no pending request to authorize a second update.
      await controller.previewResponse('fresh-response');
      expect(container.read(contactExchangeProvider).candidate, isNull);
    },
  );

  test('portable export includes legacy direct signing records', () async {
    final storage = FixtureStore();
    final direct = SecureContactRepository(store: storage);
    final signer = ContactSigner(
      identity: testContact().identity,
      secret: Uint8List.fromList(List.filled(32, 9)),
      address: 'fixture-address',
      sequence: 4,
    );
    await direct.saveSigner(sourceScope, signer);
    signer.clear();
    final snapshot = await SecureContactBackupStore(
      store: storage,
    ).snapshot(sourceScope);
    expect(snapshot.signers.single.secret.first, 9);
    expect(snapshot.signers.single.sequence, 4);
    snapshot.clearSecrets();
  });
  test(
    'portable restoration quarantines keys and requires fresh contact verification',
    () async {
      final archive = await exporter.export();
      expect(crypto.lastPlain!.every((v) => v == 0), isTrue);
      expect(source.book.signers.single.secret.first, 7);
      final review = await importer.prepare(archive);
      expect(crypto.lastPlain!.every((v) => v == 0), isTrue);
      expect(review.book.contacts.single.canPay, isFalse);
      expect(review.book.contacts.single.canRequestUpdate, isTrue);
      expect(review.book.signers, isEmpty);
      expect(review.book.associations, isEmpty);
      expect(review.book.sessions, isEmpty);
      await expectLater(
        importer.restore(review, approved: false),
        throwsA(isA<ContactFailure>()),
      );
      await importer.restore(review, approved: true);
      expect(target.book.contacts.single.status, ContactTrustStatus.restored);
      expect(target.book.quarantinedSigners.single.secret.first, 7);
      expect(
        review.book.quarantinedSigners.single.secret.every((v) => v == 0),
        isTrue,
      );
    },
  );
  test('existing data and revoked review never grant restoration', () async {
    final review = await importer.prepare(await exporter.export());
    target.occupied = true;
    await expectLater(
      importer.restore(review, approved: true),
      throwsA(isA<ContactFailure>()),
    );
    expect(target.book.contacts, isEmpty);
    target.occupied = false;
    importer.invalidate();
    await expectLater(
      importer.restore(review, approved: true),
      throwsA(isA<ContactFailure>()),
    );
    expect(target.book.contacts, isEmpty);
  });
  test(
    'late decrypt after lifecycle invalidation clears plaintext without review',
    () async {
      final archive = await exporter.export();
      crypto.pause = Completer<void>();
      final pending = importer.prepare(archive);
      final result = expectLater(pending, throwsA(isA<ContactFailure>()));
      await Future<void>.delayed(Duration.zero);
      importer.invalidate();
      crypto.pause!.complete();
      await result;
      expect(crypto.lastPlain!.every((v) => v == 0), isTrue);
    },
  );
  test(
    'restore preserves suspension and retirement; wrong network is rejected',
    () async {
      source.book = ContactBook(
        contacts: [
          testContact().copyWith(status: ContactTrustStatus.suspended),
        ],
      );
      var review = await importer.prepare(await exporter.export());
      expect(review.book.contacts.single.canRequestUpdate, isFalse);
      source.book = ContactBook(
        contacts: [testContact().copyWith(status: ContactTrustStatus.retired)],
      );
      review = await importer.prepare(await exporter.export());
      expect(review.book.contacts.single.status, ContactTrustStatus.retired);
      final archive =
          jsonDecode(await exporter.export()) as Map<String, dynamic>;
      archive['book']['network'] = 'main';
      await expectLater(
        importer.prepare(jsonEncode(archive)),
        throwsA(isA<ContactFailure>()),
      );
    },
  );
}
