import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_build_defaults.dart';
import 'package:zcash_wallet/src/features/zns/presentation/zns_view_data.dart';

void main() {
  test('changing the RPC preserves the complete saved deployment', () {
    const initial = ZnsConfigurationInput(
      rpcUrl: 'https://old.example',
      chainId: 84532,
      registryAddress: '0x1111111111111111111111111111111111111111',
      tokenAddress: '0x2222222222222222222222222222222222222222',
      delegateAddress: '0x3333333333333333333333333333333333333333',
    );
    final changed = initial.withRpcUrl('https://custom.example/private-path');
    expect(changed.rpcUrl, 'https://custom.example/private-path');
    expect(changed.chainId, initial.chainId);
    expect(changed.registryAddress, initial.registryAddress);
    expect(changed.tokenAddress, initial.tokenAddress);
    expect(changed.delegateAddress, initial.delegateAddress);
    expect(initial.rpcUrl, 'https://old.example');
  });

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
      expect(config.rpcUrl, 'https://api.sybil.cash/api/base/rpc');
      expect(
        config.registryAddress,
        '0x17ea278fe9bee80449e7e576fb8fa4ec2f0ec3a5',
      );
      expect(config.tokenAddress, '0xB2000000000000000000008501b13360000cb2EC');
      expect(
        config.delegateAddress,
        '0x4f93112eb41dbec6fada4494272d3d410187a942',
      );
      expect(znsConfigurationStorageKey, 'zns:configuration:v1');
    }
  });
}
