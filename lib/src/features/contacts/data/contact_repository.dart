import 'dart:convert';
import 'dart:typed_data';
import '../../../core/storage/app_secure_store.dart';
import '../domain/contact_models.dart';
import '../domain/contact_introduction_models.dart';
import 'contact_introduction_repository.dart';

class ContactSigner {
  ContactSigner({
    required this.identity,
    required this.secret,
    required this.address,
    required this.sequence,
  });
  final String identity, address;
  final Uint8List secret;
  final int sequence;
  void clear() => secret.fillRange(0, secret.length, 0);
}

abstract class ContactRepository {
  Future<List<VerifiedContact>> load(ContactScope scope);
  Future<void> save(ContactScope scope, List<VerifiedContact> contacts);
  Future<ContactSigner?> loadSigner(ContactScope scope, String identity);
  Future<void> saveSigner(
    ContactScope scope,
    ContactSigner signer, {
    void Function()? beforeWrite,
  });
}

class SecureContactRepository implements ContactRepository {
  SecureContactRepository({AppSecureStore? store})
    : _store = store ?? AppSecureStore.instance;
  final AppSecureStore _store;
  SecureContactIntroductionRepository get _books =>
      SecureContactIntroductionRepository(store: _store);

  @override
  Future<List<VerifiedContact>> load(ContactScope scope) async {
    final book = await _books.loadBook(scope);
    try {
      return book.contacts;
    } finally {
      book.clearSecrets();
    }
  }

  @override
  Future<void> save(ContactScope scope, List<VerifiedContact> contacts) async {
    if (contacts.length > 100) {
      throw const ContactFailure(
        'This experiment supports up to 100 contacts.',
      );
    }
    // Caller holds ContactMutationGate across read/compare/write. Preserve all
    // introduction records when a direct contact is accepted or suspended.
    final book = await _books.loadBook(scope);
    try {
      await _books.saveBook(scope, book.copyWith(contacts: contacts));
    } finally {
      book.clearSecrets();
    }
  }

  String _signerKey(ContactScope scope, String identity) =>
      '${scope.storagePrefix}signer_${contactIdentity(identity).substring(8)}';

  @override
  Future<ContactSigner?> loadSigner(ContactScope scope, String identity) async {
    final book = await _books.loadBook(scope);
    try {
      if (book.quarantinedSigners.any((s) => s.identity == identity)) {
        throw const ContactFailure(
          'This restored relationship key stays inactive. Ask the other person for a new contact request and independently check your new receiving details.',
        );
      }
      final stored = book.signers
          .where((s) => s.identity == identity)
          .firstOrNull;
      if (stored != null) {
        return ContactSigner(
          identity: stored.identity,
          secret: Uint8List.fromList(stored.secret),
          address: stored.address,
          sequence: stored.sequence,
        );
      }
    } finally {
      book.clearSecrets();
    }
    final raw = await _store.readSecretStringWithOptions(
      _signerKey(scope, identity),
      requireUnlockedSession: true,
      rejectInvalidEnvelope: true,
    );
    if (raw == null) return null;
    Uint8List? secret;
    try {
      if (raw.length > 4096) throw const FormatException();
      final map = contactObject(jsonDecode(raw), {
        'domain',
        'account',
        'network',
        'identity',
        'address',
        'sequence',
        'secret',
      });
      if (map['domain'] != 'zcash-contact/signer' ||
          map['account'] != scope.accountUuid ||
          map['network'] != scope.network ||
          map['identity'] != identity ||
          map['secret'] is! String) {
        throw const FormatException();
      }
      secret = base64Decode(map['secret'] as String);
      if (secret.length != 32 || base64Encode(secret) != map['secret']) {
        throw const FormatException();
      }
      return ContactSigner(
        identity: identity,
        secret: secret,
        address: contactText(map['address'], max: 512),
        sequence: contactInteger(map['sequence']),
      );
    } catch (_) {
      secret?.fillRange(0, secret.length, 0);
      throw const ContactFailure(
        'This contact signing record is unavailable. A new independently checked contact is required.',
      );
    }
  }

  @override
  Future<void> saveSigner(
    ContactScope scope,
    ContactSigner signer, {
    void Function()? beforeWrite,
  }) async {
    // Snapshot before the first await: cancellation can clear the controller's
    // original mutable buffer while a book read is pending.
    final secret = Uint8List.fromList(signer.secret);
    try {
      final book = await _books.loadBook(scope);
      try {
        beforeWrite?.call();
        if (book.quarantinedSigners.any((s) => s.identity == signer.identity)) {
          throw const ContactFailure(
            'A restored relationship key cannot overwrite active signing state.',
          );
        }
        final existing = book.signers
            .where((s) => s.identity == signer.identity)
            .firstOrNull;
        if (existing != null) {
          if (signer.sequence < existing.sequence ||
              (signer.sequence == existing.sequence &&
                  signer.address != existing.address)) {
            throw const ContactFailure(
              'This signing record changed. Start a fresh address update.',
            );
          }
          final next = IntroductionStoredSigner(
            identity: signer.identity,
            secret: Uint8List.fromList(secret),
            address: signer.address,
            sequence: signer.sequence,
          );
          try {
            await _books.saveBook(
              scope,
              book.copyWith(
                signers: [
                  for (final stored in book.signers)
                    if (stored.identity != signer.identity) stored,
                  next,
                ],
              ),
            );
          } finally {
            next.clear();
          }
          return;
        }
      } finally {
        book.clearSecrets();
      }
      beforeWrite?.call();
      await _store.writeSecretString(
        _signerKey(scope, signer.identity),
        jsonEncode({
          'domain': 'zcash-contact/signer',
          'account': scope.accountUuid,
          'network': scope.network,
          'identity': signer.identity,
          'address': signer.address,
          'sequence': signer.sequence,
          'secret': base64Encode(secret),
        }),
      );
    } finally {
      secret.fillRange(0, secret.length, 0);
    }
  }
}
