import '../../swap/domain/swap_contract.dart';
import '../../swap/integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import '../../swap/models/swap_deposit_broadcast_result.dart';
import '../../swap/providers/swap_deposit_sender.dart';
import '../../swap/providers/swap_zec_staging_address_service.dart';
import 'zns_http_transport.dart';
import 'zns_network_config.dart';

/// A durable, account-scoped funding plan. Persist toJson() BEFORE sending ZEC.
/// This record is the authoritative recipient/refund/deposit binding on resume.
class ZnsFundingQuote {
  const ZnsFundingQuote({
    required this.accountUuid,
    required this.owner,
    required this.refundAddress,
    required this.requiredWei,
    required this.quote,
    required this.dryRun,
    required this.createdAt,
    required this.chainId,
    required this.registryAddress,
  });
  final String accountUuid, owner, refundAddress;
  final BigInt requiredWei;
  final SwapQuote quote;
  final bool dryRun;
  final DateTime createdAt;
  final int chainId;
  final String registryAddress;
  String get protocolId => ZnsNetworkConfig.protocolId;
  BigInt get depositZatoshi => quote.sellAmountBaseUnits!;
  String get depositAddress => quote.depositInstruction.address;
  String? get depositMemo => quote.depositInstruction.memo;
  DateTime get expiresAt => quote.quoteExpiresAt!;

  Map<String, Object?> toJson() => {
    'version': 1,
    'protocolId': protocolId,
    'chainId': chainId,
    'registryAddress': registryAddress,
    'accountUuid': accountUuid,
    'owner': owner,
    'refundAddress': refundAddress,
    'requiredWei': requiredWei.toString(),
    'dryRun': dryRun,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'depositZatoshi': depositZatoshi.toString(),
    'depositAddress': depositAddress,
    'depositMemo': depositMemo,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'providerQuoteId': quote.providerQuoteId,
    'receiveAmount': quote.receiveEstimateTextOverride,
    'minimumReceiveAmount': quote.minimumReceiveTextOverride,
    'feeLabel': quote.feeLabel,
    'totalFeesText': quote.totalFeesText,
  };

  factory ZnsFundingQuote.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1 ||
        json['protocolId'] != ZnsNetworkConfig.protocolId ||
        json['chainId'] != 8453) {
      throw const FormatException('Unsupported ZNS funding record');
    }
    final registry = znsAddress(json['registryAddress'] as String);
    final owner = znsAddress(json['owner'] as String);
    final account = json['accountUuid'] as String,
        refund = json['refundAddress'] as String;
    final required = znsDecimalUnits(json['requiredWei'] as String, 0);
    final deposit = znsDecimalUnits(json['depositZatoshi'] as String, 0);
    final expiry = DateTime.parse(json['expiresAt'] as String).toUtc();
    final created = DateTime.parse(json['createdAt'] as String).toUtc();
    final address = json['depositAddress'] as String;
    if (account.trim().isEmpty ||
        refund.trim().isEmpty ||
        required <= BigInt.zero ||
        deposit <= BigInt.zero ||
        address.trim().isEmpty ||
        !expiry.isAfter(created)) {
      throw const FormatException('Invalid ZNS funding record');
    }
    final received = _ethUnits(json['receiveAmount'] as String?);
    final minimum = _ethUnits(json['minimumReceiveAmount'] as String?);
    if (received < required || minimum < required || minimum > received) {
      throw const FormatException('Funding output is insufficient');
    }
    return ZnsFundingQuote(
      accountUuid: account,
      owner: owner,
      refundAddress: refund,
      requiredWei: required,
      dryRun: json['dryRun'] as bool,
      createdAt: created,
      chainId: json['chainId'] as int,
      registryAddress: registry,
      quote: SwapQuote(
        direction: SwapDirection.zecToExternal,
        sellAsset: SwapAsset.zec,
        receiveAsset: ZnsFundingGateway.baseEth,
        externalAsset: ZnsFundingGateway.baseEth,
        mode: SwapQuoteMode.exactOutput,
        sellAmount: double.parse(znsFormatUnits(deposit, 8)),
        receiveAmount: double.parse(znsFormatUnits(received, 18)),
        minimumReceiveAmount: double.parse(znsFormatUnits(minimum, 18)),
        providerLabel: 'NEAR Intents',
        feeLabel: json['feeLabel'] as String? ?? 'Included in shown rate',
        expiryLabel: '',
        totalFeesText: json['totalFeesText'] as String?,
        quoteExpiresAt: expiry,
        providerQuoteId: json['providerQuoteId'] as String?,
        sellAmountBaseUnits: deposit,
        receiveEstimateTextOverride: json['receiveAmount'] as String?,
        minimumReceiveTextOverride: json['minimumReceiveAmount'] as String?,
        depositInstruction: SwapDepositInstruction(
          asset: SwapAsset.zec,
          address: address,
          memo: json['depositMemo'] as String?,
          expiresInLabel: '',
          reuseWarning: 'Do not reuse this address',
          deadline: expiry,
        ),
      ),
    );
  }
}

