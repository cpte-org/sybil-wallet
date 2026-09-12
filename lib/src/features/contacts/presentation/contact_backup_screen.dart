import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String? _archive, _notice;
  bool _busy = false, _approved = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear() {
    _epoch++;
    _input.clear();
    _review = null;
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
      setState(_clear);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(contactScopeProvider);
    ref.watch(contactBackupCoordinatorProvider);
    ref.listen(contactScopeProvider, (_, _) => _clear());
    return Scaffold(
      appBar: AppBar(title: const Text('Connection backup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Keep this encrypted archive with your wallet backup. Restore it using the same recovery phrase, BIP39 passphrase, account index and network. The wallet password may be different.',
            ),
            const SizedBox(height: 16),
            const Text(
              'This saves connected contacts and relationship keys. Manually saved addresses, notes, pins, SimpleX connections and pending exchanges are not included. Restored contacts need a fresh address check. Restored signing keys stay inactive until recovery reconciliation is implemented.',
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
                          _notice =
                              'Contacts restored. Request and independently verify a fresh address response before paying each contact.';
                        }),
                      ),
                child: const Text('Restore contacts'),
              ),
            ],
            if (_notice != null) Text(_notice!),
          ],
        ),
      ),
    );
  }
}
