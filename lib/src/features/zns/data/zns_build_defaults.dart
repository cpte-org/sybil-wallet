import '../../../core/config/network_config.dart';

/// Explicit test builds use the published Sepolia deployment without changing
/// production defaults or overwriting another deployment's saved settings.
const znsTestnetPreset =
    kZcashDefaultNetworkRaw == 'test' &&
    bool.fromEnvironment('ZNS_BASE_SEPOLIA', defaultValue: false);
const znsDefaultRpc = znsTestnetPreset
    ? 'https://sepolia.base.org'
    : 'https://mainnet.base.org';
const znsDefaultChainId = znsTestnetPreset ? 84532 : 8453;
const znsDefaultRegistry = znsTestnetPreset
    ? '0x402c249649ccb865fe4f16bd26e61007244b2102'
    : '';
const znsDefaultToken = znsTestnetPreset
    ? '0xd8d322f879ff945f35ec355e021f3a6ad1cc0f88'
    : '0xB2000000000000000000008501b13360000cb2EC';
const znsDefaultDelegate = znsTestnetPreset
    ? '0xe1c5701477af9345d88dd25af41721f7d60e9cb2'
    : '';
const znsConfigurationStorageKey = znsTestnetPreset
    ? 'zns:configuration:v1:84532:$znsDefaultRegistry'
    : 'zns:configuration:v1';
