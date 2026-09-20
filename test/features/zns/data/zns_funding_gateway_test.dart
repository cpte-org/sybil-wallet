import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_deposit_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_deposit_sender.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_funding_gateway.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_network_config.dart';
import 'zns_rpc_client_test.dart' show configuration, owner;

final now = DateTime.utc(2026, 9, 8);
const transparent = 't1Hsc1LR8yKnbbe3twRp88p6vFfC5t7DLbs';

class Sender implements SwapDepositSender {
  String? estimatedAddress;
  int sends = 0;
  @override
  Future<BigInt> estimateZecDepositFee({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    estimatedAddress = quote.depositInstruction.address;
    expect(quote.sellAmountBaseUnits, BigInt.from(223193));
    return BigInt.from(10000);
  }

  @override
  Future<SwapDepositBroadcastResult> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
    BigInt? maximumFeeZatoshi,
  }) async {
    sends++;
    return const SwapDepositBroadcastResult(
      txHash: 'public-fixture',
      status: 'broadcasted',
    );
  }
}

class Provider implements SwapProvider {
  SwapQuoteRequest? request;
  bool missingAsset = false, insufficient = false, inconsistentMinimum = false;
  String? statusAddress;
  @override
  String get providerLabel => 'NEAR Intents';
  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async =>
      missingAsset ? [] : [ZnsFundingGateway.baseEth];
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    this.request = request;
    return SwapQuote(
      direction: SwapDirection.zecToExternal,
      sellAsset: SwapAsset.zec,
      receiveAsset: ZnsFundingGateway.baseEth,
      externalAsset: ZnsFundingGateway.baseEth,
      mode: SwapQuoteMode.exactOutput,
      sellAmount: .00223193,
      receiveAmount: .001,
      minimumReceiveAmount: .001,
      providerLabel: providerLabel,
      feeLabel: 'Included',
      expiryLabel: '',
      quoteExpiresAt: now.add(const Duration(hours: 2)),
      sellAmountBaseUnits: BigInt.from(223193),
      receiveEstimateTextOverride: '0.001 ETH',
      minimumReceiveTextOverride: insufficient
          ? '0.0009 ETH'
          : inconsistentMinimum
          ? '0.002 ETH'
          : '0.001 ETH',
      depositInstruction: SwapDepositInstruction(
        asset: SwapAsset.zec,
        address: request.dryRun ? 'dry-placeholder' : transparent,
        expiresInLabel: '',
        reuseWarning: 'Do not reuse',
        deadline: now.add(const Duration(hours: 2)),
      ),
    );
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async =>
      SwapIntentSnapshot.fromQuote(quote, id: quote.depositInstruction.address);
  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusAddress = intentId;
    return SwapIntentSnapshot.fromQuote(await quote(request!), id: intentId);
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) => getStatus(depositAddress);
}

void main() {
  late Provider provider;
  late Sender sender;
  late ZnsFundingGateway gateway;
  setUp(() {
    provider = Provider();
    sender = Sender();
    gateway = ZnsFundingGateway(
      config: configuration(),
      provider: provider,
      sender: sender,
      staging: SwapZecStagingAddressService(
        reserveFreshOrchardAddress: ({required accountUuid}) async =>
            'u1public-refund-fixture',
      ),
      now: () => now,
    );
  });
  Future<ZnsFundingQuote> quote({bool dry = true}) => gateway.quoteExactOutput(
    accountUuid: 'account-1',
    baseOwner: owner,
    requiredWei: BigInt.from(1000000000000000),
    dryRun: dry,
  );
  test('funding binds native Base ETH and exact decimal requirement', () async {
    final plan = await quote();
    expect(provider.request!.mode, SwapQuoteMode.exactOutput);
    expect(provider.request!.amountText, '0.001000000000000000');
    expect(provider.request!.refundAddress, 'u1public-refund-fixture');
    expect(provider.request!.destination, owner);
    expect(plan.protocolId, ZnsNetworkConfig.protocolId);
    expect(plan.depositZatoshi, BigInt.from(223193));
  });
  test(
    'dry fee estimation substitutes only the output shape and cannot send',
    () async {
      final plan = await quote();
      expect(await gateway.estimateDepositFee(plan), BigInt.from(10000));
      expect(sender.estimatedAddress, transparent);
      expect(plan.depositAddress, 'dry-placeholder');
      expect(() => gateway.sendDeposit(plan), throwsA(isA<Exception>()));
      expect(sender.sends, 0);
    },
  );
  test(
    'live persisted quote recovers original deposit address without re-quoting',
    () async {
      final original = await quote(dry: false);
      final restored = ZnsFundingQuote.fromJson(original.toJson());
      expect(restored.owner, owner);
      expect(restored.registryAddress, configuration().registryAddress);
      expect(restored.chainId, 8453);
      expect(restored.requiredWei, original.requiredWei);
      await gateway.status(restored);
      expect(provider.statusAddress, transparent);
      expect(await gateway.estimateDepositFee(restored), BigInt.from(10000));
      expect(sender.estimatedAddress, restored.depositAddress);
    },
  );
  test('old or altered economic funding records cannot resume', () async {
    final original = (await quote()).toJson();
    for (final field in ['protocolId', 'chainId', 'registryAddress']) {
      final old = {...original}..remove(field);
      expect(() => ZnsFundingQuote.fromJson(old), throwsA(anything));
    }
    expect(
      () => ZnsFundingQuote.fromJson({
        ...original,
        'requiredWei': '2000000000000000',
      }),
      throwsFormatException,
    );
  });
  test(
    'missing native asset and inconsistent output bounds reject funding',
    () async {
      provider.missingAsset = true;
      await expectLater(quote(), throwsA(isA<Exception>()));
      provider.missingAsset = false;
      provider.insufficient = true;
      await expectLater(quote(), throwsA(isA<Exception>()));
      provider.insufficient = false;
      provider.inconsistentMinimum = true;
      await expectLater(quote(), throwsA(isA<Exception>()));
      expect(sender.sends, 0);
    },
  );
}
