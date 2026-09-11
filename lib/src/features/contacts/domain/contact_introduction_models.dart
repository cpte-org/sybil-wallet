// Local encrypted introduction state. Wire verification belongs to Rust.
import 'dart:convert';
import 'dart:typed_data';

import 'contact_models.dart';

const contactBookMaxBytes = 1048576;
const contactBookMaxRecords = 100;
const contactIntroductionPacketMaxBytes = 32768;

enum ContactIntroductionRole { requester, introducer, subject }

enum ContactIntroductionPhase { prepared, published, accepted, cancelled }

class ContactPeerAssociation {
  const ContactPeerAssociation({
    required this.incomingContactId,
    required this.incomingIdentity,
    required this.outgoingIdentity,
    required this.independentlyConfirmedAt,
  });

  final String incomingContactId, incomingIdentity, outgoingIdentity;
  final DateTime independentlyConfirmedAt;

  Map<String, Object?> toJson() => {
    'incomingContactId': incomingContactId,
    'incomingIdentity': incomingIdentity,
    'outgoingIdentity': outgoingIdentity,
    'independentlyConfirmedAt': independentlyConfirmedAt.millisecondsSinceEpoch,
  };

  static ContactPeerAssociation decode(Object? value) {
    final map = contactObject(value, {
      'incomingContactId',
      'incomingIdentity',
      'outgoingIdentity',
      'independentlyConfirmedAt',
    });
    return ContactPeerAssociation(
      incomingContactId: _id(map['incomingContactId']),
      incomingIdentity: contactIdentity(map['incomingIdentity']),
      outgoingIdentity: contactIdentity(map['outgoingIdentity']),
      independentlyConfirmedAt: _time(map['independentlyConfirmedAt']),
    );
  }
}

/// A snapshot of independently associated peer keys, never a local label.
class ContactIntroductionPin {
  const ContactIntroductionPin({
    required this.contactId,
    required this.identity,
    required this.outgoingIdentity,
  });

  final String contactId, identity, outgoingIdentity;

  Map<String, Object?> toJson() => {
    'contactId': contactId,
    'identity': identity,
    'outgoingIdentity': outgoingIdentity,
  };

  static ContactIntroductionPin decode(Object? value) {
    final map = contactObject(value, {
      'contactId',
      'identity',
      'outgoingIdentity',
    });
    return ContactIntroductionPin(
      contactId: _id(map['contactId']),
      identity: contactIdentity(map['identity']),
      outgoingIdentity: contactIdentity(map['outgoingIdentity']),
    );
  }
}

/// Exact imported/generated strings are retained for retry and transcript checks.
/// The coordinator enforces role-specific transitions and verifies wire data.
class ContactIntroductionSession {
  ContactIntroductionSession({
    required this.role,
    required this.requestHash,
    required this.requestJson,
    required this.expiresAt,
    required this.phase,
    List<ContactIntroductionPin> pins = const [],
    this.inputPacket,
    this.outputPacket,
    this.consentPacket,
    this.offerJson,
    this.endpointJson,
    this.suggestion,
    this.contactId,
  }) : pins = List.unmodifiable(pins);

  final ContactIntroductionRole role;
  final String requestHash, requestJson;
  final DateTime expiresAt;
  final ContactIntroductionPhase phase;
  final List<ContactIntroductionPin> pins;
  final String? inputPacket,
      outputPacket,
      consentPacket,
      offerJson,
      endpointJson;
  final String? suggestion, contactId;

  String get id => '${role.name}:$requestHash';

  ContactIntroductionSession copyWith({
    ContactIntroductionPhase? phase,
    List<ContactIntroductionPin>? pins,
    String? inputPacket,
    String? outputPacket,
    String? consentPacket,
    String? offerJson,
    String? endpointJson,
    String? suggestion,
    String? contactId,
  }) => ContactIntroductionSession(
    role: role,
    requestHash: requestHash,
    requestJson: requestJson,
    expiresAt: expiresAt,
    phase: phase ?? this.phase,
    pins: pins ?? this.pins,
    inputPacket: inputPacket ?? this.inputPacket,
    outputPacket: outputPacket ?? this.outputPacket,
    consentPacket: consentPacket ?? this.consentPacket,
    offerJson: offerJson ?? this.offerJson,
    endpointJson: endpointJson ?? this.endpointJson,
    suggestion: suggestion ?? this.suggestion,
    contactId: contactId ?? this.contactId,
  );

