import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/data/simplex_embedded_host.dart';
import 'package:zcash_wallet/src/features/contacts/data/simplex_native_transport.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.keplr.vizor/simplex');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Future<Object?> Function(MethodCall)? handler;
  setUp(() {
    calls.clear();
    handler = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (handler != null) return handler!(call);
      switch (call.method) {
        case 'availability':
          return true;
        case 'open':
          return '{"type":"ok"}';
        case 'poll':
          return '';
        case 'close':
          return null;
        default:
          return jsonEncode({
            'result': call.arguments['command'] == '/u'
                ? {
                    'type': 'activeUser',
                    'user': {'userId': 1},
                  }
                : {'type': 'ok'},
          });
      }
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  SimplexNativeTransport transport({bool Function()? allowed}) =>
      SimplexNativeTransport(
        scope: const ContactScope(
          accountUuid: 'disposable',
          network: 'regtest',
        ),
        networkAllowed: allowed ?? () => true,
        embeddedHost: AndroidSimplexHost(),
      );
  Future<void> open(SimplexNativeTransport value) => value.open(
    hostPath: '',
    libraryPath: '',
    databasePath: '/private/disposable/simplex',
    databaseKey: 'independent-key',
  );

  test('availability probes no core, missing plugin fails closed', () async {
    expect(await AndroidSimplexHost.available(), isTrue);
    expect(calls.map((c) => c.method), ['availability']);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await AndroidSimplexHost.available(), isFalse);
  });
  test(
    'shared initialization configures route before start; empty poll works',
    () async {
      final value = transport();
      await open(value);
      expect(
        calls
            .where((c) => c.method == 'command')
            .map((c) => c.arguments['command']),
        [
          '/u',
          '/network socks=off smp-proxy=always smp-proxy-fallback=no',
          '/_start',
        ],
      );
      expect(await value.poll(), isEmpty);
      value.close();
    },
  );
  test(
    'cancelled open cannot start networking; close is session scoped',
    () async {
      final pending = Completer<Object?>();
      handler = (call) async => call.method == 'open' ? pending.future : null;
      final value = transport();
      final opening = open(value);
      final rejected = expectLater(opening, throwsA(isA<ContactFailure>()));
      await Future<void>.delayed(Duration.zero);
      value.close();
      pending.complete('{"type":"ok"}');
      await rejected;
      expect(calls.map((c) => c.method), ['open', 'close']);
      expect(
        calls.first.arguments['sessionId'],
        calls.last.arguments['sessionId'],
      );
      final next = AndroidSimplexHost();
      final nextOpening = next.open('/private/new', 'key');
      await nextOpening;
      expect(
        calls.last.arguments['sessionId'],
        isNot(calls.first.arguments['sessionId']),
      );
      await next.close();
    },
  );
  test(
    'late command after privacy invalidation is rejected; queued work never sent',
    () async {
      var allowed = true;
      final value = transport(allowed: () => allowed);
      await open(value);
      final pending = Completer<Object?>();
      handler = (call) async =>
          call.method == 'command' ? pending.future : null;
      final first = value.command('/first');
      final second = value.command('/second');
      final rejectedFirst = expectLater(first, throwsA(isA<ContactFailure>()));
      final rejectedSecond = expectLater(
        second,
        throwsA(isA<ContactFailure>()),
      );
      await Future<void>.delayed(Duration.zero);
      allowed = false;
      pending.complete('{"result":{"type":"ok"}}');
      await Future.wait([rejectedFirst, rejectedSecond]);
      expect(
        calls.where(
          (c) => c.method == 'command' && c.arguments['command'] == '/second',
        ),
        isEmpty,
      );
      expect(calls.last.method, 'close');
    },
  );
  test(
    'commands serialize and oversized or malformed responses terminate session',
    () async {
      final value = transport();
      await open(value);
      final pending = Completer<Object?>();
      handler = (call) async {
        if (call.method != 'command') return null;
        if (call.arguments['command'] == '/first') return pending.future;
        return '{"result":{"type":"ok"}}';
      };
      final first = value.command('/first');
      final second = value.command('/second');
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.arguments['command'], '/first');
      pending.complete('{"result":{"type":"ok"}}');
      await Future.wait([first, second]);
      expect(calls.last.arguments['command'], '/second');
      handler = (call) async =>
          call.method == 'command' ? 'x' * (256 * 1024 + 1) : null;
      await expectLater(
        value.command('/oversize'),
        throwsA(isA<ContactFailure>()),
      );
      expect(calls.last.method, 'close');
    },
  );
  test('replacement open waits for prior native process death', () async {
    final first = AndroidSimplexHost(), second = AndroidSimplexHost();
    await first.open('/private/one', 'key');
    final pendingClose = Completer<Object?>();
    handler = (call) async {
      if (call.method == 'close') return pendingClose.future;
      return '{"type":"ok"}';
    };
    final closing = first.close();
    final replacement = second.open('/private/two', 'key');
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.method == 'open').length, 1);
    pendingClose.complete(null);
    await closing;
    await replacement;
    expect(calls.where((c) => c.method == 'open').length, 2);
    await second.close();
  });

  test(
    'closed old host cannot close replacement; close is idempotent',
    () async {
      final first = AndroidSimplexHost(), second = AndroidSimplexHost();
      await first.open('/private/one', 'key');
      await first.close();
      await second.open('/private/two', 'key');
      await first.close();
      expect(calls.where((c) => c.method == 'close').length, 1);
      expect(calls.last.method, 'open');
      await second.close();
    },
  );
  test(
    'locked scope never opens host and invalid command never reaches native',
    () async {
      final locked = transport(allowed: () => false);
      await expectLater(open(locked), throwsA(isA<ContactFailure>()));
      expect(calls.where((c) => c.method == 'open'), isEmpty);
      final value = transport();
      await open(value);
      await expectLater(
        value.command('/bad\ncommand'),
        throwsA(isA<ContactFailure>()),
      );
      value.close();
    },
  );
}
