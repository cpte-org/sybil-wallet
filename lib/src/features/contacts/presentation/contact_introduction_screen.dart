import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/sybil_widgets.dart';
import '../application/contact_exchange_controller.dart';
import '../application/contact_introduction_coordinator.dart';
import '../application/contact_introduction_providers.dart';
import '../application/contact_mutation_gate.dart';
import '../application/contact_ui_preferences.dart';
import '../data/contact_introduction_gateway.dart';
import '../domain/contact_models.dart';
import '../domain/contact_packet_kind.dart';
import 'contact_packet_delivery_controls.dart';
import 'contact_code_widgets.dart';
import 'contact_identity_code.dart';

class ContactIntroductionScreen extends ConsumerWidget {
  const ContactIntroductionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(contactScopeProvider);
    final available = ref.watch(contactExchangeAvailableProvider);
    final content = available && scope != null
        ? ContactIntroductionView(
            key: ValueKey(scope),
            coordinator: ref.watch(contactIntroductionCoordinatorProvider),
            advanced:
                ref.watch(contactAdvancedToolsProvider).asData?.value == true,
            onConnect: () => context.push('/contacts/exchange'),
            onAccepted: () =>
                ref.read(contactExchangeProvider.notifier).reload(),
            onCopy: SensitiveClipboard.copyText,
            inboxBuilder: (selected) => ContactPacketDeliveryControls.inbox(
              onSelected: selected,
              kinds: const {
                ContactPacketKind.ask,
                ContactPacketKind.offer,
                ContactPacketKind.consent,
                ContactPacketKind.delivery,
                ContactPacketKind.response,
              },
            ),
            sendBuilder: (packet, expires, contactId, identity) =>
                ContactPacketDeliveryControls.send(
                  packet: packet,
                  expiresAt: expires,
                  contactId: contactId,
                  recipientIdentity: identity,
                ),
          )
        : const Center(
            child: Text('Unlock your software account to use introductions.'),
          );
    void back() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/people');
      }
    }

    return kAppFormFactor == AppFormFactor.mobile
        ? Scaffold(
            backgroundColor: context.colors.background.window,
            body: SafeArea(
              child: Column(
                children: [
                  MobileTopNav.back(title: 'Introductions', onBack: back),
                  Expanded(child: content),
                ],
              ),
            ),
          )
        : AppDesktopShell(
            sidebar: const AppMainSidebar(),
            pane: AppDesktopPane(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  AppPaneToolbar(
                    leading: AppButton(
                      onPressed: back,
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.small,
                      child: const Text('Back to People'),
                    ),
                  ),
                  Expanded(child: content),
                ],
              ),
            ),
          );
  }
}

enum IntroductionTask {
  pair('Pair contact keys'),
  request('Ask for an introduction'),
  offer('Introduce two contacts'),
  consent('Approve being introduced'),
  endorse('Endorse approved details'),
  accept('Accept an introduction');

  const IntroductionTask(this.label);
  final String label;
}

/// Shared desktop/mobile presentation. All authority stays in the coordinator.
class ContactIntroductionView extends StatefulWidget {
  const ContactIntroductionView({
    super.key,
    required this.coordinator,
    this.onCopy,
    this.onAccepted,
    this.inboxBuilder,
    this.sendBuilder,
    this.advanced = false,
    this.onConnect,
  });
  final ContactIntroductionCoordinator coordinator;
  final bool advanced;
  final VoidCallback? onConnect;
  final Future<void> Function(String)? onCopy;
  final Future<void> Function()? onAccepted;
  final Widget Function(Future<void> Function(String))? inboxBuilder;
  final Widget Function(String, DateTime, String?, String?)? sendBuilder;

  @override
  State<ContactIntroductionView> createState() =>
      _ContactIntroductionViewState();
}

