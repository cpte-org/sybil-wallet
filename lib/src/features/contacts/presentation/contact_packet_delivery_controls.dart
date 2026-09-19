import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_button.dart';
import '../application/contact_delivery_providers.dart';
import '../domain/contact_delivery.dart';
import '../domain/contact_models.dart';
import '../domain/contact_connection_binding.dart';
import '../domain/contact_packet_kind.dart';

/// Inline transport controls. Parent reviews still own all wallet authority.
/// No packet is placed in a URL, clipboard, or navigation-history argument.
class ContactPacketDeliveryControls extends ConsumerStatefulWidget {
  const ContactPacketDeliveryControls.inbox({
    super.key,
    required this.onSelected,
    required this.kinds,
  }) : packet = null,
       expiresAt = null,
       contactId = null,
       recipientIdentity = null;
  const ContactPacketDeliveryControls.send({
    super.key,
    required this.packet,
    required this.expiresAt,
    this.contactId,
    this.recipientIdentity,
  }) : onSelected = null,
       kinds = const {};
  final Future<void> Function(String)? onSelected;
  final Set<ContactPacketKind> kinds;
  final String? packet;
  final DateTime? expiresAt;
  final String? contactId;
  final String? recipientIdentity;
  @override
  ConsumerState<ContactPacketDeliveryControls> createState() =>
      _ControlsState();
}

