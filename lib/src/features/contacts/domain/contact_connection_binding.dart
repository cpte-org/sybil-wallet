import 'contact_models.dart';
import 'contact_delivery.dart' show deliveryPeer;

/// Locally attested association after an independent security-code comparison.
/// This is not a peer-signed identity claim or a backup recovery credential.
class ContactConnectionBinding {
  const ContactConnectionBinding({
    required this.contactId,
    required this.identity,
    required this.peer,
    required this.code,
  });
  final String contactId, identity, peer, code;
  Map<String, Object?> toJson() => {
    'contactId': contactId,
    'identity': identity,
    'peer': peer,
    'code': code,
  };
  static ContactConnectionBinding decode(Object? value) {
    final m = contactObject(value, {'contactId', 'identity', 'peer', 'code'});
    final code = contactText(m['code'], max: 160);
    if (!RegExp(r'^[0-9]{20,160}$').hasMatch(code)) {
      throw const ContactFailure('Invalid connection security code.');
    }
    return ContactConnectionBinding(
      contactId: contactText(m['contactId'], max: 64),
      identity: contactIdentity(m['identity']),
      peer: deliveryPeer(m['peer']),
      code: code,
    );
  }
}
