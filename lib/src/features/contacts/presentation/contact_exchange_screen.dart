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
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/familiar_widgets.dart';
import '../application/contact_ui_preferences.dart';
import 'contact_code_widgets.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../send/models/send_prefill_args.dart';
import '../application/contact_exchange_controller.dart';
import '../domain/contact_models.dart';
import '../domain/contact_packet_kind.dart';
import 'contact_packet_delivery_controls.dart';
import 'contact_availability.dart';

export '../domain/contact_models.dart';

/// The wallet adapter preserves the authenticated recipient through Send.
class ContactExchangeScreen extends ConsumerWidget {
  const ContactExchangeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(contactExchangeProvider.notifier);
    final state = ref.watch(contactExchangeProvider);
    final available = ref.watch(contactExchangeAvailableProvider);
    final scope = ref.watch(contactScopeProvider);
    final advanced =
        ref.watch(contactAdvancedToolsProvider).asData?.value == true;
    void back() {
      controller.cancelTransient();
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/people');
      }
    }

    final content = ContactExchangeView(
      // Never carry partially entered exchanges across account or network switches.
      key: ValueKey(scope),
      advanced: advanced,
      inboxBuilder: (selected) => ContactPacketDeliveryControls.inbox(
        onSelected: selected,
        kinds: const {ContactPacketKind.request, ContactPacketKind.response},
      ),
      sendBuilder: (packet, expires, contactId, identity) =>
          ContactPacketDeliveryControls.send(
            packet: packet,
            expiresAt: expires,
            contactId: contactId,
            recipientIdentity: identity,
          ),
      state: available
          ? state
          : ContactExchangeState(
              unavailableReason:
                  ref.watch(contactUnavailableMessageProvider) ??
                  state.unavailableReason ??
                  'Contact exchange is available only for unlocked software accounts on testnet or regtest.',
            ),
      callbacks: ContactExchangeCallbacks(
        onDone: () {
          controller.cancelTransient();
          context.go('/people');
        },
        onBackup: () {
          controller.cancelTransient();
          context.push('/contacts/backup');
        },
        onReload: controller.reload,
        onIntroductions: () {
          controller.cancelTransient();
          context.push('/contacts/introductions');
        },
        onStartRequest: controller.startRequest,
        onPreviewResponse: controller.previewResponse,
        onAcceptResponse: controller.acceptResponse,
        onSuspend: controller.suspendContact,
        onPrepareShare: controller.prepareShare,
        onConfirmShare: controller.confirmShare,
        onCancel: controller.cancelTransient,
        onPauseReview: controller.pauseExchange,
        onClearError: controller.clearError,
        onCopy: (text, message) async {
          await SensitiveClipboard.copyText(text);
          if (context.mounted) showAppToast(context, message);
        },
        onSend: (id) {
          try {
            final recipient = controller.recipientFor(id);
            context.push(
              '/send',
              extra: SendPrefillArgs(
                id: 'contact-${DateTime.now().microsecondsSinceEpoch}',
                source: 'contact',
                address: recipient.address,
                label: recipient.label,
                contactRecipient: recipient,
              ),
            );
          } catch (_) {
            showAppToast(
              context,
              'This contact changed. Refresh and review it before sending.',
            );
          }
        },
      ),
    );
    final Widget shell;
    if (kAppFormFactor == AppFormFactor.mobile) {
      shell = Scaffold(
        backgroundColor: context.colors.background.window,
        body: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: 'Connect privately',
                onBack: back,
                titleStyle: AppTypography.headlineSmall,
              ),
              Expanded(child: content),
            ],
          ),
        ),
      );
    } else {
      shell = AppDesktopShell(
        sidebar: const AppMainSidebar(),
        pane: AppDesktopPane(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              AppPaneToolbar(
                leading: Row(
                  children: [
                    AppButton(
                      onPressed: back,
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.small,
                      child: const Text('Back to People'),
                    ),
                    if (advanced)
                      AppButton(
                        onPressed: available
                            ? () => context.push('/contacts/delivery')
                            : null,
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.small,
                        child: const Text('Private delivery'),
                      ),
                  ],
                ),
              ),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) controller.cancelTransient();
      },
      child: AppToastHost(child: shell),
    );
  }
}

class ContactExchangeCallbacks {
  const ContactExchangeCallbacks({
    this.onReload,
    this.onBackup,
    this.onIntroductions,
    this.onStartRequest,
    this.onPreviewResponse,
    this.onAcceptResponse,
    this.onSuspend,
    this.onPrepareShare,
    this.onConfirmShare,
    this.onCancel,
    this.onClearError,
    this.onSend,
    this.onCopy,
    this.onPauseReview,
    this.onDone,
  });
  final VoidCallback? onIntroductions, onBackup;
  final Future<void> Function()? onReload;
  final Future<void> Function({String? contactId})? onStartRequest;
  final Future<void> Function(String)? onPreviewResponse;
  final Future<void> Function({
    required String label,
    required bool independentlyVerified,
  })?
  onAcceptResponse;
  final Future<void> Function(String)? onSuspend;
  final Future<void> Function(String)? onPrepareShare;
  final Future<void> Function({required bool consent})? onConfirmShare;
  final VoidCallback? onCancel, onClearError;
  final ValueChanged<String>? onSend;
  final Future<void> Function(String text, String successMessage)? onCopy;
  final VoidCallback? onPauseReview, onDone;
}

