import 'dart:typed_data';
import '../../../core/storage/wallet_paths.dart';
import '../../../rust/api/contacts.dart' as rust;
import '../../../rust/api/sync.dart' as sync;
import '../domain/contact_models.dart';
import 'contact_repository.dart';

class ContactWireRequest {
  const ContactWireRequest({
    required this.json,
    required this.audience,
    required this.expiresAt,
    this.subject,
  });
  final String json, audience;
  final DateTime expiresAt;
  final String? subject;
}

class ContactWireEndpoint {
  const ContactWireEndpoint({
    required this.identity,
    required this.address,
    required this.sequence,
    required this.expiresAt,
  });
  final String identity, address;
  final int sequence;
  final DateTime expiresAt;
}

abstract class ContactGateway {
  Future<ContactSigner> createIdentity();
  Future<ContactWireRequest> createRequest(
    ContactScope scope,
    String? subject,
    DateTime now,
  );
  Future<ContactWireRequest> inspectRequest(
    ContactScope scope,
    String json,
    DateTime now,
  );
  Future<ContactWireEndpoint> verify(
    ContactScope scope,
    String request,
    String response,
    DateTime now,
  );
  Future<String> sign(
    ContactScope scope,
    String request,
    ContactSigner signer,
    DateTime now,
  );
  Future<bool> validateAddress(ContactScope scope, String address);
  Future<String> freshAddress(ContactScope scope);
}

class RustContactGateway implements ContactGateway {
  BigInt _seconds(DateTime now) =>
      BigInt.from(now.millisecondsSinceEpoch ~/ 1000);
  ContactWireRequest _request(rust.ContactRequestResult value) =>
      ContactWireRequest(
        json: value.requestJson,
        audience: value.audience,
        subject: value.subjectIdentity,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          value.expiresAt.toInt() * 1000,
        ),
      );
  @override
  Future<ContactSigner> createIdentity() async {
    final result = await rust.contactsCreateIdentity();
    final bytes = Uint8List.fromList(result.secretKey);
    result.secretKey.fillRange(0, result.secretKey.length, 0);
    return ContactSigner(
      identity: result.identity,
      secret: bytes,
      address: '',
      sequence: 1,
    );
  }

  @override
  Future<ContactWireRequest> createRequest(
    ContactScope scope,
    String? subject,
    DateTime now,
  ) async => _request(
    await rust.contactsCreateRequest(
      network: scope.network,
      subjectIdentity: subject,
      now: _seconds(now),
    ),
  );
  @override
  Future<ContactWireRequest> inspectRequest(
    ContactScope scope,
    String json,
    DateTime now,
  ) async => _request(
    await rust.contactsInspectRequest(
      network: scope.network,
      requestJson: json,
      now: _seconds(now),
    ),
  );
  @override
  Future<ContactWireEndpoint> verify(
    ContactScope scope,
    String request,
    String response,
    DateTime now,
  ) async {
    final result = await rust.contactsVerifyResponse(
      network: scope.network,
      requestJson: request,
      exchangeJson: response,
      now: _seconds(now),
    );
    return ContactWireEndpoint(
      identity: result.identity,
      address: result.address,
      sequence: result.sequence.toInt(),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        result.expiresAt.toInt() * 1000,
      ),
    );
  }

  @override
  Future<String> sign(
    ContactScope scope,
    String request,
    ContactSigner signer,
    DateTime now,
  ) async {
    final bytes = Uint8List.fromList(signer.secret);
    try {
      return await rust.contactsSignResponse(
        network: scope.network,
        requestJson: request,
        secretKey: bytes,
        address: signer.address,
        sequence: BigInt.from(signer.sequence),
        now: _seconds(now),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<bool> validateAddress(ContactScope scope, String address) => rust
      .contactsValidateUnifiedAddress(network: scope.network, address: address);
  @override
  Future<String> freshAddress(ContactScope scope) async =>
      sync.getNextAvailableAddress(
        dbPath: await getWalletDbPath(),
        network: scope.network,
        accountUuid: scope.accountUuid,
        addressRequest: 'orchard',
      );
}
