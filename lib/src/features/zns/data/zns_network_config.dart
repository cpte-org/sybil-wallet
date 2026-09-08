/// Deployment configuration is explicit; an unset registry never becomes a
/// placeholder contract that a user can accidentally fund.
class ZnsNetworkConfig {
  ZnsNetworkConfig({
    required this.chainId,
    required this.rpcUri,
    required String registryAddress,
    String tokenAddress = canonicalCbZec,
    this.tokenDecimals = 8,
    Uri? oneClickBaseUri,
    Uri? kyberBaseUri,
    String kyberRouterAddress = canonicalKyberRouter,
    this.allowLocalTestEndpoints = false,
  }) : registryAddress = znsAddress(registryAddress),
       tokenAddress = znsAddress(tokenAddress),
       kyberRouterAddress = znsAddress(kyberRouterAddress),
       oneClickBaseUri =
           oneClickBaseUri ??
           Uri.parse('https://functions.vizor.cash/api/near-intents/1click'),
       kyberBaseUri =
           kyberBaseUri ??
           Uri.parse('https://aggregator-api.kyberswap.com/base') {
    if (chainId <= 0 || tokenDecimals < 0 || tokenDecimals > 36) {
      throw ArgumentError('Invalid ZNS chain or token decimals');
    }
    if (chainId == 8453 &&
        (this.tokenAddress != canonicalCbZec.toLowerCase() ||
            tokenDecimals != 8 ||
            this.kyberRouterAddress != canonicalKyberRouter.toLowerCase())) {
      throw ArgumentError(
        'Base mainnet requires canonical cbZEC and Kyber router',
      );
    }
    if (chainId != 8453 && !allowLocalTestEndpoints) {
      throw ArgumentError(
        'Non-mainnet deployments require explicit test configuration',
      );
    }
    for (final uri in [rpcUri, this.oneClickBaseUri, this.kyberBaseUri]) {
      final local = ['localhost', '127.0.0.1', '::1'].contains(uri.host);
      if (uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          (uri.scheme != 'https' &&
              !(allowLocalTestEndpoints && local && uri.scheme == 'http'))) {
        throw ArgumentError(
          'ZNS endpoints require HTTPS or explicit local test mode',
        );
      }
    }
  }

  static const protocolId =
      '0xd1a382e424de62cfc7a26d4829be41e2b15b5d49ae43bd839f997afde7a0538f';
  static final rewardScale = BigInt.from(10).pow(24);
  static const canonicalCbZec = '0xB2000000000000000000008501b13360000cb2EC';
  static const canonicalKyberRouter =
      '0x6131B5fae19EA4f9D964eAc0408E4408b66337b5';
  static const nativeEth = '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
  static const zeroAddress = '0x0000000000000000000000000000000000000000';
  final int chainId;
  final Uri rpcUri;
  final String registryAddress;
  final String tokenAddress;
  final int tokenDecimals;
  final Uri oneClickBaseUri;
  final Uri kyberBaseUri;
  final String kyberRouterAddress;
  final bool allowLocalTestEndpoints;
}

String znsAddress(String value, {bool allowZero = false}) {
  if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value) ||
      (!allowZero && value.toLowerCase() == ZnsNetworkConfig.zeroAddress)) {
    throw const FormatException('Invalid or zero EVM address');
  }
  return value.toLowerCase();
}

String znsHex(String value, {int? bytes, bool allowEmpty = false}) {
  if (!RegExp(r'^0x(?:[0-9a-fA-F]{2})*$').hasMatch(value) ||
      (!allowEmpty && value.length == 2) ||
      (bytes != null && value.length != 2 + bytes * 2)) {
    throw const FormatException('Invalid EVM hex bytes');
  }
  return value.toLowerCase();
}

String znsQuantity(BigInt value) {
  if (value.isNegative || value.bitLength > 256) {
    throw const FormatException('Invalid EVM quantity');
  }
  return '0x${value.toRadixString(16)}';
}

BigInt znsParseQuantity(Object? value) {
  if (value is! String ||
      !RegExp(r'^0x(?:0|[1-9a-fA-F][0-9a-fA-F]*)$').hasMatch(value)) {
    throw const FormatException('Malformed EVM quantity');
  }
  final result = BigInt.parse(value.substring(2), radix: 16);
  if (result.bitLength > 256) {
    throw const FormatException('EVM quantity overflow');
  }
  return result;
}

BigInt znsDecimalUnits(String value, int decimals) {
  if (!RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]+)?$').hasMatch(value)) {
    throw const FormatException('Expected an unsigned decimal amount');
  }
  final parts = value.split('.');
  final fractional = parts.length == 2 ? parts[1] : '';
  if (fractional.length > decimals) {
    throw const FormatException('Amount has too many decimals');
  }
  final units =
      BigInt.parse(parts[0]) * BigInt.from(10).pow(decimals) +
      BigInt.parse(
        fractional.padRight(decimals, '0').isEmpty
            ? '0'
            : fractional.padRight(decimals, '0'),
      );
  if (units.bitLength > 256) throw const FormatException('Amount overflow');
  return units;
}

String znsFormatUnits(BigInt units, int decimals) {
  if (units.isNegative) throw const FormatException('Negative amount');
  if (decimals == 0) return units.toString();
  final padded = units.toString().padLeft(decimals + 1, '0');
  return '${padded.substring(0, padded.length - decimals)}.${padded.substring(padded.length - decimals)}';
}
