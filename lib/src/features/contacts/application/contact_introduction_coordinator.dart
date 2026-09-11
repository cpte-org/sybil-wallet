import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../data/contact_gateway.dart';
import '../data/contact_introduction_gateway.dart';
import '../data/contact_introduction_repository.dart';
import '../data/contact_repository.dart';
import '../domain/contact_introduction_models.dart';
import '../domain/contact_models.dart';
import 'contact_lifecycle.dart';
import 'contact_mutation_gate.dart';

/// Public review data contains no signing secret. Only this coordinator can
/// construct it; confirmation requires the identical still-current review.
class ReciprocalContactReview {
  ReciprocalContactReview._(
    this.scope,
    this.peer,
    this.outgoingIdentity,
    this.outgoingAddress,
  );
  final ContactScope scope;
  final VerifiedContact peer;
  final String outgoingIdentity, outgoingAddress;
}

class IntroductionReview {
  IntroductionReview._({
    required this.scope,
    required this.stage,
    required this.wire,
    required this.pins,
    required this.contacts,
    required this.input,
    this.suggestion,
    this.identity,
    this.address,
    this.retry = false,
  });
  final ContactScope scope;
  final IntroductionWireStage stage;
  final IntroductionWireResult wire;
  final List<ContactIntroductionPin> pins;
  final List<VerifiedContact> contacts;
  final String input;
  final String? suggestion, identity, address;
  final bool retry;
}

/// Public display data only. Saved packets and signing secrets remain internal.
class ContactIntroductionOverview {
  ContactIntroductionOverview({
    required Iterable<VerifiedContact> contacts,
    required Iterable<ContactPeerAssociation> associations,
    required Iterable<ContactIntroductionProvenance> provenance,
    required Iterable<String> savedEndorsements,
    this.pendingRequests = const [],
  }) : contacts = List.unmodifiable(contacts),
       associations = List.unmodifiable(associations),
       provenance = List.unmodifiable(provenance),
       savedEndorsements = List.unmodifiable(savedEndorsements);
  final List<VerifiedContact> contacts;
  final List<ContactPeerAssociation> associations;
  final List<ContactIntroductionProvenance> provenance;
  final List<String> savedEndorsements;
  final List<({String hash, String label, DateTime expiresAt})> pendingRequests;
}

class _IntroductionAddressCheck {
  const _IntroductionAddressCheck(
    this.scope,
    this.packet,
    this.request,
    this.requestHash,
  );
  final ContactScope scope;
  final String packet;
  final ContactWireRequest request;
  final String requestHash;
}

/// Stateful authority boundary for the gated testnet experiment. No UI or
/// transport is implicit: every signature/export and acceptance requires an
/// explicit caller approval of the returned review. Storage owns the replay
/// record; this instance alone owns live requests and unfinished consent.
class ContactIntroductionCoordinator {
  ContactIntroductionCoordinator({
    required this.scope,
    required this.repository,
    required this.directRepository,
    required this.gateway,
    required this.directGateway,
    required this.clock,
  });
  final ContactScope? Function() scope;
  final ContactIntroductionRepository repository;
  final ContactRepository directRepository;
  final ContactIntroductionGateway gateway;
  final ContactGateway directGateway;
  final DateTime Function() clock;
  final _live = <ContactIntroductionRole, String>{};
  final _heldSigners = <ContactSigner>{};
  final _heldBooks = <ContactBook>{};
  Object? _review;
  ContactSigner? _fresh;
  bool _disposed = false, _running = false;
  int _epoch = 0;
  int? _clockFloor;
  Timer? _reviewExpiry;
  _IntroductionAddressCheck? _addressCheck;

  DateTime get _now {
    final value = clock();
    if (_clockFloor != null && value.millisecondsSinceEpoch < _clockFloor!) {
      pauseReview();
      throw const ContactFailure(
        'The clock moved backwards. Correct it before starting a new introduction.',
      );
    }
    _clockFloor = value.millisecondsSinceEpoch;
    return value;
  }

  void _setReview(Object review) {
    _review = review;
    if (review is IntroductionReview) {
      _reviewExpiry?.cancel();
      final delay = review.wire.expiresAt.difference(_now);
      _reviewExpiry = Timer(delay.isNegative ? Duration.zero : delay, () {
        if (identical(_review, review)) pauseReview();
      });
    }
  }

  void pauseReview() {
    _epoch++;
    _clearReview();
    for (final signer in _heldSigners) {
      signer.clear();
    }
    for (final book in _heldBooks) {
      book.clearSecrets();
    }
  }

  void invalidate() {
    pauseReview();
    _live.clear();
    _addressCheck = null;
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }

  void _clearReview() {
    _reviewExpiry?.cancel();
    _reviewExpiry = null;
    _review = null;
    _fresh?.clear();
    _fresh = null;
  }

  void _release(ContactSigner signer) {
    signer.clear();
    _heldSigners.remove(signer);
  }

  ContactScope _ready() {
    final current = scope();
    if (_disposed ||
        current == null ||
        !['test', 'regtest'].contains(current.network) ||
        !ContactLifecycle.allowed(current.accountUuid)) {
      throw const ContactFailure(
        'Unlock this test-network software account to use introductions.',
      );
    }
    return current;
  }

