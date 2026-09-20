import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../domain/zns_operation.dart';
import 'zns_network_config.dart';
import 'zns_http_transport.dart';
import 'zns_rpc_client.dart';

/// A failed swap simulation, proven to precede signing. Never use for a
/// broadcast error, receipt failure, pricing change or transport failure.
class ZnsUnsignedSwapRejected implements Exception {
  const ZnsUnsignedSwapRejected();
  @override
  String toString() =>
      'The swap route is no longer usable. No transaction was '
      'signed for this attempt. Your funding remains on Base. Resume to try a fresh route.';
}

/// Quote and EVM execution share a canonical block, including its timestamp.
/// Base's pending Flashblocks context can combine new state with an older time.
class ZnsTransactionPreflight {
  ZnsTransactionPreflight(
    this.rpc, {
    void Function(Map<String, Object?>)? diagnostic,
  }) : _diagnostic = diagnostic ?? _log;
  final ZnsRpcClient rpc;
  final void Function(Map<String, Object?>) _diagnostic;

  static void _log(Map<String, Object?> event) =>
      debugPrint('[zcash] ZNS preflight: ${jsonEncode(event)}');

  Future<BigInt?> run({
    required ZnsCall call,
    required void Function() ensureAuthorized,
    required bool hasAtomicSwap,
    Map<String, Object?>? overrides,
    String? registrationName,
    void Function(ZnsRegistrationQuote)? checkQuote,
    BigInt? gasLimit,
    ZnsFeeQuote? fees,
    DateTime? routeExpiresAt,
  }) async {
    ensureAuthorized();
    final at = await rpc.block();
    final method = gasLimit == null ? 'eth_estimateGas' : 'eth_call';
    // Allowlisted local diagnostics only: never calldata, name, address,
    // commitment secret, raw provider text, or endpoint credentials.
    final event = <String, Object?>{
      'method': method,
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'blockNumber': at.number.toString(),
      'blockHash': at.hash,
      'blockTimestamp': at.timestamp.toString(),
      'gasLimit': gasLimit?.toString(),
      'maxFeePerGas': fees?.maxFeePerGas.toString(),
      'maxPriorityFeePerGas': fees?.maxPriorityFeePerGas.toString(),
      'routeExpiresAt': routeExpiresAt?.toIso8601String(),
    };
    try {
      await rpc.verifyProtocol(at: at);
      if (registrationName != null) {
        if (checkQuote == null) {
          throw StateError('Missing registration quote check');
        }
        checkQuote(await rpc.quoteRegistration(registrationName, at: at));
      }
      ensureAuthorized();
      final result = await rpc.request(method, [
        {
          ...call.toJson(),
          if (gasLimit != null) 'gas': znsQuantity(gasLimit),
          if (fees != null) ...{
            'maxFeePerGas': znsQuantity(fees.maxFeePerGas),
            'maxPriorityFeePerGas': znsQuantity(fees.maxPriorityFeePerGas),
          },
        },
        znsQuantity(at.number),
        ?overrides,
      ]);
      await rpc.checkFreshCanonical(at);
      ensureAuthorized();
      _diagnostic({...event, 'outcome': 'passed'});
      return gasLimit == null ? znsParseQuantity(result) : null;
    } catch (error) {
      _diagnostic({
        ...event,
        'outcome': 'rejected',
        if (error is ZnsDataException) 'rpcCode': error.code,
        if (error is ZnsRpcRevert) ...{
          'batchStep': error.batchStep,
          'revertSelector': error.revertSelector,
        },
      });
      // Step zero is the swap only when this exact unsigned operation has one.
      if (hasAtomicSwap && error is ZnsRpcRevert && error.batchStep == 0) {
        throw const ZnsUnsignedSwapRejected();
      }
      rethrow;
    }
  }
}
