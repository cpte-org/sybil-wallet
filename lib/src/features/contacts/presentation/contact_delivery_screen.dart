import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/widgets/app_button.dart';
import '../application/contact_delivery_providers.dart';
import '../domain/contact_delivery.dart';
import '../domain/contact_models.dart';
import 'contact_connection_binding_panel.dart';

class ContactDeliveryScreen extends ConsumerWidget {
  const ContactDeliveryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(contactDeliveryScopeProvider);
    final content = scope == null
        ? const Center(
            child: Text(
              'Private delivery currently supports unlocked Linux test accounts using a direct wallet route. Manual exchange remains available.',
            ),
          )
        : _DeliveryView(key: ValueKey(scope));
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
                child: const Text('Back to contacts'),
              ),
            ),
            Expanded(child: content),
          ],
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
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(simplexNativeTransportProvider);
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

  Future<void> _refresh(int epoch) async {
    final transport = await ref.read(simplexNativeTransportProvider.future);
    _check(epoch);
    final coordinator = ref.read(contactDeliveryCoordinatorProvider);
    await transport.reconcile(coordinator);
    _check(epoch);
    final peers = await transport.peers();
    _check(epoch);
    final records = await coordinator.overview();
    _check(epoch);
    _peers = peers;
    _records = records;
    if (!peers.any((p) => p.id == _peer)) _peer = null;
  }

  @override
  Widget build(BuildContext context) {
    final native = ref.watch(simplexNativeTransportProvider);
    ref.watch(contactDeliveryCoordinatorProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Private contact delivery',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'SimpleX carries contact packets. Receiving a packet does not accept a contact or approve a payment. This is the Linux transport experiment.',
        ),
        if (native.hasError)
          const Text(
            'The native delivery component could not open. Manual packet exchange remains available.',
          ),
        const SizedBox(height: 16),
        const ContactConnectionBindingPanel(),
        AppButton(
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
          child: const Text('Create a private connection link'),
        ),
        if (_invitation != null)
          AppButton(
            onPressed: _busy
                ? null
                : () => unawaited(
                    _run((epoch) async {
                      _check(epoch);
                      await SensitiveClipboard.copyText(_invitation!);
                    }),
                  ),
            child: const Text('Copy connection link'),
          ),
        TextField(
          controller: _link,
          decoration: const InputDecoration(
            labelText: 'One-time connection link from the other person',
          ),
        ),
        AppButton(
          onPressed: _busy
              ? null
              : () => unawaited(
                  _run((epoch) async {
                    final invitation = _link.text;
                    final transport = await ref.read(
                      simplexNativeTransportProvider.future,
                    );
                    _check(epoch);
                    await transport.connect(invitation);
                    _check(epoch);
                    _link.clear();
                    _notice =
                        'Connection requested. Refresh after the other person connects.';
                  }),
                ),
          child: const Text('Connect'),
        ),
        AppButton(
          onPressed: _busy ? null : () => unawaited(_run(_refresh)),
          child: const Text('Refresh delivery inbox'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Connection names below are supplied by the transport, not independently verified contact identities. Check the connection with the intended recipient before sharing.',
        ),
        DropdownButton<String>(
          value: _peer,
          isExpanded: true,
          hint: const Text('Choose a delivery connection'),
          items: [
            for (final peer in _peers)
              DropdownMenuItem(
                value: peer.id,
                child: Text('${peer.label} · ${peer.id}'),
              ),
          ],
          onChanged: _busy ? null : (v) => setState(() => _peer = v),
        ),
        TextField(
          controller: _packet,
          maxLines: 3,
          maxLength: contactDeliveryMaxPacketBytes,
          decoration: const InputDecoration(
            labelText: 'Approved contact packet',
          ),
        ),
        AppButton(
          onPressed: _busy || _peer == null
              ? null
              : () => unawaited(
                  _run((epoch) async {
                    final peer = _peer!, packet = _packet.text;
                    final transport = await ref.read(
                      simplexNativeTransportProvider.future,
                    );
                    _check(epoch);
                    final coordinator = ref.read(
                      contactDeliveryCoordinatorProvider,
                    );
                    final id = await coordinator.enqueue(peer, packet);
                    _check(epoch);
                    _packet.clear();
                    await coordinator.submit(id, transport);
                    _check(epoch);
                    await _refresh(epoch);
                    _notice =
                        'Submitted to SimpleX. This does not confirm recipient acceptance.';
                  }),
                ),
          child: const Text('Approve and send packet'),
        ),
        if (_notice != null) Text(_notice!),
        for (final record in _records)
          ListTile(
            title: Text(
              record.incoming
                  ? 'Received packet · connection ${record.peer}'
                  : 'Outgoing packet · connection ${record.peer}',
            ),
            subtitle: Text(switch (record.state) {
              ContactDeliveryState.queued => 'Queued — retry available',
              ContactDeliveryState.submitted => 'Submitted to SimpleX',
              ContactDeliveryState.received =>
                'Awaiting your review in contact exchange',
              ContactDeliveryState.dismissed => 'Dismissed',
            }),
            trailing: record.state == ContactDeliveryState.queued
                ? TextButton(
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
                    child: const Text('Retry'),
                  )
                : record.state == ContactDeliveryState.received
                ? TextButton(
                    onPressed: _busy
                        ? null
                        : () => unawaited(
                            _run((epoch) async {
                              _check(epoch);
                              await SensitiveClipboard.copyText(record.packet);
                            }),
                          ),
                    child: const Text('Copy for review'),
                  )
                : null,
          ),
      ],
    );
  }
}