class _ContactIntroductionViewState extends State<ContactIntroductionView>
    with WidgetsBindingObserver {
  final _packet = TextEditingController(),
      _outgoing = TextEditingController(),
      _suggestion = TextEditingController(),
      _freshResponse = TextEditingController(),
      _label = TextEditingController();
  ContactIntroductionOverview? _overview;
  IntroductionTask _task = IntroductionTask.pair;
  String? _peer, _subject, _output, _error, _notice, _outputInstruction;
  DateTime? _outputExpiresAt;
  String? _outputContactId;
  String? _outputRecipientIdentity;
  Object? _review;
  bool _consent = false, _busy = false, _reloadNeeded = false;
  bool _guidedStarted = false, _openingInvitation = false;
  int _epoch = 0;
  Timer? _expiry;
  ContactIntroductionCoordinator get coordinator => widget.coordinator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ContactMutationGate.listeners.add(_bookChanged);
    unawaited(_run(_loadOverview));
  }

  @override
  void didUpdateWidget(covariant ContactIntroductionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.advanced != widget.advanced) {
      _reset();
      _guidedStarted = false;
      _openingInvitation = false;
      _task = IntroductionTask.pair;
      _packet.clear();
      _outgoing.clear();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _expiry?.cancel();
    coordinator.pauseReview();
    WidgetsBinding.instance.removeObserver(this);
    ContactMutationGate.listeners.remove(_bookChanged);
    for (final c in [_packet, _outgoing, _suggestion, _label, _freshResponse]) {
      c.dispose();
    }
    super.dispose();
  }

  void _bookChanged(ContactScope scope, Object? source) {
    if (scope == coordinator.scope() && !identical(source, coordinator)) {
      _reset();
      setState(() {
        _overview = null;
        _peer = null;
        _subject = null;
      });
      if (_busy) {
        _reloadNeeded = true;
      } else {
        unawaited(_run(_loadOverview));
      }
    }
  }

  Future<void> _loadOverview() async {
    final overview = await coordinator.overview();
    _overview = overview;
    if (!overview.contacts.any((c) => c.canPay && c.id == _peer)) {
      _peer = null;
    }
    if (!overview.contacts.any((c) => c.canPay && c.id == _subject)) {
      _subject = null;
    }
  }

  VerifiedContact? get _selectedContact =>
      _overview?.contacts.where((c) => c.canPay && c.id == _peer).firstOrNull;

  String get _approvalText {
    final review = _review;
    if (review is ReciprocalContactReview) {
      return 'I independently checked both exact keys with ${review.peer.label}.';
    }
    if (review is IntroductionReview) {
      final first = review.contacts.first.label;
      return switch (review.stage) {
        IntroductionWireStage.ask =>
          'I approve asking ${review.contacts.last.label} to be introduced to $first using this shareable suggestion.',
        IntroductionWireStage.offer =>
          'I approve sharing this fresh identity and address through $first with the person $first describes as “${review.suggestion}”.',
        IntroductionWireStage.consent =>
          'I endorse these exact details as ${review.suggestion} for $first, based on ${review.contacts.last.label}’s approval.',
        IntroductionWireStage.delivery =>
          'I accept these exact details based on $first’s claim that this is ${review.suggestion}.',
      };
    }
    return 'I authorize ${_selectedContact?.label ?? "the selected contact"} to arrange this introduction.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _reset();
      _packet.clear();
      _outgoing.clear();
      _suggestion.clear();
      _label.clear();
    }
  }

  void _reset() {
    _outputContactId = null;
    _outputRecipientIdentity = null;
    coordinator.pauseReview();
    _freshResponse.clear();
    _expiry?.cancel();
    _epoch++;
    if (mounted) {
      setState(() {
        _review = null;
        _consent = false;
        _output = null;
        _notice = null;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted || epoch != _epoch) {
        _review = null;
        _output = null;
        _consent = false;
        return;
      }
      final review = _review;
      DateTime? expires = review is IntroductionReview
          ? review.wire.expiresAt
          : null;
      if (_output != null &&
          _outputExpiresAt != null &&
          (expires == null || _outputExpiresAt!.isBefore(expires))) {
        expires = _outputExpiresAt;
      }
      if (expires != null) {
        _expiry?.cancel();
        _expiry = Timer(expires.difference(coordinator.clock()), _reset);
      }
    } catch (error) {
      if (mounted && epoch == _epoch) {
        _review = null;
        _consent = false;
        _output = null;
        _error = error is ContactFailure
            ? error.message
            : 'Could not complete this introduction. Review the details and try again.';
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
        if (_reloadNeeded) {
          _reloadNeeded = false;
          unawaited(_run(_loadOverview));
        }
      }
    }
  }

  String get _selectedPeer {
    if (_peer == null) {
      throw const ContactFailure('Choose an accepted contact first.');
    }
    return _peer!;
  }

  Future<void> _prepare() async {
    _consent = false;
    _output = null;
    _review = switch (_task) {
      IntroductionTask.pair => await coordinator.reviewAssociation(
        _selectedPeer,
        _outgoing.text,
      ),
      IntroductionTask.offer => await coordinator.reviewAsk(
        _selectedPeer,
        _subject ?? '',
        _packet.text,
        suggestedRecipient: _suggestion.text,
      ),
      IntroductionTask.consent => await coordinator.reviewOffer(
        _selectedPeer,
        _packet.text,
      ),
      IntroductionTask.endorse => await coordinator.reviewConsent(
        _packet.text,
        suggestedContact: _suggestion.text,
      ),
      IntroductionTask.accept => await coordinator.reviewDelivery(_packet.text),
      IntroductionTask.request => null,
    };
  }

  Future<void> _importPacket(String packet) {
    if (_busy) return Future.value();
    _reset();
    return _run(() async {
      final kind = contactPacketKind(packet);
      if (kind == ContactPacketKind.response) {
        final epoch = _epoch;
        final original = await coordinator.pendingAcceptancePacket();
        if (!mounted || epoch != _epoch) return;
        _task = IntroductionTask.accept;
        _packet.text = original;
        _freshResponse.text = packet;
      } else {
        _task = switch (kind) {
          ContactPacketKind.ask => IntroductionTask.offer,
          ContactPacketKind.offer => IntroductionTask.consent,
          ContactPacketKind.consent => IntroductionTask.endorse,
          ContactPacketKind.delivery => IntroductionTask.accept,
          _ => throw const ContactFailure(
            'This packet is not an introduction.',
          ),
        };
        _packet.text = packet;
        _peer = null;
        _subject = null;
      }
      _guidedStarted = true;
      _openingInvitation = false;
      _notice =
          'Invitation opened. Review the people and details before approving.';
    });
  }

  Future<void> _confirm() async {
    final review = _review;
    if (review is IntroductionReview) _outputExpiresAt = review.wire.expiresAt;
    if (_task == IntroductionTask.request) {
      _outputContactId = _selectedPeer;
      _outputRecipientIdentity = _selectedContact?.identity;
      _outputInstruction =
          'Send this invitation to ${_selectedContact?.label}. You can close the wallet and resume the saved invitation later.';
      _output = await coordinator.createRequest(
        _selectedPeer,
        consent: _consent,
      );
      _outputExpiresAt = await coordinator.pendingRequestExpiry();
      _expiry?.cancel();
      _expiry = Timer(
        _outputExpiresAt!.difference(coordinator.clock()),
        _reset,
      );
    } else if (review is ReciprocalContactReview) {
      await coordinator.confirmAssociation(
        review,
        independentlyVerified: _consent,
      );
      _notice = 'Exact keys paired. This does not prove a person’s identity.';
    } else if (review is IntroductionReview) {
      switch (review.stage) {
        case IntroductionWireStage.ask:
          _outputContactId = review.contacts.last.id;
          _outputRecipientIdentity = review.contacts.last.identity;
          _outputInstruction =
              'Send this offer to ${review.contacts.last.label}. Ask them to review and return their approval packet.';
          _output = await coordinator.confirmOffer(review, consent: _consent);
        case IntroductionWireStage.offer:
          _outputContactId = review.contacts.first.id;
          _outputRecipientIdentity = review.contacts.first.identity;
          _outputInstruction =
              'Send this approval to ${review.contacts.first.label}. They must review and endorse the exact details before forwarding them.';
          _output = await coordinator.confirmConsent(review, consent: _consent);
        case IntroductionWireStage.consent:
          _outputContactId = review.contacts.first.id;
          _outputRecipientIdentity = review.contacts.first.identity;
          _outputInstruction =
              'Send this endorsed introduction to ${review.contacts.first.label}. They must choose a local label and explicitly accept it.';
          _output = await coordinator.confirmDelivery(
            review,
            consent: _consent,
          );
        case IntroductionWireStage.delivery:
          final contact = await coordinator.acceptDelivery(
            review,
            label: _label.text,
            consent: _consent,
            freshResponse: _freshResponse.text,
          );
          await widget.onAccepted?.call();
          _notice =
              '${contact.label} is now in People. Their connection records who introduced you.';
          if (!widget.advanced) _guidedStarted = false;
      }
    }
    _review = null;
    _consent = false;
    await _loadOverview();
  }

  Widget _text(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s),
    child: Text(
      text,
      style: AppTypography.bodyMedium.copyWith(
        color: context.colors.text.primary,
      ),
    ),
  );
  Widget _detail(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(title),
        SelectableText(value, style: AppTypography.bodySmall),
      ],
    ),
  );
  Widget _field(
    String title,
    TextEditingController controller, {
    bool packet = false,
    bool label = false,
  }) => Padding(
    key: ObjectKey(controller),
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: AppTextField(
      label: title,
      controller: controller,
      enabled: !_busy,
      minLines: packet ? 3 : 1,
      maxLines: packet ? 5 : 1,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: [LengthLimitingTextInputFormatter(packet ? 32769 : 256)],
      onChanged: (_) {
        if (label) {
          setState(() {
            _consent = false;
          });
        } else {
          _reset();
        }
      },
    ),
  );
  Widget _picker(String title, String? value, ValueChanged<String?> changed) {
    final contacts = widget.advanced || _task == IntroductionTask.pair
        ? (_overview?.contacts.where((c) => c.canPay).toList() ??
              <VerifiedContact>[])
        : _pairedContacts;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DropdownButtonFormField<String>(
        initialValue: contacts.any((c) => c.id == value) ? value : null,
        isExpanded: true,
        style: AppTypography.bodyMedium,
        decoration: InputDecoration(
          labelText: title,
          labelStyle: AppTypography.bodyMedium,
        ),
        items: [
          for (final c in contacts)
            DropdownMenuItem(
              value: c.id,
              child: Text(
                c.label,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium,
              ),
            ),
        ],
        onChanged: _busy
            ? null
            : (v) {
                _reset();
                setState(() => changed(v));
              },
      ),
    );
  }

  List<Widget> _identityDetails(IntroductionReview review) => [
    for (final contact in review.contacts)
      _detail('Local contact: ${contact.label}', contact.identity),
    _detail('Expires (UTC)', review.wire.expiresAt.toUtc().toString()),
    if (review.suggestion != null)
      _detail('Shareable suggestion', review.suggestion!),
    if (review.identity != null)
      _detail('New recipient identity', review.identity!),
    if (review.address != null)
      _detail(
        'New receiving address (visible to the introducer)',
        review.address!,
      ),
  ];

  Future<void> _copyOutput() async {
    final epoch = _epoch;
    await coordinator.overview();
    if (epoch != _epoch ||
        _output == null ||
        _outputExpiresAt == null ||
        !coordinator.clock().isBefore(_outputExpiresAt!)) {
      _reset();
      throw const ContactFailure(
        'This code is no longer available. Start a new review.',
      );
    }
    await widget.onCopy!(_output!);
    _notice = 'Code copied.';
  }

  List<VerifiedContact> get _pairedContacts =>
      _overview?.contacts
          .where(
            (contact) =>
                contact.canPay &&
                _overview!.associations.any(
                  (pair) =>
                      pair.incomingContactId == contact.id &&
                      pair.incomingIdentity == contact.identity,
                ),
          )
          .toList() ??
      [];

  void _start(IntroductionTask task) {
    _reset();
    setState(() {
      _task = task;
      _guidedStarted = true;
      _openingInvitation = false;
      _packet.clear();
      _suggestion.clear();
      _label.clear();
      _peer = null;
      _subject = null;
    });
  }

  Widget _choice(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback? action,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SybilCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: action,
        enabled: action != null,
      ),
    ),
  );

  Widget _pairingNotice(int pairs) => SybilCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pairs == 0 ? 'Connect before introducing' : 'Introduce two people',
          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          pairs == 0
              ? 'Introductions need a private connection checked in both directions.'
              : 'To introduce two people, both private connections must be checked in both directions.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Checking compares the exact keys you and your peer accepted from each other. Saving a name and address does not need it.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton(
              onPressed: widget.onConnect,
              child: const Text('Connect privately'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _guidedOverview() {
    final pairs = _pairedContacts.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pairs == 0 && _overview != null) ...[
          _pairingNotice(pairs),
          const SizedBox(height: 16),
        ],
        if (pairs > 0)
          _choice(
            'Ask someone I know',
            'Let a connected person introduce you.',
            Icons.person_add_alt_1_outlined,
            _busy ? null : () => _start(IntroductionTask.request),
          ),
        if (pairs >= 2)
          _choice(
            'Introduce two people',
            'Start with the request one of them shared.',
            Icons.people_outline,
            _busy ? null : () => _start(IntroductionTask.offer),
          ),
        if (_overview?.contacts.any((c) => c.canPay) ?? false)
          _choice(
            'Check a connection',
            'Confirm a private connection in both directions.',
            Icons.verified_user_outlined,
            _busy ? null : () => _start(IntroductionTask.pair),
          ),
        _choice(
          'Open an invitation',
          'Scan a code or paste what they shared.',
          Icons.qr_code_scanner,
          _busy
              ? null
              : () => setState(() => _openingInvitation = !_openingInvitation),
        ),
        if (_openingInvitation)
          ContactCodeInput(
            key: const ValueKey('introduction-invitation-input'),
            title: 'Open an invitation',
            enabled: !_busy,
            onRead: _importPacket,
          ),
        if (pairs == 1) ...[const SizedBox(height: 12), _pairingNotice(pairs)],
      ],
    );
  }

  String get _stepTitle => switch (_task) {
    IntroductionTask.pair => 'Check a connection',
    IntroductionTask.request => 'Ask someone I know',
    IntroductionTask.offer => 'Introduce two people',
    IntroductionTask.consent => 'Review your introduction',
    IntroductionTask.endorse => 'Share the approved introduction',
    IntroductionTask.accept => 'Meet your new contact',
  };

  @override
  Widget build(BuildContext context) {
    final review = _review;
    final active = widget.advanced || _guidedStarted;
    return SingleChildScrollView(
      padding: EdgeInsets.all(
        kAppFormFactor == AppFormFactor.mobile ? AppSpacing.sm : AppSpacing.md,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SybilPageHeader(
                title: 'Introductions',
                subtitle: 'Meet through someone you know.',
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_busy) const LinearProgressIndicator(),
              if (!active || widget.advanced) _guidedOverview(),
              if (!widget.advanced && active) ...[
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          _reset();
                          setState(() {
                            _guidedStarted = false;
                            _openingInvitation = false;
                          });
                        },
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('All introductions'),
                ),
                Text(_stepTitle, style: AppTypography.headlineSmall),
                const SizedBox(height: 16),
              ],
              if (widget.inboxBuilder != null)
                widget.inboxBuilder!(_importPacket),
              if (active) ...[
                if (widget.advanced)
                  DropdownButtonFormField<IntroductionTask>(
                    key: ValueKey(_task),
                    initialValue: _task,
                    isExpanded: true,
                    style: AppTypography.bodyMedium,
                    decoration: const InputDecoration(
                      labelText: 'Your next step',
                      labelStyle: AppTypography.bodyMedium,
                    ),
                    items: [
                      for (final task in IntroductionTask.values)
                        DropdownMenuItem(value: task, child: Text(task.label)),
                    ],
                    onChanged: _busy
                        ? null
                        : (task) {
                            if (task != null) {
                              _reset();
                              setState(() {
                                _task = task;
                                _packet.clear();
                                _suggestion.clear();
                                _label.clear();
                              });
                            }
                          },
                  ),
                const SizedBox(height: AppSpacing.sm),
                if ([
                  IntroductionTask.pair,
                  IntroductionTask.request,
                  IntroductionTask.offer,
                  IntroductionTask.consent,
                ].contains(_task))
                  _picker(
                    _task == IntroductionTask.offer
                        ? 'Person who asked'
                        : _task == IntroductionTask.request
                        ? 'Who would you like to ask?'
                        : _task == IntroductionTask.pair
                        ? 'Who are you checking with?'
                        : 'Person who shared this',
                    _peer,
                    (v) {
                      _peer = v;
                      if (_task == IntroductionTask.pair) _outgoing.clear();
                    },
                  ),
                if (_task == IntroductionTask.pair) ...[
                  if (widget.advanced)
                    _text(
                      'Complete a direct exchange in both directions. Ask your peer for the exact key they accepted from you. Compare both full keys over an independently trusted channel; matching labels or addresses is not enough.',
                    )
                  else
                    _text(
                      'Ask your peer to open People, choose you, and open Check connection. Scan their code in person or paste it from an independently trusted channel. You will review both full keys before confirming.',
                    ),
                  if (widget.advanced)
                    _field('Your outgoing key accepted by this peer', _outgoing)
                  else ...[
                    if (_selectedContact != null)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Show the code you accepted'),
                        children: [
                          ContactIdentityCode(
                            key: ValueKey(_selectedContact!.identity),
                            identity: _selectedContact!.identity,
                            personLabel: _selectedContact!.label,
                            enabled: !_busy,
                            onCopy: widget.onCopy,
                          ),
                        ],
                      ),
                    ContactCodeInput(
                      key: ValueKey('connection-check-$_peer'),
                      title: _outgoing.text.isEmpty
                          ? 'The exact key your peer accepted from you'
                          : 'Replace the code your peer shared',
                      enabled: !_busy && _selectedContact != null,
                      onRead: (value) async {
                        _reset();
                        _outgoing.clear();
                        try {
                          final identity = readContactIdentityCode(value);
                          setState(() {
                            _outgoing.text = identity;
                            _error = null;
                          });
                        } on FormatException {
                          setState(() {});
                          rethrow;
                        }
                      },
                    ),
                    if (_outgoing.text.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Full connection key ready to review'),
                    ],
                    const SizedBox(height: 16),
                  ],
                ],
                if (_task == IntroductionTask.offer)
                  _picker(
                    'Contact to introduce',
                    _subject,
                    (v) => _subject = v,
                  ),
                if ([
                  IntroductionTask.offer,
                  IntroductionTask.endorse,
                ].contains(_task)) ...[
                  _text(
                    'Choose a name to share with both people (up to 20 characters). Your private contact names stay private.',
                  ),
                  _field(
                    _task == IntroductionTask.offer
                        ? 'Name to share for the person asking'
                        : 'Name to share for the person introduced',
                    _suggestion,
                  ),
                ],
                if (![
                  IntroductionTask.pair,
                  IntroductionTask.request,
                ].contains(_task))
                  if (widget.advanced)
                    _field(
                      'Packet received through your trusted channel',
                      _packet,
                      packet: true,
                    )
                  else if (_packet.text.isEmpty)
                    ContactCodeInput(
                      title: 'Open their invitation',
                      enabled: !_busy,
                      onRead: _importPacket,
                    )
                  else
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Invitation ready to review'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _reset();
                                  setState(() => _packet.clear());
                                },
                          child: const Text('Replace'),
                        ),
                      ],
                    ),
                if (_task == IntroductionTask.request) ...[
                  _text(
                    'This invitation lasts 30 days. You will review the introduction and check the receiving address before adding anyone.',
                  ),
                  if (_selectedContact != null && widget.advanced)
                    _detail(
                      'Selected introducer key',
                      _selectedContact!.identity,
                    ),
                ] else
                  AppButton(
                    onPressed:
                        !_busy &&
                            (widget.advanced ||
                                (_task == IntroductionTask.pair
                                    ? _outgoing.text.isNotEmpty
                                    : _packet.text.isNotEmpty))
                        ? () => unawaited(_run(_prepare))
                        : null,
                    child: const Text('Review details'),
                  ),
                if (review is ReciprocalContactReview) ...[
                  _detail('Their accepted incoming key', review.peer.identity),
                  _detail(
                    'Your outgoing key they accepted',
                    review.outgoingIdentity,
                  ),
                ],
                if (review is IntroductionReview) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _text(
                    review.retry
                        ? 'Review to resend the same saved packet. No new identity or signature is created.'
                        : 'Review the exact introduction details',
                  ),
                  if (widget.advanced)
                    ..._identityDetails(review)
                  else ...[
                    SybilCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final contact in review.contacts)
                            _text('Person you know: ${contact.label}'),
                          if (review.suggestion != null)
                            _text('Name shared: ${review.suggestion}'),
                          if (review.address != null)
                            const Text(
                              'The introducer can see the new receiving address.',
                            ),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Connection details'),
                            children: _identityDetails(review),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (review.stage == IntroductionWireStage.delivery) ...[
                    _text(
                      'Ask this person to confirm their current receiving address. Share the check below, then open their reply.',
                    ),
                    AppButton(
                      onPressed: _busy
                          ? null
                          : () => unawaited(
                              _run(() async {
                                final request = await coordinator
                                    .createAcceptanceRequest(
                                      review,
                                      consent: true,
                                    );
                                _freshResponse.clear();
                                _consent = false;
                                _output = request.json;
                                _outputContactId = null;
                                _outputRecipientIdentity = null;
                                _outputExpiresAt = request.expiresAt;
                                _outputInstruction =
                                    'Send this address check to the introduced person, directly or through your introducer. Paste their signed response below. It expires at ${request.expiresAt.toUtc()}.';
                              }),
                            ),
                      child: const Text('Create fresh address check'),
                    ),
                    if (widget.advanced)
                      _field(
                        'Fresh signed address response',
                        _freshResponse,
                        packet: true,
                        label: true,
                      )
                    else
                      ContactCodeInput(
                        title: _freshResponse.text.isEmpty
                            ? 'Open their address-check reply'
                            : 'Replace address-check reply',
                        enabled: !_busy,
                        onRead: (value) async {
                          setState(() {
                            _freshResponse.text = value;
                            _consent = false;
                          });
                        },
                      ),
                    _field('Name in your People', _label, label: true),
                  ],
                ],
                if (review != null || _task == IntroductionTask.request) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _consent,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _consent = v ?? false;
                          }),
                    title: Text(_approvalText, style: AppTypography.bodyMedium),
                  ),
                  AppButton(
                    onPressed:
                        !_busy &&
                            _consent &&
                            (_task != IntroductionTask.accept ||
                                _freshResponse.text.isNotEmpty)
                        ? () => unawaited(_run(_confirm))
                        : null,
                    child: Text(
                      _task == IntroductionTask.accept
                          ? 'Accept contact'
                          : _task == IntroductionTask.pair
                          ? 'Confirm pairing'
                          : widget.advanced
                          ? 'Approve and create packet'
                          : 'Approve and continue',
                    ),
                  ),
                ],
                if (_output != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _text(_outputInstruction ?? 'Packet ready.'),
                  if (widget.sendBuilder != null && _outputExpiresAt != null)
                    widget.sendBuilder!(
                      _output!,
                      _outputExpiresAt!,
                      _outputContactId,
                      _outputRecipientIdentity,
                    ),
                  if (widget.advanced)
                    AppButton(
                      onPressed: !_busy && widget.onCopy != null
                          ? () => unawaited(_run(_copyOutput))
                          : null,
                      child: const Text('Copy packet'),
                    )
                  else
                    ContactCodeOutput(
                      key: ValueKey(_output),
                      data: _output!,
                      title: 'Share this code',
                      enabled: !_busy,
                      onCopy: widget.onCopy == null
                          ? null
                          : (_) => _run(_copyOutput),
                    ),
                ],
              ],
              if (_notice != null) _text(_notice!),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: AppTypography.bodyMedium.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              if (active)
                AppButton(
                  variant: AppButtonVariant.ghost,
                  onPressed: !_busy
                      ? () => unawaited(
                          _run(() async {
                            await coordinator.cancel();
                            _reset();
                            _packet.clear();
                            _label.clear();
                            _guidedStarted = false;
                          }),
                        )
                      : null,
                  child: const Text('Cancel pending introduction'),
                ),
              if (_overview != null) ...[
                if (widget.advanced ||
                    _overview!.pendingRequests.isNotEmpty ||
                    _overview!.savedEndorsements.isNotEmpty)
                  const Divider(),
                if (widget.advanced)
                  _text(
                    'Confirmed reciprocal pairings: ${_overview!.associations.length}',
                  ),
                for (final request in _overview!.pendingRequests)
                  AppButton(
                    constrainContent: true,
                    variant: AppButtonVariant.ghost,
                    onPressed: _busy
                        ? null
                        : () {
                            _reset();
                            setState(() {
                              _task = IntroductionTask.accept;
                              _guidedStarted = true;
                            });
                            unawaited(
                              _run(() async {
                                final resumed = await coordinator.resumeRequest(
                                  request.hash,
                                );
                                _output = resumed.packet;
                                _outputExpiresAt = resumed.expiresAt;
                                _outputInstruction =
                                    'Invitation resumed. Paste the endorsed reply to review it, or copy this original invitation to resend. A fresh address check is still required before acceptance.';
                              }),
                            );
                          },
                    child: Text(
                      widget.advanced
                          ? 'Resume invitation via ${request.label} · ${request.expiresAt.toUtc()}'
                          : 'Continue introduction through ${request.label}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                for (final hash in _overview!.savedEndorsements)
                  AppButton(
                    variant: AppButtonVariant.ghost,
                    onPressed: !_busy
                        ? () {
                            _reset();
                            setState(() {
                              _task = IntroductionTask.endorse;
                              _guidedStarted = true;
                            });
                            unawaited(
                              _run(() async {
                                _review = await coordinator.reviewSavedDelivery(
                                  hash,
                                );
                              }),
                            );
                          }
                        : null,
                    child: const Text('Review saved endorsement to resend'),
                  ),

                if (widget.advanced)
                  for (final p in _overview!.provenance) ...[
                    _detail(
                      'Historical introduction for ${_overview!.contacts.where((c) => c.id == p.introducedContactId).firstOrNull?.label ?? "removed contact"}',
                      'Introducer key at acceptance: ${p.introducerIdentity}\nAccepted: ${p.acceptedAt.toUtc()}\nSuggestion: ${p.suggestion ?? "none"}',
                    ),
                  ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