/// The existing swap provider keeps transport, Zcash fee estimation, account
/// staging and broadcast behavior consistent with ordinary Vizor swaps.
class ZnsFundingGateway {
  ZnsFundingGateway({
    required this.config,
    required SwapZecStagingAddressService staging,
    required SwapDepositSender sender,
    SwapProvider? provider,
    DateTime Function()? now,
  }) : _staging = staging,
       _sender = sender,
       _provider =
           provider ??
           NearIntentsOneClickSwapAdapter(
             baseUri: config.oneClickBaseUri,
             referral: 'vizor',
           ),
       _now = now ?? DateTime.now;
  final ZnsNetworkConfig config;
  final SwapZecStagingAddressService _staging;
  final SwapDepositSender _sender;
  final SwapProvider _provider;
  final DateTime Function() _now;
  static final baseEth = SwapAsset.live(
    assetId: 'nep141:base.omft.near',
    symbol: 'ETH',
    blockchain: 'base',
    decimals: 18,
  );

  Future<ZnsFundingQuote> quoteExactOutput({
    required String accountUuid,
    required String baseOwner,
    required BigInt requiredWei,
    bool dryRun = true,
    int slippageBps = 100,
  }) async {
    if (config.chainId != 8453) {
      throw const ZnsDataException(
        'ZEC bridge funding is available only for Base mainnet',
      );
    }
    if (accountUuid.trim().isEmpty ||
        requiredWei <= BigInt.zero ||
        slippageBps < 0 ||
        slippageBps > 300) {
      throw ArgumentError('Invalid funding account, amount or slippage');
    }
    baseOwner = znsAddress(baseOwner);
    final assets = await _provider.listSupportedExternalAssets();
    if (!assets.any(
      (a) =>
          a.assetId == baseEth.assetId &&
          a.decimals == 18 &&
          a.symbol == 'ETH' &&
          a.chainTicker == 'base',
    )) {
      throw const ZnsDataException(
        'NEAR Intents does not currently list native Base ETH',
      );
    }
    final staging = await _staging.prepareForQuote(accountUuid: accountUuid);
    final text = znsFormatUnits(requiredWei, 18);
    final quote = await _provider.quote(
      SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: baseEth,
        mode: SwapQuoteMode.exactOutput,
        amount: double.parse(text),
        amountText: text,
        destination: baseOwner,
        refundAddress: staging.address,
        dryRun: dryRun,
        slippageBps: slippageBps,
      ),
    );
    // Uses preserved provider decimal strings, never floating point, to decide
    // whether funding can cover the registration's reviewed ETH requirement.
    _validateQuote(quote, requiredWei, dryRun: dryRun);
    return ZnsFundingQuote(
      accountUuid: accountUuid,
      owner: baseOwner,
      refundAddress: staging.address,
      requiredWei: requiredWei,
      quote: quote,
      dryRun: dryRun,
      createdAt: _now().toUtc(),
      chainId: config.chainId,
      registryAddress: config.registryAddress,
    );
  }

  void _validateQuote(
    SwapQuote quote,
    BigInt required, {
    required bool dryRun,
  }) {
    if (quote.direction != SwapDirection.zecToExternal ||
        quote.mode != SwapQuoteMode.exactOutput ||
        quote.sellAsset != SwapAsset.zec ||
        quote.receiveAsset.assetId != baseEth.assetId ||
        quote.receiveAsset.decimals != 18 ||
        quote.sellAmountBaseUnits == null ||
        quote.sellAmountBaseUnits! <= BigInt.zero ||
        _ethUnits(quote.receiveEstimateTextOverride) < required ||
        _ethUnits(quote.minimumReceiveTextOverride) < required ||
        _ethUnits(quote.minimumReceiveTextOverride) >
            _ethUnits(quote.receiveEstimateTextOverride) ||
        quote.quoteExpiresAt == null ||
        !quote.quoteExpiresAt!.isAfter(
          _now().toUtc().add(kSwapQuoteStartExpiryBuffer),
        )) {
      throw const ZnsDataException(
        'Funding quote does not satisfy the reviewed route, amount or expiry',
      );
    }
    if (!dryRun &&
        (!RegExp(
              r'^(t1|t3)[1-9A-HJ-NP-Za-km-z]{33}$',
            ).hasMatch(quote.depositInstruction.address) ||
            quote.depositInstruction.memo != null)) {
      throw const ZnsDataException(
        'Funding quote returned an unsupported Zcash deposit instruction',
      );
    }
  }

  Future<BigInt> estimateDepositFee(ZnsFundingQuote plan) {
    // A dry quote has no deposit address. Estimate the same transparent output
    // shape against a public synthetic address. This copy is confined to fee
    // estimation and never reaches sendDeposit. Re-estimate the real live quote
    // before authorization; note selection can change between these stages.
    final source = plan.quote;
    final quote = !plan.dryRun
        ? source
        : SwapQuote(
            direction: source.direction,
            sellAsset: source.sellAsset,
            receiveAsset: source.receiveAsset,
            externalAsset: source.externalAsset,
            mode: source.mode,
            sellAmount: source.sellAmount,
            receiveAmount: source.receiveAmount,
            minimumReceiveAmount: source.minimumReceiveAmount,
            providerLabel: source.providerLabel,
            feeLabel: source.feeLabel,
            expiryLabel: source.expiryLabel,
            quoteExpiresAt: source.quoteExpiresAt,
            sellAmountBaseUnits: source.sellAmountBaseUnits,
            depositInstruction: SwapDepositInstruction(
              asset: SwapAsset.zec,
              address: 't1Hsc1LR8yKnbbe3twRp88p6vFfC5t7DLbs',
              expiresInLabel: source.expiryLabel,
              reuseWarning: 'Fee estimation only',
              deadline: source.depositInstruction.deadline,
            ),
          );
    return _sender.estimateZecDepositFee(
      accountUuid: plan.accountUuid,
      quote: quote,
    );
  }

  /// Start and persist its returned id alongside the plan before sendDeposit.
  Future<SwapIntentSnapshot> start(ZnsFundingQuote plan) async {
    _requireSendable(plan);
    return _provider.startSwap(plan.quote);
  }

  /// Caller owns an atomic persistent send-attempt guard. Never invoke again
  /// after timeout without reconciling the original Zcash send flow.
  Future<SwapDepositBroadcastResult> sendDeposit(ZnsFundingQuote plan) {
    _requireSendable(plan);
    return _sender.sendZecDeposit(
      accountUuid: plan.accountUuid,
      quote: plan.quote,
    );
  }

  void _requireSendable(ZnsFundingQuote plan) {
    if (plan.dryRun) {
      throw const ZnsDataException(
        'Request a live deposit quote before sending ZEC',
      );
    }
    _validateQuote(plan.quote, plan.requiredWei, dryRun: false);
  }

  Future<SwapIntentSnapshot> submitDeposit({
    required ZnsFundingQuote plan,
    required String txHash,
  }) => _provider.submitDepositTransaction(
    depositAddress: plan.depositAddress,
    txHash: txHash,
    depositMemo: plan.depositMemo,
  );
  Future<SwapIntentSnapshot> status(ZnsFundingQuote plan) =>
      _provider.getStatus(plan.depositAddress, depositMemo: plan.depositMemo);
}

BigInt _ethUnits(String? text) {
  if (text == null || !text.endsWith(' ETH')) {
    throw const ZnsDataException(
      'Funding provider did not preserve an exact ETH amount',
    );
  }
  return znsDecimalUnits(text.substring(0, text.length - 4), 18);
}