  Map<String, Object?> toJson() => {
    'role': role.name,
    'requestHash': requestHash,
    'requestJson': requestJson,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    'phase': phase.name,
    'pins': [for (final pin in pins) pin.toJson()],
    if (inputPacket != null) 'inputPacket': inputPacket,
    if (outputPacket != null) 'outputPacket': outputPacket,
    if (consentPacket != null) 'consentPacket': consentPacket,
    if (offerJson != null) 'offerJson': offerJson,
    if (endpointJson != null) 'endpointJson': endpointJson,
    if (suggestion != null) 'suggestion': suggestion,
    if (contactId != null) 'contactId': contactId,
  };

  static ContactIntroductionSession decode(Object? value) {
    final map = _object(
      value,
      {'role', 'requestHash', 'requestJson', 'expiresAt', 'phase', 'pins'},
      {
        'inputPacket',
        'outputPacket',
        'consentPacket',
        'offerJson',
        'endpointJson',
        'suggestion',
        'contactId',
      },
    );
    final role = ContactIntroductionRole.values
        .where((role) => role.name == map['role'])
        .firstOrNull;
    final phase = ContactIntroductionPhase.values
        .where((phase) => phase.name == map['phase'])
        .firstOrNull;
    if (role == null || phase == null) throw const FormatException();
    final pins = _records(map['pins'], ContactIntroductionPin.decode, max: 2);
    _unique(pins.map((pin) => pin.contactId));
    _unique(pins.map((pin) => pin.identity));
    _unique(pins.map((pin) => pin.outgoingIdentity));
    return ContactIntroductionSession(
      role: role,
      requestHash: _hash(map['requestHash']),
      requestJson: _packet(map['requestJson']),
      expiresAt: _time(map['expiresAt']),
      phase: phase,
      pins: pins,
      inputPacket: _optional(map, 'inputPacket', _packet),
      outputPacket: _optional(map, 'outputPacket', _packet),
      consentPacket: _optional(map, 'consentPacket', _packet),
      offerJson: _optional(map, 'offerJson', _packet),
      endpointJson: _optional(map, 'endpointJson', _packet),
      suggestion: _optional(map, 'suggestion', _suggestion),
      contactId: _optional(map, 'contactId', _id),
    );
  }
}

class ContactIntroductionProvenance {
  const ContactIntroductionProvenance({
    required this.introducedContactId,
    required this.introducerContactId,
    required this.introducerIdentity,
    required this.requestHash,
    required this.endpointHash,
    required this.attestationHash,
    required this.acceptedAt,
    this.suggestion,
  });

  final String introducedContactId, introducerContactId, introducerIdentity;
  final String requestHash, endpointHash, attestationHash;
  final DateTime acceptedAt;
  final String? suggestion;

  Map<String, Object?> toJson() => {
    'introducedContactId': introducedContactId,
    'introducerContactId': introducerContactId,
    'introducerIdentity': introducerIdentity,
    'requestHash': requestHash,
    'endpointHash': endpointHash,
    'attestationHash': attestationHash,
    'acceptedAt': acceptedAt.millisecondsSinceEpoch,
    if (suggestion != null) 'suggestion': suggestion,
  };

  static ContactIntroductionProvenance decode(Object? value) {
    final map = _object(
      value,
      {
        'introducedContactId',
        'introducerContactId',
        'introducerIdentity',
        'requestHash',
        'endpointHash',
        'attestationHash',
        'acceptedAt',
      },
      {'suggestion'},
    );
    return ContactIntroductionProvenance(
      introducedContactId: _id(map['introducedContactId']),
      introducerContactId: _id(map['introducerContactId']),
      introducerIdentity: contactIdentity(map['introducerIdentity']),
      requestHash: _hash(map['requestHash']),
      endpointHash: _hash(map['endpointHash']),
      attestationHash: _hash(map['attestationHash']),
      acceptedAt: _time(map['acceptedAt']),
      suggestion: _optional(map, 'suggestion', _suggestion),
    );
  }
}

