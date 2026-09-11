import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_button.dart';
import '../application/contact_binding_coordinator.dart';
import '../application/contact_delivery_providers.dart';
import '../domain/contact_models.dart';
import '../domain/contact_connection_binding.dart';

class ContactConnectionBindingPanel extends ConsumerStatefulWidget {
  const ContactConnectionBindingPanel({super.key});
  @override
  ConsumerState<ContactConnectionBindingPanel> createState() => _PanelState();
}

class _PanelState extends ConsumerState<ContactConnectionBindingPanel>
    with WidgetsBindingObserver {
  List<VerifiedContact> _contacts = [];
  List<ContactConnectionBinding> _saved = [];
  List<({String id, String label})> _peers = [];
  String? _contact, _peer, _notice;
  ContactBindingReview? _review;
  bool _busy = false, _active = false, _compared = false;
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

  void _clear() {
    _epoch++;
    _review = null;
    _contacts = [];
    _saved = [];
    _peers = [];
    _contact = null;
    _peer = null;
    _compared = false;
    _notice = null;
    _active = false;
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
      throw const ContactFailure('Connection verification paused.');
    }
  }

  Future<void> _run(Future<void> Function(ContactScope, int) action) async {
    final scope = ref.read(contactDeliveryScopeProvider), epoch = _epoch;
    if (_busy || scope == null) return;
    setState(() {
      _busy = true;
      _active = true;
      _notice = null;
    });
    try {
      await action(scope, epoch);
    } catch (e) {
      if (mounted && epoch == _epoch) {
        _notice = e is ContactFailure
            ? e.message
            : 'Could not verify this connection. Try again.';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(contactDeliveryScopeProvider);
    ref.watch(contactBindingCoordinatorProvider);
    ref.listen(contactDeliveryScopeProvider, (_, _) => _clear());
    if (scope == null) return const SizedBox.shrink();
    if (_active) ref.watch(simplexNativeTransportProvider);
    final review = _review;
    return ExpansionTile(
      title: const Text('Verify a contact connection'),
      children: [
        const Text(
          'Compare the SimpleX security code with your existing contact through an independent trusted channel. This saves your checked association; a connection label alone proves nothing.',
        ),
        AppButton(
          onPressed: _busy
              ? null
              : () => unawaited(
                  _run((scope, epoch) async {
                    _review = null;
                    _compared = false;
                    final contacts = await ref
                        .read(contactBindingCoordinatorProvider)
                        .acceptedContacts();
                    _check(scope, epoch);
                    final saved = await ref
                        .read(contactBindingCoordinatorProvider)
                        .savedBindings();
                    _check(scope, epoch);
                    final native = await ref.read(
                      simplexNativeTransportProvider.future,
                    );
                    _check(scope, epoch);
                    final peers = await native.peers();
                    _check(scope, epoch);
                    _contacts = contacts;
                    _saved = saved;
                    _peers = peers;
                    _contact = null;
                    _peer = null;
                  }),
                ),
          child: const Text('Load contacts and connections'),
        ),
        DropdownButton<String>(
          value: _contact,
          isExpanded: true,
          hint: const Text('Accepted wallet contact'),
          items: [
            for (final c in _contacts)
              DropdownMenuItem(value: c.id, child: Text(c.label)),
          ],
          onChanged: _busy
              ? null
              : (v) => setState(() {
                  _contact = v;
                  _review = null;
                  _compared = false;
                }),
        ),
        DropdownButton<String>(
          value: _peer,
          isExpanded: true,
          hint: const Text('SimpleX connection'),
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
          onChanged: _busy
              ? null
              : (v) => setState(() {
                  _peer = v;
                  _review = null;
                  _compared = false;
                }),
        ),
        AppButton(
          onPressed: _busy || _contact == null || _peer == null
              ? null
              : () => unawaited(
                  _run((scope, epoch) async {
                    final native = await ref.read(
                      simplexNativeTransportProvider.future,
                    );
                    _check(scope, epoch);
                    final result = await ref
                        .read(contactBindingCoordinatorProvider)
                        .prepare(_contact!, _peer!, native);
                    _check(scope, epoch);
                    _review = result;
                    _compared = false;
                  }),
                ),
          child: const Text('Show code to compare'),
        ),
        if (review != null) ...[
          Text('Wallet contact: ${review.contact.label}'),
          SelectableText(review.contact.identity),
          SelectableText(
            review.binding.code
                .replaceAllMapped(RegExp(r'.{4}'), (m) => '${m[0]} ')
                .trim(),
          ),
          CheckboxListTile(
            value: _compared,
            onChanged: _busy
                ? null
                : (v) => setState(() => _compared = v ?? false),
            title: Text(
              'I independently compared this code with ${review.contact.label} through a trusted channel.',
            ),
          ),
          AppButton(
            onPressed: _busy || !_compared
                ? null
                : () => unawaited(
                    _run((scope, epoch) async {
                      final native = await ref.read(
                        simplexNativeTransportProvider.future,
                      );
                      _check(scope, epoch);
                      await ref
                          .read(contactBindingCoordinatorProvider)
                          .confirm(
                            review,
                            native,
                            independentlyVerified: _compared,
                          );
                      _check(scope, epoch);
                      _review = null;
                      _compared = false;
                      _saved = [
                        ..._saved.where(
                          (b) => b.contactId != review.binding.contactId,
                        ),
                        review.binding,
                      ];
                      _notice =
                          'Checked connection saved for ${review.contact.label}.';
                    }),
                  ),
            child: const Text('Save checked connection'),
          ),
        ],
        if (_notice != null) Text(_notice!),
        for (final binding in _saved)
          AppButton(
            constrainContent: true,
            onPressed: _busy
                ? null
                : () => unawaited(
                    _run((scope, epoch) async {
                      await ref
                          .read(contactBindingCoordinatorProvider)
                          .forget(binding.contactId);
                      _check(scope, epoch);
                      _saved = _saved
                          .where((b) => b.contactId != binding.contactId)
                          .toList();
                      _review = null;
                      _compared = false;
                      _notice =
                          'Saved connection forgotten. Queued sends using it will stop.';
                    }),
                  ),
            child: Text(
              'Forget connection: ${_contacts.where((c) => c.id == binding.contactId).firstOrNull?.label ?? binding.contactId}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
