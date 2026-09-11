import 'dart:convert';
import 'dart:math';

import '../data/contact_delivery_repository.dart';
import '../domain/contact_delivery.dart';
import '../domain/contact_models.dart';
import '../domain/contact_connection_binding.dart';
import 'contact_lifecycle.dart';
import 'contact_mutation_gate.dart';

/// A session must be bound to one scope and a network privacy policy before it
/// reaches this boundary. Local peer IDs are routing handles, never identities.
abstract class ContactPacketTransport {
  ContactScope get scope;
  Future<void> submit(String peer, String deliveryId, String packet);
}

abstract class ContactChannelTransport {
  ContactScope get scope;
  Future<String> securityCode(String peer);
}

/// Durable at-least-once delivery. A retry preserves its ID and exact bytes.
/// Receiving a packet never calls a signing or contact-acceptance operation.
class ContactDeliveryCoordinator {
  ContactDeliveryCoordinator({
    required this.scope,
    required this.repository,
    this.validateBinding,
  });
  final ContactScope? Function() scope;
  final ContactDeliveryRepository repository;
  final Future<void> Function(
    ContactScope,
    ContactConnectionBinding,
    ContactChannelTransport,
  )?
  validateBinding;
  int _epoch = 0;

  /// Call synchronously on lock, account/network change, background or disposal.
  void invalidate() => _epoch++;

  void _check(ContactScope expected, int epoch) {
    if (scope() != expected ||
        epoch != _epoch ||
        !ContactLifecycle.allowed(expected.accountUuid)) {
      throw const ContactFailure(
        'Contact delivery is paused. Unlock and retry.',
      );
    }
  }

  Future<T> _run<T>(
    Future<T> Function(
      ContactScope current,
      int epoch,
      ContactDeliveryJournal journal,
    )
    action,
  ) async {
    final current = scope(), epoch = _epoch;
    if (current == null) {
      throw const ContactFailure('Unlock an account to use contact delivery.');
    }
    return ContactMutationGate.run(current, () async {
      _check(current, epoch);
      final journal = await repository.load(current);
      _check(current, epoch);
      return action(current, epoch, journal);
    });
  }

  Future<void> _save(
    ContactScope current,
    int epoch,
    ContactDeliveryJournal journal,
  ) async {
    _check(current, epoch);
    await repository.save(current, journal);
    _check(current, epoch);
  }

  Future<List<ContactDelivery>> overview() =>
      _run((current, epoch, journal) async => journal.records);

  /// Caller has already obtained approval to send these exact bytes to this
  /// connection. Persistence completes before any network action can occur.
  Future<String> enqueue(
    String peer,
    String packet, {
    ContactConnectionBinding? binding,
  }) => _run((current, epoch, journal) async {
    final id = base64Url
        .encode(List.generate(24, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
    final record = ContactDelivery(
      id: id,
      peer: deliveryPeer(peer),
      packet: deliveryPacket(packet),
      state: ContactDeliveryState.queued,
      binding: binding,
    );
    await _save(
      current,
      epoch,
      ContactDeliveryJournal([...journal.records, record]),
    );
    return id;
  });

  /// One explicitly approved attempt. Transport acceptance is not receipt or
  /// contact acceptance. An ambiguous failure leaves the record retryable.
  Future<void> submit(String id, ContactPacketTransport transport) =>
      _run((current, epoch, journal) async {
        if (transport.scope != current) {
          throw const ContactFailure(
            'The delivery connection belongs to another account.',
          );
        }
        final record = journal.records
            .where((r) => !r.incoming && r.id == id)
            .firstOrNull;
        if (record == null) {
          throw const ContactFailure('No queued delivery was found.');
        }
        if (record.state == ContactDeliveryState.submitted) return;
        if (record.binding != null) {
          if (record.binding!.peer != record.peer ||
              validateBinding == null ||
              transport is! ContactChannelTransport) {
            throw const ContactFailure(
              'Verified delivery cannot be checked in this session.',
            );
          }
          await validateBinding!(
            current,
            record.binding!,
            transport as ContactChannelTransport,
          );
          _check(current, epoch);
        }
        _check(current, epoch);
        await transport.submit(record.peer, record.id, record.packet);
        _check(current, epoch);
        await _save(
          current,
          epoch,
          ContactDeliveryJournal([
            for (final r in journal.records)
              if (identical(r, record))
                r.withState(ContactDeliveryState.submitted)
              else
                r,
          ]),
        );
      });

  /// The adapter may acknowledge an event only after this returns. While locked
  /// it must retain the event in its durable transport store and retry later.
  Future<bool> receive(
    ContactScope sourceScope,
    String peer,
    String id,
    String packet,
  ) => _run((current, epoch, journal) async {
    if (sourceScope != current) {
      throw const ContactFailure('This packet belongs to another account.');
    }
    deliveryPeer(peer);
    deliveryToken(id);
    deliveryPacket(packet);
    final previous = journal.records
        .where((r) => r.incoming && r.peer == peer && r.id == id)
        .firstOrNull;
    if (previous != null) {
      if (previous.packet != packet) {
        throw const ContactFailure('Conflicting contact delivery.');
      }
      return false;
    }
    await _save(
      current,
      epoch,
      ContactDeliveryJournal([
        ...journal.records,
        ContactDelivery(
          id: id,
          peer: peer,
          packet: packet,
          state: ContactDeliveryState.received,
        ),
      ]),
    );
    return true;
  });

  /// Retain the deduplication record. Do not evict tombstones silently: limits
  /// fail closed until a separately specified replay-window policy exists.
  Future<void> dismiss(String peer, String id) =>
      _run((current, epoch, journal) async {
        await _save(
          current,
          epoch,
          ContactDeliveryJournal([
            for (final r in journal.records)
              if (r.incoming && r.peer == peer && r.id == id)
                r.withState(ContactDeliveryState.dismissed)
              else
                r,
          ]),
        );
      });
}
