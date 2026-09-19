import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/widgets/app_button.dart';
import '../application/contact_backup_coordinator.dart';
import '../application/contact_backup_providers.dart';
import '../application/contact_exchange_controller.dart';
import '../domain/contact_models.dart';

class ContactBackupScreen extends ConsumerStatefulWidget {
  const ContactBackupScreen({super.key});
  @override
  ConsumerState<ContactBackupScreen> createState() =>
      _ContactBackupScreenState();
}

class _ContactBackupScreenState extends ConsumerState<ContactBackupScreen>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  ContactBackupReview? _review;
  ContactRecoveryProgress? _recovery;
  String? _archive, _notice;
  bool _busy = false, _approved = false;
  int _epoch = 0;
  bool _foreground = true, _refreshPending = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _queueRecoveryRefresh();
  }

  void _queueRecoveryRefresh() {
    _refreshPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_foreground || _busy || !_refreshPending) return;
      _refreshPending = false;
      unawaited(_refreshRecovery());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _clear() {
    _epoch++;
    _input.clear();
    _review = null;
    _recovery = null;
    _archive = null;
    _approved = false;
    _notice = null;
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _foreground = false;
      setState(_clear);
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _queueRecoveryRefresh();
    }
  }

  Future<void> _run(
    Future<void> Function(ContactBackupCoordinator, void Function()) action,
  ) async {
    final scope = ref.read(contactScopeProvider), epoch = _epoch;
    if (_busy || scope == null) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    void check() {
      if (!mounted ||
          epoch != _epoch ||
          ref.read(contactScopeProvider) != scope) {
        throw const ContactFailure('Backup review interrupted.');
      }
    }

    try {
      await action(ref.read(contactBackupCoordinatorProvider), check);
    } catch (e) {
      if (mounted && epoch == _epoch) {
        _notice = e is ContactFailure
            ? e.message
            : 'The backup could not be verified. Check the wallet recovery phrase, BIP39 passphrase, account index and network.';
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_refreshPending) _queueRecoveryRefresh();
      }
    }
  }

  Future<void> _refreshRecovery() => _run((coordinator, check) async {
    final progress = await coordinator.recoveryProgress();
    check();
    _recovery = progress;
  });

  Future<void> _openRecovery({String? contactId}) async {
    await _run((_, check) async {
      final controller = ref.read(contactExchangeProvider.notifier);
      // The provider schedules its initial reload in a microtask. Let that
      // start before this explicit reload so it cannot invalidate our request.
      await Future<void>.value();
      check();
      controller.cancelTransient();
      await controller.reload();
      check();
      if (contactId != null) {
        await controller.startRequest(contactId: contactId);
        check();
        final state = ref.read(contactExchangeProvider);
        if (state.request?.contactId != contactId) {
          throw ContactFailure(state.error ?? 'Reload contacts and try again.');
        }
      }
      if (mounted) await context.push('/contacts/exchange');
    });
    if (mounted) await _refreshRecovery();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(contactScopeProvider);
    ref.watch(contactBackupCoordinatorProvider);
    ref.listen(contactScopeProvider, (_, _) {
      _clear();
      _queueRecoveryRefresh();
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Connection backup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Save an encrypted copy of your connections outside this device.',
            ),
            const ExpansionTile(
              title: Text('What this backup includes'),
              childrenPadding: EdgeInsets.only(bottom: 16),
              children: [
                Text(
                  'Includes connected contacts and relationship keys. Manually saved addresses, notes, pins, SimpleX connections and pending exchanges are not included.',
                ),
                SizedBox(height: 12),
                Text(
                  'Restore into a fresh account using the same recovery phrase, BIP39 passphrase, account index and network. The wallet password and database account ID may be different. Existing contact data will not be overwritten.',
                ),
                SizedBox(height: 12),
                Text(
                  'Restored contacts need a fresh address check. Old signing keys stay inactive because another device may still use them. To receive again, exchange new receiving details and independently compare them. No hosted backup is made.',
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppButton(
              onPressed: _busy || scope == null
                  ? null
                  : () => unawaited(
                      _run((coordinator, check) async {
                        final archive = await coordinator.export();
                        check();
                        _archive = archive;
                      }),
                    ),
              child: const Text('Create encrypted backup'),
            ),
            if (_archive != null) ...[
              const Text(
                'Encrypted backup ready. Copy it into a file and keep that file outside this device. No hosted backup has been made.',
              ),
              AppButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _run((_, check) async {
                          check();
                          await SensitiveClipboard.copyText(_archive!);
                          check();
                          _notice = 'Encrypted backup copied.';
                        }),
                      ),
                child: const Text('Copy encrypted backup'),
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              controller: _input,
              enabled: !_busy && scope != null,
              minLines: 3,
              maxLines: 6,
              maxLength: 2097152,
              decoration: const InputDecoration(
                labelText: 'Encrypted contact backup',
                hintText: 'Paste your encrypted archive',
              ),
              onChanged: (_) {
                ref.read(contactBackupCoordinatorProvider).invalidate();
                setState(() {
                  _review = null;
                  _approved = false;
                });
              },
            ),
            AppButton(
              onPressed: _busy || scope == null
                  ? null
                  : () => unawaited(
                      _run((coordinator, check) async {
                        _review = null;
                        _approved = false;
                        final review = await coordinator.prepare(
                          _input.text.trim(),
                        );
                        check();
                        _review = review;
                      }),
                    ),
              child: const Text('Review restoration'),
            ),
            if (_review case final review?) ...[
              Text(
                '${review.contactCount} contacts and ${review.keyCount} inactive relationship keys. Backup created ${review.createdAt.toLocal()}. This date does not prove this is your latest backup.',
              ),
              CheckboxListTile(
                value: _approved,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _approved = v ?? false),
                title: const Text(
                  'Restore into this fresh account. I understand payments require fresh verification and old signing keys remain inactive.',
                ),
              ),
              AppButton(
                onPressed: _busy || !_approved
                    ? null
                    : () => unawaited(
                        _run((coordinator, check) async {
                          await coordinator.restore(
                            review,
                            approved: _approved,
                          );
                          check();
                          _review = null;
                          _input.clear();
                          _approved = false;
                          _recovery = await coordinator.recoveryProgress();
                          check();
                          _notice =
                              'Contacts restored. Request and independently verify a fresh address response before paying each contact.';
                        }),
                      ),
                child: const Text('Restore contacts'),
              ),
            ],
            const SizedBox(height: 24),
            const Text('Continue recovery'),
            const Text(
              'First, check each restored contact before sending. This verifies their current receiving details without reactivating your old signing keys.',
            ),
            AppButton(
              onPressed: _busy || scope == null
                  ? null
                  : () => unawaited(_refreshRecovery()),
              child: const Text('Refresh recovery progress'),
            ),
            if (_recovery case final progress?) ...[
              Text(
                '${progress.pendingContacts.length} contacts need a fresh check.',
              ),
              for (final contact in progress.pendingContacts)
                AppButton(
                  onPressed: _busy || scope == null
                      ? null
                      : () => unawaited(_openRecovery(contactId: contact.id)),
                  child: Text('Check ${contact.label}'),
                ),
              if (progress.inactiveKeyCount > 0) ...[
                Text(
                  '${progress.inactiveKeyCount} old relationship keys remain inactive.',
                ),
                const Text(
                  'To receive again, ask the other person to create a new contact request, not an update to your old identity. Open the exchange below and reply to that request to create new receiving details. Compare the new identity and address through a trusted channel before they save it. Ask them to suspend your old contact after checking the new one. If both people restored a backup, both need this new exchange.',
                ),
                AppButton(
                  onPressed: _busy || scope == null
                      ? null
                      : () => unawaited(_openRecovery()),
                  child: const Text('Reconnect for receiving'),
                ),
                const Text(
                  'Fresh address checks do not retire keys on another device. Automatic key rotation and hosted backup recovery are not available. Keep your encrypted archive.',
                ),
              ],
            ],
            if (_notice != null) Text(_notice!),
          ],
        ),
      ),
    );
  }
}