/// Secret bytes are deliberately mutable so their owner can clear them.
/// This is not a spending key. A copied book shares signer objects with its
/// source; callers must finish using both books before clearing their secrets.
class IntroductionStoredSigner {
  IntroductionStoredSigner({
    required this.identity,
    required this.secret,
    required this.address,
    required this.sequence,
  });

  final String identity, address;
  final Uint8List secret;
  final int sequence;

  void clear() => secret.fillRange(0, secret.length, 0);

  Map<String, Object?> toJson() => {
    'identity': identity,
    'address': address,
    'sequence': sequence,
    'secret': base64Encode(secret),
  };

  static IntroductionStoredSigner decode(Object? value) {
    final map = contactObject(value, {
      'identity',
      'address',
      'sequence',
      'secret',
    });
    Uint8List? secret;
    try {
      final encoded = contactText(map['secret'], max: 44);
      secret = base64Decode(encoded);
      if (secret.length != 32 || base64Encode(secret) != encoded) {
        throw const FormatException();
      }
      final address = contactText(map['address'], max: 512);
      if (address.trim() != address) throw const FormatException();
      return IntroductionStoredSigner(
        identity: contactIdentity(map['identity']),
        secret: secret,
        address: address,
        sequence: contactInteger(map['sequence']),
      );
    } catch (_) {
      secret?.fillRange(0, secret.length, 0);
      rethrow;
    }
  }
}

/// A single account/network-scoped plaintext for the existing encrypted book.
/// This aggregate does not provide concurrency control or storage transactions.
class ContactBook {
  ContactBook({
    List<VerifiedContact> contacts = const [],
    List<ContactPeerAssociation> associations = const [],
    List<ContactIntroductionSession> sessions = const [],
    List<IntroductionStoredSigner> signers = const [],
    List<IntroductionStoredSigner> quarantinedSigners = const [],
    List<ContactIntroductionProvenance> provenance = const [],
  }) : contacts = List.unmodifiable(contacts),
       associations = List.unmodifiable(associations),
       sessions = List.unmodifiable(sessions),
       signers = List.unmodifiable(signers),
       quarantinedSigners = List.unmodifiable(quarantinedSigners),
       provenance = List.unmodifiable(provenance);

  final List<VerifiedContact> contacts;
  final List<ContactPeerAssociation> associations;
  final List<ContactIntroductionSession> sessions;
  final List<IntroductionStoredSigner> signers;
  // Restored keys must never enter active signing without state reconciliation.
  final List<IntroductionStoredSigner> quarantinedSigners;
  final List<ContactIntroductionProvenance> provenance;

  ContactBook copyWith({
    List<VerifiedContact>? contacts,
    List<ContactPeerAssociation>? associations,
    List<ContactIntroductionSession>? sessions,
    List<IntroductionStoredSigner>? signers,
    List<IntroductionStoredSigner>? quarantinedSigners,
    List<ContactIntroductionProvenance>? provenance,
  }) => ContactBook(
    contacts: contacts ?? this.contacts,
    associations: associations ?? this.associations,
    sessions: sessions ?? this.sessions,
    signers: signers ?? this.signers,
    quarantinedSigners: quarantinedSigners ?? this.quarantinedSigners,
    provenance: provenance ?? this.provenance,
  );

  void clearSecrets() {
    for (final signer in [...signers, ...quarantinedSigners]) {
      signer.clear();
    }
  }

  Map<String, Object?> toJson(ContactScope scope) => {
    'domain': 'zcash-contact/book',
    'account': scope.accountUuid,
    'network': scope.network,
    'contacts': [for (final contact in contacts) contact.toJson()],
    'associations': [
      for (final association in associations) association.toJson(),
    ],
    'introductionSessions': [for (final session in sessions) session.toJson()],
    'introductionSigners': [for (final signer in signers) signer.toJson()],
    'quarantinedSigners': [
      for (final signer in quarantinedSigners) signer.toJson(),
    ],
    'provenance': [for (final item in provenance) item.toJson()],
  };

