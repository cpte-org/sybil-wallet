import 'dart:convert';
import '../../../core/storage/app_secure_store.dart';
import '../domain/contact_connection_binding.dart';
import '../domain/contact_models.dart';

abstract class ContactBindingRepository {
  Future<List<ContactConnectionBinding>> load(ContactScope scope);
  Future<void> save(
    ContactScope scope,
    List<ContactConnectionBinding> bindings,
  );
}

class SecureContactBindingRepository implements ContactBindingRepository {
  SecureContactBindingRepository({AppSecureStore? store})
    : _store = store ?? AppSecureStore.instance;
  final AppSecureStore _store;
  String _key(ContactScope scope) => '${scope.storagePrefix}connections';
  @override
  Future<List<ContactConnectionBinding>> load(ContactScope scope) async {
    final raw = await _store.readSecretStringWithOptions(
      _key(scope),
      requireUnlockedSession: true,
      rejectInvalidEnvelope: true,
    );
    if (raw == null) return [];
    if (raw.length > 100000) {
      throw const ContactFailure('Connection bindings are too large.');
    }
    final m = contactObject(jsonDecode(raw), {
      'domain',
      'account',
      'network',
      'bindings',
    });
    if (m['domain'] != 'zcash-contact/connections' ||
        m['account'] != scope.accountUuid ||
        m['network'] != scope.network ||
        m['bindings'] is! List) {
      throw const ContactFailure('Connection bindings have the wrong scope.');
    }
    final bindings = (m['bindings'] as List)
        .map(ContactConnectionBinding.decode)
        .toList();
    _validate(bindings);
    return bindings;
  }

  void _validate(List<ContactConnectionBinding> bindings) {
    if (bindings.length > 100 ||
        bindings.map((b) => b.contactId).toSet().length != bindings.length ||
        bindings.map((b) => b.peer).toSet().length != bindings.length ||
        bindings.map((b) => b.identity).toSet().length != bindings.length) {
      throw const ContactFailure(
        'Conflicting or excessive connection bindings.',
      );
    }
    for (final b in bindings) {
      ContactConnectionBinding.decode(b.toJson());
    }
  }

  @override
  Future<void> save(
    ContactScope scope,
    List<ContactConnectionBinding> bindings,
  ) async {
    _validate(bindings);
    await _store.writeSecretString(
      _key(scope),
      jsonEncode({
        'domain': 'zcash-contact/connections',
        'account': scope.accountUuid,
        'network': scope.network,
        'bindings': bindings.map((b) => b.toJson()).toList(),
      }),
    );
  }
}
