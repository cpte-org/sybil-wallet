import 'dart:convert';
import '../../../core/network/network_http_client.dart';

class ZnsDataException implements Exception {
  const ZnsDataException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => message;
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

Map<String, Object?> znsObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const ZnsDataException('Expected a JSON object');
  }
  return value;
}
