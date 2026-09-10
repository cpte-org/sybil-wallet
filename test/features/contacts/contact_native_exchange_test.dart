@Tags(['contact-native'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_exchange_controller.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_gateway.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'package:zcash_wallet/src/rust/api/contacts.dart' as native_contacts;
import 'package:zcash_wallet/src/rust/api/sync.dart' as native_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as native_wallet;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import 'support/file_contact_storage.dart';

const _libraryPath = String.fromEnvironment('CONTACT_NATIVE_LIBRARY');
const _password = 'ContactCheck1!';
const _newPassword = 'ContactCheck2!';
// Public BIP39 test vector, never a user seed. No funds or network calls.
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
    'real bridge exchanges and persists contacts between two disposable wallets',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'zcash-contact-native-',
      );
      final actors = <_Actor>[];
      final clock = _Clock();
      try {
        final alice = await _Actor.create(root, 'alice', clock);
        actors.add(alice);
        final bob = await _Actor.create(root, 'bob', clock);
        actors.add(bob);
        expect(alice.scope.accountUuid, isNot(bob.scope.accountUuid));

        await alice.controller.startRequest();
        final request = alice.state.request!.json;
        alice.controller.pauseExchange(); // Switching to the transport app.
        expect(alice.state.request!.json, request);
        await bob.controller.prepareShare(request);
        expect(bob.state.error, isNull);
        final firstShare = bob.state.shareReview!;
        expect(firstShare.address, startsWith('utest1'));
        expect(
          await bob.gateway.validateAddress(bob.scope, firstShare.address),
          isTrue,
        );
        await bob.controller.confirmShare(consent: true);
        expect(bob.state.error, isNull);
        final firstReply = bob.state.response!;

        // The UI's independent human check is represented here by comparing the
        // sender's known identity/address directly; this is not human validation.
        await alice.controller.previewResponse(firstReply);
        expect(alice.state.candidate!.identity, firstShare.identity);
        expect(alice.state.candidate!.address, firstShare.address);
        expect(alice.state.contacts, isEmpty);
        await alice.controller.acceptResponse(
          label: 'Bob',
          independentlyVerified: true,
        );
        expect(alice.state.error, isNull);
        final accepted = alice.state.contacts.single;
        final originalSelection = alice.controller.recipientFor(accepted.id);
        alice.validate(originalSelection);
        await alice.controller.previewResponse(firstReply);
        expect(alice.state.error, contains('Create a contact request first'));
        expect(alice.state.contacts.single.address, firstShare.address);

        // Native validation rejects both a changed signed payload and mainnet.
        final wrongRequest = await alice.gateway.createRequest(
          alice.scope,
          null,
          clock.now,
        );
        await expectLater(
          alice.gateway.verify(
            alice.scope,
            wrongRequest.json,
            firstReply,
            clock.now,
          ),
          throwsA(anything),
        );
        final envelope = jsonDecode(firstReply) as List<dynamic>;
        final signed = envelope[1] as List<dynamic>;
        final payload =
            jsonDecode(
                  utf8.decode(
                    base64Url.decode(base64Url.normalize(signed[0] as String)),
                  ),
                )
                as List<dynamic>;
        payload[8] = '${payload[8]}x';
        signed[0] = base64Url
            .encode(utf8.encode(jsonEncode(payload)))
            .replaceAll('=', '');
        await expectLater(
          alice.gateway.verify(
            alice.scope,
            request,
            jsonEncode(envelope),
            clock.now,
          ),
          throwsA(anything),
        );
        await expectLater(
          native_contacts.contactsValidateUnifiedAddress(
            network: 'main',
            address: firstShare.address,
          ),
          throwsA(anything),
        );
        expect(
          await native_contacts.contactsValidateUnifiedAddress(
            network: 'regtest',
            address: firstShare.address,
          ),
          isFalse,
        );

        // Public labels/addresses and private signing records are encrypted on disk.
        final aliceBytes = await alice.storageFile.readAsString();
        final bobBytes = await bob.storageFile.readAsString();
        expect(aliceBytes.contains(firstShare.identity), isFalse);
        expect(aliceBytes.contains(firstShare.address), isFalse);
        expect(aliceBytes.contains('"label":"Bob"'), isFalse);
        expect(bobBytes.contains('"secret":'), isFalse);
        expect(bobBytes.contains(firstShare.address), isFalse);
        final persistedSigner = await bob.repository.loadSigner(
          bob.scope,
          firstShare.identity,
        );
        expect(persistedSigner, isNotNull);
        persistedSigner!.clear();

        // New controllers + storage adapters read the existing encrypted records.
        await alice.reopen();
        await bob.reopen();
        expect(alice.state.contacts.single.identity, firstShare.identity);
        expect(
          () => alice.validate(originalSelection),
          throwsA(isA<ContactFailure>()),
        );
        clock.now = clock.now.add(const Duration(minutes: 6));
        alice.validate(alice.controller.recipientFor(accepted.id));

        await alice.controller.startRequest(contactId: accepted.id);
        await bob.controller.prepareShare(alice.state.request!.json);
        expect(bob.state.error, isNull);
        final update = bob.state.shareReview!;
        expect(update.identity, firstShare.identity);
        expect(update.previousAddress, firstShare.address);
        expect(update.address, isNot(firstShare.address));
        await bob.controller.confirmShare(consent: true);
        final updateReply = bob.state.response!;
        await alice.controller.previewResponse(updateReply);
        expect(alice.state.candidate!.sequence, accepted.sequence + 1);
        expect(alice.state.contacts.single.address, firstShare.address);
        await alice.controller.acceptResponse(
          label: 'Bob',
          independentlyVerified: true,
        );
        expect(alice.state.contacts.single.address, update.address);

        // The existing password-rotation path must keep real encrypted contact data usable.
        expect(
          await bob.store.changePassword(
            currentPassword: _password,
            newPassword: _newPassword,
          ),
          isTrue,
        );
        await bob.reopen(password: _newPassword);
        final signer = await bob.repository.loadSigner(
          bob.scope,
          update.identity,
        );
        expect(signer!.sequence, accepted.sequence + 1);
        expect(signer.address, update.address);
        signer.clear();

        final selected = alice.controller.recipientFor(accepted.id);
        await alice.controller.suspendContact(accepted.id);
        expect(() => alice.validate(selected), throwsA(isA<ContactFailure>()));
        await alice.reopen();
        expect(
          alice.state.contacts.single.status,
          ContactTrustStatus.suspended,
        );
        expect(
          () => alice.controller.recipientFor(accepted.id),
          throwsA(isA<ContactFailure>()),
        );

        // Corrupt only this disposable book's envelope. It must not become an empty usable book.
        await alice.store.writePlain(
          '${alice.scope.storagePrefix}book',
          'damaged envelope',
        );
        await alice.controller.reload();
        expect(alice.state.error, contains('storage could not be opened'));
        expect(
          () => alice.controller.recipientFor(accepted.id),
          throwsA(isA<ContactFailure>()),
        );
      } finally {
        for (final actor in actors) {
          actor.close();
        }
        await root.delete(
          recursive: true,
        ); // Only the unique directory created above.
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
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
  _Actor(this.scope, this.storageFile, this.gateway, this.clock);
  final ContactScope scope;
  final File storageFile;
  final _DatabaseGateway gateway;
  final _Clock clock;
  late AppSecureStore store;
  late SecureContactRepository repository;
  ProviderContainer? _container;
  ContactExchangeController get controller =>
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
      bip39Passphrase: 'public-contact-check-$name',
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

  Future<void> reopen({bool first = false, String password = _password}) async {
    _container?.dispose();
    _container = null;
    if (!first) store.clearSessionPassword();
    store = AppSecureStore.testing(
      storage: FileBackedContactSecureStorage(storageFile),
    );
    if (first) {
      await store.configurePassword(password);
    } else {
      expect(await store.verifyPassword(password), isTrue);
    }
    repository = SecureContactRepository(store: store);
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

  void validate(ContactRecipientSnapshot snapshot) =>
      controller.validateRecipient(
        snapshot,
        address: snapshot.address,
        accountUuid: scope.accountUuid,
        network: scope.network,
      );
  void close() {
    _container?.dispose();
    _container = null;
    store.clearSessionPassword();
  }
}
