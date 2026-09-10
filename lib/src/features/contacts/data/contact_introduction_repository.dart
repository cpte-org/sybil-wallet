import 'dart:convert';

import '../../../core/storage/app_secure_store.dart';
import '../domain/contact_introduction_models.dart';
import '../domain/contact_models.dart';

/// Raw whole-book operations. Callers must serialize read/modify/write with the
/// shared contact mutation gate and check scope/lifecycle before publishing.
abstract class ContactIntroductionRepository {
  Future<ContactBook> loadBook(ContactScope scope);
  Future<void> saveBook(ContactScope scope, ContactBook book);
}

class SecureContactIntroductionRepository
    implements ContactIntroductionRepository {
  SecureContactIntroductionRepository({AppSecureStore? store})
    : _store = store ?? AppSecureStore.instance;

  final AppSecureStore _store;

  @override
  Future<ContactBook> loadBook(ContactScope scope) async {
    final raw = await _store.readSecretStringWithOptions(
      '${scope.storagePrefix}book',
      requireUnlockedSession: true,
      rejectInvalidEnvelope: true,
    );
    if (raw == null) return ContactBook();
    try {
      _checkSize(raw);
      return ContactBook.decode(jsonDecode(raw), scope);
    } catch (_) {
      throw const ContactFailure(
        'Saved contact data could not be verified. Contact payments are blocked.',
      );
    }
  }

  @override
  Future<void> saveBook(ContactScope scope, ContactBook book) async {
    if ([
      book.contacts.length,
      book.associations.length,
      book.sessions.length,
      book.signers.length,
      book.provenance.length,
    ].any((count) => count > contactBookMaxRecords)) {
      throw const ContactFailure(
        'This experiment supports up to 100 records of each contact data type.',
      );
    }
    final raw = jsonEncode(book.toJson(scope));
    _checkSize(raw);
    // Validate programmatically built records before writing anything. Clear
    // the validation copy; ownership of the caller's secret bytes is unchanged.
    final checked = ContactBook.decode(jsonDecode(raw), scope);
    checked.clearSecrets();
    await _store.writeSecretString('${scope.storagePrefix}book', raw);
  }
}

void _checkSize(String raw) {
  if (raw.length > contactBookMaxBytes ||
      utf8.encode(raw).length > contactBookMaxBytes) {
    throw const ContactFailure('Saved contact data exceeds the storage limit.');
  }
}
