import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../application/contact_delivery_coordinator.dart';
import '../domain/contact_delivery.dart';
import '../domain/contact_models.dart';

/// Experimental desktop adapter. The dedicated native host has no listening
/// socket and is killed on invalidation, taking its native key state with it.
/// Android/iOS embedding is intentionally not claimed by this Linux adapter.
class SimplexNativeTransport
    implements ContactPacketTransport, ContactChannelTransport {
  SimplexNativeTransport({required this.scope, required this.networkAllowed});
  @override
  final ContactScope scope;
  final bool Function() networkAllowed;
  Process? _process;
  StreamSubscription<List<int>>? _output, _errors;
  Completer<Map<String, dynamic>>? _response;
  Future<void> _tail = Future.value();
  final _line = <int>[];
  bool _closed = false;
  int? _user;

  void _check() {
    if (_closed || !networkAllowed()) {
      close();
      throw const ContactFailure(
        'Private delivery is paused by wallet privacy or lock settings.',
      );
    }
  }

  Future<void> open({
    required String hostPath,
    required String libraryPath,
    required String databasePath,
    required String databaseKey,
  }) async {
    if (_process != null || _closed) {
      throw const ContactFailure('Delivery is already open or closed.');
    }
    _check();
    if (!Platform.isLinux ||
        !hostPath.startsWith('/') ||
        !libraryPath.startsWith('/') ||
        !databasePath.startsWith('/') ||
        [databasePath, databaseKey].any(
          (v) => v.contains('\n') || v.contains('\r') || v.contains('\x00'),
        ) ||
        databasePath.length > 4000 ||
        databaseKey.isEmpty ||
        databaseKey.length > 200) {
      throw const ContactFailure(
        'The native delivery configuration is unavailable.',
      );
    }
    final process = await Process.start(hostPath, [
      libraryPath,
    ], runInShell: false);
    _process = process;
    if (_closed || !networkAllowed()) {
      close();
      _check();
    }
    _output = process.stdout.listen(
      (chunk) {
        for (final byte in chunk) {
          if (_line.length >= 1024 * 1024) {
            close();
            return;
          }
          if (byte == 10) {
            try {
              final value = jsonDecode(utf8.decode(_line));
              final response = _response;
              _response = null;
              if (value is! Map<String, dynamic> || response == null) {
                close();
                return;
              }
              response.complete(value);
            } catch (_) {
              close();
              return;
            }
            _line.clear();
          } else {
            _line.add(byte);
          }
        }
      },
      onError: (_) => close(),
      onDone: close,
    );
    // Never put core diagnostics (which can contain connection details) into
    // application logs. Unexpected process exit surfaces a generic error.
    _errors = process.stderr.listen((_) {}, onError: (_) => close());
    unawaited(process.exitCode.then((_) => close()));
    try {
      final initialized = await _request('$databasePath\n$databaseKey');
      if (initialized['type'] != 'ok') {
        throw const ContactFailure(
          'The encrypted delivery database could not be opened.',
        );
      }
      // Profile creation is local; the core is still in maintenance mode.
      var user = await _rawCommand('/u');
      if (user['error'] != null) {
        final error = user['error'];
        if (error is! Map ||
            error['errorType'] is! Map ||
            error['errorType']['type'] != 'noActiveUser') {
          throw const ContactFailure('The delivery profile could not be read.');
        }
        user = await _rawCommand(
          '/_create user {"profile":{"displayName":"Contact","fullName":""},"pastTimestamp":false,"userChatRelay":false,"clientService":false}',
        );
      }
      final value = user['result'];
      if (value is! Map ||
          value['type'] != 'activeUser' ||
          value['user'] is! Map ||
          value['user']['userId'] is! int) {
        throw const ContactFailure(
          'The delivery profile could not be initialized.',
        );
      }
      _user = value['user']['userId'] as int;
      // Routing is installed before starting network activity.
      await command(
        '/network socks=off smp-proxy=always smp-proxy-fallback=no',
      );
      await command('/_start');
    } catch (_) {
      close();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _request(String line) async {
    _check();
    final process = _process;
    if (process == null || _response != null) {
      throw const ContactFailure('Private delivery is busy.');
    }
    final response = Completer<Map<String, dynamic>>();
    _response = response;
    try {
      process.stdin.writeln(line);
      final result = await response.future.timeout(const Duration(seconds: 45));
      _check();
      return result;
    } catch (_) {
      close();
      throw const ContactFailure(
        'Private delivery disconnected. The saved packet can be retried.',
      );
    }
  }

  Future<Map<String, dynamic>> _rawCommand(String cmd) {
    if (cmd.contains('\n') ||
        cmd.contains('\r') ||
        cmd.contains('\x00') ||
        utf8.encode(cmd).length > 120000) {
      throw const ContactFailure('Invalid private delivery command.');
    }
    return _serialized(() => _request('CMD $cmd'));
  }

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _tail, done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      _check();
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<Map<String, dynamic>> command(String cmd) async {
    final response = await _rawCommand(cmd), result = response['result'];
    if (result is! Map<String, dynamic> ||
        response['error'] != null ||
        result['type'] == 'chatCmdError') {
      throw const ContactFailure(
        'SimpleX could not complete this action. Retry after checking the connection.',
      );
    }
    return result;
  }

  Future<String> createInvitation() async {
    final r = await command('/_connect $_user incognito=on');
    final link = r['connLinkInvitation'];
    if (link is! Map || link['connFullLink'] is! String) {
      throw const ContactFailure('No invitation was returned.');
    }
    return link['connFullLink'] as String;
  }

  Future<void> connect(String invitation) async {
    if (!invitation.startsWith('simplex:/invitation#') ||
        invitation.length > 16384 ||
        invitation.contains(RegExp(r'\s'))) {
      throw const ContactFailure('Use a SimpleX one-time invitation link.');
    }
    await command('/connect $invitation');
  }

  Future<List<({String id, String label})>> peers() async {
    final r = await command('/_contacts $_user'), contacts = r['contacts'];
    if (contacts is! List || contacts.length > 100) {
      throw const ContactFailure(
        'The delivery connection list is unavailable or too large.',
      );
    }
    return [
      for (final c in contacts)
        if (c is Map && c['contactId'] is int && c['contactId'] > 0)
          (
            id: c['contactId'].toString(),
            label: c['localDisplayName'] is String
                ? (c['localDisplayName'] as String).substring(
                    0,
                    (c['localDisplayName'] as String).length.clamp(0, 80),
                  )
                : 'Connection',
          ),
    ];
  }

  @override
  Future<String> securityCode(String peer) async {
    final id = int.tryParse(peer);
    if (id == null || id < 1) {
      throw const ContactFailure('Invalid delivery connection.');
    }
    final result = await command('/_get code @$id');
    final code = result['connectionCode'];
    if (result['type'] != 'contactCode' ||
        code is! String ||
        !RegExp(r'^[0-9 ]{20,160}$').hasMatch(code)) {
      throw const ContactFailure(
        'The connection security code is unavailable.',
      );
    }
    return code.replaceAll(' ', '');
  }

  /// Reconcile durable native history rather than relying on transient events.
  /// Walk all pages so crashes between native receipt and wallet save
  /// cannot silently drop messages. Journal tombstones make this idempotent.
  Future<void> reconcile(ContactDeliveryCoordinator coordinator) async {
    for (final peer in await peers()) {
      int? before;
      for (var page = 0; ; page++) {
        if (page >= 20) {
          throw const ContactFailure(
            'Delivery history exceeds this experiment’s limit. No history was discarded.',
          );
        }
        final r = await command(
          '/_get chat @${peer.id} ${before == null ? '' : 'before=$before '}count=100',
        );
        final chat = r['chat'];
        if (chat is! Map || chat['chatItems'] is! List) {
          throw const ContactFailure('Delivery history could not be read.');
        }
        final items = chat['chatItems'] as List;
        if (items.length > 100) {
          throw const ContactFailure('Delivery history is too large.');
        }
        int? next;
        for (final item in items) {
          if (item is! Map ||
              item['meta'] is! Map ||
              item['meta']['itemId'] is! int) {
            throw const ContactFailure('Delivery history has an invalid item.');
          }
          final itemId = item['meta']['itemId'] as int;
          if (next == null || itemId < next) next = itemId;
          final packet = incomingPacket(item, scope.network);
          if (packet != null) {
            await coordinator.receive(scope, peer.id, packet.id, packet.packet);
            _check();
          }
        }
        if (items.length < 100) break;
        if (next == null || (before != null && next >= before)) {
          throw const ContactFailure('Delivery history did not advance.');
        }
        before = next;
      }
    }
  }

  @override
  Future<void> submit(String peer, String deliveryId, String packet) async {
    final contactId = int.tryParse(peer);
    if (contactId == null || contactId < 1) {
      throw const ContactFailure('Invalid delivery peer.');
    }
    final envelope = jsonEncode({
      'domain': 'zcash-contact/transport',
      'network': scope.network,
      'id': deliveryToken(deliveryId),
      'packet': deliveryPacket(packet),
    });
    final r = await command(
      '/_send @$contactId json ${jsonEncode([
        {
          'msgContent': {'type': 'text', 'text': envelope},
        },
      ])}',
    );
    if (r['type'] != 'newChatItems') {
      throw const ContactFailure('The packet was not submitted.');
    }
  }

  /// A poll can be lost on shutdown, so callers must also reconcile persisted
  /// native chat history. An event by itself is not the durable delivery inbox.
  Future<Map<String, dynamic>> poll() => _serialized(() async {
    final r = await _request('POLL');
    return r['result'] is Map<String, dynamic>
        ? r['result'] as Map<String, dynamic>
        : <String, dynamic>{};
  });

  void close() {
    _closed = true;
    _process?.kill(ProcessSignal.sigkill);
    _process = null;
    unawaited(_output?.cancel());
    unawaited(_errors?.cancel());
    _line.clear();
    final pending = _response;
    _response = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const ContactFailure('Private delivery is closed.'),
      );
    }
  }
}

/// Strict carrier parsing. It intentionally returns untrusted bytes for later
/// signature/audience/freshness verification by the contact coordinator.
({String id, String packet})? incomingPacket(Map item, String network) {
  if (item['chatDir'] is! Map ||
      item['chatDir']['type'] != 'directRcv' ||
      item['content'] is! Map ||
      item['content']['type'] != 'rcvMsgContent') {
    return null;
  }
  final content = item['content']['msgContent'];
  if (content is! Map ||
      content['type'] != 'text' ||
      content['text'] is! String) {
    return null;
  }
  final text = content['text'] as String;
  if (text.length > 120000 || utf8.encode(text).length > 120000) return null;
  try {
    final map = contactObject(jsonDecode(text), {
      'domain',
      'network',
      'id',
      'packet',
    });
    if (map['domain'] != 'zcash-contact/transport' ||
        map['network'] != network) {
      return null;
    }
    return (
      id: deliveryToken(map['id']),
      packet: deliveryPacket(map['packet']),
    );
  } catch (_) {
    return null;
  }
}
