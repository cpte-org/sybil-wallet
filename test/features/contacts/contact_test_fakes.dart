import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_exchange_controller.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_gateway.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import 'contact_test_fixtures.dart';

export 'contact_test_fixtures.dart';

class FakeContactRepository implements ContactRepository {
  FakeContactRepository([List<VerifiedContact> initial = const []])
    : contacts = [...initial];
  List<VerifiedContact> contacts;
  final signers = <String, ContactSigner>{};
  final loadedSigners = <ContactSigner>[];
  final events = <String>[];
  Completer<List<VerifiedContact>>? loadGate;
  Completer<void>? saveGate, signerSaveGate;
  Object? loadError, saveError, signerSaveError;
  int saves = 0, signerSaves = 0, signerLoads = 0;

  @override
  Future<List<VerifiedContact>> load(ContactScope scope) async {
    if (loadError != null) throw loadError!;
    return loadGate == null ? [...contacts] : await loadGate!.future;
  }

  @override
  Future<void> save(ContactScope scope, List<VerifiedContact> value) async {
    saves++;
    if (saveGate != null) await saveGate!.future;
    if (saveError != null) throw saveError!;
    contacts = [...value];
  }

  @override
  Future<ContactSigner?> loadSigner(ContactScope scope, String identity) async {
    signerLoads++;
    final stored = signers[identity];
    if (stored == null) return null;
    final signer = ContactSigner(
      identity: stored.identity,
      secret: Uint8List.fromList(stored.secret),
      address: stored.address,
      sequence: stored.sequence,
    );
    loadedSigners.add(signer);
    return signer;
  }

  @override
  Future<void> saveSigner(
    ContactScope scope,
    ContactSigner signer, {
    void Function()? beforeWrite,
  }) async {
    beforeWrite?.call();
    signerSaves++;
    events.add('save-start');
    // Production serializes the secret before its storage await.
    final stored = ContactSigner(
      identity: signer.identity,
      secret: Uint8List.fromList(signer.secret),
      address: signer.address,
      sequence: signer.sequence,
    );
    if (signerSaveGate != null) await signerSaveGate!.future;
    if (signerSaveError != null) {
      stored.clear();
      throw signerSaveError!;
    }
    signers[signer.identity] = stored;
    events.add('save-complete');
  }
}

class FakeContactGateway implements ContactGateway {
  FakeContactGateway()
    : endpoint = ContactWireEndpoint(
        identity: testIdentity(1),
        address: 'test-address-new',
        sequence: 6,
        expiresAt: testContactNow.add(const Duration(minutes: 5)),
      );
  ContactWireEndpoint endpoint;
  String? requestedSubject, incomingSubject;
  String address = 'test-address-fresh';
  DateTime expiry = testContactNow.add(const Duration(minutes: 5));
  Completer<ContactWireEndpoint>? verifyGate;
  Completer<ContactSigner>? identityGate;
  Completer<String>? addressGate, signGate;
  final createdSigners = <ContactSigner>[];
  final signingSigners = <ContactSigner>[];
  final invalidAddresses = <String>{};
  int verifications = 0,
      identityCreates = 0,
      addressAllocations = 0,
      signatures = 0;

  @override
  Future<ContactSigner> createIdentity() async {
    identityCreates++;
    final signer = identityGate == null
        ? ContactSigner(
            identity: testIdentity(3),
            secret: Uint8List.fromList(List.filled(32, 7)),
            address: '',
            sequence: 1,
          )
        : await identityGate!.future;
    createdSigners.add(signer);
    return signer;
  }

  @override
  Future<ContactWireRequest> createRequest(
    ContactScope scope,
    String? subject,
    DateTime now,
  ) async {
    requestedSubject = subject;
    return ContactWireRequest(
      json: 'pending-request',
      audience: testIdentity(2),
      subject: subject,
      expiresAt: expiry,
    );
  }

  @override
  Future<ContactWireRequest> inspectRequest(
    ContactScope scope,
    String json,
    DateTime now,
  ) async => ContactWireRequest(
    json: json,
    audience: testIdentity(2),
    subject: incomingSubject,
    expiresAt: expiry,
  );
  @override
  Future<ContactWireEndpoint> verify(
    ContactScope scope,
    String request,
    String response,
    DateTime now,
  ) async {
    verifications++;
    return verifyGate == null ? endpoint : await verifyGate!.future;
  }

  @override
  Future<String> sign(
    ContactScope scope,
    String request,
    ContactSigner signer,
    DateTime now,
  ) async {
    signatures++;
    signingSigners.add(signer);
    return signGate == null
        ? 'signed-contact-response'
        : await signGate!.future;
  }

  @override
  Future<bool> validateAddress(ContactScope scope, String address) async =>
      !invalidAddresses.contains(address);
  @override
  Future<String> freshAddress(ContactScope scope) async {
    addressAllocations++;
    return addressGate == null ? address : await addressGate!.future;
  }
}

class TestContactScopeNotifier extends Notifier<ContactScope?> {
  @override
  ContactScope? build() => testContactScope;
  void change(ContactScope? next) => state = next;
}

final testContactScopeProvider =
    NotifierProvider<TestContactScopeNotifier, ContactScope?>(
      TestContactScopeNotifier.new,
    );

class ContactHarness {
  ContactHarness({
    FakeContactRepository? repository,
    FakeContactGateway? gateway,
  }) : repository = repository ?? FakeContactRepository(),
       gateway = gateway ?? FakeContactGateway() {
    container = ProviderContainer(
      overrides: [
        contactScopeProvider.overrideWith(
          (ref) => ref.watch(testContactScopeProvider),
        ),
        contactRepositoryProvider.overrideWithValue(this.repository),
        contactGatewayProvider.overrideWithValue(this.gateway),
        contactClockProvider.overrideWithValue(() => now),
      ],
    );
    controller = container.read(contactExchangeProvider.notifier);
    addTearDown(container.dispose);
  }
  final FakeContactRepository repository;
  final FakeContactGateway gateway;
  late final ProviderContainer container;
  late final ContactExchangeController controller;
  DateTime now = testContactNow;
  ContactExchangeState get state => container.read(contactExchangeProvider);
  Future<void> ready() async {
    await pumpEventQueue();
    expect(state.loading, isFalse);
  }

  Future<void> scope(ContactScope? next) async {
    container.read(testContactScopeProvider.notifier).change(next);
    await pumpEventQueue();
  }

  Future<void> candidate({String? contactId}) async {
    await controller.startRequest(contactId: contactId);
    await controller.previewResponse('signed-response');
    expect(state.candidate, isNotNull);
  }

  void validate(ContactRecipientSnapshot snapshot) =>
      controller.validateRecipient(
        snapshot,
        address: snapshot.address,
        accountUuid: snapshot.scope.accountUuid,
        network: snapshot.scope.network,
      );
}
