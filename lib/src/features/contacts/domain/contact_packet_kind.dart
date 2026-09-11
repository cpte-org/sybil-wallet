import 'dart:convert';
import 'contact_delivery.dart';

/// Presentation hints only. Never use a packet's domain or transport label as
/// evidence of identity, audience, freshness, consent, or signature validity.
enum ContactPacketKind { ask, offer, consent, delivery, request, response }

ContactPacketKind? contactPacketKind(String packet) {
  try {
    deliveryPacket(packet);
    final value = jsonDecode(packet);
    if (value is! List || value.isEmpty) return null;
    return switch (value.first) {
      'zcash-contact/intro-ask-package' => ContactPacketKind.ask,
      'zcash-contact/intro-offer-package' => ContactPacketKind.offer,
      'zcash-contact/intro-consent-package' => ContactPacketKind.consent,
      'zcash-contact/intro-delivery' => ContactPacketKind.delivery,
      'zcash-contact/request' => ContactPacketKind.request,
      'zcash-contact/exchange' => ContactPacketKind.response,
      _ => null,
    };
  } catch (_) {
    return null;
  }
}
