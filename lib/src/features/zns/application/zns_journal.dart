import 'dart:convert';
import '../../../core/storage/app_secure_store.dart';
import '../domain/zns_operation.dart';

abstract interface class ZnsJournalStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class ZnsSecureJournalStorage implements ZnsJournalStorage {
  const ZnsSecureJournalStorage();
  @override
  Future<String?> read(String key) => AppSecureStore.instance.readString(key);
  @override
  Future<void> write(String key, String value) =>
      AppSecureStore.instance.writeString(key, value);
}

/// Single serialized record, saved before funding or signed transaction
/// broadcast. Failure to read is not interpreted as absence of an operation.
class ZnsJournal {
  const ZnsJournal(this.storage);
  final ZnsJournalStorage storage;
  Future<ZnsOperation?> load(ZnsScope scope) async {
    final raw = await storage.read(scope.key);
    return raw == null || raw == 'null'
        ? null
        : ZnsOperation.decode(raw, scope);
  }

  Future<void> save(ZnsOperation operation, String accountUuid) async {
    final indexKey = 'zns:account:$accountUuid';
    final rawIndex = await storage.read(indexKey);
    final scopes = rawIndex == null
        ? <String>[]
        : (jsonDecode(rawIndex) as List).cast<String>();
    if (!scopes.contains(operation.scope.key)) {
      scopes.add(operation.scope.key);
      // Index first: an interrupted save must conservatively block deletion.
      await storage.write(indexKey, jsonEncode(scopes));
    }
    final previous = await storage.read(operation.scope.key);
    if (previous != null && previous != 'null') {
      final old = ZnsOperation.decode(previous, operation.scope);
      if (old.secret != operation.secret) {
        await _archiveBytes(operation.scope, previous);
      }
    }
    await storage.write(operation.scope.key, jsonEncode(operation.toJson()));
  }

  Future<void> _archiveBytes(ZnsScope scope, String raw) async {
    final key = '${scope.key}:history';
    final saved = await storage.read(key);
    final history = saved == null ? <dynamic>[] : jsonDecode(saved) as List;
    final record = jsonDecode(raw) as Map;
    if (!history.any((v) => v['secret'] == record['secret'])) {
      history.add(record);
      await storage.write(key, jsonEncode(history));
    }
  }

  Future<void> archive(ZnsOperation operation) async {
    await _archiveBytes(operation.scope, jsonEncode(operation.toJson()));
    await storage.write(operation.scope.key, 'null');
  }

  Future<bool> hasAccountRecords(String accountUuid) async {
    final value = await storage.read('zns:account:$accountUuid');
    return value != null && (jsonDecode(value) as List).isNotEmpty;
  }
}
