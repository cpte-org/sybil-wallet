import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../domain/contact_models.dart';

/// The embedded host owns native state; protocol and reconciliation stay in
/// SimplexNativeTransport. Closing is deliberately independent of command IPC.
abstract interface class SimplexEmbeddedHost {
  Future<Map<String, dynamic>> open(String databasePath, String databaseKey);
  Future<Map<String, dynamic>> command(String command);
  Future<Map<String, dynamic>> poll();
  Future<void> close();
}

class AndroidSimplexHost implements SimplexEmbeddedHost {
  AndroidSimplexHost({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.keplr.vizor/simplex');

  // Native close acknowledges Binder death. Keep this process-wide because
  // Riverpod can dispose one host and create its replacement in the same frame.
  static Future<bool> _shutdown = Future<bool>.value(true);
  final MethodChannel _channel;
  final String _sessionId = base64Url.encode(
    List<int>.generate(24, (_) => Random.secure().nextInt(256)),
  );
  bool _closed = false;
  Future<void>? _closing;

  /// Metadata probe only: must not bind the service or load the native core.
  static Future<bool> available({MethodChannel? channel}) async {
    try {
      return await (channel ?? const MethodChannel('com.keplr.vizor/simplex'))
              .invokeMethod<bool>('availability') ==
          true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String method, [
    Map<String, String> arguments = const {},
  ]) async {
    if (_closed) throw const ContactFailure('Private delivery is closed.');
    try {
      final raw = await _channel
          .invokeMethod<String>(method, {'sessionId': _sessionId, ...arguments})
          .timeout(const Duration(seconds: 45));
      if (_closed || raw == null || utf8.encode(raw).length > 256 * 1024) {
        throw const ContactFailure('Private delivery disconnected.');
      }
      if (raw.isEmpty && method == 'poll') return {};
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) {
        throw const ContactFailure(
          'Private delivery returned an invalid response.',
        );
      }
      return value;
    } catch (_) {
      unawaited(close());
      throw const ContactFailure(
        'Private delivery disconnected. The saved packet can be retried.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> open(
    String databasePath,
    String databaseKey,
  ) async {
    if (!await _shutdown) {
      throw const ContactFailure(
        'Private delivery could not confirm shutdown. Restart the app before reopening it.',
      );
    }
    return _invoke('open', {
      'databasePath': databasePath,
      'databaseKey': databaseKey,
    });
  }

  @override
  Future<Map<String, dynamic>> command(String command) =>
      _invoke('command', {'command': command});

  @override
  Future<Map<String, dynamic>> poll() => _invoke('poll');

  @override
  Future<void> close() {
    _closed = true;
    if (_closing != null) return _closing!;
    final previous = _shutdown;
    // Dispatch immediately, independently of pending open/command IPC.
    final current = _close();
    _shutdown = Future.wait([
      previous,
      current,
    ]).then((results) => results.every((ok) => ok));
    return _closing = _shutdown.then((_) {});
  }

  Future<bool> _close() async {
    try {
      await _channel
          .invokeMethod<void>('close', {'sessionId': _sessionId})
          .timeout(const Duration(seconds: 10));
      return true;
    } catch (_) {
      // An error/timeout is not proof of native death. Fail subsequent opens
      // closed while letting the UI finish. Never log connection diagnostics.
      return false;
    }
  }
}
