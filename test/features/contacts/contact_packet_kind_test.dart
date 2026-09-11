import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_packet_kind.dart';

void main() {
  test(
    'domain hints route only recognized bounded packets, never verify them',
    () {
      expect(
        contactPacketKind('["zcash-contact/intro-delivery"]'),
        ContactPacketKind.delivery,
      );
      expect(
        contactPacketKind('["zcash-contact/request"]'),
        ContactPacketKind.request,
      );
      expect(
        contactPacketKind('["zcash-contact/exchange",null,null]'),
        ContactPacketKind.response,
      );
      for (final invalid in [
        '{}',
        '[]',
        'null',
        'invalid',
        '["other"]',
        'x' * 16385,
      ]) {
        expect(contactPacketKind(invalid), isNull);
      }
    },
  );
}
