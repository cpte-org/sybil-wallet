import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/features/zns/domain/zns_operation.dart';

void main() {
  test(
    'live funding uses the wallet canonical main network and Base mainnet',
    () {
      ZnsScope scope(String network, int chain) => ZnsScope(
        zcashNetwork: network,
        chainId: chain,
        registry: '0x1111111111111111111111111111111111111111',
        owner: '0x2222222222222222222222222222222222222222',
      );
      expect(
        scope(ZcashNetwork.mainnet.name, 8453).supportsLiveZecFunding,
        isTrue,
      );
      for (final network in [
        ZcashNetwork.testnet.name,
        ZcashNetwork.regtest.name,
        '',
        'mainnet',
      ]) {
        expect(scope(network, 8453).supportsLiveZecFunding, isFalse);
      }
      expect(
        scope(ZcashNetwork.mainnet.name, 84532).supportsLiveZecFunding,
        isFalse,
      );
    },
  );
}
