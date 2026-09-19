import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../application/contact_exchange_controller.dart';

/// Explains the existing gate; never grants exchange or payment authority.
final contactUnavailableMessageProvider = Provider<String?>((ref) {
  if (ref.watch(contactScopeProvider) != null) return null;
  if (!ref.watch(appSecurityProvider).isUnlocked) {
    return 'Unlock your wallet to connect with someone.';
  }
  if (!ref.watch(contactExperimentEnabledProvider)) {
    return 'Private connections are not enabled in this build. You can still save a name and Zcash address.';
  }
  final account = ref.watch(accountProvider);
  if (account.isLoading) return 'Opening your account…';
  if (account.hasError || account.value?.activeAccount == null) {
    return 'Open a wallet account to connect with someone.';
  }
  if (account.value!.activeAccount!.isHardware) {
    return 'Private connections do not support hardware accounts yet. You can still save a name and Zcash address.';
  }
  final network = ref.watch(rpcEndpointFailoverProvider).current.networkName;
  if (!['test', 'regtest'].contains(network)) {
    return 'Private connections are being tested on testnet. You can save names and addresses on this network.';
  }
  return 'Private connections are paused. Reopen People after unlocking your wallet.';
});
