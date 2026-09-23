import 'dart:convert';

import '../../../core/storage/app_secure_store.dart';
import '../domain/contact_models.dart';

/// Private presentation preferences. These never grant contact authority and
/// are deliberately separate from the authenticated contact/recovery book.
class SybilPersonMetadata {
  const SybilPersonMetadata({this.notes = '', this.pinned = false});

  final String notes;
  final bool pinned;

  SybilPersonMetadata copyWith({String? notes, bool? pinned}) =>
      SybilPersonMetadata(
        notes: notes ?? this.notes,
        pinned: pinned ?? this.pinned,
      );

  void validate() {
    if (notes.length > 2000 ||
        notes.runes.any(
          (rune) =>
              (rune < 32 && rune != 10) ||
              (rune >= 127 && rune <= 159) ||
              (rune >= 0xd800 && rune <= 0xdfff),
        )) {
      throw const ContactFailure('Use a note of at most 2,000 characters.');
    }
  }

  Map<String, Object> toJson() {
    validate();
    return {'notes': notes, 'pinned': pinned};
  }

  static SybilPersonMetadata decode(Object? value) {
    final map = contactObject(value, {'notes', 'pinned'});
    if (map['notes'] is! String || map['pinned'] is! bool) {
      throw const ContactFailure('Private contact details are unavailable.');
    }
    final metadata = SybilPersonMetadata(
      notes: map['notes'] as String,
      pinned: map['pinned'] as bool,
    );
    metadata.validate();
    return metadata;
  }
}

class SybilPeopleMetadataRepository {
  SybilPeopleMetadataRepository({AppSecureStore? store})
    : _store = store ?? AppSecureStore.instance;

  final AppSecureStore _store;

  // The existing account-deletion path removes all contact-prefixed secrets.
  String _key(ContactScope scope) => '${scope.storagePrefix}people_metadata_v1';

  Future<Map<String, SybilPersonMetadata>> load(ContactScope scope) async {
    final raw = await _store.readSecretStringWithOptions(
      _key(scope),
      requireUnlockedSession: true,
      rejectInvalidEnvelope: true,
    );
    if (raw == null) return const {};
    try {
      if (raw.length > 1500000) throw const FormatException();
      final map = contactObject(jsonDecode(raw), {
        'domain',
        'account',
        'network',
        'people',
      });
      if (map['domain'] != 'zcash-contact/people-metadata-v1' ||
          map['account'] != scope.accountUuid ||
          map['network'] != scope.network ||
          map['people'] is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final people = map['people'] as Map<String, dynamic>;
      if (people.length > 100) throw const FormatException();
      return Map.unmodifiable({
        for (final entry in people.entries)
          contactIdentity(entry.key): SybilPersonMetadata.decode(entry.value),
      });
    } catch (_) {
      throw const ContactFailure('Private notes and pins could not be opened.');
    }
  }

  Future<void> save(
    ContactScope scope,
    Map<String, SybilPersonMetadata> people, {
    required void Function() beforeWrite,
  }) async {
    if (people.length > 100) {
      throw const ContactFailure('Private details support up to 100 people.');
    }
    final encoded = jsonEncode({
      'domain': 'zcash-contact/people-metadata-v1',
      'account': scope.accountUuid,
      'network': scope.network,
      'people': {
        for (final entry in people.entries)
          contactIdentity(entry.key): entry.value.toJson(),
      },
    });
    beforeWrite();
    await _store.writeSecretString(_key(scope), encoded);
  }
}