class _ControlsState extends ConsumerState<ContactPacketDeliveryControls>
    with WidgetsBindingObserver {
  List<ContactDelivery> _records = [];
  List<({String id, String label})> _peers = [];
  String? _peer, _notice;
  ContactConnectionBinding? _binding;
  bool _active = false, _busy = false;
  bool _refreshing = false, _refreshAgain = false;
  bool _refreshPaused = false;
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
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ContactPacketDeliveryControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packet != widget.packet ||
        oldWidget.expiresAt != widget.expiresAt ||
        oldWidget.contactId != widget.contactId ||
        oldWidget.recipientIdentity != widget.recipientIdentity) {
      _clear();
    }
  }

  void _clear() {
    _epoch++;
    _records = [];
    _peers = [];
    _peer = null;
    _binding = null;
    _notice = null;
    _active = false;
    _refreshAgain = false;
    _refreshPaused = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      setState(_clear);
    }
  }

  void _check(ContactScope scope, int epoch) {
    if (!mounted ||
        epoch != _epoch ||
        ref.read(contactDeliveryScopeProvider) != scope) {
      throw const ContactFailure('Delivery changed. Reopen this review.');
    }
    final expires = widget.expiresAt;
    if (widget.packet != null &&
        (expires == null || !DateTime.now().isBefore(expires))) {
      throw const ContactFailure(
        'This packet expired. Create a fresh request or review.',
      );
    }
  }

  Future<void> _run(Future<void> Function(ContactScope, int) action) async {
    final scope = ref.read(contactDeliveryScopeProvider);
    if (_busy || scope == null) return;
    final epoch = _epoch;
    setState(() {
      _active = true;
      _busy = true;
      _notice = null;
    });
    try {
      await action(scope, epoch);
    } catch (e) {
      if (mounted &&
          epoch == _epoch &&
          ref.read(contactDeliveryScopeProvider) == scope) {
        _notice = e is ContactFailure
            ? e.message
            : 'Private delivery is unavailable. Manual exchange remains available.';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && epoch == _epoch && _refreshAgain) {
        _refreshAgain = false;
        unawaited(_refreshInbox());
      }
    }
  }

  Future<void> _load(ContactScope scope, int epoch) async {
    if (_refreshPaused) {
      _refreshPaused = false;
      ref.invalidate(simplexNativeTransportProvider);
    }
    final transport = await ref.read(simplexNativeTransportProvider.future);
    _check(scope, epoch);
    if (widget.packet != null) {
      _peers = [];
      _peer = null;
      _binding = null;
      if (widget.contactId != null && widget.recipientIdentity != null) {
        final binding = await ref
            .read(contactBindingCoordinatorProvider)
            .resolve(
              widget.contactId!,
              transport,
              expectedIdentity: widget.recipientIdentity,
            );
        _check(scope, epoch);
        if (binding != null) {
          _binding = binding;
          _peer = binding.peer;
          _peers = [(id: binding.peer, label: 'Checked contact connection')];
          return;
        }
      }
      final peers = await transport.peers();
      _check(scope, epoch);
      _peers = peers;
      if (!_peers.any((p) => p.id == _peer)) _peer = null;
    } else {
      final coordinator = ref.read(contactDeliveryCoordinatorProvider);
      await transport.reconcile(coordinator);
      _check(scope, epoch);
      final records = await coordinator.overview();
      _check(scope, epoch);
      _records = records
          .where(
            (r) =>
                r.state == ContactDeliveryState.received &&
                widget.kinds.contains(contactPacketKind(r.packet)),
          )
          .toList();
      if (_records.isEmpty && !_refreshPaused) {
        _notice = 'Waiting for a reply. This inbox updates while open.';
      }
    }
  }

  Future<void> _refreshInbox() async {
    if (!_active || widget.packet != null) return;
    if (_busy || _refreshing) {
      _refreshAgain = true;
      return;
    }
    final scope = ref.read(contactDeliveryScopeProvider);
    if (scope == null) return;
    final epoch = _epoch;
    _refreshing = true;
    try {
      final records = await ref
          .read(contactDeliveryCoordinatorProvider)
          .overview();
      _check(scope, epoch);
      setState(() {
        _records = records
            .where(
              (r) =>
                  r.state == ContactDeliveryState.received &&
                  widget.kinds.contains(contactPacketKind(r.packet)),
            )
            .toList();
        if (!_refreshPaused) {
          _notice = _records.isEmpty
              ? 'Waiting for a reply. This inbox updates while open.'
              : null;
        }
      });
    } catch (_) {
      // A stale read must never repopulate a cleared or changed account's inbox.
    } finally {
      _refreshing = false;
      if (mounted && epoch == _epoch && _refreshAgain) {
        _refreshAgain = false;
        unawaited(_refreshInbox());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(contactDeliveryScopeProvider);
    ref.listen(contactDeliveryScopeProvider, (_, _) {
      if (mounted) _clear(); // The watched scope already schedules a rebuild.
    });
    ref.watch(contactDeliveryCoordinatorProvider);
    if (scope == null) return const SizedBox.shrink();
    // Keep the auto-disposed native session alive only after a user action.
    if (_active) ref.watch(simplexNativeTransportProvider);
    if (_active) {
      ref.listen(contactDeliveryRefreshProvider, (_, next) {
        if (next.isLoading) return;
        if (next.hasError) {
          setState(() {
            _refreshPaused = true;
            _refreshAgain = false;
            _notice = widget.packet == null
                ? 'Inbox updates paused. Load the inbox again to retry.'
                : 'Private delivery paused. Prepare the connection again to retry.';
          });
        } else if (next.hasValue && widget.packet == null) {
          unawaited(_refreshInbox());
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          constrainContent: true,
          onPressed: _busy ? null : () => unawaited(_run(_load)),
          child: Text(
            widget.packet == null
                ? 'Load from private inbox'
                : widget.contactId == null
                ? 'Choose private delivery connection'
                : 'Prepare contact delivery',
          ),
        ),
        if (_peers.isNotEmpty) ...[
          Text(
            _binding == null
                ? 'Connection labels are not verified contact identities. Confirm the intended connection before sharing.'
                : 'Using this contact’s independently checked connection. Its security code is rechecked before sending.',
          ),
          DropdownButton<String>(
            value: _peer,
            isExpanded: true,
            hint: const Text('Choose connection'),
            items: [
              for (final p in _peers)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    '${p.label} · ${p.id}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy || _binding != null
                ? null
                : (p) => setState(() => _peer = p),
          ),
          AppButton(
            constrainContent: true,
            onPressed: _busy || _refreshPaused || _peer == null
                ? null
                : () => unawaited(
                    _run((scope, epoch) async {
                      final packet = widget.packet!,
                          peer = _peer!,
                          binding = _binding;
                      _check(scope, epoch);
                      final transport = await ref.read(
                        simplexNativeTransportProvider.future,
                      );
                      _check(scope, epoch);
                      final coordinator = ref.read(
                        contactDeliveryCoordinatorProvider,
                      );
                      final id = await coordinator.enqueue(
                        peer,
                        packet,
                        binding: binding,
                      );
                      _check(scope, epoch);
                      await coordinator.submit(id, transport);
                      _check(scope, epoch);
                      _notice =
                          'Submitted to SimpleX. This does not mean the other person accepted it.';
                      _peer = null;
                    }),
                  ),
            child: const Text('Approve and send'),
          ),
        ],
        for (final record in _records)
          AppButton(
            constrainContent: true,
            onPressed: _busy
                ? null
                : () => unawaited(
                    _run((scope, epoch) async {
                      _check(scope, epoch);
                      await widget.onSelected!(record.packet);
                      // Selection is not acceptance; keep the durable inbox record intact.
                    }),
                  ),
            child: Text(
              'Review ${_packetLabel(contactPacketKind(record.packet)!)} · connection ${record.peer}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (_notice != null) Text(_notice!),
      ],
    );
  }
}

String _packetLabel(ContactPacketKind kind) => switch (kind) {
  ContactPacketKind.ask => 'introduction request',
  ContactPacketKind.offer => 'introduction offer',
  ContactPacketKind.consent => 'approved introduction',
  ContactPacketKind.delivery => 'introduction',
  ContactPacketKind.request => 'invitation',
  ContactPacketKind.response => 'reply',
};
