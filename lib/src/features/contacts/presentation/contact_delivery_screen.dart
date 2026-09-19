import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/familiar_widgets.dart';
import '../application/contact_delivery_providers.dart';
import '../application/contact_ui_preferences.dart';
import '../domain/contact_delivery.dart';
import '../domain/contact_models.dart';
import 'contact_connection_binding_panel.dart';
import 'contact_code_widgets.dart';

class ContactDeliveryScreen extends ConsumerStatefulWidget {
  const ContactDeliveryScreen({super.key});
  @override
  ConsumerState<ContactDeliveryScreen> createState() =>
      _ContactDeliveryScreenState();
}

class _ContactDeliveryScreenState extends ConsumerState<ContactDeliveryScreen>
    with WidgetsBindingObserver {
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      setState(() => _paused = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final advanced =
        ref.watch(contactAdvancedToolsProvider).asData?.value == true;
    final scope = advanced ? ref.watch(contactDeliveryScopeProvider) : null;
    final unavailable = advanced
        ? ref.watch(contactDeliveryUnavailableReasonProvider)
        : null;
    ref.listen(contactDeliveryScopeProvider, (previous, next) {
      if (previous != null && previous != next) _paused = true;
    });
    final content = !advanced
        ? const _DeliveryUnavailable(
            title: 'Connection tools',
            message:
                'Advanced contact tools are off. You can still connect '
                'with someone by exchanging a contact code.',
          )
        : unavailable != null
        ? _DeliveryUnavailable(
            title: 'Private delivery isn’t available',
            message: unavailable,
          )
        : scope == null
        ? const _DeliveryUnavailable(
            title: 'Private delivery is paused',
            message:
                'This feature needs an unlocked supported test account and '
                'a direct network connection.',
          )
        : _paused
        ? _DeliveryUnavailable(
            title: 'Private delivery is paused',
            message:
                'Reopen private delivery when you are ready to connect again.',
            retryLabel: 'Reopen private delivery',
            onRetry: () {
              ref.invalidate(simplexNativeTransportProvider);
              setState(() => _paused = false);
            },
          )
        : _DeliveryView(key: ValueKey(scope));
    if (kAppFormFactor == AppFormFactor.mobile) {
      return Scaffold(
        backgroundColor: context.colors.background.window,
        appBar: AppBar(title: const Text('Private delivery')),
        body: SafeArea(child: content),
      );
    }
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        child: Column(
          children: [
            AppPaneToolbar(
              leading: AppButton(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/contacts/exchange'),
                child: const Text('Back'),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class _DeliveryUnavailable extends StatelessWidget {
  const _DeliveryUnavailable({
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.loading = false,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return _DeliveryLayout(
      children: [
        FamiliarPageHeader(title: title),
        FamiliarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (loading) ...[
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(
                message,
                style: AppTypography.bodyMedium.copyWith(
                  color: FamiliarPalette.of(context).muted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  AppButton(
                    onPressed: () => context.push('/contacts/exchange'),
                    child: const Text('Exchange a contact code'),
                  ),
                  if (onRetry != null)
                    AppButton(
                      variant: AppButtonVariant.secondary,
                      onPressed: onRetry,
                      child: Text(retryLabel),
                    ),
                  AppButton(
                    variant: AppButtonVariant.ghost,
                    onPressed: () => context.push('/settings/contacts'),
                    child: const Text('Contact settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeliveryLayout extends StatelessWidget {
  const _DeliveryLayout({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryView extends ConsumerStatefulWidget {
  const _DeliveryView({super.key});
  @override
  ConsumerState<_DeliveryView> createState() => _DeliveryViewState();
}

class _DeliveryViewState extends ConsumerState<_DeliveryView>
    with WidgetsBindingObserver {
  final _link = TextEditingController(), _packet = TextEditingController();
  List<({String id, String label})> _peers = [];
  List<ContactDelivery> _records = [];
  String? _peer, _invitation, _notice;
  bool _busy = false;
  bool _refreshing = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    _link.dispose();
    _packet.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _epoch++;
      _link.clear();
      _packet.clear();
      setState(() {
        _records = [];
        _invitation = null;
        _peer = null;
        _peers = [];
      });
    }
  }

  Future<void> _run(Future<void> Function(int epoch) action) async {
    if (_busy) return;
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await action(epoch);
    } catch (e) {
      if (mounted && epoch == _epoch) {
        _notice = e is ContactFailure
            ? e.message
            : 'Private delivery is unavailable. Your saved packets remain available to retry.';
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _check(int epoch) {
    if (!mounted ||
        epoch != _epoch ||
        ref.read(contactDeliveryScopeProvider) == null) {
      throw const ContactFailure('Delivery was paused.');
    }
  }

  Future<void> _refresh(int epoch, {bool reconcile = true}) async {
    final transport = await ref.read(simplexNativeTransportProvider.future);
    _check(epoch);
    final coordinator = ref.read(contactDeliveryCoordinatorProvider);
    if (reconcile) await transport.reconcile(coordinator);
    _check(epoch);
    final peers = await transport.peers();
    _check(epoch);
    final records = await coordinator.overview();
    _check(epoch);
    _peers = peers;
    _records = records;
    if (!peers.any((p) => p.id == _peer)) _peer = null;
  }

  Future<void> _receiveRefresh() async {
    if (_busy || _refreshing) return;
    _refreshing = true;
    final epoch = _epoch;
    try {
      await _refresh(epoch, reconcile: false);
      if (mounted && epoch == _epoch) setState(() {});
    } catch (_) {
      if (mounted && epoch == _epoch && !_busy) {
        setState(() {
          _notice = 'The inbox could not be refreshed. Try refreshing again.';
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _copyCode(String value) async {
    final epoch = _epoch;
    _check(epoch);
    await SensitiveClipboard.copyText(value);
    _check(epoch);
  }

  Future<void> _connect(int epoch) async {
    final invitation = _link.text;
    final transport = await ref.read(simplexNativeTransportProvider.future);
    _check(epoch);
    await transport.connect(invitation);
    _check(epoch);
    _link.clear();
    _notice = 'Connection requested. Waiting for the other person to connect.';
  }

  Future<void> _send(int epoch) async {
    final peer = _peer!, packet = _packet.text;
    final transport = await ref.read(simplexNativeTransportProvider.future);
    _check(epoch);
    final coordinator = ref.read(contactDeliveryCoordinatorProvider);
    final id = await coordinator.enqueue(peer, packet);
    _check(epoch);
    _packet.clear();
    await coordinator.submit(id, transport);
    _check(epoch);
    await _refresh(epoch);
    _notice =
        'Submitted to private delivery. The recipient still needs to '
        'review it.';
  }

  String _peerLabel(String id) {
    for (final peer in _peers) {
      if (peer.id == id) return peer.label;
    }
    return 'Connection $id';
  }

  @override
  Widget build(BuildContext context) {
    final native = ref.watch(simplexNativeTransportProvider);
    final refresh = ref.watch(contactDeliveryRefreshProvider);
    ref.listen(contactDeliveryRefreshProvider, (_, next) {
      if (next.hasValue && !next.hasError) unawaited(_receiveRefresh());
    });
    ref.watch(contactDeliveryCoordinatorProvider);
    if (native.hasError || refresh.hasError) {
      final error = native.error ?? refresh.error;
      return _DeliveryUnavailable(
        title: 'Private delivery isn’t available',
        message: error is ContactFailure
            ? error.message
            : 'You can still exchange contact codes. Try private delivery '
                  'again when the connection is ready.',
        onRetry: _busy
            ? null
            : () => ref.invalidate(simplexNativeTransportProvider),
      );
    }
    if (!native.hasValue) {
      return const _DeliveryUnavailable(
        title: 'Opening private delivery',
        message: 'Getting this connection ready.',
        loading: true,
      );
    }
    final palette = FamiliarPalette.of(context);
    return _DeliveryLayout(
      children: [
        const FamiliarPageHeader(
          title: 'Private delivery',
          eyebrow: 'Advanced contact tools',
          subtitle: 'Set up a connection, then choose what to share.',
        ),
        FamiliarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Connect with someone',
                style: AppTypography.headlineSmall.copyWith(color: palette.ink),
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                'Share a connection code or open one they sent you.',
                style: AppTypography.bodyMedium.copyWith(color: palette.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                          _run((epoch) async {
                            final transport = await ref.read(
                              simplexNativeTransportProvider.future,
                            );
                            _check(epoch);
                            final link = await transport.createInvitation();
                            _check(epoch);
                            _invitation = link;
                          }),
                        ),
                  child: const Text('Create a connection code'),
                ),
              ),
              if (_invitation != null) ...[
                const SizedBox(height: AppSpacing.md),
                ContactCodeOutput(
                  data: _invitation!,
                  title: 'Your connection code',
                  enabled: !_busy,
                  advanced: true,
                  onCopy: _copyCode,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              ContactCodeInput(
                title: 'Open their connection code',
                enabled: !_busy,
                advanced: true,
                onRead: (value) async {
                  _check(_epoch);
                  setState(() => _link.text = value);
                },
              ),
              if (_link.text.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s),
                Text(
                  'Connection code ready.',
                  style: AppTypography.bodySmall.copyWith(color: palette.muted),
                ),
                const SizedBox(height: AppSpacing.s),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    onPressed: _busy ? null : () => unawaited(_run(_connect)),
                    child: const Text('Connect'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const FamiliarCard(
          child: Material(
            type: MaterialType.transparency,
            child: ContactConnectionBindingPanel(),
          ),
        ),
        FamiliarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Send a contact code',
                style: AppTypography.headlineSmall.copyWith(color: palette.ink),
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                'Connection labels do not verify a person. Check the '
                'connection with your recipient before sharing.',
                style: AppTypography.bodyMedium.copyWith(color: palette.muted),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : () => unawaited(_run(_refresh)),
                  child: const Text('Refresh connections and inbox'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButton<String>(
                value: _peer,
                isExpanded: true,
                hint: Text(
                  _peers.isEmpty
                      ? 'No connections loaded'
                      : 'Choose a connection',
                ),
                items: [
                  for (final peer in _peers)
                    DropdownMenuItem(
                      value: peer.id,
                      child: Text('${peer.label} · ${peer.id}'),
                    ),
                ],
                onChanged: _busy || _peers.isEmpty
                    ? null
                    : (value) => setState(() => _peer = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              ContactCodeInput(
                title: 'Open the approved contact code',
                enabled: !_busy,
                advanced: true,
                onRead: (value) async {
                  _check(_epoch);
                  if (value.length > contactDeliveryMaxPacketBytes) {
                    throw const ContactFailure(
                      'This contact code is too large.',
                    );
                  }
                  setState(() => _packet.text = value);
                },
              ),
              if (_packet.text.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s),
                Text(
                  'Contact code ready. Sending shares it with the '
                  'selected connection; it does not accept a contact or '
                  'approve a payment.',
                  style: AppTypography.bodySmall.copyWith(color: palette.muted),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    onPressed: _busy || _peer == null
                        ? null
                        : () => unawaited(_run(_send)),
                    child: const Text('Approve and send code'),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_notice != null)
          FamiliarCard(
            color: palette.lilac,
            child: Text(
              _notice!,
              style: AppTypography.bodyMedium.copyWith(color: palette.ink),
            ),
          ),
        if (_records.isNotEmpty)
          FamiliarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Delivery activity',
                  style: AppTypography.headlineSmall.copyWith(
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final record in _records) ...[
                  Text(
                    '${record.incoming ? 'From' : 'To'} ${_peerLabel(record.peer)}',
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    switch (record.state) {
                      ContactDeliveryState.queued =>
                        'Queued. You can retry this delivery.',
                      ContactDeliveryState.submitted =>
                        'Submitted to private delivery.',
                      ContactDeliveryState.received => 'Ready for your review.',
                      ContactDeliveryState.dismissed => 'Dismissed',
                    },
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.muted,
                    ),
                  ),
                  if (record.state == ContactDeliveryState.queued)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        variant: AppButtonVariant.secondary,
                        onPressed: _busy
                            ? null
                            : () => unawaited(
                                _run((epoch) async {
                                  final transport = await ref.read(
                                    simplexNativeTransportProvider.future,
                                  );
                                  _check(epoch);
                                  await ref
                                      .read(contactDeliveryCoordinatorProvider)
                                      .submit(record.id, transport);
                                  _check(epoch);
                                  await _refresh(epoch);
                                }),
                              ),
                        child: const Text('Retry delivery'),
                      ),
                    ),
                  if (record.state == ContactDeliveryState.received)
                    ContactCodeOutput(
                      data: record.packet,
                      title: 'Received contact code',
                      enabled: !_busy,
                      advanced: true,
                      onCopy: _copyCode,
                    ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.push('/contacts/exchange'),
                    child: const Text('Review a contact code'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
