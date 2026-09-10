import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Test-only platform storage for exercising the real AppSecureStore crypto.
///
/// The caller supplies an absolute file in its freshly created temporary root
/// and owns that root's lifetime. No OS keyring, plugin global, or application
/// storage is accessed. Options are accepted for API compatibility only.
///
/// Every operation rereads the file; constructing another adapter over the
/// same file therefore exercises persistence rather than an in-memory cache.
/// Small synchronous file operations keep read-modify-write indivisible within
/// the test isolate. This is not a multiprocess storage implementation.
class FileBackedContactSecureStorage extends FlutterSecureStorage {
  FileBackedContactSecureStorage(this.file) {
    if (!file.uri.isAbsolute) {
      throw ArgumentError('Contact test storage requires an absolute file.');
    }
  }

  final File file;

  Map<String, String> _load() {
    if (!file.existsSync()) return <String, String>{};
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      // Do not attach the stored JSON to errors emitted by a failing test.
      throw const FormatException('Invalid contact test storage JSON.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.values.any((value) => value is! String)) {
      throw const FormatException('Invalid contact test storage values.');
    }
    return Map<String, String>.from(decoded);
  }

  void _replace(Map<String, String> values) {
    final suffix = Random.secure().nextInt(1 << 32).toRadixString(16);
    final temporary = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-$suffix',
    );
    try {
      temporary.writeAsStringSync(jsonEncode(values), flush: true);
      temporary.renameSync(file.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _load()[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final values = _load();
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    _replace(values);
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _load();

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final values = _load()..remove(key);
    _replace(values);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _replace(<String, String>{});
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _load().containsKey(key);
}
