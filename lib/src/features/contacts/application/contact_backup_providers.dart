import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../rust/api/contact_backup.dart' as rust;
import '../data/contact_backup_store.dart';
import '../domain/contact_models.dart';
import 'contact_backup_coordinator.dart';
import 'contact_exchange_controller.dart';
import 'contact_lifecycle.dart';

final contactBackupCoordinatorProvider = Provider.autoDispose((ref) {
  final coordinator = ContactBackupCoordinator(
    scope: () => ref.read(contactScopeProvider),
    store: SecureContactBackupStore(),
    crypto: _WalletBackupCrypto(ref),
  );
  ref.listen(contactScopeProvider, (_, _) => coordinator.invalidate());
  ContactLifecycle.listeners.add(coordinator.invalidate);
  final lifecycle = AppLifecycleListener(
    onHide: coordinator.invalidate,
    onPause: coordinator.invalidate,
  );
  ref.onDispose(() {
    coordinator.invalidate();
    ContactLifecycle.listeners.remove(coordinator.invalidate);
    lifecycle.dispose();
  });
  return coordinator;
});

class _WalletBackupCrypto implements ContactBackupCrypto {
  _WalletBackupCrypto(this.ref);
  final Ref ref;
  void check(ContactScope scope) {
    if (ref.read(contactScopeProvider) != scope) {
      throw const ContactFailure('Unlock the selected software account.');
    }
  }

  Future<T> use<T>(
    ContactScope scope,
    Future<T> Function(String, Uint8List) action,
  ) async {
    check(scope);
    final db = await getWalletDbPath();
    check(scope);
    final secret = await ref
        .read(accountProvider.notifier)
        .getMnemonicBytesForAccount(scope.accountUuid);
    try {
      check(scope);
      if (secret == null || secret.isEmpty) {
        throw const ContactFailure(
          'Software recovery is unavailable for this account.',
        );
      }
      return await action(db, secret);
    } finally {
      secret?.fillRange(0, secret.length, 0);
    }
  }

  @override
  Future<String> encrypt(ContactScope scope, Uint8List plain) => use(
    scope,
    (db, secret) => rust.contactBackupEncrypt(
      dbPath: db,
      network: scope.network,
      accountUuid: scope.accountUuid,
      secretBytes: secret,
      plainBytes: plain,
    ),
  );
  @override
  Future<Uint8List> decrypt(ContactScope scope, String archive) => use(
    scope,
    (db, secret) => rust.contactBackupDecrypt(
      dbPath: db,
      network: scope.network,
      accountUuid: scope.accountUuid,
      secretBytes: secret,
      archive: archive,
    ),
  );
}
