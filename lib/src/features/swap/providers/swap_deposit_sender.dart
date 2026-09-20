// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/linux_keyring_coordinator.dart';
import '../../../core/storage/linux_secret_operation_guard.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../send/services/send_flow.dart';
import '../domain/swap_contract.dart';
import '../models/swap_deposit_broadcast_result.dart';

final swapDepositSenderProvider = Provider<SwapDepositSender>((ref) {
  return RustSwapDepositSender(ref);
});

abstract interface class SwapDepositSender {
  Future<BigInt> estimateZecDepositFee({
    required String accountUuid,
    required SwapQuote quote,
  });

  Future<SwapDepositBroadcastResult> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
    BigInt? maximumFeeZatoshi,
  });
}

class RustSwapDepositSender implements SwapDepositSender {
  RustSwapDepositSender(this._ref, {this.beforeSoftwareSign});

  final Ref _ref;
  int _depositRequestGeneration = 0;

  /// Optional authorization and actual proposal fee check for a composed workflow. Ordinary
  /// swaps retain their existing review flow when this callback is absent.
  final void Function(BigInt feeZatoshi)? beforeSoftwareSign;

  @override
  Future<BigInt> estimateZecDepositFee({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    if (quote.sellAsset != SwapAsset.zec) {
      throw StateError('Only ZEC deposits can be sent by this wallet');
    }

    final amountZatoshi = zecDepositAmountZatoshiForQuote(quote);
    final fee = await _ref
        .read(syncProvider.notifier)
        .runWithAuthoritativeSpendable(
          accountUuid: accountUuid,
          operation: () async {
            final dbPath = await getWalletDbPath();
            final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
            log(
              'SwapDepositSender: preflight begin '
              'deposit=${_shortSwapValue(quote.depositInstruction.address)} '
              'zatoshi=$amountZatoshi',
            );
            return rust_sync.estimateFee(
              dbPath: dbPath,
              network: endpoint.networkName,
              accountUuid: accountUuid,
              toAddress: quote.depositInstruction.address,
              amountZatoshi: amountZatoshi,
            );
          },
        );
    log('SwapDepositSender: preflight complete fee=$fee');
    return fee;
  }

  @override
  Future<SwapDepositBroadcastResult> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
    BigInt? maximumFeeZatoshi,
  }) async {
    final requestGeneration = ++_depositRequestGeneration;
    final secretGuard = LinuxSecretOperationGuard(
      store: _ref.read(linuxSecretOperationStoreProvider),
      coordinator: _ref.read(linuxKeyringCoordinatorProvider),
      isRequestCurrent: () =>
          _ref.mounted && requestGeneration == _depositRequestGeneration,
      readAccounts: () => _ref.read(accountProvider).value,
      accountUuid: accountUuid,
    );
    if (quote.sellAsset != SwapAsset.zec) {
      throw StateError('Only ZEC deposits can be sent by this wallet');
    }

    final amountZatoshi = zecDepositAmountZatoshiForQuote(quote);
    final sendFlowId = _newSwapSendFlowId();
    // Capture the notifier while the provider is alive. Proposal cleanup may
    // finish after the initiating surface has been disposed.
    final syncNotifier = _ref.read(syncProvider.notifier);
    BigInt? proposalId;
    var proposalConsumed = false;

    try {
      log(
        'SwapDepositSender: propose begin flow=$sendFlowId '
        'deposit=${_shortSwapValue(quote.depositInstruction.address)} '
        'zatoshi=$amountZatoshi',
      );
      final proposalContext = await _ref
          .read(syncProvider.notifier)
          .runWithAuthoritativeSpendable(
            accountUuid: accountUuid,
            operation: () async {
              final dbPath = await getWalletDbPath();
              secretGuard.check();
              final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
              final proposal = await rust_sync.proposeSend(
                dbPath: dbPath,
                network: endpoint.networkName,
                accountUuid: accountUuid,
                sendFlowId: sendFlowId,
                toAddress: quote.depositInstruction.address,
                amountZatoshi: amountZatoshi,
              );
              return (proposal: proposal, dbPath: dbPath, endpoint: endpoint);
            },
          );
      final proposal = proposalContext.proposal;
      final dbPath = proposalContext.dbPath;
      final endpoint = proposalContext.endpoint;
      proposalId = proposal.proposalId;
      secretGuard.check();
      log(
        'SwapDepositSender: proposal ready flow=$sendFlowId '
        'proposal=${proposal.proposalId} '
        'needsSapling=${proposal.needsSaplingParams}',
      );

      if (proposal.needsSaplingParams) {
        throw StateError(
          'Sapling parameter download is not supported in the swap UI yet',
        );
      }

      late final rust_sync.ExecuteProposalResult result;
      log(
        'SwapDepositSender: broadcast begin flow=$sendFlowId '
        'proposal=${proposal.proposalId}',
      );

      if (Platform.isMacOS && !secretGuard.enabled) {
        checkSwapDepositFee(proposal.feeZatoshi, maximumFeeZatoshi);
        beforeSoftwareSign?.call(proposal.feeZatoshi);
        final password = _ref
            .read(appSecurityProvider.notifier)
            .requireSessionPasswordForNativeSecretUse();
        result = await rust_sync.executeProposalWithMacosStoredMnemonic(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          proposalId: proposal.proposalId,
          sendFlowId: sendFlowId,
          password: password,
        );
      } else {
        final mnemonicBytes = await _ref
            .read(accountProvider.notifier)
            .getMnemonicBytesForAccount(accountUuid);
        late final Future<rust_sync.ExecuteProposalResult> resultFuture;
        try {
          secretGuard.check();
          if (secretGuard.enabled) {
            final deadline = quote.actionDeadline;
            if (deadline != null &&
                !DateTime.now().toUtc().isBefore(deadline)) {
              throw StateError(
                'Swap quote expired. Refresh the quote and try again.',
              );
            }
          }
          if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
            throw StateError('Mnemonic not found for the active account');
          }
          checkSwapDepositFee(proposal.feeZatoshi, maximumFeeZatoshi);
          beforeSoftwareSign?.call(proposal.feeZatoshi);
          resultFuture = rust_sync.executeProposal(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            proposalId: proposal.proposalId,
            sendFlowId: sendFlowId,
            mnemonicBytes: mnemonicBytes,
          );
        } finally {
          mnemonicBytes?.fillRange(0, mnemonicBytes.length, 0);
        }
        result = await resultFuture;
      }
      proposalConsumed = true;

      if (!secretGuard.enabled || _ref.mounted) {
        try {
          await _ref.read(syncProvider.notifier).refreshAfterSend();
        } catch (e) {
          log(
            'SwapDepositSender: refreshAfterSend failed flow=$sendFlowId: $e',
          );
        }
      }

      final txid = _firstTxid(result.txids);
      if (txid == null) {
        throw StateError('ZEC deposit broadcast returned no txid');
      }
      log(
        'SwapDepositSender: broadcast complete flow=$sendFlowId '
        'tx=${_shortSwapValue(txid)} status=${result.status}',
      );
      return SwapDepositBroadcastResult(
        txHash: txid,
        status: result.status,
        message: result.message,
      );
    } catch (e) {
      log('SwapDepositSender: failed flow=$sendFlowId error=$e');
      rethrow;
    } finally {
      if (proposalId != null && !proposalConsumed) {
        final released = await discardSendProposal(
          proposalId: proposalId,
          sendFlowId: sendFlowId,
          logContext: 'SwapDepositSender',
          syncNotifier: syncNotifier,
          accountUuid: accountUuid,
        );
        if (released) {
          log(
            'SwapDepositSender: discarded proposal flow=$sendFlowId '
            'proposal=$proposalId',
          );
        } else {
          log(
            'SwapDepositSender: discard proposal remains pending '
            'flow=$sendFlowId proposal=$proposalId',
          );
        }
      }
    }
  }
}

BigInt zecDepositAmountZatoshiForQuote(SwapQuote quote) {
  if (quote.sellAsset != SwapAsset.zec) {
    throw StateError('Only ZEC deposits can be sent by this wallet');
  }
  final zatoshi = quote.sellAmountBaseUnits;
  if (zatoshi == null || zatoshi <= BigInt.zero) {
    throw StateError('Swap quote is missing executable ZEC amount');
  }
  return zatoshi;
}

String _newSwapSendFlowId() {
  return 'swap-${DateTime.now().microsecondsSinceEpoch}';
}

String? _firstTxid(String txids) {
  for (final part in txids.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

String _shortSwapValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return '-';
  if (trimmed.length <= 14) return trimmed;
  return '${trimmed.substring(0, 7)}...${trimmed.substring(trimmed.length - 6)}';
}

/// Refuse a changed proposal before any software signature can be produced.
void checkSwapDepositFee(BigInt actualFee, BigInt? reviewedFee) {
  if (reviewedFee != null && actualFee > reviewedFee) {
    throw const SwapDepositFeeChanged();
  }
}

class SwapDepositFeeChanged implements Exception {
  const SwapDepositFeeChanged();
  @override
  String toString() =>
      'Zcash network fee increased. Review the swap again before sending.';
}
