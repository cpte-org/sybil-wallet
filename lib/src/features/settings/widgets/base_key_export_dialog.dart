import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';

/// Secrets live only in this short-lived dialog, never in provider view data.
class BaseKeyExportDialog extends StatefulWidget {
  const BaseKeyExportDialog({
    super.key,
    required this.session,
    required this.owner,
    required this.enabled,
    required this.exportKey,
  });
  final String session, owner;
  final bool enabled;
  final Future<Uint8List> Function(String password) exportKey;
  @override
  State<BaseKeyExportDialog> createState() => _BaseKeyExportDialogState();
}

class _BaseKeyExportDialogState extends State<BaseKeyExportDialog>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  Uint8List? _key;
  Timer? _expiry;
  int _epoch = 0;
  bool _busy = false, _visible = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear() {
    _epoch++;
    _expiry?.cancel();
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
    _password.clear();
    _visible = false;
    _busy = false;
    _message = null;
  }

  @override
  void didUpdateWidget(BaseKeyExportDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session != oldWidget.session || !widget.enabled) _clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) setState(_clear);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clear();
    _password.dispose();
    super.dispose();
  }

  String get _hex =>
      _key!.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  Future<void> _authenticate() async {
    if (_busy || !widget.enabled || _password.text.isEmpty) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final key = await widget.exportKey(_password.text);
      if (!mounted || epoch != _epoch || !widget.enabled) {
        key.fillRange(0, key.length, 0);
        return;
      }
      if (key.length != 32) {
        key.fillRange(0, key.length, 0);
        throw StateError('Invalid export');
      }
      setState(() {
        _key = key;
        _busy = false;
        _password.clear();
      });
      _expiry = Timer(const Duration(minutes: 1), () {
        if (mounted) setState(_clear);
      });
    } catch (_) {
      // Never interpolate native errors or secret values into UI/logs.
      if (mounted && epoch == _epoch) {
        setState(() {
          _busy = false;
          _password.clear();
          _message =
              'Could not export. Check your password and unlock the selected software account.';
        });
      }
    }
  }

  Future<void> _copy() async {
    if (_key == null || !widget.enabled) return;
    final epoch = _epoch;
    try {
      await SensitiveClipboard.copyText(_hex);
      if (mounted && epoch == _epoch) {
        setState(
          () => _message = 'Copied. Clear your clipboard after importing.',
        );
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() => _message = 'Could not copy the key.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => SensitivePrivacyOverlay(
    sensitiveContentVisible: _key != null,
    child: AlertDialog(
      title: const Text('Export Base account private key'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Anyone with this key can take all names and funds in this Base account. Never share it or send it to support.',
              ),
              const SizedBox(height: 12),
              Text('Base account: ${widget.owner}'),
              const SizedBox(height: 12),
              const Text(
                'Import this key as a separate account in MetaMask. Importing your Vizor seed may produce a different address. Both wallets will control this account.',
              ),
              const SizedBox(height: 16),
              if (!widget.enabled)
                const Text('Unlock the selected software account to continue.')
              else if (_key == null) ...[
                TextField(
                  key: const Key('zns-export-password'),
                  controller: _password,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Wallet password',
                  ),
                  onSubmitted: (_) => _authenticate(),
                ),
                TextButton(
                  key: const Key('zns-export-authenticate'),
                  onPressed: _busy ? null : _authenticate,
                  child: Text(_busy ? 'Authenticating…' : 'Confirm password'),
                ),
              ] else ...[
                if (_visible)
                  SelectableText(_hex, key: const Key('zns-export-secret'))
                else
                  const Text('Private key hidden'),
                Wrap(
                  children: [
                    TextButton(
                      key: const Key('zns-export-reveal'),
                      onPressed: () => setState(() => _visible = !_visible),
                      child: Text(_visible ? 'Hide key' : 'Reveal key'),
                    ),
                    TextButton(
                      key: const Key('zns-export-copy'),
                      onPressed: _copy,
                      child: const Text('Copy private key'),
                    ),
                  ],
                ),
                const Text(
                  'Cleared from this dialog after one minute or when you leave it. Your system clipboard may retain copied keys.',
                ),
              ],
              if (_message != null) Text(_message!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _clear();
            Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
