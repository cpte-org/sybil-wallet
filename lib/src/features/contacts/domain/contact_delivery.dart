import 'dart:convert';

import 'contact_models.dart';
import 'contact_connection_binding.dart';

const contactDeliveryMaxPacketBytes = 16384;
const contactDeliveryMaxRecords = 100;
const contactDeliveryMaxJournalBytes = 4 * 1024 * 1024;

/// Delivery states are deliberately not contact trust or user consent states.
enum ContactDeliveryState { queued, submitted, received, dismissed }

class ContactDelivery {
  const ContactDelivery({
    required this.id,
    required this.peer,
    required this.packet,
    required this.state,
    this.binding,
  });
  final String id, peer, packet;
  final ContactDeliveryState state;
  final ContactConnectionBinding? binding;
  bool get incoming =>
      state == ContactDeliveryState.received ||
      state == ContactDeliveryState.dismissed;

  ContactDelivery withState(ContactDeliveryState value) => ContactDelivery(
    id: id,
    peer: peer,
    packet: packet,
    state: value,
    binding: binding,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'peer': peer,
    'packet': packet,
    'state': state.name,
    if (binding != null) 'binding': binding!.toJson(),
  };

  static ContactDelivery decode(Object? value) {
    final map = contactObject(value, {
      'id',
      'peer',
      'packet',
      'state',
      if (value is Map && value.containsKey('binding')) 'binding',
    });
    final binding = map.containsKey('binding')
        ? ContactConnectionBinding.decode(map['binding'])
        : null;
    if (binding != null &&
        (binding.peer != map['peer'] ||
            map['state'] == 'received' ||
            map['state'] == 'dismissed')) {
      throw const ContactFailure('Invalid bound delivery.');
    }
    final state = ContactDeliveryState.values
        .where((v) => v.name == map['state'])
        .firstOrNull;
    if (state == null) throw const ContactFailure('Invalid delivery state.');
    return ContactDelivery(
      id: deliveryToken(map['id']),
      peer: deliveryPeer(map['peer']),
      packet: deliveryPacket(map['packet']),
      state: state,
      binding: binding,
    );
  }
}

String deliveryToken(Object? value) {
  final text = contactText(value, max: 64);
  if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(text)) {
    throw const ContactFailure('Invalid delivery identifier.');
  }
  return text;
}

String deliveryPeer(Object? value) {
  final peer = contactText(value, max: 128);
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(peer)) {
    throw const ContactFailure('Invalid delivery connection.');
  }
  return peer;
}

String deliveryPacket(Object? value) {
  final packet = contactText(value, max: contactDeliveryMaxPacketBytes);
  if (utf8.encode(packet).length > contactDeliveryMaxPacketBytes) {
    throw const ContactFailure('This contact packet is too large.');
  }
  // Transport only. Signature, audience, freshness and acceptance stay in the
  // existing contact gateways/coordinators and must run again at review time.
  return packet;
}

class ContactDeliveryJournal {
  ContactDeliveryJournal([Iterable<ContactDelivery> records = const []])
    : records = List.unmodifiable(records);
  final List<ContactDelivery> records;

  String encode(ContactScope scope) {
    if (records.length > contactDeliveryMaxRecords) {
      throw const ContactFailure('The contact delivery inbox is full.');
    }
    final raw = jsonEncode({
      'domain': 'zcash-contact/delivery-journal',
      'account': scope.accountUuid,
      'network': scope.network,
      'records': records.map((r) => r.toJson()).toList(),
    });
    if (utf8.encode(raw).length > contactDeliveryMaxJournalBytes) {
      throw const ContactFailure('Contact delivery storage is full.');
    }
    return raw;
  }

  static ContactDeliveryJournal decode(String raw, ContactScope scope) {
    if (raw.length > contactDeliveryMaxJournalBytes ||
        utf8.encode(raw).length > contactDeliveryMaxJournalBytes) {
      throw const ContactFailure('Contact delivery storage is too large.');
    }
    final map = contactObject(jsonDecode(raw), {
      'domain',
      'account',
      'network',
      'records',
    });
    if (map['domain'] != 'zcash-contact/delivery-journal' ||
        map['account'] != scope.accountUuid ||
        map['network'] != scope.network ||
        map['records'] is! List ||
        (map['records'] as List).length > contactDeliveryMaxRecords) {
      throw const ContactFailure(
        'Contact delivery storage has the wrong scope.',
      );
    }
    final records = (map['records'] as List)
        .map(ContactDelivery.decode)
        .toList();
    final keys = <String>{};
    for (final r in records) {
      if (!keys.add('${r.incoming}:${r.peer}:${r.id}')) {
        throw const ContactFailure('Duplicate saved contact delivery.');
      }
    }
    return ContactDeliveryJournal(records);
  }
}
