import '../../../core/config/network_config.dart';

/// Explicit test builds use the published Sepolia deployment without changing
/// production defaults or overwriting another deployment's saved settings.
const znsTestnetPreset =
    kZcashDefaultNetworkRaw == 'test' &&
    bool.fromEnvironment('ZNS_BASE_SEPOLIA', defaultValue: false);

/// The mainnet gateway keeps the provider token on the server. Saved custom
/// endpoints take precedence over these build defaults.
const znsMainnetRpc = 'https://api.sybil.cash/api/base/rpc';
const znsSepoliaRpc = 'https://sepolia.base.org';
const znsDefaultRpc = znsTestnetPreset ? znsSepoliaRpc : znsMainnetRpc;
const znsDefaultChainId = znsTestnetPreset ? 84532 : 8453;
const znsDefaultRegistry = znsTestnetPreset
    ? '0x402c249649ccb865fe4f16bd26e61007244b2102'
    : '0x17ea278fe9bee80449e7e576fb8fa4ec2f0ec3a5';
const znsDefaultToken = znsTestnetPreset
    ? '0xd8d322f879ff945f35ec355e021f3a6ad1cc0f88'
    : '0xB2000000000000000000008501b13360000cb2EC';
const znsDefaultDelegate = znsTestnetPreset
    ? '0xe1c5701477af9345d88dd25af41721f7d60e9cb2'
    : '0x4f93112eb41dbec6fada4494272d3d410187a942';
const znsConfigurationStorageKey = znsTestnetPreset
    ? 'zns:configuration:v1:84532:$znsDefaultRegistry'
    : 'zns:configuration:v1';
