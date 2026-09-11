import '../../../core/storage/app_secure_store.dart';
import '../domain/contact_delivery.dart';
import '../domain/contact_models.dart';

abstract class ContactDeliveryRepository {
  Future<ContactDeliveryJournal> load(ContactScope scope);
  Future<void> save(ContactScope scope, ContactDeliveryJournal journal);
}

/// Uses the existing encrypted, account-prefixed store, including its account
/// deletion and password rotation paths. This is local persistence, not backup.
class SecureContactDeliveryRepository implements ContactDeliveryRepository {
  SecureContactDeliveryRepository({AppSecureStore? store})
    : _store = store ?? AppSecureStore.instance;
  final AppSecureStore _store;
  String _key(ContactScope scope) => '${scope.storagePrefix}delivery';

  @override
  Future<ContactDeliveryJournal> load(ContactScope scope) async {
    final raw = await _store.readSecretStringWithOptions(
      _key(scope),
      requireUnlockedSession: true,
      rejectInvalidEnvelope: true,
    );
    if (raw == null) return ContactDeliveryJournal();
    try {
      return ContactDeliveryJournal.decode(raw, scope);
    } catch (_) {
      throw const ContactFailure(
        'Saved contact deliveries could not be read. No packets were sent.',
      );
    }
  }

  @override
  Future<void> save(ContactScope scope, ContactDeliveryJournal journal) async {
    final raw = journal.encode(scope);
    ContactDeliveryJournal.decode(raw, scope);
    await _store.writeSecretString(_key(scope), raw);
  }
}
