import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_http_transport.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_network_config.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_rpc_client.dart';

final config = ZnsNetworkConfig(
  chainId: 8453,
  rpcUri: Uri.parse('https://rpc.example'),
  registryAddress: '0x1111111111111111111111111111111111111111',
);

class _Time {
  DateTime value = DateTime.utc(2026, 9, 20);
  final waits = <Duration>[];
  DateTime now() => value;
  Future<void> wait(Duration duration) async {
    waits.add(duration);
    value = value.add(duration);
  }
}

class _Transport implements ZnsHttpTransport {
  _Transport(this.time);
  final _Time time;
  final calls = <Map<String, Object?>>[];
  final started = <DateTime>[];
  Future<Object?> Function(Map<String, Object?>)? reply;
  int active = 0, maxActive = 0;
  @override
  void close() {}
  @override
  Future<Object?> request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    active++;
    if (active > maxActive) maxActive = active;
    calls.add(body!);
    started.add(time.now());
    try {
      await Future<void>.delayed(Duration.zero);
      return reply == null
          ? {'jsonrpc': '2.0', 'id': body['id'], 'result': '0x2105'}
          : await reply!(body);
    } finally {
      active--;
    }
  }
}

void main() {
  late _Time time;
  late _Transport transport;
  late ZnsRpcClient rpc;
  setUp(() {
    time = _Time();
    transport = _Transport(time);
    rpc = ZnsRpcClient(
      config,
      transport: transport,
      wait: time.wait,
      now: time.now,
    );
  });
  tearDown(() => rpc.close());

  test('public Base endpoints receive their sustained-quota default', () {
    for (final endpoint in [
      'https://api.sybil.cash/api/base/rpc',
      'https://api.sybil.cash:443/api/base/rpc',
      'https://api.sybil.cash/api/base/rpc?token=custom',
      'https://api.sybil.cash/private',
      'https://mainnet.base.org',
      'https://mainnet.base.org:443/',
      'https://base.drpc.org',
      'https://base.drpc.org:443/',
      'https://mainnet.base.org/?token=custom',
      'https://mainnet.base.org/private',
      'https://base.drpc.org/?token=custom',
      'https://base.drpc.org/private',
      'https://rpc.example',
    ]) {
      final public =
          endpoint == 'https://api.sybil.cash/api/base/rpc' ||
          endpoint == 'https://api.sybil.cash:443/api/base/rpc' ||
          endpoint == 'https://mainnet.base.org' ||
          endpoint == 'https://mainnet.base.org:443/' ||
          endpoint == 'https://base.drpc.org' ||
          endpoint == 'https://base.drpc.org:443/';
      final client = ZnsRpcClient(
        ZnsNetworkConfig(
          chainId: 8453,
          rpcUri: Uri.parse(endpoint),
          registryAddress: config.registryAddress,
        ),
        transport: _Transport(time),
      );
      addTearDown(client.close);
      expect(
        client.requestSpacing,
        Duration(milliseconds: public ? 1100 : 250),
      );
    }
  });

  test(
    'public endpoint pacing spans clients, cancellation and recreation; explicit override opts out',
    () async {
      final publicConfig = ZnsNetworkConfig(
        chainId: 8453,
        rpcUri: Uri.parse('https://api.sybil.cash/api/base/rpc'),
        registryAddress: config.registryAddress,
      );
      final sharedTime = _Time();
      final starts = <DateTime>[];
      Future<void> sharedWait(Duration delay) async {
        // Yield before advancing virtual time so earlier permitted requests start.
        await Future<void>.delayed(Duration.zero);
        await sharedTime.wait(delay);
      }

      ZnsRpcClient create({Duration? spacing}) {
        final transport = _Transport(sharedTime);
        transport.reply = (body) async {
          starts.add(transport.started.last);
          return {'jsonrpc': '2.0', 'id': body['id'], 'result': '0x2105'};
        };
        final client = ZnsRpcClient(
          publicConfig,
          transport: transport,
          now: sharedTime.now,
          wait: sharedWait,
          requestSpacing: spacing,
        );
        addTearDown(client.close);
        return client;
      }

      final first = create(), second = create(), cancelled = create();
      final cancelledRequest = cancelled.request('eth_chainId', []);
      cancelled.close();
      await expectLater(cancelledRequest, throwsA(isA<ZnsDataException>()));
      await Future.wait([
        first.request('eth_chainId', []),
        second.request('eth_chainId', []),
      ]);
      first.close();
      final recreated = create();
      await recreated.request('eth_chainId', []);
      expect(starts, hasLength(3));
      for (var i = 1; i < starts.length; i++) {
        expect(
          starts[i].difference(starts[i - 1]),
          const Duration(milliseconds: 1100),
        );
      }
      final explicit = create(spacing: Duration.zero);
      await explicit.request('eth_chainId', []);
      expect(starts.last, starts[starts.length - 2]);
    },
  );

  test('concurrent snapshot reads are serialized and spaced', () async {
    await Future.wait(List.generate(7, (_) => rpc.request('eth_chainId', [])));
    expect(transport.maxActive, 1);
    expect(transport.calls, hasLength(7));
    for (var i = 1; i < transport.started.length; i++) {
      expect(
        transport.started[i].difference(transport.started[i - 1]),
        const Duration(milliseconds: 250),
      );
    }
  });

  test(
    'rate-limited read respects Retry-After then succeeds on same endpoint',
    () async {
      transport.reply = (body) async {
        if (transport.calls.length == 1) {
          throw const ZnsRateLimitException(retryAfter: Duration(seconds: 3));
        }
        return {'jsonrpc': '2.0', 'id': body['id'], 'result': '0x2105'};
      };
      expect(await rpc.request('eth_chainId', []), '0x2105');
      expect(transport.calls, hasLength(2));
      expect(time.waits, contains(const Duration(seconds: 3)));
      expect(
        transport.calls.map((call) => call['method']),
        everyElement('eth_chainId'),
      );
    },
  );

  test(
    'persistent throttling is bounded and queued reads do not multiply retries',
    () async {
      transport.reply = (_) async => throw const ZnsRateLimitException();
      await expectLater(
        Future.wait(List.generate(7, (_) => rpc.request('eth_chainId', []))),
        throwsA(
          isA<ZnsRateLimitException>().having(
            (e) => e.toString(),
            'safe request context',
            'Base RPC eth_chainId is temporarily busy. Wait a moment, then try again.',
          ),
        ),
      );
      expect(transport.calls, hasLength(3));
      transport.reply = null;
      await expectLater(
        rpc.request('eth_chainId', []),
        throwsA(isA<ZnsRateLimitException>()),
      );
      expect(transport.calls, hasLength(3));
      time.value = time.value.add(const Duration(seconds: 5));
      expect(await rpc.request('eth_chainId', []), '0x2105');
      expect(transport.calls, hasLength(4));
    },
  );

  test(
    'long Retry-After fails promptly without violating server cooldown',
    () async {
      transport.reply = (_) async =>
          throw const ZnsRateLimitException(retryAfter: Duration(seconds: 60));
      await expectLater(
        rpc.request('eth_call', []),
        throwsA(
          isA<ZnsRateLimitException>()
              .having((e) => e.rpcMethod, 'RPC method', 'eth_call')
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 60),
              ),
        ),
      );
      expect(transport.calls, hasLength(1));
      expect(time.waits, isEmpty);
      time.value = time.value.add(const Duration(seconds: 59));
      await expectLater(
        rpc.request('eth_call', []),
        throwsA(isA<ZnsRateLimitException>()),
      );
      expect(transport.calls, hasLength(1));
    },
  );

  test('raw signed transaction is never automatically retried', () async {
    transport.reply = (_) async => throw const ZnsRateLimitException();
    await expectLater(
      rpc.request('eth_sendRawTransaction', ['0x1234']),
      throwsA(isA<ZnsRateLimitException>()),
    );
    expect(transport.calls, hasLength(1));
    expect(time.waits, isEmpty);
  });

  test(
    'HTTP access denial explains endpoint recovery without retry or provider text',
    () async {
      for (final status in [401, 403]) {
        final http = _AccessDeniedHttp(status);
        final client = ZnsRpcClient(
          config,
          transport: ZnsPolicyHttpTransport(client: http),
          wait: time.wait,
          now: time.now,
        );
        addTearDown(client.close);
        await expectLater(
          client.request('eth_getTransactionReceipt', ['0x1234']),
          throwsA(
            isA<ZnsDataException>()
                .having((e) => e.code, 'status', status)
                .having(
                  (e) => e.message,
                  'safe recovery guidance',
                  'The selected Base RPC endpoint rejected access ($status). '
                      'Saved progress is retained. Choose a different endpoint in '
                      'Settings → Base RPC endpoint.',
                ),
          ),
        );
        expect(http.calls, 1);
        expect(time.waits, isEmpty);
      }
    },
  );

  test('RPC limit errors retry but contract reverts do not', () async {
    transport.reply = (body) async => {
      'jsonrpc': '2.0',
      'id': body['id'],
      'error': {
        'code': [-32005, -32016, 3][transport.calls.length - 1],
        'message': 'untrusted payload',
      },
    };
    await expectLater(
      rpc.request('eth_call', []),
      throwsA(isA<ZnsDataException>()),
    );
    expect(transport.calls, hasLength(3));
  });

  test(
    'RPC throttle codes report only the safe method after bounded retries',
    () async {
      for (final code in [429, -32005, -32016]) {
        final methodTime = _Time();
        final methodTransport = _Transport(methodTime)
          ..reply = (body) async => {
            'jsonrpc': '2.0',
            'id': body['id'],
            'error': {
              'code': code,
              'message': 'private provider URL, calldata and credentials',
            },
          };
        final client = ZnsRpcClient(
          config,
          transport: methodTransport,
          wait: methodTime.wait,
          now: methodTime.now,
        );
        addTearDown(client.close);
        await expectLater(
          client.request('eth_getTransactionReceipt', [
            'private transaction argument',
          ]),
          throwsA(
            isA<ZnsRateLimitException>()
                .having(
                  (e) => e.rpcMethod,
                  'RPC method',
                  'eth_getTransactionReceipt',
                )
                .having(
                  (e) => e.message,
                  'safe context',
                  'Base RPC eth_getTransactionReceipt is temporarily busy. Wait a moment, then try again.',
                ),
          ),
        );
        expect(methodTransport.calls, hasLength(3));
      }
    },
  );

  test('close during backoff cancels retry and queued work', () async {
    rpc.close();
    rpc = ZnsRpcClient(
      config,
      transport: transport,
      now: time.now,
      wait: (_) async => rpc.close(),
    );
    transport.reply = (_) async => throw const ZnsRateLimitException();
    await expectLater(
      Future.wait([
        rpc.request('eth_call', []),
        rpc.request('eth_chainId', []),
      ]),
      throwsA(isA<ZnsDataException>()),
    );
    expect(transport.calls, hasLength(1));
  });

  test(
    'HTTP 429 preserves Retry-After and presents a useful message',
    () async {
      final http = ZnsPolicyHttpTransport(client: _Http429());
      addTearDown(http.close);
      await expectLater(
        http.request('POST', config.rpcUri),
        throwsA(
          isA<ZnsRateLimitException>()
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 4),
              )
              .having(
                (e) => e.message,
                'message',
                isNot(contains('connectivity')),
              ),
        ),
      );
    },
  );

  test('Retry-After dates and invalid values are handled', () {
    final now = DateTime.utc(2026, 9, 20, 4, 0, 0);
    expect(
      znsRetryAfter('Sun, 20 Sep 2026 04:00:05 GMT', now: now),
      const Duration(seconds: 5),
    );
    expect(
      znsRetryAfter('Sun, 20 Sep 2026 03:00:00 GMT', now: now),
      Duration.zero,
    );
    expect(znsRetryAfter('not a date'), isNull);
    expect(znsRetryAfter('-1'), isNull);
  });
}

class _Http429 extends Fake implements NetworkHttpClient {
  @override
  Future<NetworkHttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> bodyBytes = const [],
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async => NetworkHttpResponse(
    statusCode: 429,
    bodyBytes: utf8.encode('provider-specific private details'),
    headers: const {
      'retry-after': ['4'],
    },
  );
  @override
  void close({bool force = false}) {}
}

class _AccessDeniedHttp extends Fake implements NetworkHttpClient {
  _AccessDeniedHttp(this.status);
  final int status;
  int calls = 0;

  @override
  Future<NetworkHttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> bodyBytes = const [],
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    calls++;
    return NetworkHttpResponse(
      statusCode: status,
      bodyBytes: utf8.encode(
        '{"error":{"code":-32602,"message":"Archive requests require a personal token; private provider details"}}',
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}
