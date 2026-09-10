// Experimental direct contacts. Local labels never confer signing authority.
import 'dart:convert';

enum ContactTrustStatus { accepted, suspended, restored, retired }

class ContactFailure implements Exception {
  const ContactFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class ContactScope {
  const ContactScope({required this.accountUuid, required this.network});
  final String accountUuid;
  final String network;
  String get storagePrefix => 'zcash_contact_${accountUuid}_${network}_';
  @override
  bool operator ==(Object other) =>
      other is ContactScope &&
      other.accountUuid == accountUuid &&
      other.network == network;
  @override
  int get hashCode => Object.hash(accountUuid, network);
}

class VerifiedContact {
  const VerifiedContact({
    required this.id,
    required this.label,
    required this.identity,
    required this.address,
    required this.sequence,
    required this.revision,
    this.status = ContactTrustStatus.accepted,
  });
  final String id, label, identity, address;
  final int sequence, revision;
  final ContactTrustStatus status;
  bool get canPay => status == ContactTrustStatus.accepted;
  bool get canRequestUpdate => status == ContactTrustStatus.accepted;

  VerifiedContact copyWith({
    String? label,
    String? address,
    int? sequence,
    int? revision,
    ContactTrustStatus? status,
  }) => VerifiedContact(
    id: id,
    label: label ?? this.label,
    identity: identity,
    address: address ?? this.address,
    sequence: sequence ?? this.sequence,
    revision: revision ?? this.revision,
    status: status ?? this.status,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'identity': identity,
    'address': address,
    'sequence': sequence,
    'revision': revision,
    'status': status.name,
  };

  static VerifiedContact decode(Object? value) {
    final map = contactObject(value, {
      'id',
      'label',
      'identity',
      'address',
      'sequence',
      'revision',
      'status',
    });
    final id = contactText(map['id'], max: 64);
    final label = contactLabel(contactText(map['label'], max: 80));
    if (label != map['label']) {
      throw const ContactFailure('Saved contact data is invalid.');
    }
    final identity = contactIdentity(map['identity']);
    final address = contactText(map['address'], max: 512);
    if (address != address.trim()) {
      throw const ContactFailure('Saved contact data is invalid.');
    }
    final status = ContactTrustStatus.values
        .where((s) => s.name == map['status'])
        .firstOrNull;
    if (status == null) {
      throw const ContactFailure('Saved contact data is invalid.');
    }
    return VerifiedContact(
      id: id,
      label: label,
      identity: identity,
      address: address,
      sequence: contactInteger(map['sequence']),
      revision: contactInteger(map['revision']),
      status: status,
    );
  }
}

String contactLabel(String value) {
  final label = value.trim();
  // Match the existing address-book length limit without splitting a surrogate.
  if (label.isEmpty ||
      label.length > 20 ||
      label.runes.any(
        (c) => c < 32 || (c >= 127 && c <= 159) || (c >= 0xd800 && c <= 0xdfff),
      )) {
    throw const ContactFailure('Use a local label of 1–20 characters.');
  }
  return label;
}

String contactIdentity(Object? value) {
  final identity = contactText(value, max: 51);
  if (!identity.startsWith('ed25519:')) {
    throw const ContactFailure('Saved contact identity is invalid.');
  }
  final encoded = identity.substring(8);
  try {
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    if (bytes.length != 32 ||
        base64Url.encode(bytes).replaceAll('=', '') != encoded) {
      throw const FormatException();
    }
  } catch (_) {
    throw const ContactFailure('Saved contact identity is invalid.');
  }
  return identity;
}

int contactInteger(Object? value) {
  if (value is! int || value < 1 || value > 9007199254740991) {
    throw const ContactFailure('Saved contact revision is invalid.');
  }
  return value;
}

String contactText(Object? value, {required int max}) {
  if (value is! String || value.isEmpty || value.length > max) {
    throw const ContactFailure('Saved contact data is invalid.');
  }
  return value;
}

Map<String, dynamic> contactObject(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !value.keys.every(keys.contains)) {
    throw const ContactFailure('Saved contact data is invalid.');
  }
  return value;
}

class ContactRecipientSnapshot {
  const ContactRecipientSnapshot({
    required this.scope,
    required this.bookInstance,
    required this.generation,
    required this.contact,
  });
  final ContactScope scope;
  final String bookInstance;
  final int generation;
  final VerifiedContact contact;
  String get address => contact.address;
  String get label => contact.label;
  String get identity => contact.identity;
  String get fingerprint =>
      '$bookInstance:$generation:${contact.id}:${contact.revision}';
}

class ContactRequestView {
  const ContactRequestView({
    required this.json,
    required this.expiresAt,
    this.contactId,
    this.label,
  });
  final String json;
  final DateTime expiresAt;
  final String? contactId, label;
  bool get isUpdate => contactId != null;
}

class ContactCandidateView {
  const ContactCandidateView({
    required this.identity,
    required this.address,
    required this.sequence,
    required this.expiresAt,
    this.previousAddress,
    this.label,
  });
  final String identity, address;
  final int sequence;
  final DateTime expiresAt;
  final String? previousAddress, label;
  bool get isUpdate => previousAddress != null;
}

class ContactShareReview {
  const ContactShareReview({
    required this.identity,
    required this.address,
    required this.audience,
    required this.expiresAt,
    this.previousAddress,
  });
  final String identity, address, audience;
  final DateTime expiresAt;
  final String? previousAddress;
  bool get isUpdate => previousAddress != null;
}

class ContactExchangeState {
  const ContactExchangeState({
    this.available = false,
    this.loading = false,
    this.busy = false,
    this.error,
    this.unavailableReason,
    this.contacts = const [],
    this.request,
    this.candidate,
    this.shareReview,
    this.response,
  });
  final bool available, loading, busy;
  final String? error, unavailableReason;
  final List<VerifiedContact> contacts;
  final ContactRequestView? request;
  final ContactCandidateView? candidate;
  final ContactShareReview? shareReview;
  final String? response;
}
