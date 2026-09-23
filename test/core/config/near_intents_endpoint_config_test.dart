import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/core/config/near_intents_endpoint_config.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_provider_config.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_network_config.dart';

class RecordingTransport implements OneClickApiTransport {
  final uris = <Uri>[];
  final headers = <Map<String, String>>[];
  Map<String, Object?>? body;
  @override
  Future<OneClickHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    uris.add(uri);
    this.headers.add(headers);
    return uri.path.endsWith('/tokens')
        ? OneClickHttpResponse(
            statusCode: 200,
            body: jsonEncode([
              {
                'assetId': 'nep141:zec.omft.near',
                'decimals': 8,
                'blockchain': 'zec',
                'symbol': 'ZEC',
              },
              {
                'assetId': 'nep141:usdc.example',
                'decimals': 6,
                'blockchain': 'eth',
                'symbol': 'USDC',
              },
            ]),
          )
        : const OneClickHttpResponse(statusCode: 503, body: '{}');
  }

  @override
  Future<OneClickHttpResponse> post(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) async {
    uris.add(uri);
    this.headers.add(headers);
    this.body = body;
    return const OneClickHttpResponse(statusCode: 503, body: '{}');
  }
}

void main() {
  const address = '0x1111111111111111111111111111111111111111';
  test('wallet builds default to the public Sybil proxy', () {
    expect(
      NearIntentsEndpointConfig.build.requireBaseUri().toString(),
      'https://api.sybil.cash/api/near-intents/1click',
    );
    expect(NearIntentsEndpointConfig.build.allowLoopback, isFalse);
  });
  test(
    'HTTPS config preserves service prefix and rejects credentials or query secrets',
    () {
      expect(
        const NearIntentsEndpointConfig(
          baseUrl: 'https://api.sybil.cash/api/near-intents/1click/',
        ).requireBaseUri().toString(),
        'https://api.sybil.cash/api/near-intents/1click',
      );
      for (final value in [
        'http://sybil.cash/api',
        'https://token@sybil.cash/api',
        'https://sybil.cash/api?jwt=x',
        'https://sybil.cash/api#x',
        'file:///tmp/api',
        'https:///',
      ]) {
        expect(
          () => NearIntentsEndpointConfig(baseUrl: value).requireBaseUri(),
          throwsA(isA<NearIntentsConfigurationException>()),
        );
      }
    },
  );
  test('HTTP development endpoints require explicit exact-loopback opt-in', () {
    for (final host in ['localhost', '127.0.0.1', '[::1]']) {
      final value = 'http://$host:8787/api/near-intents/1click';
      expect(
        () => NearIntentsEndpointConfig(baseUrl: value).requireBaseUri(),
        throwsA(isA<NearIntentsConfigurationException>()),
      );
      expect(
        NearIntentsEndpointConfig(
          baseUrl: value,
          allowLoopback: true,
        ).requireBaseUri().scheme,
        'http',
      );
    }
    expect(
      () => const NearIntentsEndpointConfig(
        baseUrl: 'http://localhost.evil.test/api',
        allowLoopback: true,
      ).requireBaseUri(),
      throwsA(isA<NearIntentsConfigurationException>()),
    );
  });
  test('unconfigured service is lazy and does not open a transport', () async {
    final transport = RecordingTransport();
    final adapter = NearIntentsOneClickSwapAdapter(
      endpointConfig: const NearIntentsEndpointConfig(baseUrl: ''),
      transport: transport,
    );
    expect(adapter.providerLabel, 'NEAR Intents');
    await expectLater(
      adapter.listSupportedExternalAssets(),
      throwsA(
        isA<OneClickApiException>().having(
          (e) => e.message,
          'message',
          contains('not configured'),
        ),
      ),
    );
    expect(transport.uris, isEmpty);
    final config = ZnsNetworkConfig(
      chainId: 8453,
      rpcUri: Uri.parse('https://rpc.example'),
      registryAddress: address,
    );
    expect(config.registryAddress, address);
    expect(
      identical(config.oneClickEndpoint, NearIntentsEndpointConfig.build),
      isTrue,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final swap =
        container.read(swapIntentProvider) as NearIntentsOneClickSwapAdapter;
    expect(identical(swap.endpointConfig, config.oneClickEndpoint), isTrue);
    expect(swap.referral, isNull);
    expect(swap.bearerToken, isNull);
  });
  test('explicit local ZNS injection remains available', () {
    final local = Uri.parse('http://127.0.0.1:8787/api/near-intents/1click');
    final config = ZnsNetworkConfig(
      chainId: 31337,
      rpcUri: Uri.parse('http://localhost:8545'),
      registryAddress: address,
      oneClickBaseUri: local,
      allowLocalTestEndpoints: true,
    );
    expect(config.oneClickBaseUri, local);
  });
  test(
    'all wallet requests use Sybil paths without client secret referral or fee',
    () async {
      final transport = RecordingTransport();
      final adapter = NearIntentsOneClickSwapAdapter(
        endpointConfig: const NearIntentsEndpointConfig(
          baseUrl: 'https://api.sybil.cash/api/near-intents/1click',
        ),
        transport: transport,
      );
      await adapter.listSupportedExternalAssets();
      await expectLater(
        adapter.quote(
          const SwapQuoteRequest(
            direction: SwapDirection.zecToExternal,
            externalAsset: SwapAsset.usdc,
            sellAmount: 1,
            sellAmountText: '1',
            destination: '0xrecipient',
            refundAddress: 'u1refund',
          ),
        ),
        throwsA(isA<OneClickApiException>()),
      );
      expect(transport.body!.containsKey('referral'), isFalse);
      expect(transport.body!.containsKey('appFees'), isFalse);
      await expectLater(
        adapter.getStatus('deposit-fixture', depositMemo: 'memo'),
        throwsA(isA<OneClickApiException>()),
      );
      expect(transport.uris.last.queryParameters, {
        'depositAddress': 'deposit-fixture',
        'depositMemo': 'memo',
      });
      await expectLater(
        adapter.submitDepositTransaction(
          depositAddress: 'deposit-fixture',
          txHash: 'tx-fixture',
        ),
        throwsA(isA<OneClickApiException>()),
      );
      expect(transport.uris.map((uri) => uri.path), [
        '/api/near-intents/1click/v0/tokens',
        '/api/near-intents/1click/v0/quote',
        '/api/near-intents/1click/v0/status',
        '/api/near-intents/1click/v0/deposit/submit',
      ]);
      expect(
        transport.uris.every((uri) => uri.host == 'api.sybil.cash'),
        isTrue,
      );
      expect(
        transport.headers.every(
          (headers) => !headers.containsKey('authorization'),
        ),
        isTrue,
      );
    },
  );
}
