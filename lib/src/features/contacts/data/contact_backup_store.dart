import 'dart:typed_data';
import '../../../core/storage/app_secure_store.dart';
import '../domain/contact_introduction_models.dart';
import '../domain/contact_models.dart';
import 'contact_introduction_repository.dart';
import 'contact_repository.dart';

abstract class ContactBackupStore {
  Future<ContactBook> snapshot(ContactScope scope);
  Future<void> restoreEmpty(
    ContactScope scope,
    ContactBook book,
    void Function() check,
  );
}

class SecureContactBackupStore implements ContactBackupStore {
  SecureContactBackupStore({AppSecureStore? store})
    : store = store ?? AppSecureStore.instance;
  final AppSecureStore store;
  @override
  Future<ContactBook> snapshot(ContactScope scope) async {
    final books = SecureContactIntroductionRepository(store: store);
    final direct = SecureContactRepository(store: store);
    final book = await books.loadBook(scope);
    final extra = <IntroductionStoredSigner>[];
    try {
      final prefix = '${scope.storagePrefix}signer_';
      final keys = await store.storedKeysWithPrefix(prefix);
      if (keys.length > contactBookMaxRecords) {
        throw const ContactFailure('Too many contact signing records.');
      }
      for (final key in keys) {
        final identity = contactIdentity(
          'ed25519:${key.substring(prefix.length)}',
        );
        if ([
          ...book.signers,
          ...book.quarantinedSigners,
        ].any((s) => s.identity == identity)) {
          continue;
        }
        final signer = await direct.loadSigner(scope, identity);
        if (signer == null) {
          throw const ContactFailure('A contact signing record is missing.');
        }
        try {
          extra.add(
            IntroductionStoredSigner(
              identity: signer.identity,
              secret: Uint8List.fromList(signer.secret),
              address: signer.address,
              sequence: signer.sequence,
            ),
          );
        } finally {
          signer.clear();
        }
      }
      // Transient invitations and prior approvals do not belong in recovery.
      return book.copyWith(signers: [...book.signers, ...extra], sessions: []);
    } catch (_) {
      book.clearSecrets();
      for (final s in extra) {
        s.clear();
      }
      rethrow;
    }
  }

  @override
  Future<void> restoreEmpty(
    ContactScope scope,
    ContactBook book,
    void Function() check,
  ) async {
    final keys = await store.storedKeysWithPrefix(scope.storagePrefix);
    check();
    // Avoid multi-record merge/rollback and resurrecting queued approvals or
    // existing transport profiles. Recovery initially targets a fresh account.
    if (keys.isNotEmpty) {
      throw const ContactFailure(
        'Restore into a fresh wallet account before creating contacts or private delivery connections. Existing contact data will not be overwritten.',
      );
    }
    await SecureContactIntroductionRepository(
      store: store,
    ).saveBook(scope, book);
    check();
  }
}