  void _check(ContactScope expected, int epoch) {
    _now; // Observe clock rollback at every asynchronous boundary.
    if (epoch != _epoch || _ready() != expected) {
      throw const ContactFailure(
        'The introduction session changed. Start a new review.',
      );
    }
  }

  void _liveTime(DateTime expires) {
    if (!_now.isBefore(expires)) {
      pauseReview();
      throw const ContactFailure(
        'This introduction expired. Ask for a fresh request.',
      );
    }
  }

  Future<T> _run<T>(
    Future<T> Function(ContactScope, int, ContactBook) action, {
    bool mutation = false,
  }) async {
    if (_running) {
      throw const ContactFailure(
        'Wait for the current contact action to finish.',
      );
    }
    final current = _ready(), epoch = _epoch;
    _running = true;
    try {
      return await ContactMutationGate.run(
        current,
        () async {
          _check(current, epoch);
          final book = await repository.loadBook(current);
          _heldBooks.add(book);
          try {
            _check(current, epoch);
            return await action(current, epoch, book);
          } finally {
            book.clearSecrets();
            _heldBooks.remove(book);
          }
        },
        source: this,
        mutation: mutation,
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _commit(
    ContactScope current,
    int epoch,
    ContactBook book, {
    DateTime? expires,
  }) async {
    // A commit aggregate may own a newly copied signer that is absent from the
    // originally loaded book. Keep that copy reachable by pauseReview too.
    final added = _heldBooks.add(book);
    try {
      _check(current, epoch);
      if (expires != null) _liveTime(expires);
      // The single envelope is the durable acceptance/publication point. A write
      // dispatched before invalidation may finish, but can expose no late result.
      await repository.saveBook(current, book);
      _check(current, epoch);
      final saved = await repository.loadBook(current);
      try {
        _check(current, epoch);
        if (jsonEncode(saved.toJson(current)) !=
            jsonEncode(book.toJson(current))) {
          throw const ContactFailure(
            'The contact save could not be confirmed. Reload before continuing.',
          );
        }
      } finally {
        saved.clearSecrets();
      }
      if (expires != null) _liveTime(expires);
    } finally {
      if (added) {
        book.clearSecrets();
        _heldBooks.remove(book);
      }
    }
  }

  VerifiedContact _contact(ContactBook book, String id) {
    final contact = book.contacts.where((c) => c.id == id).firstOrNull;
    if (contact == null || contact.status != ContactTrustStatus.accepted) {
      throw const ContactFailure(
        'This contact is unavailable or needs independent verification.',
      );
    }
    return contact;
  }

  ContactIntroductionPin _pin(ContactBook book, String id) {
    final contact = _contact(book, id);
    final association = book.associations
        .where((a) => a.incomingContactId == id)
        .firstOrNull;
    if (association == null ||
        association.incomingIdentity != contact.identity) {
      throw const ContactFailure(
        'Complete the independently checked two-way contact setup first.',
      );
    }
    return ContactIntroductionPin(
      contactId: id,
      identity: contact.identity,
      outgoingIdentity: association.outgoingIdentity,
    );
  }

  void _checkPins(ContactBook book, List<ContactIntroductionPin> pins) {
    for (final pin in pins) {
      if (jsonEncode(_pin(book, pin.contactId).toJson()) !=
          jsonEncode(pin.toJson())) {
        throw const ContactFailure(
          'The paired contact changed. Start a new introduction.',
        );
      }
    }
  }

  void _checkReview(ContactBook book, Object review) {
    if (!identical(_review, review)) {
      throw const ContactFailure(
        'This review is no longer active. Review the details again.',
      );
    }
    if (review is IntroductionReview) {
      _liveTime(review.wire.expiresAt);
      _checkPins(book, review.pins);
      for (final previous in review.contacts) {
        if (jsonEncode(_contact(book, previous.id).toJson()) !=
            jsonEncode(previous.toJson())) {
          throw const ContactFailure(
            'A contact changed during review. Review the introduction again.',
          );
        }
      }
    }
  }

  Future<ContactSigner> _signer(
    ContactScope current,
    int epoch,
    ContactIntroductionPin pin,
  ) async {
    final signer = await directRepository.loadSigner(
      current,
      pin.outgoingIdentity,
    );
    if (signer == null) {
      throw const ContactFailure(
        'This relationship signing key is unavailable. Independently set up a new contact.',
      );
    }
    _heldSigners.add(signer);
    try {
      _check(current, epoch);
      if (!await gateway.validateAssociation(current, pin.identity, signer)) {
        throw const ContactFailure(
          'The paired contact signing key could not be verified.',
        );
      }
      _check(current, epoch);
      return signer;
    } catch (_) {
      _release(signer);
      rethrow;
    }
  }

  ContactIntroductionSession? _session(
    ContactBook book,
    ContactIntroductionRole role,
    String hash,
  ) => book.sessions
      .where((s) => s.role == role && s.requestHash == hash)
      .firstOrNull;

  ContactIntroductionSession _pending(
    ContactBook book,
    ContactIntroductionRole role,
  ) {
    final hash = _live[role];
    final saved = hash == null ? null : _session(book, role, hash);
    if (saved == null || saved.phase != ContactIntroductionPhase.published) {
      throw const ContactFailure(
        'No invitation is selected. Resume a saved invitation or start a new exchange.',
      );
    }
    _liveTime(saved.expiresAt);
    _checkPins(book, saved.pins);
    return saved;
  }

  ContactBook _withSession(
    ContactBook book,
    ContactIntroductionSession session,
  ) => book.copyWith(
    sessions: [
      for (final s in book.sessions)
        if (s.id != session.id) s,
      session,
    ],
  );

  void _retryContext(
    ContactIntroductionSession existing,
    String input,
    List<ContactIntroductionPin> pins, {
    String? suggestion,
  }) {
    if (existing.phase != ContactIntroductionPhase.published ||
        existing.inputPacket != input ||
        jsonEncode(existing.pins.map((p) => p.toJson()).toList()) !=
            jsonEncode(pins.map((p) => p.toJson()).toList()) ||
        (suggestion != null && existing.suggestion != suggestion)) {
      throw const ContactFailure(
        'This request was already used with different or cancelled details. Ask for a new request.',
      );
    }
  }

  /// Scope-checked, serialized read; _run clears every loaded signing buffer.
  Future<ContactIntroductionOverview> overview() =>
      _run((current, epoch, book) async {
        final now = _now;
        return ContactIntroductionOverview(
          contacts: book.contacts,
          associations: book.associations,
          provenance: book.provenance,
          pendingRequests: List.unmodifiable([
            for (final s in book.sessions)
              if (s.role == ContactIntroductionRole.requester &&
                  s.phase == ContactIntroductionPhase.published &&
                  s.pins.length == 1 &&
                  now.isBefore(s.expiresAt))
                (
                  hash: s.requestHash,
                  label:
                      book.contacts
                          .where((c) => c.id == s.pins.single.contactId)
                          .firstOrNull
                          ?.label ??
                      'Unavailable contact',
                  expiresAt: s.expiresAt,
                ),
          ]),
          savedEndorsements: book.sessions
              .where(
                (s) =>
                    s.role == ContactIntroductionRole.introducer &&
                    s.phase == ContactIntroductionPhase.published &&
                    s.consentPacket != null &&
                    now.isBefore(s.expiresAt),
              )
              .map((s) => s.requestHash),
        );
      });

  Future<ReciprocalContactReview> reviewAssociation(
    String contactId,
    String outgoingIdentity,
  ) => _run((current, epoch, book) async {
    _clearReview();
    final peer = _contact(book, contactId);
    final pin = ContactIntroductionPin(
      contactId: contactId,
      identity: peer.identity,
      outgoingIdentity: contactIdentity(outgoingIdentity),
    );
    final signer = await _signer(current, epoch, pin);
    try {
      final review = ReciprocalContactReview._(
        current,
        peer,
        signer.identity,
        signer.address,
      );
      _setReview(review);
      return review;
    } finally {
      _release(signer);
    }
  });

  Future<void> confirmAssociation(
    ReciprocalContactReview review, {
    required bool independentlyVerified,
  }) => _run((current, epoch, book) async {
    _checkReview(book, review);
    if (!independentlyVerified) {
      throw const ContactFailure(
        'Independently confirm the exact identity your peer accepted and their identity shown here.',
      );
    }
    final peer = _contact(book, review.peer.id);
    if (review.scope != current ||
        jsonEncode(peer.toJson()) != jsonEncode(review.peer.toJson())) {
      throw const ContactFailure(
        'This contact changed. Repeat the independent check.',
      );
    }
    for (final a in book.associations) {
      if ((a.incomingContactId == peer.id &&
              a.outgoingIdentity != review.outgoingIdentity) ||
          (a.incomingContactId != peer.id &&
              a.outgoingIdentity == review.outgoingIdentity)) {
        throw const ContactFailure(
          'These keys already belong to another pairing. This experiment does not replace pairings.',
        );
      }
    }
    final signer = await _signer(
      current,
      epoch,
      ContactIntroductionPin(
        contactId: peer.id,
        identity: peer.identity,
        outgoingIdentity: review.outgoingIdentity,
      ),
    );
    try {
      _checkReview(book, review);
      await _commit(
        current,
        epoch,
        book.copyWith(
          associations: [
            for (final a in book.associations)
              if (a.incomingContactId != peer.id) a,
            ContactPeerAssociation(
              incomingContactId: peer.id,
              incomingIdentity: peer.identity,
              outgoingIdentity: signer.identity,
              independentlyConfirmedAt: _now,
            ),
          ],
        ),
      );
      _clearReview();
    } finally {
      _release(signer);
    }
  }, mutation: true);

  Future<String> createRequest(String aliceId, {required bool consent}) => _run(
    (current, epoch, book) async {
      if (!consent) {
        throw const ContactFailure(
          'Approve asking this contact for an introduction.',
        );
      }
      final pin = _pin(book, aliceId);
      final signer = await _signer(current, epoch, pin);
      try {
        final result = await gateway.ask(current, pin.identity, signer, _now);
        _check(current, epoch);
        if (_session(
              book,
              ContactIntroductionRole.requester,
              result.requestHash,
            ) !=
            null) {
          throw const ContactFailure(
            'This request already exists. Create a fresh request.',
          );
        }
        final session = ContactIntroductionSession(
          role: ContactIntroductionRole.requester,
          requestHash: result.requestHash,
          requestJson: result.request,
          expiresAt: result.expiresAt,
          phase: ContactIntroductionPhase.published,
          pins: [pin],
          outputPacket: result.packet,
        );
        // Cancellation must know this hash even while its write/readback waits.
        _live[ContactIntroductionRole.requester] = result.requestHash;
        try {
          await _commit(
            current,
            epoch,
            _withSession(book, session),
            expires: result.expiresAt,
          );
        } catch (_) {
          if (_live[ContactIntroductionRole.requester] == result.requestHash) {
            _live.remove(ContactIntroductionRole.requester);
          }
          rethrow;
        }
        _clearReview();
        return result.packet;
      } finally {
        _release(signer);
      }
    },
    mutation: true,
  );

  Future<DateTime> pendingRequestExpiry() => _run(
    (current, epoch, book) async =>
        _pending(book, ContactIntroductionRole.requester).expiresAt,
  );

  /// Explicitly select a durable invitation after unlocking/restarting. This
  /// restores only its request nonce, never a prior review or address proof.
  Future<IntroductionWireResult> resumeRequest(String hash) => _run((
    current,
    epoch,
    book,
  ) async {
    _clearReview();
    _addressCheck = null;
    final session = _session(book, ContactIntroductionRole.requester, hash);
    if (session == null ||
        session.phase != ContactIntroductionPhase.published ||
        session.pins.length != 1 ||
        session.outputPacket == null) {
      throw const ContactFailure('No pending invitation is available.');
    }
    _checkPins(book, session.pins);
    _liveTime(session.expiresAt);
    final pin = session.pins.single;
    // Verify our original signature from the intended introducer's perspective.
    final result = await gateway.verify(
      current,
      IntroductionWireStage.ask,
      pin.outgoingIdentity,
      pin.identity,
      session.outputPacket!,
      _now,
    );
    _check(current, epoch);
    if (result.request != session.requestJson ||
        result.requestHash != hash ||
        !result.expiresAt.isAtSameMomentAs(session.expiresAt)) {
      throw const ContactFailure('The saved invitation could not be verified.');
    }
    _live[ContactIntroductionRole.requester] = hash;
    return result;
  });

  Future<IntroductionReview> reviewAsk(
    String carolId,
    String bobId,
    String packet, {
    required String suggestedRecipient,
  }) => _run((current, epoch, book) async {
    _clearReview();
    if (carolId == bobId) {
      throw const ContactFailure('Choose two different contacts.');
    }
    final carol = _pin(book, carolId), bob = _pin(book, bobId);
    final result = await gateway.verify(
      current,
      IntroductionWireStage.ask,
      carol.identity,
      carol.outgoingIdentity,
      packet,
      _now,
    );
    _check(current, epoch);
    _liveTime(result.expiresAt);
    final existing = _session(
      book,
      ContactIntroductionRole.introducer,
      result.requestHash,
    );
    if (existing != null) {
      _retryContext(existing, result.packet, [
        carol,
        bob,
      ], suggestion: suggestedRecipient);
      if (existing.consentPacket != null) {
        throw const ContactFailure(
          'This introduction already has an endorsement. Reopen its consent review.',
        );
      }
    }
    final review = IntroductionReview._(
      scope: current,
      stage: IntroductionWireStage.ask,
      wire: result,
      pins: List.unmodifiable([carol, bob]),
      contacts: List.unmodifiable([
        _contact(book, carolId),
        _contact(book, bobId),
      ]),
      input: result.packet,
      suggestion: suggestedRecipient,
      retry: existing != null,
    );
    _setReview(review);
    return review;
  });

  Future<String> confirmOffer(
    IntroductionReview review, {
    required bool consent,
  }) => _run((current, epoch, book) async {
    _checkReview(book, review);
    if (!consent || review.stage != IntroductionWireStage.ask) {
      throw const ContactFailure('Approve this introduction request first.');
    }
    final carol = review.pins[0], bob = review.pins[1];
    final ask = await gateway.verify(
      current,
      IntroductionWireStage.ask,
      carol.identity,
      carol.outgoingIdentity,
      review.input,
      _now,
    );
    _check(current, epoch);
    _checkReview(book, review);
    final existing = _session(
      book,
      ContactIntroductionRole.introducer,
      ask.requestHash,
    );
    if (existing != null) {
      _retryContext(
        existing,
        ask.packet,
        review.pins,
        suggestion: review.suggestion,
      );
      if (existing.consentPacket != null) {
        throw const ContactFailure(
          'This introduction has already been endorsed.',
        );
      }
      _live[ContactIntroductionRole.introducer] = existing.requestHash;
      _clearReview();
      return existing.outputPacket!;
    }
    final signer = await _signer(current, epoch, bob);
    try {
      final result = await gateway.offer(
        current,
        ask.request,
        bob.identity,
        signer,
        review.suggestion!,
        _now,
      );
      _check(current, epoch);
      _checkReview(book, review);
      final session = ContactIntroductionSession(
        role: ContactIntroductionRole.introducer,
        requestHash: ask.requestHash,
        requestJson: ask.request,
        expiresAt: ask.expiresAt,
        phase: ContactIntroductionPhase.published,
        pins: review.pins,
        inputPacket: ask.packet,
        outputPacket: result.packet,
        offerJson: result.offer,
        suggestion: review.suggestion,
      );
      await _commit(
        current,
        epoch,
        _withSession(book, session),
        expires: ask.expiresAt,
      );
      _live[ContactIntroductionRole.introducer] = ask.requestHash;
      _clearReview();
      return result.packet;
    } finally {
      _release(signer);
    }
  }, mutation: true);

  Future<IntroductionReview> reviewOffer(
    String aliceId,
    String packet,
  ) => _run((current, epoch, book) async {
    _clearReview();
    final alice = _pin(book, aliceId);
    final result = await gateway.verify(
      current,
      IntroductionWireStage.offer,
      alice.identity,
      alice.outgoingIdentity,
      packet,
      _now,
    );
    _check(current, epoch);
    _liveTime(result.expiresAt);
    final existing = _session(
      book,
      ContactIntroductionRole.subject,
      result.requestHash,
    );
    String identity, address;
    if (existing != null) {
      _retryContext(existing, result.packet, [alice]);
      final reply = await gateway.verify(
        current,
        IntroductionWireStage.consent,
        alice.outgoingIdentity,
        alice.identity,
        existing.outputPacket!,
        _now,
        request: result.request,
        offer: result.offer,
      );
      _check(current, epoch);
      if (!book.signers.any((s) => s.identity == reply.identity)) {
        throw const ContactFailure(
          'The published signing record is unavailable. Do not restart this request.',
        );
      }
      final freshSigner = await _signer(
        current,
        epoch,
        ContactIntroductionPin(
          contactId: alice.contactId,
          identity: alice.identity,
          outgoingIdentity: reply.identity!,
        ),
      );
      _release(freshSigner);
      identity = reply.identity!;
      address = reply.address!;
    } else {
      final fresh = await directGateway.createIdentity();
      _heldSigners.add(fresh);
      try {
        _check(current, epoch);
        final freshAddress = await directGateway.freshAddress(current);
        _check(current, epoch);
        if (!await directGateway.validateAddress(current, freshAddress)) {
          throw const ContactFailure(
            'A receiving address could not be allocated for this network.',
          );
        }
        _check(current, epoch);
        _liveTime(result.expiresAt);
        _freshness(book, fresh.identity, freshAddress);
        _fresh = ContactSigner(
          identity: fresh.identity,
          secret: Uint8List.fromList(fresh.secret),
          address: freshAddress,
          sequence: 1,
        );
        identity = fresh.identity;
        address = freshAddress;
      } finally {
        _release(fresh);
      }
    }
    final review = IntroductionReview._(
      scope: current,
      stage: IntroductionWireStage.offer,
      wire: result,
      pins: List.unmodifiable([alice]),
      contacts: List.unmodifiable([_contact(book, aliceId)]),
      input: result.packet,
      suggestion: result.suggestion,
      identity: identity,
      address: address,
      retry: existing != null,
    );
    _setReview(review);
    return review;
  });

  void _freshness(ContactBook book, String identity, String address) {
    if (book.contacts.any(
          (c) => c.identity == identity || c.address == address,
        ) ||
        book.associations.any((a) => a.outgoingIdentity == identity) ||
        book.signers.any(
          (s) => s.identity == identity || s.address == address,
        )) {
      throw const ContactFailure(
        'These receiving details are already known. Start a fresh introduction.',
      );
    }
  }

  Future<String> confirmConsent(
    IntroductionReview review, {
    required bool consent,
  }) => _run((current, epoch, book) async {
    _checkReview(book, review);
    if (!consent || review.stage != IntroductionWireStage.offer) {
      throw const ContactFailure(
        'Approve sharing these new receiving details with Alice and the person being introduced.',
      );
    }
    final alice = review.pins.single;
    final offer = await gateway.verify(
      current,
      IntroductionWireStage.offer,
      alice.identity,
      alice.outgoingIdentity,
      review.input,
      _now,
    );
    _check(current, epoch);
    _checkReview(book, review);
    final existing = _session(
      book,
      ContactIntroductionRole.subject,
      offer.requestHash,
    );
    if (existing != null) {
      _retryContext(existing, offer.packet, review.pins);
      if (!review.retry) {
        throw const ContactFailure(
          'This request changed. Review its saved reply.',
        );
      }
      final freshSigner = await _signer(
        current,
        epoch,
        ContactIntroductionPin(
          contactId: alice.contactId,
          identity: alice.identity,
          outgoingIdentity: review.identity!,
        ),
      );
      _release(freshSigner);
      _check(current, epoch);
      _checkReview(book, review);
      _clearReview();
      return existing.outputPacket!;
    }
    final fresh = _fresh;
    if (fresh == null ||
        review.retry ||
        fresh.identity != review.identity ||
        fresh.address != review.address) {
      throw const ContactFailure(
        'The fresh receiving details are no longer available. Review the request again.',
      );
    }
    _freshness(book, fresh.identity, fresh.address);
    final signer = await _signer(current, epoch, alice);
    try {
      if (signer.address == fresh.address) {
        throw const ContactFailure(
          'This address is already used for your existing relationship. Start a fresh introduction.',
        );
      }
      final result = await gateway.consent(
        current,
        alice.identity,
        signer,
        fresh,
        offer.packet,
        _now,
      );
      _check(current, epoch);
      _checkReview(book, review);
      final stored = IntroductionStoredSigner(
        identity: fresh.identity,
        secret: Uint8List.fromList(fresh.secret),
        address: fresh.address,
        sequence: 1,
      );
      try {
        final session = ContactIntroductionSession(
          role: ContactIntroductionRole.subject,
          requestHash: offer.requestHash,
          requestJson: offer.request,
          expiresAt: offer.expiresAt,
          phase: ContactIntroductionPhase.published,
          pins: review.pins,
          inputPacket: offer.packet,
          outputPacket: result.packet,
          offerJson: offer.offer,
          endpointJson: result.endpoint,
          suggestion: offer.suggestion,
        );
        await _commit(
          current,
          epoch,
          _withSession(
            book,
            session,
          ).copyWith(signers: [...book.signers, stored]),
          expires: offer.expiresAt,
        );
        _clearReview();
        return result.packet;
      } finally {
        stored.clear();
      }
    } finally {
      _release(signer);
    }
  }, mutation: true);

  Future<IntroductionReview> reviewConsent(
    String packet, {
    required String suggestedContact,
  }) => _run((current, epoch, book) async {
    _clearReview();
    final session = _pending(book, ContactIntroductionRole.introducer);
    final bob = session.pins[1];
    final result = await gateway.verify(
      current,
      IntroductionWireStage.consent,
      bob.identity,
      bob.outgoingIdentity,
      packet,
      _now,
      request: session.requestJson,
      offer: session.offerJson,
    );
    _check(current, epoch);
    _liveTime(result.expiresAt);
    if (session.consentPacket != null &&
        (session.consentPacket != result.packet ||
            session.suggestion != suggestedContact)) {
      throw const ContactFailure(
        'This introduction already endorsed different details. Ask for a new request.',
      );
    }
    _freshness(book, result.identity!, result.address!);
    final review = IntroductionReview._(
      scope: current,
      stage: IntroductionWireStage.consent,
      wire: result,
      pins: session.pins,
      contacts: List.unmodifiable(
        session.pins.map((p) => _contact(book, p.contactId)),
      ),
      input: result.packet,
      suggestion: suggestedContact,
      identity: result.identity,
      address: result.address,
      retry: session.consentPacket != null,
    );
    _setReview(review);
    return review;
  });

  Future<String> confirmDelivery(
    IntroductionReview review, {
    required bool consent,
  }) => _run((current, epoch, book) async {
    _checkReview(book, review);
    if (!consent || review.stage != IntroductionWireStage.consent) {
      throw const ContactFailure(
        'Approve endorsing these exact receiving details.',
      );
    }
    final session = _pending(book, ContactIntroductionRole.introducer);
    if (session.requestHash != review.wire.requestHash) {
      throw const ContactFailure('The pending introduction changed.');
    }
    final carol = session.pins[0], bob = session.pins[1];
    final verified = await gateway.verify(
      current,
      IntroductionWireStage.consent,
      bob.identity,
      bob.outgoingIdentity,
      review.input,
      _now,
      request: session.requestJson,
      offer: session.offerJson,
    );
    _check(current, epoch);
    _checkReview(book, review);
    _freshness(book, verified.identity!, verified.address!);
    if (session.consentPacket != null) {
      if (session.consentPacket != review.input ||
          session.suggestion != review.suggestion) {
        throw const ContactFailure(
          'This request already endorsed different details.',
        );
      }
      await _verifySavedDelivery(current, epoch, session);
      _checkReview(book, review);
      _clearReview();
      return session.outputPacket!;
    }
    final signer = await _signer(current, epoch, carol);
    try {
      final result = await gateway.delivery(
        current,
        bob.identity,
        bob.outgoingIdentity,
        carol.identity,
        signer,
        session.requestJson,
        session.offerJson!,
        review.input,
        review.suggestion!,
        _now,
      );
      _check(current, epoch);
      _checkReview(book, review);
      await _commit(
        current,
        epoch,
        _withSession(
          book,
          session.copyWith(
            outputPacket: result.packet,
            consentPacket: review.input,
            endpointJson: result.endpoint,
            suggestion: review.suggestion,
          ),
        ),
        expires: session.expiresAt,
      );
      _clearReview();
      return result.packet;
    } finally {
      _release(signer);
    }
  }, mutation: true);

  /// Explicit recovery of an already signed endorsement, never a restoration
  /// of consent or a requester challenge. Confirming returns the same packet.
  Future<IntroductionReview> reviewSavedDelivery(String requestHash) => _run((
    current,
    epoch,
    book,
  ) async {
    _clearReview();
    final session = _session(
      book,
      ContactIntroductionRole.introducer,
      requestHash,
    );
    if (session == null ||
        session.phase != ContactIntroductionPhase.published ||
        session.pins.length != 2 ||
        session.consentPacket == null ||
        session.inputPacket == null ||
        session.offerJson == null ||
        session.outputPacket == null) {
      throw const ContactFailure(
        'No published endorsement is available for this request.',
      );
    }
    _checkPins(book, session.pins);
    _liveTime(session.expiresAt);
    final carol = session.pins[0], bob = session.pins[1];
    final ask = await gateway.verify(
      current,
      IntroductionWireStage.ask,
      carol.identity,
      carol.outgoingIdentity,
      session.inputPacket!,
      _now,
    );
    _check(current, epoch);
    if (ask.request != session.requestJson ||
        ask.requestHash != session.requestHash) {
      throw const ContactFailure(
        'The saved introduction context could not be verified.',
      );
    }
    final result = await gateway.verify(
      current,
      IntroductionWireStage.consent,
      bob.identity,
      bob.outgoingIdentity,
      session.consentPacket!,
      _now,
      request: session.requestJson,
      offer: session.offerJson,
    );
    _check(current, epoch);
    _freshness(book, result.identity!, result.address!);
    final delivered = await _verifySavedDelivery(current, epoch, session);
    if (delivered.endpoint != result.endpoint ||
        delivered.suggestion != session.suggestion) {
      throw const ContactFailure(
        'The saved endorsement differs from its approved receiving details.',
      );
    }
    final review = IntroductionReview._(
      scope: current,
      stage: IntroductionWireStage.consent,
      wire: result,
      pins: session.pins,
      contacts: List.unmodifiable(
        session.pins.map((p) => _contact(book, p.contactId)),
      ),
      input: session.consentPacket!,
      suggestion: delivered.suggestion,
      identity: result.identity,
      address: result.address,
      retry: true,
    );
    _live[ContactIntroductionRole.introducer] = session.requestHash;
    _setReview(review);
    return review;
  });

  Future<IntroductionWireResult> _verifySavedDelivery(
    ContactScope current,
    int epoch,
    ContactIntroductionSession session,
  ) async {
    final carol = session.pins[0];
    final result = await gateway.verify(
      current,
      IntroductionWireStage.delivery,
      carol.outgoingIdentity,
      carol.identity,
      session.outputPacket!,
      _now,
      request: session.requestJson,
    );
    _check(current, epoch);
    _liveTime(session.expiresAt);
    return result;
  }

  Future<IntroductionReview> reviewDelivery(String packet) => _run((
    current,
    epoch,
    book,
  ) async {
    _clearReview();
    final session = _pending(book, ContactIntroductionRole.requester);
    final alice = session.pins.single;
    final result = await gateway.verify(
      current,
      IntroductionWireStage.delivery,
      alice.identity,
      alice.outgoingIdentity,
      packet,
      _now,
      request: session.requestJson,
    );
    _check(current, epoch);
    _liveTime(result.expiresAt);
    if (book.contacts.any((c) => c.identity == result.identity) ||
        book.signers.any((s) => s.identity == result.identity) ||
        book.associations.any((a) => a.outgoingIdentity == result.identity)) {
      throw const ContactFailure(
        'This identity is already recorded. Use its existing contact.',
      );
    }
    final review = IntroductionReview._(
      scope: current,
      stage: IntroductionWireStage.delivery,
      wire: result,
      pins: session.pins,
      contacts: List.unmodifiable([_contact(book, alice.contactId)]),
      input: result.packet,
      suggestion: result.suggestion,
      identity: result.identity,
      address: result.address,
    );
    _setReview(review);
    return review;
  });

  /// An introduction authenticates provenance, not current address possession.
  /// Request a fresh response from the exact introduced relationship key before
  /// acceptance. This public nonce survives a review pause for app switching;
  /// invalidation (lock/account/network change) discards it. No approval survives.
  Future<ContactWireRequest> createAcceptanceRequest(
    IntroductionReview review, {
    required bool consent,
  }) => _run((current, epoch, book) async {
    _checkReview(book, review);
    if (!consent || review.stage != IntroductionWireStage.delivery) {
      throw const ContactFailure(
        'Approve checking this introduced identity first.',
      );
    }
    final session = _pending(book, ContactIntroductionRole.requester);
    if (session.requestHash != review.wire.requestHash) {
      throw const ContactFailure('The pending introduction changed.');
    }
    _addressCheck = null;
    final request = await directGateway.createRequest(
      current,
      review.identity,
      _now,
    );
    _check(current, epoch);
    _checkReview(book, review);
    _liveTime(request.expiresAt);
    if (request.subject != review.identity) {
      throw const ContactFailure('The address check has the wrong identity.');
    }
    _addressCheck = _IntroductionAddressCheck(
      current,
      review.input,
      request,
      review.wire.requestHash,
    );
    return request;
  });

  /// Recover only the already-reviewed transcript associated with our live
  /// address nonce. The imported reply must still be verified at acceptance.
  Future<String> pendingAcceptancePacket() => _run((
    current,
    epoch,
    book,
  ) async {
    final check = _addressCheck;
    if (check == null || check.scope != current) {
      throw const ContactFailure(
        'No fresh introduction address check is pending. Review the introduction and create one first.',
      );
    }
    final session = _pending(book, ContactIntroductionRole.requester);
    if (session.requestHash != check.requestHash) {
      throw const ContactFailure(
        'The selected invitation changed. Create a new address check for it.',
      );
    }
    _liveTime(check.request.expiresAt);
    return check.packet;
  });

  Future<VerifiedContact> acceptDelivery(
    IntroductionReview review, {
    required String label,
    required bool consent,
    String? freshResponse,
  }) => _run((current, epoch, book) async {
    _checkReview(book, review);
    if (!consent || review.stage != IntroductionWireStage.delivery) {
      throw const ContactFailure(
        'Choose a local label and approve this introduction before saving.',
      );
    }
    final session = _pending(book, ContactIntroductionRole.requester);
    if (session.requestHash != review.wire.requestHash) {
      throw const ContactFailure('The pending introduction changed.');
    }
    final check = _addressCheck;
    if (check == null ||
        check.scope != current ||
        check.packet != review.input ||
        freshResponse == null ||
        freshResponse.isEmpty ||
        utf8.encode(freshResponse).length > contactIntroductionPacketMaxBytes) {
      throw const ContactFailure(
        'Request and verify a fresh address response before accepting this contact.',
      );
    }
    _liveTime(check.request.expiresAt);
    final name = contactLabel(label), alice = session.pins.single;
    final result = await gateway.verify(
      current,
      IntroductionWireStage.delivery,
      alice.identity,
      alice.outgoingIdentity,
      review.input,
      _now,
      request: session.requestJson,
    );
    _check(current, epoch);
    _checkReview(book, review);
    final fresh = await directGateway.verify(
      current,
      check.request.json,
      freshResponse,
      _now,
    );
    _check(current, epoch);
    _checkReview(book, review);
    _liveTime(check.request.expiresAt);
    _liveTime(fresh.expiresAt);
    if (!identical(_addressCheck, check) ||
        fresh.identity != result.identity ||
        fresh.address != result.address ||
        fresh.sequence != result.sequence) {
      throw const ContactFailure(
        'The fresh response differs from the introduced receiving details. Ask for a new introduction.',
      );
    }
    if (book.contacts.any(
          (c) =>
              c.label.toLowerCase() == name.toLowerCase() ||
              c.identity == result.identity,
        ) ||
        book.signers.any((s) => s.identity == result.identity) ||
        book.associations.any((a) => a.outgoingIdentity == result.identity)) {
      throw const ContactFailure(
        'This identity or local label is already recorded. Keep the existing contact.',
      );
    }
    final accepted = VerifiedContact(
      id: _randomId(),
      label: name,
      identity: result.identity!,
      address: result.address!,
      sequence: result.sequence!,
      revision: 1,
    );
    final next = _withSession(
      book,
      session.copyWith(
        phase: ContactIntroductionPhase.accepted,
        inputPacket: result.packet,
        endpointJson: result.endpoint,
        contactId: accepted.id,
      ),
    );
    await _commit(
      current,
      epoch,
      next.copyWith(
        contacts: [...book.contacts, accepted],
        provenance: [
          ...book.provenance,
          ContactIntroductionProvenance(
            introducedContactId: accepted.id,
            introducerContactId: alice.contactId,
            introducerIdentity: alice.identity,
            requestHash: result.requestHash,
            endpointHash: result.endpointHash!,
            attestationHash: result.endorsementHash!,
            suggestion: result.suggestion,
            acceptedAt: _now,
          ),
        ],
      ),
      expires: check.request.expiresAt.isBefore(session.expiresAt)
          ? check.request.expiresAt
          : session.expiresAt,
    );
    _live.remove(ContactIntroductionRole.requester);
    _addressCheck = null;
    _clearReview();
    return accepted;
  }, mutation: true);

  Future<void> cancel() async {
    final current = _ready();
    final live = Map.of(_live);
    final review = _review;
    if (review is IntroductionReview) {
      live[switch (review.stage) {
            IntroductionWireStage.ask ||
            IntroductionWireStage.consent => ContactIntroductionRole.introducer,
            IntroductionWireStage.offer => ContactIntroductionRole.subject,
            IntroductionWireStage.delivery => ContactIntroductionRole.requester,
          }] =
          review.wire.requestHash;
    }
    invalidate(); // Suppress any in-flight result before waiting for the gate.
    final epoch = _epoch;
    await ContactMutationGate.run(
      current,
      () async {
        _check(current, epoch);
        final book = await repository.loadBook(current);
        _heldBooks.add(book);
        try {
          _check(current, epoch);
          var next = book.copyWith(
            sessions: [
              for (final s in book.sessions)
                if (live[s.role] == s.requestHash &&
                    s.phase != ContactIntroductionPhase.accepted)
                  s.copyWith(phase: ContactIntroductionPhase.cancelled)
                else
                  s,
            ],
          );
          if (review is IntroductionReview) {
            final role = switch (review.stage) {
              IntroductionWireStage.ask || IntroductionWireStage.consent =>
                ContactIntroductionRole.introducer,
              IntroductionWireStage.offer => ContactIntroductionRole.subject,
              IntroductionWireStage.delivery =>
                ContactIntroductionRole.requester,
            };
            if (_session(next, role, review.wire.requestHash) == null) {
              next = _withSession(
                next,
                ContactIntroductionSession(
                  role: role,
                  requestHash: review.wire.requestHash,
                  requestJson: review.wire.request,
                  expiresAt: review.wire.expiresAt,
                  phase: ContactIntroductionPhase.cancelled,
                  pins: review.pins,
                  inputPacket: review.input,
                ),
              );
            }
          }
          await _commit(current, epoch, next);
        } finally {
          book.clearSecrets();
          _heldBooks.remove(book);
        }
      },
      source: this,
      mutation: true,
    );
  }
}

String _randomId() => base64Url
    .encode(List<int>.generate(24, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
