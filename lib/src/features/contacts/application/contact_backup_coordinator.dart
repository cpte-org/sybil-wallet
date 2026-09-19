import 'dart:convert';
import 'dart:typed_data';
import '../data/contact_backup_store.dart';
import '../domain/contact_introduction_models.dart';
import '../domain/contact_models.dart';
import 'contact_mutation_gate.dart';

abstract class ContactBackupCrypto {
  Future<String> encrypt(ContactScope scope, Uint8List plain);
  Future<Uint8List> decrypt(ContactScope scope, String archive);
}

class ContactBackupReview {
  ContactBackupReview._(this.scope, this.book, this.createdAt);
  final ContactScope scope;
  final ContactBook book;
  final DateTime createdAt;
  int get contactCount => book.contacts.length;
  int get keyCount => book.quarantinedSigners.length;
}

/// Public recovery progress only. Never exposes restored signing material.
class ContactRecoveryProgress {
  ContactRecoveryProgress({
    required List<VerifiedContact> contacts,
    required this.inactiveKeyCount,
  }) : pendingContacts = List.unmodifiable(
         contacts.where(
           (contact) => contact.status == ContactTrustStatus.restored,
         ),
       );
  final List<VerifiedContact> pendingContacts;
  final int inactiveKeyCount;
}

class ContactBackupCoordinator {
  ContactBackupCoordinator({
    required this.scope,
    required this.store,
    required this.crypto,
  });
  final ContactScope? Function() scope;
  final ContactBackupStore store;
  final ContactBackupCrypto crypto;
  int _epoch = 0;
  ContactBackupReview? _review;
  void invalidate() {
    _epoch++;
    _review?.book.clearSecrets();
    _review = null;
  }

  void _check(ContactScope current, int epoch) {
    if (scope() != current || _epoch != epoch) {
      throw const ContactFailure(
        'Backup operation interrupted. Unlock and review again.',
      );
    }
  }

  Future<T> _run<T>(
    Future<T> Function(ContactScope, int) work, {
    bool mutation = false,
  }) {
    final current = scope(), epoch = _epoch;
    if (current == null) {
      throw const ContactFailure('Unlock a software account first.');
    }
    return ContactMutationGate.run(current, () async {
      _check(current, epoch);
      return work(current, epoch);
    }, mutation: mutation);
  }

  Future<ContactRecoveryProgress> recoveryProgress() =>
      _run((current, epoch) async {
        final book = await store.snapshot(current);
        try {
          _check(current, epoch);
          return ContactRecoveryProgress(
            contacts: book.contacts,
            inactiveKeyCount: book.quarantinedSigners.length,
          );
        } finally {
          book.clearSecrets();
        }
      });

  Future<String> export() => _run((current, epoch) async {
    final book = await store.snapshot(current);
    Uint8List? bytes;
    try {
      _check(current, epoch);
      if (book.signers.length + book.quarantinedSigners.length >
          contactBookMaxRecords) {
        throw const ContactFailure(
          'Too many relationship keys for this portable backup.',
        );
      }
      bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'domain': 'zcash-contact/portable-snapshot',
            'createdAt': DateTime.now().toUtc().millisecondsSinceEpoch,
            'book': book.toJson(current),
          }),
        ),
      );
      if (bytes.length > contactBookMaxBytes) {
        throw const ContactFailure('Contact backup is too large.');
      }
      final archive = await crypto.encrypt(current, bytes);
      _check(current, epoch);
      return archive;
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      book.clearSecrets();
    }
  });

  Future<ContactBackupReview> prepare(String archive) => _run((
    current,
    epoch,
  ) async {
    _review?.book.clearSecrets();
    _review = null;
    if (archive.length > contactBookMaxBytes * 2) {
      throw const ContactFailure('Contact backup is too large.');
    }
    final plain = await crypto.decrypt(current, archive);
    ContactBook? source;
    try {
      _check(current, epoch);
      if (plain.length > contactBookMaxBytes) {
        throw const ContactFailure('Contact backup is too large.');
      }
      final map = contactObject(jsonDecode(utf8.decode(plain)), {
        'domain',
        'createdAt',
        'book',
      });
      if (map['domain'] != 'zcash-contact/portable-snapshot') {
        throw const ContactFailure('Unsupported contact snapshot.');
      }
      final date = DateTime.fromMillisecondsSinceEpoch(
        contactInteger(map['createdAt']),
        isUtc: true,
      );
      final rawBook = map['book'];
      if (rawBook is! Map<String, dynamic>) {
        throw const ContactFailure('Invalid contact snapshot.');
      }
      final original = ContactScope(
        accountUuid: contactText(rawBook['account'], max: 128),
        network: current.network,
      );
      source = ContactBook.decode(rawBook, original);
      final recovered = source.copyWith(
        contacts: [
          for (final c in source.contacts)
            c.copyWith(
              status: c.status == ContactTrustStatus.accepted
                  ? ContactTrustStatus.restored
                  : c.status,
            ),
        ],
        signers: [],
        quarantinedSigners: [...source.signers, ...source.quarantinedSigners],
        associations: [],
        sessions: [],
      );
      // Transfer ownership of the secret buffers to the pending review.
      source = null;
      return _review = ContactBackupReview._(current, recovered, date);
    } finally {
      plain.fillRange(0, plain.length, 0);
      source?.clearSecrets();
    }
  });
  Future<void> restore(
    ContactBackupReview review, {
    required bool approved,
  }) => _run((current, epoch) async {
    if (!approved || !identical(review, _review) || review.scope != current) {
      throw const ContactFailure(
        'Review this backup and approve restoration first.',
      );
    }
    // Copy before awaiting: lifecycle invalidation clears pending review keys.
    final copy = ContactBook.decode(
      jsonDecode(jsonEncode(review.book.toJson(current))),
      current,
    );
    try {
      await store.restoreEmpty(current, copy, () => _check(current, epoch));
      _check(current, epoch);
      invalidate();
    } finally {
      copy.clearSecrets();
    }
  }, mutation: true);
}
