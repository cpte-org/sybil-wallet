import 'dart:convert';

import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

const testContactScope = ContactScope(
  accountUuid: 'contact-test-account',
  network: 'test',
);
final testContactNow = DateTime.utc(2026, 9, 10, 12);
String testIdentity(int byte) =>
    'ed25519:${base64Url.encode(List.filled(32, byte)).replaceAll('=', '')}';

VerifiedContact testContact({
  String id = 'alice',
  String label = 'Alice',
  int identityByte = 1,
  String address = 'test-address-old',
  int sequence = 5,
  int revision = 2,
  ContactTrustStatus status = ContactTrustStatus.accepted,
}) => VerifiedContact(
  id: id,
  label: label,
  identity: testIdentity(identityByte),
  address: address,
  sequence: sequence,
  revision: revision,
  status: status,
);
