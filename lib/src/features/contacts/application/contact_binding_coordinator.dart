import 'dart:convert';
import '../data/contact_binding_repository.dart';
import '../data/contact_repository.dart';
import '../domain/contact_connection_binding.dart';
import '../domain/contact_models.dart';
import 'contact_delivery_coordinator.dart';
import 'contact_mutation_gate.dart';

class ContactBindingReview {
  ContactBindingReview._(this.scope, this.contact, this.binding);
  final ContactScope scope;
  final VerifiedContact contact;
  final ContactConnectionBinding binding;
}

class ContactBindingCoordinator {
  ContactBindingCoordinator({
    required this.scope,
    required this.repository,
    required this.contacts,
  });
  final ContactScope? Function() scope;
  final ContactBindingRepository repository;
  final ContactRepository contacts;
  int _epoch = 0;
  ContactBindingReview? _review;
  void invalidate() {
    _epoch++;
    _review = null;
  }

  void _check(ContactScope expected, int epoch) {
    if (scope() != expected || epoch != _epoch) {
      throw const ContactFailure(
        'Connection verification was interrupted. Review again.',
      );
    }
  }

  Future<T> _run<T>(Future<T> Function(ContactScope, int) work) {
    final current = scope(), epoch = _epoch;
    if (current == null) {
      throw const ContactFailure(
        'Unlock a supported account to verify connections.',
      );
    }
    return ContactMutationGate.run(current, () async {
      _check(current, epoch);
      return work(current, epoch);
    });
  }

  Future<VerifiedContact> _contact(
    ContactScope current,
    int epoch,
    String id,
  ) async {
    final all = await contacts.load(current);
    _check(current, epoch);
    final c = all.where((c) => c.id == id && c.canPay).firstOrNull;
    if (c == null) {
      throw const ContactFailure('This contact is no longer accepted.');
    }
    return c;
  }

  Future<List<VerifiedContact>> acceptedContacts() =>
      _run((current, epoch) async {
        final result = await contacts.load(current);
        _check(current, epoch);
        return result.where((c) => c.canPay).toList();
      });

  Future<List<ContactConnectionBinding>> savedBindings() =>
      _run((current, epoch) async {
        final all = await repository.load(current);
        _check(current, epoch);
        return all;
      });
  Future<void> forget(String contactId) => _run((current, epoch) async {
    _review = null;
    final all = await repository.load(current);
    _check(current, epoch);
    await repository.save(
      current,
      all.where((b) => b.contactId != contactId).toList(),
    );
    _check(current, epoch);
  });
  Future<ContactBindingReview> prepare(
    String contactId,
    String peer,
    ContactChannelTransport transport,
  ) => _run((current, epoch) async {
    _review = null;
    if (transport.scope != current) {
      throw const ContactFailure('Wrong delivery account.');
    }
    final c = await _contact(current, epoch, contactId);
    final code = await transport.securityCode(peer);
    _check(current, epoch);
    final binding = ContactConnectionBinding.decode(
      ContactConnectionBinding(
        contactId: c.id,
        identity: c.identity,
        peer: peer,
        code: code,
      ).toJson(),
    );
    return _review = ContactBindingReview._(current, c, binding);
  });
  Future<void> confirm(
    ContactBindingReview review,
    ContactChannelTransport transport, {
    required bool independentlyVerified,
  }) => _run((current, epoch) async {
    if (!independentlyVerified ||
        !identical(_review, review) ||
        review.scope != current ||
        transport.scope != current) {
      throw const ContactFailure(
        'Independently compare the connection code with this contact before confirming.',
      );
    }
    final c = await _contact(current, epoch, review.contact.id);
    final code = await transport.securityCode(review.binding.peer);
    _check(current, epoch);
    if (jsonEncode(c.toJson()) != jsonEncode(review.contact.toJson()) ||
        code != review.binding.code) {
      throw const ContactFailure(
        'The contact or connection changed during verification.',
      );
    }
    final all = await repository.load(current);
    _check(current, epoch);
    if (all.any(
      (b) =>
          b.contactId != c.id &&
          (b.peer == review.binding.peer || b.identity == c.identity),
    )) {
      throw const ContactFailure(
        'This connection is already assigned to another contact.',
      );
    }
    await repository.save(current, [
      ...all.where((b) => b.contactId != c.id),
      review.binding,
    ]);
    _check(current, epoch);
    _review = null;
  });
  Future<ContactConnectionBinding?> resolve(
    String contactId,
    ContactChannelTransport transport, {
    String? expectedIdentity,
  }) => _run((current, epoch) async {
    final all = await repository.load(current);
    _check(current, epoch);
    final binding = all.where((b) => b.contactId == contactId).firstOrNull;
    if (binding != null &&
        expectedIdentity != null &&
        binding.identity != expectedIdentity) {
      throw const ContactFailure(
        'The intended recipient identity changed. Create a new review before sending.',
      );
    }
    if (binding != null) await checkForSend(current, binding, transport);
    _check(current, epoch);
    return binding;
  });

  /// Called while the delivery coordinator already holds ContactMutationGate.
  /// Do not acquire the same gate recursively. Check again on every retry.
  Future<void> checkForSend(
    ContactScope current,
    ContactConnectionBinding binding,
    ContactChannelTransport transport,
  ) async {
    final epoch = _epoch;
    _check(current, epoch);
    if (transport.scope != current) {
      throw const ContactFailure('Wrong delivery account.');
    }
    final c = await _contact(current, epoch, binding.contactId);
    final all = await repository.load(current);
    _check(current, epoch);
    if (c.identity != binding.identity ||
        !all.any(
          (b) => jsonEncode(b.toJson()) == jsonEncode(binding.toJson()),
        )) {
      throw const ContactFailure(
        'This verified connection changed or was removed. Review the contact connection again.',
      );
    }
    final code = await transport.securityCode(binding.peer);
    _check(current, epoch);
    if (code != binding.code) {
      throw const ContactFailure(
        'The connection security code changed. Independently verify the new code before sending.',
      );
    }
  }
}
