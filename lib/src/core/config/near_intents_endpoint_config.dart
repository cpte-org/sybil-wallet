/// Public endpoint only. Upstream credentials, referral and fee policy belong
/// to the Sybil service and must never be compiled into wallet builds.
class NearIntentsEndpointConfig {
  const NearIntentsEndpointConfig({
    this.baseUrl = const String.fromEnvironment(
      'SIGIL_NEAR_INTENTS_BASE_URL',
      defaultValue: defaultBaseUrl,
    ),
    this.allowLoopback = const bool.fromEnvironment(
      'SIGIL_NEAR_INTENTS_ALLOW_LOOPBACK',
      defaultValue: false,
    ),
  });

  static const defaultBaseUrl = 'https://api.sybil.cash/api/near-intents/1click';
  static const build = NearIntentsEndpointConfig();
  final String baseUrl;
  final bool allowLoopback;
  bool get isConfigured => baseUrl.trim().isNotEmpty;

  /// Lazy by design: an undeployed bridge must not block startup or management
  /// of names whose Base account already has sufficient funds.
  Uri requireBaseUri() {
    if (!isConfigured) {
      throw const NearIntentsConfigurationException(
        'Sybil swaps and bridge funding are not configured for this build.',
      );
    }
    final uri = Uri.tryParse(baseUrl.trim());
    final local =
        uri != null &&
        const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(allowLoopback && local && uri.scheme == 'http'))) {
      throw const NearIntentsConfigurationException(
        'The Sybil swaps and bridge endpoint is invalid. Use HTTPS, or an explicitly enabled loopback development endpoint.',
      );
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
  }
}

class NearIntentsConfigurationException implements Exception {
  const NearIntentsConfigurationException(this.message);
  final String message;
  @override
  String toString() => message;
}
