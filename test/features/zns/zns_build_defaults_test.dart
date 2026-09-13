import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_build_defaults.dart';
import 'package:zcash_wallet/src/features/zns/presentation/zns_view_data.dart';

void main() {
  test('Sepolia preset is opt-in and its saved configuration is isolated', () {
    const config = ZnsConfigurationInput();
    const requested = bool.fromEnvironment('ZNS_BASE_SEPOLIA');
    if (requested && kZcashDefaultNetworkRaw == 'test') {
      expect(config.chainId, 84532);
      expect(config.rpcUrl, 'https://sepolia.base.org');
      expect(
        config.registryAddress,
        '0x402c249649ccb865fe4f16bd26e61007244b2102',
      );
      expect(config.tokenAddress, '0xd8d322f879ff945f35ec355e021f3a6ad1cc0f88');
      expect(
        config.delegateAddress,
        '0xe1c5701477af9345d88dd25af41721f7d60e9cb2',
      );
      expect(
        znsConfigurationStorageKey,
        'zns:configuration:v1:84532:${config.registryAddress}',
      );
    } else {
      expect(config.chainId, 8453);
      expect(config.registryAddress, isEmpty);
      expect(znsConfigurationStorageKey, 'zns:configuration:v1');
    }
  });
}
