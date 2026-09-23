import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/zns.dart' as rust;
import '../data/zns_http_transport.dart';
import '../data/zns_network_config.dart';
import '../data/zns_rpc_client.dart';
import '../domain/zns_operation.dart';
import '../presentation/zns_view_data.dart';

abstract interface class PublicNameLookupPreferenceStore {
  Future<bool> read();
  Future<void> write(bool enabled);
}

class SecurePublicNameLookupPreferenceStore
    implements PublicNameLookupPreferenceStore {
  static const _key = 'zcash_public_name_lookup_enabled';
  @override
  Future<bool> read() async =>
      await AppSecureStore.instance.readPlain(_key) == 'true';
  @override
  Future<void> write(bool enabled) =>
      AppSecureStore.instance.writePlain(_key, enabled ? 'true' : 'false');
}

final publicNameLookupPreferenceStoreProvider =
    Provider<PublicNameLookupPreferenceStore>(
      (_) => SecurePublicNameLookupPreferenceStore(),
    );

final publicNameLookupPreferenceProvider =
    AsyncNotifierProvider<PublicNameLookupPreference, bool>(
      PublicNameLookupPreference.new,
    );

class PublicNameLookupPreference extends AsyncNotifier<bool> {
  bool _saving = false;
  @override
  Future<bool> build() async {
    try {
      return await ref.watch(publicNameLookupPreferenceStoreProvider).read();
    } catch (_) {
      // Storage trouble must never silently enable public lookups.
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (_saving) return;
    _saving = true;
    state = const AsyncLoading();
    try {
      await ref.read(publicNameLookupPreferenceStoreProvider).write(enabled);
      state = AsyncData(enabled);
    } catch (_) {
      state = const AsyncData(false);
      throw const PublicNameLookupFailure(
        'Could not save this setting. Public lookups are off.',
      );
    } finally {
      _saving = false;
    }
  }
}

class PublicNameLookupSession {
  const PublicNameLookupSession({
    required this.accountUuid,
    required this.network,
    required this.unlocked,
  });
  final String? accountUuid;
  final String network;
  final bool unlocked;
  bool get available => unlocked && accountUuid != null;
}

final publicNameLookupSessionProvider = Provider<PublicNameLookupSession>(
  (ref) => PublicNameLookupSession(
    accountUuid: ref.watch(
      accountProvider.select((value) => value.asData?.value.activeAccountUuid),
    ),
    network: ref.watch(
      rpcEndpointFailoverProvider.select((value) => value.current.networkName),
    ),
    unlocked: ref.watch(
      appSecurityProvider.select((value) => value.isUnlocked),
    ),
  ),
);

class PublicNameLookupFailure implements Exception {
  const PublicNameLookupFailure(this.message);
  final String message;
}

class PublicNameResolution {
  const PublicNameResolution({
    required this.name,
    required this.address,
    required this.owner,
    required this.positionId,
  });
  final String name, address, owner;
  final BigInt positionId;

  bool sameRecipient(PublicNameResolution other) =>
      name == other.name &&
      address == other.address &&
      owner.toLowerCase() == other.owner.toLowerCase() &&
      positionId == other.positionId;
}

String normalizePublicZcashName(String input) {
  var label = input.trim().toLowerCase();
  if (label.endsWith('.zec')) label = label.substring(0, label.length - 4);
  return znsValidateLabel(label);
}

typedef PublicNameAddressValidator =
    Future<bool> Function(String network, String address);

final publicNameLookupServiceProvider = Provider<PublicNameLookupService>(
  (_) => PublicNameLookupService(),
);

/// Public record reads require no derived Base account, keys, token quotes or
/// registration-policy compatibility. The configured RPC remains a trust input.
class PublicNameLookupService {
  PublicNameLookupService({
    ZnsRpcClient Function(ZnsNetworkConfig)? rpcFactory,
    PublicNameAddressValidator? validateAddress,
  }) : _rpcFactory = rpcFactory ?? ZnsRpcClient.new,
       _validateAddress =
           validateAddress ??
           ((network, address) => rust.znsValidateUnifiedAddress(
             network: network,
             address: address,
           ));

  final ZnsRpcClient Function(ZnsNetworkConfig) _rpcFactory;
  final PublicNameAddressValidator _validateAddress;

  Future<PublicNameResolution> lookup({
    required ZnsConfigurationInput configuration,
    required String network,
    required String name,
  }) async {
    final label = normalizePublicZcashName(name);
    if (configuration.registryAddress.trim().isEmpty) {
      throw const PublicNameLookupFailure(
        'Set up the registry in Connection details first.',
      );
    }
    final rpc = _rpcFactory(
      ZnsNetworkConfig(
        chainId: configuration.chainId,
        rpcUri: Uri.parse(configuration.rpcUrl),
        registryAddress: configuration.registryAddress,
        allowLocalTestEndpoints:
            configuration.chainId == 31337 || configuration.chainId == 84532,
      ),
    );
    try {
      final record = await rpc.readNameRecord(label);
      final latest = await rpc.block();
      if (record.name != label ||
          !record.active ||
          record.owner == ZnsNetworkConfig.zeroAddress ||
          record.positionId <= BigInt.zero ||
          record.expiresAt <= latest.timestamp) {
        throw const PublicNameLookupFailure(
          'This name has no active receiving address.',
        );
      }
      if (record.unifiedAddress.isEmpty ||
          !await _validateAddress(network, record.unifiedAddress)) {
        throw const PublicNameLookupFailure(
          'This name has no valid receiving address for this Zcash network.',
        );
      }
      return PublicNameResolution(
        name: label,
        address: record.unifiedAddress,
        owner: record.owner,
        positionId: record.positionId,
      );
    } on ZnsDataException catch (error) {
      // A busy or throttled endpoint must not be reported as an unusable name or
      // as a registry mistake. Keep the transport's own wording, which names the
      // method and the wait.
      throw PublicNameLookupFailure(error.message);
    } finally {
      rpc.close();
    }
  }
}
