import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/rpc_endpoint_failover_provider.dart';
import '../zns/application/zns_wallet_gateway.dart';
import 'widgets/base_key_export_dialog.dart';

class BaseKeyExportAccess {
  const BaseKeyExportAccess(this.owner, this.exportKey);
  final String owner;
  final Future<Uint8List> Function(String) exportKey;
}

// Account recovery must work without a configured or reachable Names registry.
final baseKeyExportAccessProvider =
    FutureProvider.autoDispose<BaseKeyExportAccess?>((ref) async {
      final account = ref.watch(accountProvider).value?.activeAccount;
      final locked = ref.watch(
        appSecurityProvider.select((s) => s.requiresUnlock),
      );
      final network = ref.watch(
        rpcEndpointFailoverProvider.select((s) => s.current.networkName),
      );
      var alive = true;
      ref.onDispose(() => alive = false);
      if (locked || account == null || account.isHardware) return null;
      final uuid = account.uuid;
      bool current() =>
          alive &&
          !ref.read(appSecurityProvider).requiresUnlock &&
          ref.read(accountProvider).value?.activeAccountUuid == uuid &&
          ref.read(rpcEndpointFailoverProvider).current.networkName == network;
      final identity = await ZnsWalletGateway.account(ref, uuid, network);
      if (!current()) return null;
      final owner = identity['address'] as String;
      return BaseKeyExportAccess(owner, (password) async {
        if (!current()) {
          throw StateError('Account changed. Authenticate again.');
        }
        if (!await ref
            .read(appSecurityProvider.notifier)
            .confirmPassword(password)) {
          throw StateError('Incorrect password.');
        }
        if (!current()) {
          throw StateError('Account changed. Authenticate again.');
        }
        final key = await ZnsWalletGateway.exportKey(ref, uuid, network, owner);
        if (!current()) {
          key.fillRange(0, key.length, 0);
          throw StateError('Account changed. Authenticate again.');
        }
        return key;
      });
    });

Future<void> showBaseKeyExport(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => Consumer(
    builder: (context, ref, _) {
      final access = ref.watch(baseKeyExportAccessProvider);
      final uuid = ref.watch(accountProvider).value?.activeAccountUuid;
      final network = ref
          .watch(rpcEndpointFailoverProvider)
          .current
          .networkName;
      final value = access.asData?.value;
      return BaseKeyExportDialog(
        session: '$uuid:$network:${value?.owner}',
        owner: value?.owner ?? 'Unavailable',
        enabled: value != null,
        exportKey:
            value?.exportKey ?? (_) async => throw StateError('Unavailable'),
      );
    },
  ),
);