  static ContactBook decode(Object? value, ContactScope scope) {
    final decodedSigners = <IntroductionStoredSigner>[];
    final quarantined = <IntroductionStoredSigner>[];
    try {
      final map = _object(
        value,
        {'domain', 'account', 'network', 'contacts'},
        {
          'associations',
          'introductionSessions',
          'introductionSigners',
          'quarantinedSigners',
          'provenance',
        },
      );
      if (map['domain'] != 'zcash-contact/book' ||
          map['account'] != scope.accountUuid ||
          map['network'] != scope.network) {
        throw const FormatException();
      }
      final contacts = _records(map['contacts'], VerifiedContact.decode);
      final associations = map.containsKey('associations')
          ? _records(map['associations'], ContactPeerAssociation.decode)
          : <ContactPeerAssociation>[];
      final sessions = map.containsKey('introductionSessions')
          ? _records(
              map['introductionSessions'],
              ContactIntroductionSession.decode,
            )
          : <ContactIntroductionSession>[];
      final provenance = map.containsKey('provenance')
          ? _records(map['provenance'], ContactIntroductionProvenance.decode)
          : <ContactIntroductionProvenance>[];
      if (map.containsKey('introductionSigners')) {
        final values = _list(map['introductionSigners']);
        for (final value in values) {
          decodedSigners.add(IntroductionStoredSigner.decode(value));
        }
      }
      if (map.containsKey('quarantinedSigners')) {
        for (final value in _list(map['quarantinedSigners'])) {
          quarantined.add(IntroductionStoredSigner.decode(value));
        }
      }
      _unique([...decodedSigners, ...quarantined].map((s) => s.identity));
      _unique(contacts.map((contact) => contact.id));
      _unique(contacts.map((contact) => contact.identity));
      _unique(contacts.map((contact) => contact.label.toLowerCase()));
      _unique(associations.map((association) => association.incomingContactId));
      _unique(associations.map((association) => association.incomingIdentity));
      _unique(associations.map((association) => association.outgoingIdentity));
      _unique(sessions.map((session) => session.id));
      _unique(decodedSigners.map((signer) => signer.identity));
      _unique(provenance.map((item) => item.introducedContactId));
      _unique(provenance.map((item) => item.requestHash));
      return ContactBook(
        contacts: contacts,
        associations: associations,
        sessions: sessions,
        signers: decodedSigners,
        quarantinedSigners: quarantined,
        provenance: provenance,
      );
    } catch (_) {
      for (final signer in [...decodedSigners, ...quarantined]) {
        signer.clear();
      }
      throw const ContactFailure(
        'Saved contact data could not be verified. Contact payments are blocked.',
      );
    }
  }
}

Map<String, dynamic> _object(
  Object? value,
  Set<String> required,
  Set<String> optional,
) {
  if (value is! Map<String, dynamic> ||
      !required.every(value.containsKey) ||
      !value.keys.every(
        (key) => required.contains(key) || optional.contains(key),
      )) {
    throw const FormatException();
  }
  return value;
}

List<dynamic> _list(Object? value, {int max = contactBookMaxRecords}) {
  if (value is! List || value.length > max) throw const FormatException();
  return value;
}

List<T> _records<T>(
  Object? value,
  T Function(Object?) decode, {
  int max = contactBookMaxRecords,
}) => _list(value, max: max).map(decode).toList(growable: false);

void _unique(Iterable<String> values) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) throw const FormatException();
  }
}

T? _optional<T>(
  Map<String, dynamic> map,
  String key,
  T Function(Object?) decode,
) => map.containsKey(key) ? decode(map[key]) : null;

String _id(Object? value) => contactText(value, max: 64);

DateTime _time(Object? value) {
  final millis = contactInteger(value);
  // DateTime has a narrower range than the wire's safe integer range.
  if (millis > 8640000000000000) throw const FormatException();
  return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}

String _hash(Object? value) {
  final encoded = contactText(value, max: 43);
  final bytes = base64Url.decode(base64Url.normalize(encoded));
  if (bytes.length != 32 ||
      base64Url.encode(bytes).replaceAll('=', '') != encoded) {
    throw const FormatException();
  }
  return encoded;
}

String _packet(Object? value) {
  final packet = contactText(value, max: contactIntroductionPacketMaxBytes);
  if (utf8.encode(packet).length > contactIntroductionPacketMaxBytes) {
    throw const FormatException();
  }
  return packet;
}

String _suggestion(Object? value) {
  final suggestion = contactText(value, max: 20);
  if (suggestion.trim() != suggestion ||
      suggestion.codeUnits.any((unit) => unit < 0x20 || unit > 0x7e)) {
    throw const FormatException();
  }
  return suggestion;
}
