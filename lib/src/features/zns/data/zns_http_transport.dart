import 'dart:convert';
import 'dart:io' show HttpDate, HttpException;
import '../../../core/network/network_http_client.dart';

class ZnsDataException implements Exception {
  const ZnsDataException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => message;
}

class ZnsRateLimitException extends ZnsDataException {
  const ZnsRateLimitException({this.retryAfter, this.rpcMethod})
    : super(
        'The name service is temporarily busy. Wait a moment, then try again.',
        code: 429,
      );
  final Duration? retryAfter;

  /// Set only from the wallet's RPC method, never from provider response text.
  final String? rpcMethod;

  @override
  String get message => rpcMethod == null
      ? super.message
      : 'Base RPC $rpcMethod is temporarily busy. Wait a moment, then try again.';
}

abstract interface class ZnsHttpTransport {
  Future<Object?> request(String method, Uri uri, {Map<String, Object?>? body});
  void close();
}

/// Reuses the wallet's foreground routing policy. Tor failures never trigger
/// a direct retry. No endpoint, address, payload, signature or response logging.
class ZnsPolicyHttpTransport implements ZnsHttpTransport {
  ZnsPolicyHttpTransport({NetworkHttpClient? client})
    : _client = client ?? NetworkHttpClient();
  final NetworkHttpClient _client;

  @override
  Future<Object?> request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    final response = await _client.request(
      method,
      uri,
      headers: {
        'accept': 'application/json',
        'content-type': 'application/json',
        'x-client-id': 'vizor-zns',
      },
      bodyBytes: body == null ? const [] : utf8.encode(jsonEncode(body)),
      timeout: const Duration(seconds: 30),
    );
    if (response.statusCode == 429) {
      throw ZnsRateLimitException(
        retryAfter: znsRetryAfter(response.header('retry-after')),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ZnsDataException(
        'ZNS network request failed (${response.statusCode}). Retry after checking connectivity.',
        code: response.statusCode,
      );
    }
    if (response.bodyBytes.length > 2 * 1024 * 1024) {
      throw const ZnsDataException('ZNS network response was too large');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ZnsDataException('ZNS service returned malformed JSON');
    }
  }

  @override
  void close() => _client.close(force: true);
}

Duration? znsRetryAfter(String? header, {DateTime? now}) {
  if (header == null) return null;
  final seconds = int.tryParse(header.trim());
  if (seconds != null) {
    // Reject unreasonable input instead of overflowing Duration's arithmetic.
    return seconds >= 0 && seconds <= 86400 * 365
        ? Duration(seconds: seconds)
        : null;
  }
  try {
    final wait = HttpDate.parse(header).difference(now ?? DateTime.now());
    return wait.isNegative ? Duration.zero : wait;
  } on HttpException {
    return null;
  } on FormatException {
    return null;
  }
}

Map<String, Object?> znsObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const ZnsDataException('Expected a JSON object');
  }
  return value;
}
