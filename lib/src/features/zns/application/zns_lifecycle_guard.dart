import 'dart:convert';
import '../../../core/storage/app_secure_store.dart';

/// This guard is independent of providers so wallet deletion can consult it
/// before changing account state or erasing the encrypted journal.
class ZnsLifecycleGuard {
  static final active = <String, bool Function()>{};
  static Future<void> check(String uuid, {bool fullReset = false}) async {
    if (active[uuid]?.call() == true) {
      throw StateError('Pause ZNS registration before removing this account.');
    }
    // Full wallet reset already requires the host's destructive confirmation,
    // including its lost-password recovery flow. A dormant journal must not
    // make that recovery path impossible. Live signing is always blocked above.
    if (fullReset) return;
    final storage = AppSecureStore.instance;
    final raw = await storage.readString('zns:account:$uuid');
    if (raw != null) {
      for (final key in (jsonDecode(raw) as List).cast<String>()) {
        final record = await storage.readString(key);
        if (record != null &&
            record != 'null' &&
            (jsonDecode(record) as Map)['completedAt'] == null) {
          throw StateError(
            'This account has an unfinished ZNS operation. Open Names and resolve or archive it before removal.',
          );
        }
      }
    }
    // Names and Base balances recover from the same seed/passphrase/index.
    // Residual gas must not permanently prohibit deliberate account removal.
  }
}
