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
import '../application/contact_exchange_controller.dart';
import '../application/contact_introduction_coordinator.dart';
import '../application/contact_introduction_providers.dart';
import '../application/contact_mutation_gate.dart';
import '../data/contact_introduction_gateway.dart';
import '../domain/contact_models.dart';

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
            onAccepted: () =>
                ref.read(contactExchangeProvider.notifier).reload(),
            onCopy: SensitiveClipboard.copyText,
          )
        : const Center(
            child: Text(
              'Unlock a test-network software account to use introductions.',
            ),
          );
    void back() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/contacts/exchange');
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
                      child: const Text('Back to contact exchange'),
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
  });
  final ContactIntroductionCoordinator coordinator;
  final Future<void> Function(String)? onCopy;
  final Future<void> Function()? onAccepted;

  @override
  State<ContactIntroductionView> createState() =>
      _ContactIntroductionViewState();
}

class _ContactIntroductionViewState extends State<ContactIntroductionView>
    with WidgetsBindingObserver {
  final _packet = TextEditingController(),
      _outgoing = TextEditingController(),
      _suggestion = TextEditingController(),
      _label = TextEditingController();
  ContactIntroductionOverview? _overview;
  IntroductionTask _task = IntroductionTask.pair;
  String? _peer, _subject, _output, _error, _notice, _outputInstruction;
  DateTime? _outputExpiresAt;
  Object? _review;
  bool _consent = false, _busy = false, _reloadNeeded = false;
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
  void dispose() {
    _epoch++;
    _expiry?.cancel();
    coordinator.pauseReview();
    WidgetsBinding.instance.removeObserver(this);
    ContactMutationGate.listeners.remove(_bookChanged);
    for (final c in [_packet, _outgoing, _suggestion, _label]) {
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
    coordinator.pauseReview();
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
      if (review is IntroductionReview) {
        _expiry?.cancel();
        _expiry = Timer(
          review.wire.expiresAt.difference(coordinator.clock()),
          _reset,
        );
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

  Future<void> _confirm() async {
    final review = _review;
    if (review is IntroductionReview) _outputExpiresAt = review.wire.expiresAt;
    if (_task == IntroductionTask.request) {
      _outputInstruction =
          'Send this request to ${_selectedContact?.label}. Keep this wallet unlocked while you wait for their endorsed reply.';
      _outputExpiresAt = coordinator.clock().add(const Duration(minutes: 15));
      _expiry?.cancel();
      _expiry = Timer(const Duration(minutes: 15), _reset);
      _output = await coordinator.createRequest(
        _selectedPeer,
        consent: _consent,
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
          _outputInstruction =
              'Send this offer to ${review.contacts.last.label}. Ask them to review and return their approval packet.';
          _output = await coordinator.confirmOffer(review, consent: _consent);
        case IntroductionWireStage.offer:
          _outputInstruction =
              'Send this approval to ${review.contacts.first.label}. They must review and endorse the exact details before forwarding them.';
          _output = await coordinator.confirmConsent(review, consent: _consent);
        case IntroductionWireStage.consent:
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
          );
          await widget.onAccepted?.call();
          _notice =
              '${contact.label} saved with the introducer’s attributed claim. Return to contact exchange to use normal Send.';
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
    final contacts =
        _overview?.contacts.where((c) => c.canPay).toList() ??
        <VerifiedContact>[];
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

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return SingleChildScrollView(
      padding: EdgeInsets.all(
        kAppFormFactor == AppFormFactor.mobile ? AppSpacing.sm : AppSpacing.md,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Introductions', style: AppTypography.headlineLarge),
              const SizedBox(height: AppSpacing.sm),
              _text('Experimental · test accounts only · no funds sent'),
              _text(
                'Exchange these packets through a trusted channel. First pair reciprocal contact keys. Carol asks Alice; Alice offers to Bob; Bob approves fresh details; Alice endorses; Carol accepts.',
              ),
              _text(
                'An introduction records the introducer’s claim, not proof of a person’s identity or spending authority. Alice can see Bob’s new receiving address. Contact keys are not recovered from the wallet seed.',
              ),
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
                      ? 'Requester'
                      : 'Accepted contact',
                  _peer,
                  (v) => _peer = v,
                ),
              if (_task == IntroductionTask.pair) ...[
                _text(
                  'Complete a direct exchange in both directions. Ask your peer for the exact key they accepted from you. Compare both full keys over an independently trusted channel; matching labels or addresses is not enough.',
                ),
                _field('Your outgoing key accepted by this peer', _outgoing),
              ],
              if (_task == IntroductionTask.offer)
                _picker('Contact to introduce', _subject, (v) => _subject = v),
              if ([
                IntroductionTask.offer,
                IntroductionTask.endorse,
              ].contains(_task)) ...[
                _text(
                  'Write a shareable suggestion (1–20 printable ASCII characters). It will be disclosed to recipients. Your private contact label is never filled in here.',
                ),
                _field(
                  _task == IntroductionTask.offer
                      ? 'Shareable requester suggestion'
                      : 'Shareable recipient suggestion',
                  _suggestion,
                ),
              ],
              if (![
                IntroductionTask.pair,
                IntroductionTask.request,
              ].contains(_task))
                _field(
                  'Packet received through your trusted channel',
                  _packet,
                  packet: true,
                ),
              if (_task == IntroductionTask.request) ...[
                _text(
                  'Authorize your selected contact to arrange an introduction. The request lasts 15 minutes. Locking, switching accounts or networks, or restarting invalidates it.',
                ),
                if (_selectedContact != null)
                  _detail(
                    'Selected introducer key',
                    _selectedContact!.identity,
                  ),
              ] else
                AppButton(
                  onPressed: !_busy ? () => unawaited(_run(_prepare)) : null,
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
                for (final contact in review.contacts) ...[
                  _detail('Local contact: ${contact.label}', contact.identity),
                ],
                _detail(
                  'Expires (UTC)',
                  review.wire.expiresAt.toUtc().toString(),
                ),
                if (review.suggestion != null)
                  _detail('Shareable suggestion', review.suggestion!),
                if (review.identity != null)
                  _detail('New recipient identity', review.identity!),
                if (review.address != null)
                  _detail(
                    'New receiving address (visible to the introducer)',
                    review.address!,
                  ),
                if (review.stage == IntroductionWireStage.delivery)
                  _field(
                    'Unique private label on this wallet',
                    _label,
                    label: true,
                  ),
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
                  onPressed: !_busy && _consent
                      ? () => unawaited(_run(_confirm))
                      : null,
                  child: Text(
                    _task == IntroductionTask.accept
                        ? 'Accept contact'
                        : _task == IntroductionTask.pair
                        ? 'Confirm pairing'
                        : 'Approve and create packet',
                  ),
                ),
              ],
              if (_output != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _text(_outputInstruction ?? 'Packet ready.'),
                AppButton(
                  onPressed: !_busy && widget.onCopy != null
                      ? () => unawaited(
                          _run(() async {
                            final epoch = _epoch;
                            await coordinator
                                .overview(); // Recheck scope and observed clock rollback.
                            if (epoch != _epoch ||
                                _output == null ||
                                _outputExpiresAt == null ||
                                !coordinator.clock().isBefore(
                                  _outputExpiresAt!,
                                )) {
                              _reset();
                              throw const ContactFailure(
                                'This packet is no longer available. Start a new review.',
                              );
                            }
                            await widget.onCopy!(_output!);
                            _notice = 'Packet copied.';
                          }),
                        )
                      : null,
                  child: const Text('Copy packet'),
                ),
              ],
              if (_notice != null) _text(_notice!),
              if (_error != null) _text(_error!),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                variant: AppButtonVariant.ghost,
                onPressed: !_busy
                    ? () => unawaited(
                        _run(() async {
                          await coordinator.cancel();
                          _reset();
                          _packet.clear();
                          _label.clear();
                        }),
                      )
                    : null,
                child: const Text('Cancel pending introduction'),
              ),
              if (_overview != null) ...[
                const Divider(),
                _text(
                  'Confirmed reciprocal pairings: ${_overview!.associations.length}',
                ),
                for (final hash in _overview!.savedEndorsements)
                  AppButton(
                    variant: AppButtonVariant.ghost,
                    onPressed: !_busy
                        ? () {
                            _reset();
                            setState(() => _task = IntroductionTask.endorse);
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
                _text(
                  'To resend your approved details as Bob, choose “Approve being introduced” and paste the same offer. Review and approve again; the coordinator returns only the saved packet.',
                ),
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
