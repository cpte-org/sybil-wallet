import 'dart:typed_data';

import '../../../rust/api/contacts.dart' as rust;
import '../domain/contact_models.dart';
import 'contact_repository.dart';

enum IntroductionWireStage { ask, offer, consent, delivery }

/// A Rust-verified candidate. It carries no local acceptance or user consent.
class IntroductionWireResult {
  const IntroductionWireResult({
    required this.packet,
    required this.request,
    required this.requestHash,
    required this.expiresAt,
    this.offer,
    this.endpoint,
    this.identity,
    this.address,
    this.sequence,
    this.suggestion,
    this.endpointHash,
    this.endorsementHash,
  });
  final String packet, request, requestHash;
  final DateTime expiresAt;
  final String? offer, endpoint, identity, address, suggestion;
  final String? endpointHash, endorsementHash;
  final int? sequence;
}

abstract class ContactIntroductionGateway {
  Future<bool> validateAssociation(
    ContactScope scope,
    String peer,
    ContactSigner own,
  );
  Future<IntroductionWireResult> verify(
    ContactScope scope,
    IntroductionWireStage stage,
    String peer,
    String own,
    String packet,
    DateTime now, {
    String? request,
    String? offer,
  });
  Future<IntroductionWireResult> ask(
    ContactScope scope,
    String peer,
    ContactSigner own,
    DateTime now,
  );
  Future<IntroductionWireResult> offer(
    ContactScope scope,
    String request,
    String peer,
    ContactSigner own,
    String suggestion,
    DateTime now,
  );
  Future<IntroductionWireResult> consent(
    ContactScope scope,
    String peer,
    ContactSigner own,
    ContactSigner fresh,
    String offerPacket,
    DateTime now,
  );
  Future<IntroductionWireResult> delivery(
    ContactScope scope,
    String peerBob,
    String ownBob,
    String peerCarol,
    ContactSigner ownCarol,
    String request,
    String offer,
    String consentPacket,
    String suggestion,
    DateTime now,
  );
}

class RustContactIntroductionGateway implements ContactIntroductionGateway {
  BigInt _seconds(DateTime now) =>
      BigInt.from(now.millisecondsSinceEpoch ~/ 1000);
  IntroductionWireResult _result(rust.ContactIntroductionResult r) =>
      IntroductionWireResult(
        packet: r.packetJson,
        request: r.requestJson,
        requestHash: r.requestHash,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          r.expiresAt.toInt() * 1000,
        ),
        offer: r.offerJson,
        endpoint: r.endpointJson,
        identity: r.identity,
        address: r.address,
        sequence: r.sequence?.toInt(),
        suggestion: r.suggestion,
        endpointHash: r.endpointHash,
        endorsementHash: r.endorsementHash,
      );

  Future<T> _withSecret<T>(
    ContactSigner signer,
    Future<T> Function(Uint8List) action,
  ) async {
    final bytes = Uint8List.fromList(signer.secret);
    try {
      return await action(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<bool> validateAssociation(
    ContactScope scope,
    String peer,
    ContactSigner own,
  ) => _withSecret(
    own,
    (secret) => rust.contactsValidateIntroductionAssociation(
      network: scope.network,
      incomingIdentity: peer,
      ownIdentity: own.identity,
      ownSecretKey: secret,
    ),
  );

  @override
  Future<IntroductionWireResult> verify(
    ContactScope scope,
    IntroductionWireStage stage,
    String peer,
    String own,
    String packet,
    DateTime now, {
    String? request,
    String? offer,
  }) async {
    final rust.ContactIntroductionResult result;
    switch (stage) {
      case IntroductionWireStage.ask:
        result = await rust.contactsVerifyIntroductionAsk(
          network: scope.network,
          peerCaIdentity: peer,
          ownAcIdentity: own,
          packetJson: packet,
          now: _seconds(now),
        );
      case IntroductionWireStage.offer:
        result = await rust.contactsVerifyIntroductionOffer(
          network: scope.network,
          peerAbIdentity: peer,
          ownBaIdentity: own,
          packetJson: packet,
          now: _seconds(now),
        );
      case IntroductionWireStage.consent:
        if (request == null || offer == null) {
          throw const ContactFailure('The saved offer is unavailable.');
        }
        result = await rust.contactsVerifyIntroductionConsent(
          network: scope.network,
          peerBaIdentity: peer,
          ownAbIdentity: own,
          savedRequestJson: request,
          savedOfferJson: offer,
          packetJson: packet,
          now: _seconds(now),
        );
      case IntroductionWireStage.delivery:
        if (request == null) {
          throw const ContactFailure(
            'There is no pending introduction request.',
          );
        }
        result = await rust.contactsVerifyIntroductionDelivery(
          network: scope.network,
          peerAcIdentity: peer,
          ownCaIdentity: own,
          savedRequestJson: request,
          packetJson: packet,
          now: _seconds(now),
        );
    }
    return _result(result);
  }

  @override
  Future<IntroductionWireResult> ask(
    ContactScope scope,
    String peer,
    ContactSigner own,
    DateTime now,
  ) async => _result(
    await _withSecret(
      own,
      (secret) => rust.contactsCreateIntroductionAsk(
        network: scope.network,
        peerAcIdentity: peer,
        secretCaKey: secret,
        now: _seconds(now),
      ),
    ),
  );

  @override
  Future<IntroductionWireResult> offer(
    ContactScope scope,
    String request,
    String peer,
    ContactSigner own,
    String suggestion,
    DateTime now,
  ) async => _result(
    await _withSecret(
      own,
      (secret) => rust.contactsCreateIntroductionOffer(
        network: scope.network,
        requestJson: request,
        peerBaIdentity: peer,
        secretAbKey: secret,
        suggestedRecipient: suggestion,
        now: _seconds(now),
      ),
    ),
  );

  @override
  Future<IntroductionWireResult> consent(
    ContactScope scope,
    String peer,
    ContactSigner own,
    ContactSigner fresh,
    String offerPacket,
    DateTime now,
  ) async => _result(
    await _withSecret(
      own,
      (oldSecret) => _withSecret(
        fresh,
        (newSecret) => rust.contactsCreateIntroductionConsent(
          network: scope.network,
          peerAbIdentity: peer,
          secretBaKey: oldSecret,
          freshSecretBcKey: newSecret,
          freshAddress: fresh.address,
          offerPacketJson: offerPacket,
          now: _seconds(now),
        ),
      ),
    ),
  );

  @override
  Future<IntroductionWireResult> delivery(
    ContactScope scope,
    String peerBob,
    String ownBob,
    String peerCarol,
    ContactSigner ownCarol,
    String request,
    String offer,
    String consentPacket,
    String suggestion,
    DateTime now,
  ) async => _result(
    await _withSecret(
      ownCarol,
      (secret) => rust.contactsCreateIntroductionDelivery(
        network: scope.network,
        peerBaIdentity: peerBob,
        ownAbIdentity: ownBob,
        peerCaIdentity: peerCarol,
        secretAcKey: secret,
        savedRequestJson: request,
        savedOfferJson: offer,
        consentPacketJson: consentPacket,
        suggestedContact: suggestion,
        now: _seconds(now),
      ),
    ),
  );
}
