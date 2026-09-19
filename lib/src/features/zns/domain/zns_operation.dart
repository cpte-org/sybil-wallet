import 'dart:convert';
import '../../../core/config/network_config.dart';

final znsRewardScale = BigInt.from(10).pow(24);
const znsHoldingSeconds = 365 * 24 * 60 * 60;
const znsGraceSeconds = 90 * 24 * 60 * 60;
const znsPolicy =
    'tieredUSD-floor100k-fixedFallback-deposit365-refresh365-grace90-linearFee10-linearRewards-weighted-reserveCarry-erc721-multiName-clearUA';

class ZnsRegistrationQuote {
  const ZnsRegistrationQuote({
    required this.minimumDeposit,
    required this.usdTarget,
    required this.pricingMode,
    required this.priceUpdatedAt,
  });
  final BigInt minimumDeposit, usdTarget, priceUpdatedAt;
  final int pricingMode;

  /// Informational floor under the pinned 8-decimal, $100,000 floor policy.
  /// The quoted minimum remains the sole authority for funding and signing.
  BigInt get minimumBondFloor => usdTarget * BigInt.from(1000);
  bool get minimumFloorApplies =>
      pricingMode == 0 && minimumDeposit == minimumBondFloor;
}

BigInt znsParseAmount(String text, int decimals) {
  if (decimals < 0 ||
      decimals > 18 ||
      !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(text.trim())) {
    throw const FormatException('Enter a positive decimal amount.');
  }
  final parts = text.trim().split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals) {
    throw FormatException('Use at most $decimals decimal places.');
  }
  return BigInt.parse(parts[0]) * BigInt.from(10).pow(decimals) +
      BigInt.parse(
        fraction.padRight(decimals, '0').isEmpty
            ? '0'
            : fraction.padRight(decimals, '0'),
      );
}

String znsFormatAmount(BigInt value, int decimals) {
  final raw = value.abs().toString().padLeft(decimals + 1, '0');
  final whole = decimals == 0 ? raw : raw.substring(0, raw.length - decimals);
  final fraction = decimals == 0
      ? ''
      : raw.substring(raw.length - decimals).replaceFirst(RegExp(r'0+$'), '');
  return '${value.isNegative ? '-' : ''}$whole${fraction.isEmpty ? '' : '.$fraction'}';
}

String znsValidateLabel(String name) {
  if (!RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(name)) {
    throw const FormatException(
      'Use 1–63 lowercase letters or numbers, with hyphens only inside the name.',
    );
  }
  return name;
}

/// Public identity used to find a journal after restoration into a new UUID.
class ZnsScope {
  const ZnsScope({
    required this.zcashNetwork,
    required this.chainId,
    required this.registry,
    required this.owner,
  });
  final String zcashNetwork;
  final int chainId;
  final String registry;
  final String owner;
  bool get supportsLiveZecFunding =>
      zcashNetwork == ZcashNetwork.mainnet.name && chainId == 8453;
  String get key =>
      'zns:v1:$zcashNetwork:$chainId:${registry.toLowerCase()}:${owner.toLowerCase()}';
  Map<String, Object> toJson() => {
    'zcashNetwork': zcashNetwork,
    'chainId': chainId,
    'registry': registry,
    'owner': owner,
  };
}

