import '../../address_book/models/address_book_contact.dart';
import 'contact_models.dart';

/// Presentation only: a saved address never acquires a relationship identity.
class SybilPerson {
  const SybilPerson.connected(VerifiedContact person)
    : connected = person,
      saved = null;
  const SybilPerson.saved(AddressBookContact person)
    : saved = person,
      connected = null;

  final VerifiedContact? connected;
  final AddressBookContact? saved;
  String get id => connected?.id ?? 'saved:${saved!.id}';
  String get label => connected?.label ?? saved!.label;
  String get address => connected?.address ?? saved!.address;
  String get avatarIdentity => connected?.identity ?? id;
  bool get canPay => connected?.canPay ?? saved!.network.canSendFromWallet;
}
