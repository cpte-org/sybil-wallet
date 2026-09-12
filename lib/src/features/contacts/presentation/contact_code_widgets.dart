import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/qr_scanner.dart';
import '../../address_scan/widgets/mobile_address_scan_card.dart';

const contactCodeByteLimit = 32768;

/// QR and clipboard carry the exact existing signed packet, with no additional
/// identity, encoding protocol or authority. Validation belongs to the caller.
String boundedContactCode(String value) {
  final code = value.trim();
  if (code.isEmpty) throw const FormatException('There is no code to open.');
  if (code.length > contactCodeByteLimit ||
      utf8.encode(code).length > contactCodeByteLimit) {
    throw const FormatException(
      'This code is too large. Ask for a new invitation.',
    );
  }
  return code;
}

class ContactCodeOutput extends StatefulWidget {
  const ContactCodeOutput({
    super.key,
    required this.data,
    this.title = 'Share this code',
    this.enabled = true,
    this.advanced = false,
    this.onCopy,
  });
  final String data, title;
  final bool enabled, advanced;
  final Future<void> Function(String)? onCopy;
  @override
  State<ContactCodeOutput> createState() => _ContactCodeOutputState();
}

class _ContactCodeOutputState extends State<ContactCodeOutput>
    with WidgetsBindingObserver {
  bool _hidden = false, _copying = false;
  String? _notice;
  late QrValidationResult _qr;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _makeQr();
  }

  void _makeQr() {
    _qr = QrValidator.validate(
      data: widget.data,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
    // The QR library fills its data buffer lazily. Validate that buffer here
    // too, so oversized invitations use Copy code instead of failing in paint.
    try {
      if (_qr.isValid) {
        QrImage.withMaskPattern(_qr.qrCode!, 0);
      }
    } on Exception catch (error) {
      _qr = QrValidationResult(
        status: QrValidationStatus.contentTooLong,
        error: error,
      );
    }
  }

  @override
  void didUpdateWidget(covariant ContactCodeOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _notice = null;
      _makeQr();
    }
    if (oldWidget.enabled && !widget.enabled) _notice = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      setState(() {
        _hidden = true;
        _notice = null;
      });
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _hidden = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _copy() async {
    if (_copying || !widget.enabled || _hidden) return;
    final data = widget.data;
    bool current() =>
        mounted && widget.data == data && widget.enabled && !_hidden;
    setState(() {
      _copying = true;
      _notice = null;
    });
    try {
      await (widget.onCopy ?? SensitiveClipboard.copyText)(data);
      if (current()) {
        setState(
          () => _notice =
              'Code copied. Share it with the person you intend to connect with.',
        );
      }
    } catch (_) {
      if (current()) setState(() => _notice = 'Could not copy. Try again.');
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final show = widget.enabled && !_hidden;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: AppTypography.bodyMediumStrong),
          const SizedBox(height: 16),
          if (show && _qr.isValid)
            LayoutBuilder(
              builder: (context, constraints) {
                final size = math.min(constraints.maxWidth, 360.0);
                return Center(
                  child: Semantics(
                    label:
                        'Contact QR code. The other person can scan this or use the copied code.',
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: QrImageView.withQr(
                        qr: _qr.qrCode!,
                        size: math.max(1, size - 32),
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                !show
                    ? 'This code is no longer available.'
                    : 'This invitation is too large for one QR code. Copy and share it instead.',
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: show && !_copying ? _copy : null,
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy code'),
            ),
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(_notice!, textAlign: TextAlign.center),
              ),
            ),
          if (widget.advanced && show)
            ExpansionTile(
              title: const Text('Code contents'),
              children: [
                SelectableText(widget.data, style: AppTypography.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}

class ContactCodeInput extends StatefulWidget {
  const ContactCodeInput({
    super.key,
    required this.onRead,
    this.title = 'Open a code',
    this.enabled = true,
    this.advanced = false,
  });
  final Future<void> Function(String) onRead;
  final String title;
  final bool enabled, advanced;
  @override
  State<ContactCodeInput> createState() => _ContactCodeInputState();
}

class _ContactCodeInputState extends State<ContactCodeInput>
    with WidgetsBindingObserver {
  final _manual = TextEditingController();
  bool _working = false;
  String? _error;
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
    _manual.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ContactCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _epoch++;
      _manual.clear();
      _error = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _epoch++;
      setState(() {
        _manual.clear();
        _error = null;
      });
    }
  }

  Future<void> _read(Future<String?> Function(int) acquire) async {
    if (!widget.enabled || _working) return;
    final epoch = ++_epoch;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final raw = await acquire(epoch);
      if (!mounted || epoch != _epoch || !widget.enabled || raw == null) return;
      await widget.onRead(boundedContactCode(raw));
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Could not open this code. Check who sent it and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: AppTypography.bodyMediumStrong),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: widget.enabled && !_working
                  ? () => _read(
                      (epoch) => Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => _ContactScannerPage(
                            isCurrent: () =>
                                mounted && widget.enabled && _epoch == epoch,
                          ),
                        ),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: const Text('Scan code'),
            ),
            OutlinedButton.icon(
              onPressed: widget.enabled && !_working
                  ? () => _read(
                      (_) async =>
                          (await Clipboard.getData(
                            Clipboard.kTextPlain,
                          ))?.text ??
                          '',
                    )
                  : null,
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('Paste code'),
            ),
          ],
        ),
        if (_working)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        if (widget.advanced)
          ExpansionTile(
            title: const Text('Enter code manually'),
            children: [
              TextField(
                controller: _manual,
                enabled: widget.enabled && !_working,
                minLines: 2,
                maxLines: 5,
                maxLength: contactCodeByteLimit,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Contact code'),
                onChanged: (_) => setState(() {}),
              ),
              TextButton(
                onPressed:
                    widget.enabled &&
                        !_working &&
                        _manual.text.trim().isNotEmpty
                    ? () => _read((_) async => _manual.text)
                    : null,
                child: const Text('Open code'),
              ),
            ],
          ),
      ],
    ),
  );
}

class _ContactScannerPage extends StatefulWidget {
  const _ContactScannerPage({required this.isCurrent});
  final bool Function() isCurrent;
  @override
  State<_ContactScannerPage> createState() => _ContactScannerPageState();
}

class _ContactScannerPageState extends State<_ContactScannerPage>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  late final Timer _guard;
  bool _completed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      facing: defaultQrScannerFacing,
      formats: QrScanner.formats,
      detectionSpeed: QrScanner.detectionSpeed,
    );
    _guard = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!widget.isCurrent()) _finish(null);
    });
  }

  void _finish(String? value) {
    if (_completed || !mounted) return;
    _completed = true;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop(widget.isCurrent() ? value : null);
    } else {
      // Lock or navigation may have covered the scanner. Close only this route.
      navigator.removeRoute(route);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _finish(null);
    }
  }

  @override
  void dispose() {
    _guard.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background.window,
    appBar: AppBar(title: const Text('Scan contact code')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                MobileQrScanCard(
                  controller: _controller,
                  onClose: () => _finish(null),
                  caption:
                      'Scan the code shown by the person you want to connect with.',
                  permissionTitle: 'Scan a contact code',
                  unavailableDescription:
                      'A camera could not be opened. Go back and use Paste code instead.',
                  cameraViewBuilder: (context, controller) =>
                      PlainQrScannerView(
                        controller: controller,
                        onComplete: _finish,
                      ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => _finish(null),
                  child: const Text('Back to paste a code'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