/// A deterministic presentation surface: no wallet, storage or Rust calls.
class ContactExchangeView extends StatefulWidget {
  const ContactExchangeView({
    super.key,
    required this.state,
    this.callbacks = const ContactExchangeCallbacks(),
    this.now,
    this.inboxBuilder,
    this.sendBuilder,
    this.advanced = false,
  });
  final bool advanced;
  final ContactExchangeState state;
  final ContactExchangeCallbacks callbacks;
  final DateTime Function()? now;
  final Widget Function(Future<void> Function(String))? inboxBuilder;
  final Widget Function(String, DateTime, String?, String?)? sendBuilder;

  @override
  State<ContactExchangeView> createState() => _ContactExchangeViewState();
}

class _ContactExchangeViewState extends State<ContactExchangeView>
    with WidgetsBindingObserver {
  final _response = TextEditingController();
  final _incomingRequest = TextEditingController();
  final _label = TextEditingController();
  bool _verified = false, _shareConsent = false, _working = false;
  bool _responseTooLong = false, _requestTooLong = false;
  int _importEpoch = 0;
  bool _backgrounded = false;
  String? _confirmSuspend, _localError, _savedLabel;
  late final Timer _expiryTimer;
  static const _limit = 32768;
  static const _lengthMessage =
      'Use a contact exchange of at most 32,768 characters.';

  ContactExchangeState get data => widget.state;
  ContactExchangeCallbacks get actions => widget.callbacks;
  DateTime get now => widget.now?.call() ?? DateTime.now();
  bool get enabled =>
      data.available &&
      !data.loading &&
      !data.busy &&
      !_working &&
      !_backgrounded;
  bool get transient =>
      data.request != null ||
      data.candidate != null ||
      data.shareReview != null ||
      data.response != null;
  bool expired(DateTime deadline) => !now.isBefore(deadline);
  Future<void> _importPacket(String packet) async {
    if (!enabled) return;
    final epoch = ++_importEpoch;
    actions.onPauseReview?.call();
    // Let the controller's review-clearing update settle before pre-filling.
    // Account/lock changes dispose or invalidate this view in the meantime.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || epoch != _importEpoch || !data.available) return;
    setState(() {
      _verified = false;
      _shareConsent = false;
      _response.clear();
      _incomingRequest.clear();
      _responseTooLong = false;
      _requestTooLong = false;
      switch (contactPacketKind(packet)) {
        case ContactPacketKind.request:
          _incomingRequest.text = packet;
        case ContactPacketKind.response:
          _response.text = packet;
        default:
          _localError = 'This packet is not a direct contact exchange.';
      }
    });
  }

  String? candidateKey(ContactCandidateView? value) => value == null
      ? null
      : '${value.identity}|${value.address}|${value.previousAddress}|${value.sequence}|${value.expiresAt.toIso8601String()}';
  String? shareKey(ContactShareReview? value) => value == null
      ? null
      : '${value.identity}|${value.address}|${value.previousAddress}|${value.audience}|${value.expiresAt.toIso8601String()}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _label.text = data.candidate?.label ?? '';
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          (data.request != null ||
              data.candidate != null ||
              data.shareReview != null ||
              data.responseExpiresAt != null)) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant ContactExchangeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!data.available) {
      _importEpoch++;
      _response.clear();
      _incomingRequest.clear();
      _label.clear();
      _verified = false;
      _shareConsent = false;
      _confirmSuspend = null;
      _responseTooLong = false;
      _requestTooLong = false;
      _localError = null;
      _savedLabel = null;
    }
    if (oldWidget.advanced != widget.advanced) {
      _importEpoch++;
      _verified = false;
      _shareConsent = false;
    }
    if (candidateKey(oldWidget.state.candidate) !=
        candidateKey(data.candidate)) {
      _verified = false;
      _label.text = data.candidate?.label ?? '';
    }
    if (shareKey(oldWidget.state.shareReview) != shareKey(data.shareReview)) {
      _shareConsent = false;
    }
    if (oldWidget.state.request?.json != data.request?.json) {
      _response.clear();
      _responseTooLong = false;
    }
    if (oldWidget.state.shareReview != null && data.shareReview == null) {
      _incomingRequest.clear();
      _requestTooLong = false;
    }
    if (_confirmSuspend != null &&
        !data.contacts.any((c) => c.id == _confirmSuspend && c.canPay)) {
      _confirmSuspend = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _importEpoch++;
      setState(() {
        _backgrounded = true;
        _verified = false;
        _shareConsent = false;
      });
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _backgrounded = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer.cancel();
    _response.dispose();
    _incomingRequest.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() operation) async {
    if (!enabled) return;
    setState(() {
      _working = true;
      _localError = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        setState(
          () => _localError = error is ContactFailure
              ? error.message
              : 'Could not complete this exchange. Review it and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void cancel() {
    _response.clear();
    _incomingRequest.clear();
    _label.clear();
    setState(() {
      _verified = false;
      _shareConsent = false;
      _localError = null;
      _responseTooLong = false;
      _requestTooLong = false;
    });
    actions.onCancel?.call();
  }

  String deadline(DateTime value) {
    final utc = value.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)} UTC';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.advanced) return _guided(context);
    final candidate = data.candidate;
    final request = data.request;
    final share = data.shareReview;
    return SingleChildScrollView(
      key: const Key('contacts-scroll'),
      padding: EdgeInsets.all(
        kAppFormFactor == AppFormFactor.mobile ? AppSpacing.sm : AppSpacing.md,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.s,
                children: [
                  if (actions.onBackup != null)
                    AppButton(
                      onPressed: enabled ? actions.onBackup : null,
                      child: const Text('Contact backup'),
                    ),
                  Text(
                    'Contact exchange',
                    style: AppTypography.headlineLarge.copyWith(
                      color: context.colors.text.accent,
                    ),
                  ),
                  AppButton(
                    key: const Key('contacts-reload'),
                    onPressed: enabled && actions.onReload != null
                        ? () => unawaited(run(actions.onReload!))
                        : null,
                    size: AppButtonSize.small,
                    variant: AppButtonVariant.ghost,
                    child: const Text('Refresh contacts'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s),
              _paragraph(
                context,
                'Experimental · test accounts only',
                accent: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (!data.available)
                _Notice(
                  title: 'Contact exchange is unavailable',
                  text:
                      data.unavailableReason ??
                      'Use an unlocked software account on testnet or regtest.',
                ),
              if (data.available) ...[
                if (widget.inboxBuilder != null)
                  widget.inboxBuilder!(_importPacket),
                if (actions.onIntroductions != null)
                  AppButton(
                    onPressed: enabled ? actions.onIntroductions : null,
                    variant: AppButtonVariant.ghost,
                    child: const Text('Introductions and reciprocal setup'),
                  ),
                const _Notice(
                  title: 'A direct exchange, with no funds sent',
                  text:
                      'Use a trusted channel to exchange requests and replies. Your local labels stay on this device. Experimental contact keys are not recovered from your wallet seed.',
                ),
                if (data.error != null || _localError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _Notice(
                    title: 'Exchange needs attention',
                    text: _localError ?? data.error!,
                    isError: true,
                    action: AppButton(
                      onPressed: data.busy
                          ? null
                          : () {
                              setState(() => _localError = null);
                              actions.onClearError?.call();
                            },
                      size: AppButtonSize.small,
                      variant: AppButtonVariant.ghost,
                      child: const Text('Dismiss'),
                    ),
                  ),
                ],
                if (data.loading) ...[
                  const SizedBox(height: AppSpacing.md),
                  const _Notice(
                    title: 'Loading contacts',
                    text: 'Reading the contact book for this account.',
                  ),
                ] else ...[
                  if (data.busy || _working) ...[
                    const SizedBox(height: AppSpacing.s),
                    Semantics(
                      liveRegion: true,
                      child: _paragraph(context, 'Preparing the exchange…'),
                    ),
                  ],
                  if (candidate != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _candidateCard(context, candidate),
                  ] else if (request != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _requestCard(context, request),
                  ],
                  if (share != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _shareCard(context, share),
                  ],
                  if (data.response != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _responseCard(context, data.response!),
                  ],
                  if (!transient && data.contacts.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    ExpansionTile(
                      title: const Text('Your connected people'),
                      children: [_contactsCard(context)],
                    ),
                  ],
                  if (!transient) ...[
                    const SizedBox(height: AppSpacing.md),
                    _startCard(context),
                  ],
                  if (transient || data.contacts.isEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    ExpansionTile(
                      title: const Text('Your connected people'),
                      children: [_contactsCard(context)],
                    ),
                  ],
                ],
              ],
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _readCode(String code) async {
    if (!enabled) return;
    final epoch = ++_importEpoch;
    actions.onPauseReview?.call();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || epoch != _importEpoch || !data.available) return;
    switch (contactPacketKind(code)) {
      case ContactPacketKind.request:
        if (actions.onPrepareShare != null) {
          await run(() => actions.onPrepareShare!(code));
        }
      case ContactPacketKind.response:
        if (data.request == null) {
          setState(
            () => _localError =
                'Start an invitation on this device first, then open their reply.',
          );
        } else if (actions.onPreviewResponse != null) {
          await run(() => actions.onPreviewResponse!(code));
        }
      default:
        setState(
          () => _localError =
              'This is not a contact invitation or reply. Introduction codes open in Settings → Contact options → Introductions.',
        );
    }
  }

  Future<void> _savePerson(ContactCandidateView candidate) async {
    final label = _label.text.trim();
    await run(
      () => actions.onAcceptResponse!(
        label: label,
        independentlyVerified: _verified,
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        !data.available ||
        data.error != null ||
        data.candidate != null) {
      return;
    }
    final saved = data.contacts
        .where(
          (person) =>
              person.identity == candidate.identity &&
              person.address == candidate.address &&
              person.label == label &&
              person.canPay,
        )
        .firstOrNull;
    if (saved != null) setState(() => _savedLabel = saved.label);
  }

  String _validFor(DateTime expires) {
    final seconds = expires.difference(now).inSeconds;
    if (seconds <= 0) return 'Expired. Start again for a fresh code.';
    if (seconds < 60) return 'Valid for less than a minute.';
    final minutes = (seconds / 60).ceil();
    return 'Valid for $minutes ${minutes == 1 ? 'minute' : 'minutes'}.';
  }

  Widget _guided(BuildContext context) {
    final candidate = data.candidate,
        request = data.request,
        share = data.shareReview;
    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        key: const Key('contacts-scroll'),
        padding: EdgeInsets.all(
          kAppFormFactor == AppFormFactor.mobile ? 20 : 32,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FamiliarPageHeader(
                  title: 'Connect privately',
                  subtitle: 'A person in your wallet. A name you choose.',
                ),
                const SizedBox(height: 24),
                if (!data.available)
                  _Notice(
                    title: 'Private connections are not available here',
                    text:
                        data.unavailableReason ??
                        'Use an unlocked software account on the test network.',
                  )
                else if (data.loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  if (data.error != null || _localError != null) ...[
                    _Notice(
                      title: 'Let’s try that again',
                      text: _localError ?? data.error!,
                      isError: true,
                      action: Wrap(
                        spacing: 8,
                        children: [
                          if (data.error != null && actions.onReload != null)
                            TextButton(
                              onPressed: enabled
                                  ? () => unawaited(run(actions.onReload!))
                                  : null,
                              child: const Text('Retry'),
                            ),
                          TextButton(
                            onPressed: data.busy
                                ? null
                                : () {
                                    setState(() => _localError = null);
                                    actions.onClearError?.call();
                                  },
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_savedLabel != null && !transient)
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.check_circle_outline, size: 44),
                          const SizedBox(height: 16),
                          _heading(context, '$_savedLabel is in People'),
                          _paragraph(
                            context,
                            'Their address is saved. Future address changes will need your approval.',
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: actions.onDone,
                            child: const Text('Open People'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _savedLabel = null),
                            child: const Text('Connect with someone else'),
                          ),
                        ],
                      ),
                    )
                  else if (candidate != null)
                    _guidedCandidate(context, candidate)
                  else if (share != null)
                    _guidedShare(context, share)
                  else if (data.response != null)
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _heading(context, 'Send your reply back'),
                          _paragraph(
                            context,
                            'They scan or paste this reply to add you. To add them too, exchange another invitation in the other direction.',
                          ),
                          const SizedBox(height: 20),
                          ContactCodeOutput(
                            data: data.response!,
                            title: 'Your reply',
                            enabled:
                                enabled &&
                                data.responseExpiresAt != null &&
                                !expired(data.responseExpiresAt!),
                            onCopy: actions.onCopy == null
                                ? null
                                : (text) =>
                                      actions.onCopy!(text, 'Reply copied'),
                          ),
                          if (data.responseExpiresAt != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _validFor(data.responseExpiresAt!),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 16),
                          _cancelButton(label: 'Done'),
                        ],
                      ),
                    )
                  else if (request != null)
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _heading(
                            context,
                            request.isUpdate
                                ? 'Ask for their latest address'
                                : 'Invite them to connect',
                          ),
                          _paragraph(
                            context,
                            'They scan or paste your invitation, review their address, and give you a reply.',
                          ),
                          const SizedBox(height: 20),
                          ContactCodeOutput(
                            data: request.json,
                            title: 'Your invitation',
                            enabled: enabled && !expired(request.expiresAt),
                            onCopy: actions.onCopy == null
                                ? null
                                : (text) => actions.onCopy!(
                                    text,
                                    'Invitation copied',
                                  ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _validFor(request.expiresAt),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
                          ContactCodeInput(
                            title: 'Have their reply?',
                            onRead: _readCode,
                            enabled: enabled && !expired(request.expiresAt),
                          ),
                          const SizedBox(height: 12),
                          _cancelButton(label: 'Cancel invitation'),
                        ],
                      ),
                    )
                  else ...[
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.qr_code_2, size: 56),
                          const SizedBox(height: 20),
                          _heading(context, 'Start with an invitation'),
                          _paragraph(
                            context,
                            'Show them your code or copy it into a trusted conversation. Then open their reply and save their name.',
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const Key('contacts-new-request'),
                            onPressed: enabled && actions.onStartRequest != null
                                ? () => run(() => actions.onStartRequest!())
                                : null,
                            icon: const Icon(Icons.qr_code),
                            label: const Text('Show invitation'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _Card(
                      child: ContactCodeInput(
                        title: 'They already have a code?',
                        onRead: _readCode,
                        enabled: enabled,
                      ),
                    ),
                  ],
                  if (data.busy || _working)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'No payment is sent. Private connections are currently available on test accounts.',
                    style: AppTypography.bodySmall.copyWith(
                      color: context.colors.text.secondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _guidedCandidate(
    BuildContext context,
    ContactCandidateView candidate,
  ) {
    final checkedUpdate =
        candidate.isUpdate && !candidate.requiresRecoveryCheck;
    final labelError = validateAddressBookLabel(_label.text.trim());
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            candidate.isUpdate
                ? 'Review their new address'
                : 'Who are you adding?',
          ),
          _paragraph(
            context,
            checkedUpdate
                ? 'This update is signed by the contact you already know.'
                : candidate.requiresRecoveryCheck
                ? 'Your backup may be out of date. Check this fresh code with the person before enabling payments.'
                : 'Only continue if you got this code directly from the person or through a channel you trust.',
          ),
          const SizedBox(height: 20),
          AppTextField(
            key: const Key('contacts-label'),
            label: 'Your name for them',
            controller: _label,
            enabled: enabled,
            hintText: 'Mara',
            messageText: _label.text.isEmpty ? null : labelError,
            tone: _label.text.isNotEmpty && labelError != null
                ? AppTextFieldTone.destructive
                : AppTextFieldTone.neutral,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Receiving address and connection details'),
            initiallyExpanded:
                candidate.requiresRecoveryCheck || candidate.isUpdate,
            children: [
              if (candidate.previousAddress != null)
                _value(context, 'Previous address', candidate.previousAddress!),
              _value(context, 'Receiving address', candidate.address),
              _value(context, 'Full contact identity', candidate.identity),
              _paragraph(context, 'Address revision ${candidate.sequence}'),
            ],
          ),
          const SizedBox(height: 12),
          _Consent(
            key: const Key('contacts-verify-acceptance'),
            checked: _verified,
            enabled: enabled && !expired(candidate.expiresAt),
            label: checkedUpdate
                ? 'I reviewed this receiving address update.'
                : 'I checked this person and their receiving address.',
            onChanged: (value) => setState(() => _verified = value),
          ),
          const SizedBox(height: 16),
          AppButton(
            key: const Key('contacts-accept-response'),
            expand: true,
            onPressed:
                enabled &&
                    !expired(candidate.expiresAt) &&
                    _verified &&
                    labelError == null &&
                    actions.onAcceptResponse != null
                ? () => _savePerson(candidate)
                : null,
            child: Text(
              candidate.isUpdate ? 'Save address update' : 'Add to People',
            ),
          ),
          _cancelButton(),
          Text(
            _validFor(candidate.expiresAt),
            style: AppTypography.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _guidedShare(BuildContext context, ContactShareReview share) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          share.isUpdate ? 'Share your latest address?' : 'Let them add you?',
        ),
        _paragraph(
          context,
          'This shares a receiving address with the person who sent the invitation. It gives no access to your wallet or funds.',
        ),
        const SizedBox(height: 20),
        ExpansionTile(
          title: const Text('What you’ll share'),
          children: [
            _value(context, 'Receiving address', share.address),
            _value(context, 'Your contact identity for them', share.identity),
            _value(context, 'Invitation from', share.audience),
          ],
        ),
        const SizedBox(height: 16),
        _Consent(
          key: const Key('contacts-share-consent'),
          checked: _shareConsent,
          enabled: enabled && !expired(share.expiresAt),
          label: 'I want to share my receiving address with this person.',
          onChanged: (value) => setState(() => _shareConsent = value),
        ),
        const SizedBox(height: 16),
        AppButton(
          key: const Key('contacts-confirm-share'),
          expand: true,
          onPressed:
              enabled &&
                  !expired(share.expiresAt) &&
                  _shareConsent &&
                  actions.onConfirmShare != null
              ? () => run(() => actions.onConfirmShare!(consent: _shareConsent))
              : null,
          child: const Text('Create my reply'),
        ),
        _cancelButton(),
        Text(
          _validFor(share.expiresAt),
          style: AppTypography.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _startCard(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, 'Add someone by direct exchange'),
        _paragraph(
          context,
          'Share a request with them, then bring their reply here. You choose what to call them.',
        ),
        const SizedBox(height: AppSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            key: const Key('contacts-new-request'),
            onPressed: enabled && actions.onStartRequest != null
                ? () => unawaited(run(() => actions.onStartRequest!()))
                : null,
            child: const Text('Create contact request'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _divider(context),
        const SizedBox(height: AppSpacing.md),
        _heading(context, 'Reply to someone’s request'),
        _paragraph(
          context,
          'Paste their request and review what you will share.',
        ),
        const SizedBox(height: AppSpacing.s),
        _payloadInput(
          key: const Key('contacts-share-input'),
          label: 'Contact request from the other person',
          controller: _incomingRequest,
          tooLong: _requestTooLong,
          onReject: () => setState(() => _requestTooLong = true),
          onChanged: (_) => setState(() => _requestTooLong = false),
        ),
        const SizedBox(height: AppSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            key: const Key('contacts-prepare-share'),
            variant: AppButtonVariant.secondary,
            onPressed:
                enabled &&
                    !_requestTooLong &&
                    _incomingRequest.text.trim().isNotEmpty &&
                    actions.onPrepareShare != null
                ? () => unawaited(
                    run(
                      () =>
                          actions.onPrepareShare!(_incomingRequest.text.trim()),
                    ),
                  )
                : null,
            child: const Text('Review receiving address'),
          ),
        ),
      ],
    ),
  );

  Widget _requestCard(
    BuildContext context,
    ContactRequestView request,
  ) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          request.isUpdate
              ? 'Request an updated address'
              : 'Your contact request',
        ),
        if (request.label != null) _paragraph(context, 'For ${request.label}'),
        _paragraph(
          context,
          expired(request.expiresAt)
              ? 'This request expired. Cancel it and create another.'
              : 'Share this request through your trusted channel. It expires at ${deadline(request.expiresAt)}.',
        ),
        const SizedBox(height: AppSpacing.s),
        ExpansionTile(
          title: const Text('Show request contents'),
          children: [_payloadOutput('Request to share', request.json)],
        ),
        if (widget.sendBuilder != null)
          widget.sendBuilder!(
            request.json,
            request.expiresAt,
            request.contactId,
            request.identity,
          ),
        const SizedBox(height: AppSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            key: const Key('contacts-copy-request'),
            onPressed:
                enabled && !expired(request.expiresAt) && actions.onCopy != null
                ? () => unawaited(
                    run(
                      () => actions.onCopy!(
                        request.json,
                        'Contact request copied',
                      ),
                    ),
                  )
                : null,
            variant: AppButtonVariant.secondary,
            child: const Text('Copy request'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _payloadInput(
          key: const Key('contacts-response-input'),
          label: 'Signed reply from the other person',
          controller: _response,
          tooLong: _responseTooLong,
          onReject: () => setState(() => _responseTooLong = true),
          onChanged: (_) => setState(() => _responseTooLong = false),
        ),
        const SizedBox(height: AppSpacing.s),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            AppButton(
              key: const Key('contacts-preview-response'),
              onPressed:
                  enabled &&
                      !expired(request.expiresAt) &&
                      !_responseTooLong &&
                      _response.text.trim().isNotEmpty &&
                      actions.onPreviewResponse != null
                  ? () => unawaited(
                      run(
                        () => actions.onPreviewResponse!(_response.text.trim()),
                      ),
                    )
                  : null,
              child: const Text('Review signed reply'),
            ),
            _cancelButton(),
          ],
        ),
      ],
    ),
  );

  Widget _candidateCard(BuildContext context, ContactCandidateView candidate) {
    final labelError = validateAddressBookLabel(_label.text);
    final isExpired = expired(candidate.expiresAt);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            candidate.isUpdate
                ? 'Review the address update'
                : 'Verify this contact',
          ),
          _paragraph(
            context,
            candidate.requiresRecoveryCheck
                ? 'This contact came from a backup that may be outdated. Independently compare the complete identity and fresh receiving address with the person before enabling payments.'
                : candidate.isUpdate
                ? 'This reply uses the recognized contact identity. Review the receiving address before accepting the update.'
                : 'A valid signature identifies a key, not a person. Compare the complete identity and receiving address in person or through an independently authenticated channel.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _value(
            context,
            'Full contact identity · compare every character',
            candidate.identity,
          ),
          if (candidate.previousAddress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _value(
              context,
              'Previously accepted address',
              candidate.previousAddress!,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _value(
            context,
            candidate.isUpdate
                ? 'New receiving address'
                : 'Receiving address to accept',
            candidate.address,
          ),
          const SizedBox(height: AppSpacing.s),
          _paragraph(
            context,
            'Address revision ${candidate.sequence} · reply expires ${deadline(candidate.expiresAt)}',
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            key: const Key('contacts-label'),
            label: 'Your local label',
            controller: _label,
            enabled: enabled,
            hintText: 'For example, Alice',
            messageText: _label.text.isEmpty
                ? 'Choose 1–20 characters. This label is not shared.'
                : labelError,
            tone: _label.text.isNotEmpty && labelError != null
                ? AppTextFieldTone.destructive
                : AppTextFieldTone.neutral,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Consent(
            key: const Key('contacts-verify-acceptance'),
            checked: _verified,
            enabled: enabled && !isExpired,
            label: candidate.isUpdate && !candidate.requiresRecoveryCheck
                ? 'I reviewed this recognized identity and its receiving address update.'
                : 'I independently compared this complete identity and receiving address with the person.',
            onChanged: (value) => setState(() => _verified = value),
          ),
          if (isExpired) ...[
            const SizedBox(height: AppSpacing.s),
            const _Notice(
              title: 'Reply expired',
              text: 'Cancel this exchange and request a fresh reply.',
              isError: true,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              AppButton(
                key: const Key('contacts-accept-response'),
                onPressed:
                    enabled &&
                        !isExpired &&
                        _verified &&
                        labelError == null &&
                        actions.onAcceptResponse != null
                    ? () => unawaited(
                        run(
                          () => actions.onAcceptResponse!(
                            label: _label.text.trim(),
                            independentlyVerified: _verified,
                          ),
                        ),
                      )
                    : null,
                child: Text(
                  candidate.isUpdate
                      ? 'Accept address update'
                      : 'Accept contact',
                ),
              ),
              _cancelButton(),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          _paragraph(
            context,
            'The signature binds this address to the contact key. It does not prove control of the funds received there.',
          ),
        ],
      ),
    );
  }

  Widget _shareCard(BuildContext context, ContactShareReview share) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          share.isUpdate
              ? 'Share an updated receiving address'
              : 'Review what you will share',
        ),
        _paragraph(
          context,
          'Check who requested this reply. Sharing confirms only the receiving address below; it sends no funds and grants no spending or viewing access.',
        ),
        const SizedBox(height: AppSpacing.sm),
        _value(context, 'Requesting contact identity', share.audience),
        const SizedBox(height: AppSpacing.sm),
        _value(
          context,
          'Your contact identity for this relationship',
          share.identity,
        ),
        if (share.previousAddress != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _value(context, 'Previously shared address', share.previousAddress!),
        ],
        const SizedBox(height: AppSpacing.sm),
        _value(context, 'Fresh receiving address to share', share.address),
        const SizedBox(height: AppSpacing.s),
        _paragraph(
          context,
          'Reply expires ${deadline(share.expiresAt)}. Send the reply only to this requester using your trusted channel.',
        ),
        const SizedBox(height: AppSpacing.sm),
        _Consent(
          key: const Key('contacts-share-consent'),
          checked: _shareConsent,
          enabled: enabled && !expired(share.expiresAt),
          label:
              'I intend to share this receiving address with this requesting identity.',
          onChanged: (value) => setState(() => _shareConsent = value),
        ),
        if (expired(share.expiresAt)) ...[
          const SizedBox(height: AppSpacing.s),
          const _Notice(
            title: 'Request expired',
            text: 'Cancel this exchange and ask for a fresh request.',
            isError: true,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            AppButton(
              key: const Key('contacts-confirm-share'),
              onPressed:
                  enabled &&
                      !expired(share.expiresAt) &&
                      _shareConsent &&
                      actions.onConfirmShare != null
                  ? () => unawaited(
                      run(
                        () => actions.onConfirmShare!(consent: _shareConsent),
                      ),
                    )
                  : null,
              child: const Text('Create signed reply'),
            ),
            _cancelButton(),
          ],
        ),
      ],
    ),
  );

  Widget _responseCard(BuildContext context, String response) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, 'Your signed reply is ready'),
        _paragraph(
          context,
          'Return this reply through the same trusted channel. The other person must verify and accept your identity and address. They are not automatically added to your contacts.',
        ),
        const SizedBox(height: AppSpacing.s),
        ExpansionTile(
          title: const Text('Show reply contents'),
          children: [_payloadOutput('Signed reply to share', response)],
        ),
        if (widget.sendBuilder != null && data.responseExpiresAt != null)
          widget.sendBuilder!(response, data.responseExpiresAt!, null, null),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            AppButton(
              key: const Key('contacts-copy-response'),
              onPressed: enabled && actions.onCopy != null
                  ? () => unawaited(
                      run(
                        () => actions.onCopy!(response, 'Signed reply copied'),
                      ),
                    )
                  : null,
              child: const Text('Copy signed reply'),
            ),
            _cancelButton(label: 'Done'),
          ],
        ),
      ],
    ),
  );

  Widget _contactsCard(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, 'Saved contacts'),
        _paragraph(
          context,
          'Send uses the address you explicitly accepted, even while the contact is offline. Requesting an update never silently changes that address.',
        ),
        if (data.contacts.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _paragraph(
            context,
            'No authenticated contacts yet. Your ordinary address-book entries remain in Contacts.',
          ),
        ],
        for (final contact in data.contacts) ...[
          const SizedBox(height: AppSpacing.sm),
          _divider(context),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                contact.label,
                style: AppTypography.headlineSmall.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              _Status(contact.status),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          _value(context, 'Accepted identity', contact.identity),
          const SizedBox(height: AppSpacing.s),
          _value(context, 'Accepted receiving address', contact.address),
          const SizedBox(height: AppSpacing.s),
          if (!contact.canPay)
            _paragraph(context, switch (contact.status) {
              ContactTrustStatus.suspended =>
                'Suspended: payments and address updates are blocked. A new signature from this key cannot remove the restriction.',
              ContactTrustStatus.restored =>
                'Restored contact: request a fresh address response and independently verify it before enabling payments.',
              ContactTrustStatus.retired =>
                'Retired identity: this record is retained as history and cannot be used for payment.',
              ContactTrustStatus.accepted => '',
            }),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              AppButton(
                key: Key('contacts-send-${contact.id}'),
                onPressed: enabled && contact.canPay && actions.onSend != null
                    ? () => actions.onSend!(contact.id)
                    : null,
                size: AppButtonSize.medium,
                child: const Text('Send'),
              ),
              AppButton(
                key: Key('contacts-update-${contact.id}'),
                onPressed:
                    enabled &&
                        !transient &&
                        contact.canRequestUpdate &&
                        actions.onStartRequest != null
                    ? () => unawaited(
                        run(
                          () => actions.onStartRequest!(contactId: contact.id),
                        ),
                      )
                    : null,
                size: AppButtonSize.medium,
                variant: AppButtonVariant.secondary,
                child: const Text('Request updated address'),
              ),
              if (contact.status == ContactTrustStatus.accepted)
                AppButton(
                  key: Key('contacts-suspend-${contact.id}'),
                  onPressed: enabled && actions.onSuspend != null
                      ? () => setState(() => _confirmSuspend = contact.id)
                      : null,
                  size: AppButtonSize.medium,
                  variant: AppButtonVariant.ghost,
                  child: const Text('Suspend'),
                ),
            ],
          ),
          if (_confirmSuspend == contact.id) ...[
            const SizedBox(height: AppSpacing.s),
            _Notice(
              title: 'Suspend ${contact.label}?',
              text:
                  'This blocks payments and signed address updates, and cancels outstanding exchanges for this contact. The record remains visible. This experiment cannot reactivate a suspended identity.',
              action: Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  AppButton(
                    key: Key('contacts-confirm-suspend-${contact.id}'),
                    onPressed: enabled && actions.onSuspend != null
                        ? () => unawaited(
                            run(() => actions.onSuspend!(contact.id)),
                          )
                        : null,
                    variant: AppButtonVariant.destructive,
                    size: AppButtonSize.medium,
                    child: const Text('Suspend contact'),
                  ),
                  AppButton(
                    onPressed: enabled
                        ? () => setState(() => _confirmSuspend = null)
                        : null,
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.medium,
                    child: const Text('Keep accepted'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    ),
  );

  Widget _cancelButton({String label = 'Cancel exchange'}) => AppButton(
    key: const Key('contacts-cancel'),
    onPressed: enabled && actions.onCancel != null ? cancel : null,
    variant: AppButtonVariant.ghost,
    child: Text(label),
  );

  Widget _payloadInput({
    required Key key,
    required String label,
    required TextEditingController controller,
    required bool tooLong,
    required VoidCallback onReject,
    required ValueChanged<String> onChanged,
  }) => AppTextField(
    key: key,
    label: label,
    controller: controller,
    enabled: enabled,
    minLines: 3,
    maxLines: 5,
    hintText: 'Paste the request or reply',
    autocorrect: false,
    enableSuggestions: false,
    inputFormatters: [_RejectOversizedExchange(_limit, onReject)],
    onChanged: onChanged,
    tone: tooLong ? AppTextFieldTone.destructive : AppTextFieldTone.neutral,
    messageText: tooLong
        ? _lengthMessage
        : 'Contact exchange text only. Do not paste wallet-link data, recovery words or viewing keys.',
  );

  Widget _payloadOutput(String label, String text) => AppTextField(
    key: ValueKey('$label:${text.hashCode}'),
    label: label,
    initialValue: text,
    minLines: 3,
    maxLines: 5,
    readOnly: true,
    autocorrect: false,
    enableSuggestions: false,
    textStyle: AppTypography.codeSmall.copyWith(
      color: context.colors.text.primary,
    ),
  );
}

class _RejectOversizedExchange extends TextInputFormatter {
  _RejectOversizedExchange(this.limit, this.onReject);
  final int limit;
  final VoidCallback onReject;
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length > limit) {
      onReject();
      return oldValue;
    }
    return newValue;
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => FamiliarCard(
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.text,
    this.action,
    this.isError = false,
  });
  final String title, text;
  final Widget? action;
  final bool isError;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: isError,
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: isError
            ? context.colors.background.utilityDestructiveSubtle
            : context.colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTypography.labelLarge.copyWith(
              color: isError
                  ? context.colors.text.destructive
                  : context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _paragraph(context, text),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.s),
            action!,
          ],
        ],
      ),
    ),
  );
}

