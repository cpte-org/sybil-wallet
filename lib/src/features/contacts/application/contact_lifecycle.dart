import 'dart:async';

/// Destructive wallet actions drain contact storage/address allocation first.
/// No wallet/provider dependency: account removal can consult this safely.
class ContactLifecycle {
  static final _running = <String, Set<Future<void>>>{};
  static final _blocked = <String, int>{};
  static int _allBlocked = 0;
  static final listeners = <void Function()>[];

  static bool allowed(String account) =>
      _allBlocked == 0 && !_blocked.containsKey(account);

  static Future<T> run<T>(String account, Future<T> Function() action) async {
    if (!allowed(account)) {
      throw StateError('Contact activity is paused for account removal.');
    }
    final done = Completer<void>();
    (_running[account] ??= {}).add(done.future);
    try {
      return await action();
    } finally {
      _running[account]?.remove(done.future);
      if (_running[account]?.isEmpty == true) _running.remove(account);
      done.complete();
    }
  }

  static Future<void> quiesce({String? account}) async {
    if (account == null) {
      _allBlocked++;
    } else {
      _blocked[account] = (_blocked[account] ?? 0) + 1;
    }
    for (final listener in List.of(listeners)) {
      listener();
    }
    await Future.wait([
      for (final entry in _running.entries)
        if (account == null || entry.key == account) ...entry.value,
    ]);
  }

  static void resume({String? account}) {
    if (account == null) {
      if (_allBlocked > 0) _allBlocked--;
    } else {
      final count = _blocked[account] ?? 0;
      if (count <= 1) {
        _blocked.remove(account);
      } else {
        _blocked[account] = count - 1;
      }
    }
    for (final listener in List.of(listeners)) {
      listener();
    }
  }
}
