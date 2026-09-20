import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../data/contact_gateway.dart';
import '../data/contact_repository.dart';
import '../domain/contact_models.dart';
import 'contact_lifecycle.dart';
import 'contact_mutation_gate.dart';

final contactExperimentEnabledProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment('ZCASH_CONTACTS_EXPERIMENT'),
);
final contactScopeProvider = Provider<ContactScope?>((ref) {
  if (!ref.watch(contactExperimentEnabledProvider)) return null;
  final account = ref.watch(accountProvider).value?.activeAccount;
  final security = ref.watch(appSecurityProvider);
  final network = ref.watch(rpcEndpointFailoverProvider).current.networkName;
  if (account == null ||
      account.isHardware ||
      !security.isUnlocked ||
      !['main', 'test', 'regtest'].contains(network) ||
      !ContactLifecycle.allowed(account.uuid)) {
    return null;
  }
  return ContactScope(accountUuid: account.uuid, network: network);
});
final contactExchangeAvailableProvider = Provider<bool>(
  (ref) => ref.watch(contactScopeProvider) != null,
);
final contactRepositoryProvider = Provider<ContactRepository>(
  (ref) => SecureContactRepository(),
);
final contactGatewayProvider = Provider<ContactGateway>(
  (ref) => RustContactGateway(),
);
final contactClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final contactExchangeProvider =
    NotifierProvider<ContactExchangeController, ContactExchangeState>(
      ContactExchangeController.new,
    );