/// A durable intent is not permission to sign. Approval exists in the unlocked
/// coordinator session only, and must be renewed after lock, restart or switch.
class ZnsOperation {
  ZnsOperation({
    required this.scope,
    required this.name,
    required this.unifiedAddress,
    required this.positionId,
    required this.secret,
    required this.commitment,
    required this.kind,
    required this.maxZatoshi,
    required this.maxEthWei,
    required this.requiredTokenUnits,
    required this.maxGasFeeWei,
    required this.createdAt,
    this.estimatedZatoshi,
    this.registrationQuote,
    BigInt? extraDeposit,
    this.rateZatoshi,
    this.zcashFeeZatoshi,
    this.recipient = '',
    this.phase = 'ready',
    this.pending,
    this.funding,
    this.transactions = const [],
    this.message,
    this.baselineExpiry = 0,
    this.maturityAt = 0,
    this.exitPreview,
    this.completedAt,
  }) : extraDeposit = extraDeposit ?? BigInt.zero;
  // Informational dry-quote values, discarded on recovery. Spending authority
  // remains bound to the persisted integer limits, never these estimates.
  final BigInt? estimatedZatoshi, rateZatoshi, zcashFeeZatoshi;
  final ZnsRegistrationQuote? registrationQuote;
  final BigInt extraDeposit;
  final String recipient;
  final ZnsScope scope;
  final String name;
  final String unifiedAddress;
  final BigInt positionId;
  final String secret;
  final String commitment;
  final String kind;
  final BigInt maxZatoshi;
  final BigInt maxEthWei;
  final BigInt requiredTokenUnits;
  final BigInt maxGasFeeWei;
  final DateTime createdAt;
  final int baselineExpiry;
  final int maturityAt;
  final Map<String, dynamic>? exitPreview;
  String phase;
  Map<String, dynamic>? pending;
  Map<String, dynamic>? funding;
  List<Map<String, dynamic>> transactions;
  String? message;
  DateTime? completedAt;
  bool get isComplete => completedAt != null;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'policy': znsPolicy,
    'scope': scope.toJson(),
    'name': name,
    'unifiedAddress': unifiedAddress,
    'positionId': positionId.toString(),
    'secret': secret,
    'commitment': commitment,
    'kind': kind,
    'recipient': recipient,
    'maxZatoshi': maxZatoshi.toString(),
    'maxEthWei': maxEthWei.toString(),
    'requiredTokenUnits': requiredTokenUnits.toString(),
    'extraDeposit': extraDeposit.toString(),
    if (registrationQuote case final quote?) ...{
      'minimumDeposit': quote.minimumDeposit.toString(),
      'usdTarget': quote.usdTarget.toString(),
      'expectedPricingMode': quote.pricingMode,
      'priceUpdatedAt': quote.priceUpdatedAt.toString(),
    },
    'maxGasFeeWei': maxGasFeeWei.toString(),
    'createdAt': createdAt.toIso8601String(),
    'baselineExpiry': baselineExpiry,
    'maturityAt': maturityAt,
    'exitPreview': exitPreview,
    'phase': phase,
    'pending': pending,
    'funding': funding,
    'transactions': transactions,
    'message': message,
    'completedAt': completedAt?.toIso8601String(),
  };

  static ZnsOperation decode(String raw, ZnsScope expected) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['policy'] != znsPolicy ||
        value.containsKey('years') ||
        value['scope'] is! Map) {
      throw const FormatException('Unsupported ZNS recovery record.');
    }
    final scope = value['scope'] as Map;
    if (scope['zcashNetwork'] != expected.zcashNetwork ||
        scope['chainId'] != expected.chainId ||
        '${scope['registry']}'.toLowerCase() !=
            expected.registry.toLowerCase() ||
        '${scope['owner']}'.toLowerCase() != expected.owner.toLowerCase()) {
      throw const FormatException(
        'ZNS recovery belongs to another account or deployment.',
      );
    }
    final kind = value['kind'] as String;
    final name = value['name'] as String;
    if (kind != 'withdrawClaims') znsValidateLabel(name);
    final uint256Max = (BigInt.one << 256) - BigInt.one;
    final uint64Max = (BigInt.one << 64) - BigInt.one;
    final maxZcash = BigInt.from(21000000) * BigInt.from(100000000);
    BigInt savedAmount(Object? raw, {BigInt? maximum}) {
      if (raw is! String ||
          raw.length > 78 ||
          !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(raw)) {
        throw const FormatException('Invalid saved unsigned amount.');
      }
      final parsed = BigInt.parse(raw);
      if (parsed > (maximum ?? uint256Max)) {
        throw const FormatException('Saved amount exceeds its limit.');
      }
      return parsed;
    }

    final positionId = savedAmount(value['positionId']);
    if (positionId.isNegative ||
        (!['register', 'withdrawClaims'].contains(kind) &&
            positionId == BigInt.zero) ||
        !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(value['secret'] as String) ||
        !RegExp(
          r'^0x[0-9a-fA-F]{64}$',
        ).hasMatch(value['commitment'] as String) ||
        ![
          'register',
          'refresh',
          'claimRewards',
          'update',
          'release',
          'withdrawClaims',
          'transfer',
        ].contains(kind)) {
      throw const FormatException('Invalid ZNS recovery intent.');
    }
    final recipient = value['recipient'] as String? ?? '';
    if (kind == 'transfer' &&
        (!RegExp(r'^0x[0-9a-f]{40}$').hasMatch(recipient) ||
            BigInt.parse(recipient.substring(2), radix: 16) == BigInt.zero ||
            recipient == expected.owner.toLowerCase() ||
            recipient == expected.registry.toLowerCase())) {
      throw const FormatException('Invalid saved NFT transfer recipient.');
    }
    final maxZatoshi = savedAmount(value['maxZatoshi'], maximum: maxZcash);
    final maxEthWei = savedAmount(value['maxEthWei']);
    final requiredTokenUnits = savedAmount(value['requiredTokenUnits']);
    final maxGasFeeWei = savedAmount(value['maxGasFeeWei']);
    final extraDeposit = savedAmount(value['extraDeposit']);
    ZnsRegistrationQuote? registrationQuote;
    if (kind == 'register') {
      final mode = value['expectedPricingMode'];
      if (mode is! int || (mode != 0 && mode != 1)) {
        throw const FormatException(
          'Registration pricing must be reviewed again.',
        );
      }
      registrationQuote = ZnsRegistrationQuote(
        minimumDeposit: savedAmount(value['minimumDeposit']),
        usdTarget: savedAmount(value['usdTarget']),
        pricingMode: mode,
        priceUpdatedAt: savedAmount(value['priceUpdatedAt']),
      );
      if (registrationQuote.minimumDeposit == BigInt.zero ||
          registrationQuote.usdTarget == BigInt.zero ||
          registrationQuote.minimumDeposit + extraDeposit !=
              requiredTokenUnits) {
        throw const FormatException('Inconsistent saved registration bond.');
      }
    } else if (extraDeposit != BigInt.zero) {
      throw const FormatException(
        'Extra bond is only available at registration.',
      );
    }
    if (maxGasFeeWei > maxEthWei ||
        (kind == 'register' && requiredTokenUnits == BigInt.zero) ||
        (kind != 'register' && requiredTokenUnits != BigInt.zero) ||
        (['register', 'withdrawClaims'].contains(kind) &&
            positionId != BigInt.zero)) {
      throw const FormatException('Inconsistent saved operation limits.');
    }

    Map<String, dynamic>? savedMap(Object? raw) {
      if (raw == null) return null;
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid saved operation metadata.');
      }
      return Map<String, dynamic>.from(raw);
    }

    final pending = savedMap(value['pending']);
    if (value['transactions'] is! List) {
      throw const FormatException('Invalid saved transaction history.');
    }
    final transactions = (value['transactions'] as List).map((raw) {
      final transaction = savedMap(raw);
      if (transaction == null) {
        throw const FormatException('Invalid saved transaction history.');
      }
      return transaction;
    }).toList();
    var reservedFees = BigInt.zero;
    var reservedValue = BigInt.zero;
    for (final tx in [...transactions, ?pending]) {
      if (![
            'commit',
            'approve',
            'swap',
            'atomicRegister',
            'register',
            'refresh',
            'claimRewards',
            'update',
            'release',
            'withdrawClaims',
            'transfer',
          ].contains(tx['kind']) ||
          (kind != 'register' && tx['kind'] != kind) ||
          [
            'confirmed',
            'success',
          ].any((key) => tx.containsKey(key) && tx[key] is! bool)) {
        throw const FormatException('Invalid saved transaction intent.');
      }
      for (final key in [
        'value',
        'feeCeiling',
        'gasLimit',
        'gasUsed',
        'maxFeePerGas',
        'maxPriorityFeePerGas',
        'effectiveGasPrice',
        'l1FeeWei',
        'operatorFeeWei',
      ]) {
        if (tx.containsKey(key)) {
          savedAmount(tx[key]);
        }
      }
      for (final key in ['nonce', 'authorizationNonce', 'blockNumber']) {
        if (tx.containsKey(key)) {
          savedAmount(tx[key], maximum: uint64Max);
        }
      }
      final fee = savedAmount(tx['feeCeiling'] ?? '0');
      final nativeValue = savedAmount(tx['value'] ?? '0');
      if (fee > maxGasFeeWei || nativeValue > maxEthWei - maxGasFeeWei) {
        throw const FormatException('Saved transaction exceeds review limits.');
      }
      if ((tx.containsKey('maxFeePerGas') &&
              tx.containsKey('maxPriorityFeePerGas') &&
              savedAmount(tx['maxPriorityFeePerGas']) >
                  savedAmount(tx['maxFeePerGas'])) ||
          (tx.containsKey('gasLimit') &&
              tx.containsKey('gasUsed') &&
              savedAmount(tx['gasUsed']) > savedAmount(tx['gasLimit'])) ||
          (tx.containsKey('gasLimit') &&
              tx.containsKey('maxFeePerGas') &&
              savedAmount(tx['gasLimit']) * savedAmount(tx['maxFeePerGas']) +
                      savedAmount(tx['l1FeeWei'] ?? '0') +
                      savedAmount(tx['operatorFeeWei'] ?? '0') >
                  fee)) {
        throw const FormatException('Inconsistent saved transaction fees.');
      }
      reservedFees += fee;
      if (identical(tx, pending) || tx['success'] == true) {
        reservedValue += nativeValue;
      }
    }
    if (reservedFees > maxGasFeeWei ||
        reservedValue > maxEthWei - maxGasFeeWei) {
      throw const FormatException('Saved transactions exceed review limits.');
    }

    final funding = savedMap(value['funding']);
    if (funding != null) {
      for (final key in ['attempted', 'complete', 'failed', 'notRequired']) {
        if (funding.containsKey(key) && funding[key] is! bool) {
          throw const FormatException('Invalid saved funding state.');
        }
      }
      for (final key in ['maxZatoshi', 'zecFee', 'depositZatoshi']) {
        if (funding.containsKey(key)) {
          savedAmount(funding[key], maximum: maxZatoshi);
        }
      }
      if (funding.containsKey('requiredWei')) {
        savedAmount(funding['requiredWei'], maximum: maxEthWei);
      }
      if (funding.containsKey('depositZatoshi') &&
          savedAmount(funding['depositZatoshi']) +
                  savedAmount(funding['zecFee'] ?? '0') >
              savedAmount(funding['maxZatoshi'] ?? maxZatoshi.toString())) {
        throw const FormatException('Inconsistent saved funding fees.');
      }
      final plan = savedMap(funding['plan']);
      if (plan != null) {
        final required = savedAmount(plan['requiredWei'], maximum: maxEthWei);
        final deposit = savedAmount(
          plan['depositZatoshi'],
          maximum: maxZatoshi,
        );
        final quotedMax = savedAmount(
          funding['maxZatoshi'],
          maximum: maxZatoshi,
        );
        final fee = savedAmount(funding['zecFee'], maximum: quotedMax);
        if (required == BigInt.zero ||
            deposit == BigInt.zero ||
            deposit + fee > quotedMax) {
          throw const FormatException('Inconsistent saved funding limits.');
        }
        BigInt ethAmount(Object? raw) {
          if (raw is! String ||
              raw.length > 101 ||
              !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,18})? ETH$').hasMatch(raw)) {
            throw const FormatException('Invalid saved funding output.');
          }
          final amount = znsParseAmount(raw.substring(0, raw.length - 4), 18);
          if (amount > uint256Max) {
            throw const FormatException('Saved funding output is too large.');
          }
          return amount;
        }

        final received = ethAmount(plan['receiveAmount']);
        final minimum = ethAmount(plan['minimumReceiveAmount']);
        if (minimum < required || minimum > received) {
          throw const FormatException('Inconsistent saved funding output.');
        }
      }
    }

    final ua = value['unifiedAddress'] as String;
    if (utf8.encode(ua).length > 512 ||
        (['register', 'update'].contains(kind) && ua.isEmpty)) {
      throw const FormatException('Invalid saved Zcash address.');
    }
    if (kind == 'release') {
      final preview = value['exitPreview'];
      if (preview is! Map ||
          preview['early'] is! bool ||
          [
            'principalReturned',
            'rewardsReturned',
            'principalForfeited',
            'rewardsForfeitedScaled',
          ].any((key) => preview[key] is! String)) {
        throw const FormatException(
          'The saved release is missing its forfeiture review.',
        );
      }
      for (final key in [
        'principalReturned',
        'rewardsReturned',
        'principalForfeited',
        'rewardsForfeitedScaled',
      ]) {
        savedAmount(preview[key]);
      }
    }
    return ZnsOperation(
      recipient: recipient,
      scope: expected,
      name: name,
      unifiedAddress: ua,
      positionId: positionId,
      secret: value['secret'] as String,
      commitment: value['commitment'] as String,
      kind: value['kind'] as String,
      maxZatoshi: maxZatoshi,
      maxEthWei: maxEthWei,
      requiredTokenUnits: requiredTokenUnits,
      registrationQuote: registrationQuote,
      extraDeposit: extraDeposit,
      maxGasFeeWei: maxGasFeeWei,
      createdAt: DateTime.parse(value['createdAt'] as String),
      baselineExpiry: value['baselineExpiry'] as int? ?? 0,
      maturityAt: value['maturityAt'] as int? ?? 0,
      exitPreview: value['exitPreview'] as Map<String, dynamic>?,
      phase: value['phase'] as String,
      pending: pending,
      funding: funding,
      transactions: transactions,
      message: value['message'] as String?,
      completedAt: value['completedAt'] == null
          ? null
          : DateTime.parse(value['completedAt'] as String),
    );
  }
}