class _Consent extends StatelessWidget {
  const _Consent({
    super.key,
    required this.checked,
    required this.enabled,
    required this.label,
    required this.onChanged,
  });
  final bool checked, enabled;
  final String label;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: CheckboxListTile(
      value: checked,
      onChanged: enabled ? (value) => onChanged(value ?? false) : null,
      title: _paragraph(context, label),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeColor: context.colors.text.accent,
      checkColor: context.colors.background.base,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status(this.status);
  final ContactTrustStatus status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: context.colors.background.raised,
      borderRadius: BorderRadius.circular(AppRadii.small),
    ),
    child: Text(
      switch (status) {
        ContactTrustStatus.accepted => 'Accepted',
        ContactTrustStatus.suspended => 'Suspended',
        ContactTrustStatus.restored => 'Needs verification',
        ContactTrustStatus.retired => 'Retired',
      },
      style: AppTypography.labelSmall.copyWith(
        color: context.colors.text.secondary,
      ),
    ),
  );
}

Widget _heading(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: AppSpacing.s),
  child: Text(
    text,
    style: AppTypography.headlineSmall.copyWith(
      color: context.colors.text.accent,
    ),
  ),
);
Widget _paragraph(BuildContext context, String text, {bool accent = false}) =>
    Text(
      text,
      style: AppTypography.bodyMedium.copyWith(
        color: accent
            ? context.colors.text.accent
            : context.colors.text.secondary,
      ),
    );
Widget _divider(BuildContext context) =>
    Container(height: 1, color: context.colors.border.subtle);
Widget _value(BuildContext context, String label, String text) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Text(
      label,
      style: AppTypography.labelSmall.copyWith(
        color: context.colors.text.secondary,
      ),
    ),
    const SizedBox(height: AppSpacing.xxs),
    SelectableText(
      text,
      style: AppTypography.codeSmall.copyWith(
        color: context.colors.text.primary,
      ),
    ),
  ],
);