String _randomId() {
  final random = Random.secure();
  return base64Url
      .encode(List<int>.generate(24, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

class _Candidate {
  const _Candidate(this.request, this.response, this.endpoint, this.previous);
  final ContactRequestView request;
  final String response;
  final ContactWireEndpoint endpoint;
  final VerifiedContact? previous;
}

class _Share {
  const _Share(this.request, this.signer, this.previousAddress);
  final ContactWireRequest request;
  final ContactSigner signer;
  final String? previousAddress;
}

class ContactExchangeController extends Notifier<ContactExchangeState> {
  ContactScope? _scope;
  final String _instance = _randomId();
  List<VerifiedContact> _contacts = const [];
  ContactRequestView? _request;
  _Candidate? _candidate;
  _Share? _share;
  ContactSigner? _preparingSigner;
  String? _response, _error;
  DateTime? _responseExpiresAt;
  bool _loaded = false, _loading = false, _disposed = false;
  int _epoch = 0, _task = 0, _generation = 0, _inFlight = 0;
  int _bookGeneration = 0;
  bool _reloadAfterWork = false;
  Timer? _expiryTimer;

  @override
  ContactExchangeState build() {
    ref.listen(contactScopeProvider, (previous, next) {
      if (previous != next) unawaited(reload());
    });
    void destructiveChange() {
      if (_disposed) return;
      ref.invalidate(contactScopeProvider);
      unawaited(reload());
    }

    ContactLifecycle.listeners.add(destructiveChange);
    void bookChanged(ContactScope scope, Object? source) {
      if (!_disposed && scope == _scope && !identical(source, this)) {
        if (_inFlight > 0) {
          _reloadAfterWork = true;
        } else {
          unawaited(reload());
        }
      }
    }

    ContactMutationGate.listeners.add(bookChanged);
    final lifecycle = AppLifecycleListener(
      onHide: pauseExchange,
      onPause: pauseExchange,
    );
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
      _task++;
      _clearTransient();
      lifecycle.dispose();
      ContactLifecycle.listeners.remove(destructiveChange);
      ContactMutationGate.listeners.remove(bookChanged);
    });
    scheduleMicrotask(reload);
    return const ContactExchangeState(loading: true);
  }

  DateTime get _now => ref.read(contactClockProvider)();
  ContactGateway get _gateway => ref.read(contactGatewayProvider);
  ContactRepository get _repository => ref.read(contactRepositoryProvider);

  void _publish() {
    if (_disposed) return;
    final candidate = _candidate;
    final share = _share;
    state = ContactExchangeState(
      available: _scope != null,
      loading: _loading,
      busy: _inFlight > 0,
      error: _error,
      unavailableReason: _scope == null
          ? 'Open an unlocked software account to connect with someone.'
          : null,
      contacts: List.unmodifiable(_contacts),
      request: _request,
      response: _response,
      responseExpiresAt: _responseExpiresAt,
      candidate: candidate == null
          ? null
          : ContactCandidateView(
              identity: candidate.endpoint.identity,
              address: candidate.endpoint.address,
              sequence: candidate.endpoint.sequence,
              expiresAt: candidate.endpoint.expiresAt,
              previousAddress: candidate.previous?.address,
              requiresRecoveryCheck:
                  candidate.previous?.status == ContactTrustStatus.restored,
              label: candidate.previous?.label,
            ),
      shareReview: share == null
          ? null
          : ContactShareReview(
              identity: share.signer.identity,
              address: share.signer.address,
              audience: share.request.audience,
              expiresAt: share.request.expiresAt,
              previousAddress: share.previousAddress,
            ),
    );
  }

  void _check(int epoch, ContactScope scope, [int? task]) {
    if (_disposed ||
        epoch != _epoch ||
        scope != _scope ||
        scope != ref.read(contactScopeProvider) ||
        !ContactLifecycle.allowed(scope.accountUuid) ||
        (task != null && task != _task)) {
      throw const ContactFailure(
        'The contact session changed. Start a new exchange.',
      );
    }
  }

  ContactScope _ready() {
    final scope = _scope;
    if (scope == null || !_loaded || _loading) {
      throw const ContactFailure(
        'Contact data is not available. Unlock your account and reopen People.',
      );
    }
    _check(_epoch, scope);
    return scope;
  }

  // Public for the screen's explicit reload action, never an import/merge.
  Future<void> reload() async {
    if (_disposed) return;
    final epoch = ++_epoch;
    _task++;
    _generation++;
    _clearTransient();
    _loaded = false;
    _contacts = const [];
    _error = null;
    _scope = ref.read(contactScopeProvider);
    final scope = _scope;
    _loading = scope != null;
    _publish();
    if (scope == null) return;
    try {
      await ContactMutationGate.run(scope, () async {
        final contacts = await _repository.load(scope);
        _check(epoch, scope);
        for (final contact in contacts) {
          if (!await _gateway.validateAddress(scope, contact.address)) {
            throw const ContactFailure(
              'Saved contact addresses could not be verified for this network. Contact payments are blocked.',
            );
          }
          _check(epoch, scope);
        }
        _contacts = List.unmodifiable(contacts);
        _bookGeneration = ContactMutationGate.generation(scope);
        _loaded = true;
      });
    } catch (error) {
      if (epoch == _epoch) {
        _error = error is ContactFailure
            ? error.message
            : 'Contact storage could not be opened. Contact payments are blocked.';
      }
    } finally {
      if (!_disposed && epoch == _epoch) {
        _loading = false;
        _publish();
      }
    }
  }

  Future<void> _run(
    Future<void> Function(ContactScope, int, int) action, {
    bool mutation = false,
  }) async {
    if (_disposed || _inFlight > 0) return;
    final epoch = _epoch, task = ++_task;
    try {
      final scope = _ready();
      if (mutation) {
        _generation++; // Invalidate prepared payments before storage I/O.
      }
      _inFlight++;
      _error = null;
      _publish();
      try {
        await ContactMutationGate.run(
          scope,
          () async {
            _check(epoch, scope, task);
            await action(scope, epoch, task);
            _bookGeneration = ContactMutationGate.generation(scope);
          },
          source: this,
          mutation: mutation || _share != null,
        );
      } finally {
        _inFlight--;
      }
    } catch (error) {
      if (!_disposed && epoch == _epoch && task == _task) {
        _error = error is ContactFailure
            ? error.message
            : 'This contact action could not be completed. Check the exchange and try again.';
      }
    } finally {
      _publish();
      if (_reloadAfterWork && !_disposed && _inFlight == 0) {
        _reloadAfterWork = false;
        unawaited(reload());
      }
    }
  }

  void _clearTransient() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _share?.signer.clear();
    _preparingSigner?.clear();
    _preparingSigner = null;
    _share = null;
    _request = null;
    _candidate = null;
    _response = null;
    _responseExpiresAt = null;
  }

  // Copying a public request into another app is part of the exchange. Keep
  // that challenge until its deadline, but drop signing material and consent.
  // Account/network/lock changes still use reload(), which clears everything.
  void pauseExchange() {
    final request = _request;
    _task++;
    _clearTransient();
    if (request != null && _now.isBefore(request.expiresAt)) {
      _request = request;
      _expireAt(request.expiresAt);
    }
    _publish();
  }

  void cancelTransient() {
    _task++;
    _clearTransient();
    _publish();
  }

  void clearError() {
    _error = null;
    _publish();
  }

  void _expireAt(DateTime time) {
    _expiryTimer?.cancel();
    final delay = time.difference(_now);
    _expiryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      cancelTransient();
      _error = 'This exchange expired. Request a fresh response.';
      _publish();
    });
  }

  void _notExpired(DateTime expires) {
    if (!_now.isBefore(expires)) {
      throw const ContactFailure(
        'This exchange expired. Request a fresh response.',
      );
    }
  }

  VerifiedContact _contact(String id) =>
      _contacts.where((c) => c.id == id).firstOrNull ??
      (throw const ContactFailure('This contact is no longer available.'));

  Future<void> startRequest({String? contactId}) => _run((
    scope,
    epoch,
    task,
  ) async {
    final previous = contactId == null ? null : _contact(contactId);
    if (previous != null && !previous.canRequestUpdate) {
      throw const ContactFailure(
        'This contact is suspended. Its key cannot authorize an address update.',
      );
    }
    _clearTransient();
    final request = await _gateway.createRequest(
      scope,
      previous?.identity,
      _now,
    );
    _check(epoch, scope, task);
    _notExpired(request.expiresAt);
    _request = ContactRequestView(
      json: request.json,
      expiresAt: request.expiresAt,
      contactId: previous?.id,
      identity: previous?.identity,
      label: previous?.label,
    );
    _expireAt(request.expiresAt);
  });

  void _checkEndpoint(ContactWireEndpoint endpoint, VerifiedContact? previous) {
    _notExpired(endpoint.expiresAt);
    if (previous == null) {
      if (_contacts.any((c) => c.identity == endpoint.identity)) {
        throw const ContactFailure(
          'This identity is already recorded. Use its existing contact.',
        );
      }
    } else {
      final current = _contact(previous.id);
      if (!identical(current, previous) ||
          !current.canRequestUpdate ||
          endpoint.identity != previous.identity) {
        throw const ContactFailure(
          'The saved contact changed. Start a new review.',
        );
      }
      if (endpoint.sequence < previous.sequence ||
          (endpoint.sequence == previous.sequence &&
              endpoint.address != previous.address)) {
        throw const ContactFailure(
          'This response contains an older or conflicting address revision.',
        );
      }
    }
  }

  Future<void> previewResponse(String text) => _run((scope, epoch, task) async {
    final request = _request;
    _candidate = null;
    if (request == null) {
      throw const ContactFailure('Create a contact request first.');
    }
    _notExpired(request.expiresAt);
    if (text.length > 32768) {
      throw const ContactFailure('This contact response is too large.');
    }
    final previous = request.contactId == null
        ? null
        : _contact(request.contactId!);
    final endpoint = await _gateway.verify(
      scope,
      request.json,
      text.trim(),
      _now,
    );
    _check(epoch, scope, task);
    if (!identical(request, _request)) {
      throw const ContactFailure('This request is no longer pending.');
    }
    _checkEndpoint(endpoint, previous);
    _candidate = _Candidate(request, text.trim(), endpoint, previous);
    _expireAt(endpoint.expiresAt);
  });

  Future<void> _save(
    ContactScope scope,
    List<VerifiedContact> contacts,
    int epoch,
    int task,
  ) async {
    _loaded =
        false; // A failed or interrupted write cannot grant a fresh payment snapshot.
    // Read/compare/write all execute inside the shared mutation gate. This
    // rejects a cached whole-book replacement prepared before another writer.
    final current = await _repository.load(scope);
    _check(epoch, scope, task);
    if (jsonEncode(current.map((c) => c.toJson()).toList()) !=
        jsonEncode(_contacts.map((c) => c.toJson()).toList())) {
      throw const ContactFailure(
        'The contact book changed. Reload and review again.',
      );
    }
    await _repository.save(scope, contacts);
    _check(epoch, scope, task);
    final committed = await _repository.load(scope);
    _check(epoch, scope, task);
    if (jsonEncode(committed.map((c) => c.toJson()).toList()) !=
        jsonEncode(contacts.map((c) => c.toJson()).toList())) {
      throw const ContactFailure(
        'The contact save could not be confirmed. Reload contacts.',
      );
    }
    _contacts = List.unmodifiable(contacts);
    _loaded = true;
  }

  Future<void> acceptResponse({
    required String label,
    required bool independentlyVerified,
  }) => _run((scope, epoch, task) async {
    final candidate = _candidate;
    if (candidate == null || !identical(candidate.request, _request)) {
      throw const ContactFailure(
        'Review a response to your pending request first.',
      );
    }
    if (!independentlyVerified) {
      throw const ContactFailure(
        'Compare the identity and receiving address through a trusted exchange before accepting.',
      );
    }
    final name = contactLabel(label);
    if (_contacts.any(
      (c) =>
          c.id != candidate.previous?.id &&
          c.label.toLowerCase() == name.toLowerCase(),
    )) {
      throw const ContactFailure(
        'Choose a label that distinguishes this contact.',
      );
    }
    final endpoint = await _gateway.verify(
      scope,
      candidate.request.json,
      candidate.response,
      _now,
    );
    _check(epoch, scope, task);
    if (!identical(candidate, _candidate) ||
        !identical(candidate.request, _request)) {
      throw const ContactFailure('This response is no longer under review.');
    }
    _checkEndpoint(endpoint, candidate.previous);
    final previous = candidate.previous;
    final accepted = VerifiedContact(
      id: previous?.id ?? _randomId(),
      label: name,
      identity: endpoint.identity,
      address: endpoint.address,
      sequence: endpoint.sequence,
      revision: (previous?.revision ?? 0) + 1,
    );
    final contacts = [
      for (final c in _contacts)
        if (c.id != accepted.id) c,
      accepted,
    ];
    await _save(scope, contacts, epoch, task);
    _clearTransient(); // Consumes the locally pending challenge only after persistence.
  }, mutation: true);

  /// A private label changes presentation only. Invalidate selected recipients
  /// so review always displays the name from the current authenticated record.
  Future<void> renameContact(String id, String label) => _run((
    scope,
    epoch,
    task,
  ) async {
    final name = contactLabel(label);
    final latest = await _repository.load(scope);
    _check(epoch, scope, task);
    _contacts = List.unmodifiable(latest);
    final contact = _contact(id);
    if (_contacts.any(
      (other) =>
          other.id != id && other.label.toLowerCase() == name.toLowerCase(),
    )) {
      throw const ContactFailure(
        'Choose a label that distinguishes this contact.',
      );
    }
    _clearTransient();
    final renamed = contact.copyWith(
      label: name,
      revision: contact.revision + 1,
    );
    await _save(
      scope,
      [for (final current in _contacts) current.id == id ? renamed : current],
      epoch,
      task,
    );
  }, mutation: true);

  Future<void> suspendContact(String id) => _run((scope, epoch, task) async {
    // A queued suspension applies to the latest book, including a contact
    // accepted by another coordinator before this mutation acquired the gate.
    final latest = await _repository.load(scope);
    _check(epoch, scope, task);
    _contacts = List.unmodifiable(latest);
    final contact = _contact(id);
    _clearTransient();
    final suspended = contact.copyWith(
      status: ContactTrustStatus.suspended,
      revision: contact.revision + 1,
    );
    await _save(
      scope,
      [for (final c in _contacts) c.id == id ? suspended : c],
      epoch,
      task,
    );
  }, mutation: true);

  Future<void> prepareShare(String requestText) => _run((
    scope,
    epoch,
    task,
  ) async {
    _clearTransient();
    if (requestText.length > 32768) {
      throw const ContactFailure('This contact request is too large.');
    }
    final request = await _gateway.inspectRequest(
      scope,
      requestText.trim(),
      _now,
    );
    _check(epoch, scope, task);
    ContactSigner? signer;
    var retained = false;
    try {
      signer = request.subject == null
          ? await _gateway.createIdentity()
          : await _repository.loadSigner(scope, request.subject!);
      _check(epoch, scope, task);
      if (signer == null) {
        throw const ContactFailure(
          'The signing key for this relationship is unavailable. The other person must independently accept a new contact.',
        );
      }
      _preparingSigner = signer;
      final address = await _gateway.freshAddress(scope);
      _check(epoch, scope, task);
      if (!await _gateway.validateAddress(scope, address)) {
        throw const ContactFailure(
          'A receiving address is not available for this network.',
        );
      }
      _check(epoch, scope, task);
      _notExpired(request.expiresAt);
      final previous = request.subject == null ? null : signer.address;
      final next = ContactSigner(
        identity: signer.identity,
        secret: signer.secret,
        address: address,
        sequence: request.subject == null ? 1 : signer.sequence + 1,
      );
      contactInteger(next.sequence);
      _share = _Share(request, next, previous);
      retained = true;
      _expireAt(request.expiresAt);
    } finally {
      if (identical(_preparingSigner, signer)) _preparingSigner = null;
      if (!retained) signer?.clear();
    }
  });

  Future<void> confirmShare({required bool consent}) => _run((
    scope,
    epoch,
    task,
  ) async {
    final share = _share;
    if (share == null) {
      throw const ContactFailure('Review the receiving details first.');
    }
    if (!consent) {
      throw const ContactFailure(
        'Approve sharing these details with the person who sent the request.',
      );
    }
    _notExpired(share.request.expiresAt);
    final response = await _gateway.sign(
      scope,
      share.request.json,
      share.signer,
      _now,
    );
    _check(epoch, scope, task);
    _notExpired(share.request.expiresAt);
    // Publish only after the exact key/address/revision is durable; never reset
    // an existing relationship counter when its signing record is missing.
    await _repository.saveSigner(
      scope,
      share.signer,
      beforeWrite: () {
        _check(epoch, scope, task);
        _notExpired(share.request.expiresAt);
      },
    );
    _check(epoch, scope, task);
    _notExpired(share.request.expiresAt);
    _share = null;
    share.signer.clear();
    _response = response;
    _responseExpiresAt = share.request.expiresAt;
  });

  ContactRecipientSnapshot recipientFor(String id) {
    final scope = _ready();
    if (_inFlight > 0 ||
        ContactMutationGate.busy(scope) ||
        _bookGeneration != ContactMutationGate.generation(scope)) {
      throw const ContactFailure('Wait for the contact action to finish.');
    }
    final contact = _contact(id);
    if (!contact.canPay) {
      throw const ContactFailure(
        'This contact is suspended or needs independent verification.',
      );
    }
    return ContactRecipientSnapshot(
      scope: scope,
      bookInstance: _instance,
      generation: _generation,
      contact: contact,
    );
  }

  void validateRecipient(
    ContactRecipientSnapshot snapshot, {
    required String address,
    required String accountUuid,
    required String network,
  }) {
    final scope = _ready();
    if (_inFlight > 0 ||
        ContactMutationGate.busy(scope) ||
        _bookGeneration != ContactMutationGate.generation(scope) ||
        snapshot.scope != scope ||
        scope.accountUuid != accountUuid ||
        scope.network != network ||
        snapshot.bookInstance != _instance ||
        snapshot.generation != _generation ||
        snapshot.address != address ||
        !identical(_contact(snapshot.contact.id), snapshot.contact) ||
        !snapshot.contact.canPay) {
      throw const ContactFailure(
        'This contact changed after selection. Return to contacts and review it again.',
      );
    }
  }
}
