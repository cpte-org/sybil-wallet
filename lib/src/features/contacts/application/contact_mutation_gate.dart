import 'dart:async';

import '../domain/contact_models.dart';
import 'contact_lifecycle.dart';

/// One in-process serialization boundary shared by direct contacts and the
/// introduction coordinator. It covers read/compare/write, not only disk writes.
/// Backend writes already dispatched may commit when a wallet locks; no newer
/// mutation can interleave, and callers must recheck before publishing results.
class ContactMutationGate {
  static final _tails = <ContactScope, Future<void>>{};
  static final _pending = <ContactScope, int>{};
  static final _generations = <ContactScope, int>{};
  static final listeners = <void Function(ContactScope, Object?)>[];

  static int generation(ContactScope scope) => _generations[scope] ?? 0;
  static bool busy(ContactScope scope) => (_pending[scope] ?? 0) > 0;

  static Future<T> run<T>(
    ContactScope scope,
    Future<T> Function() action, {
    Object? source,
    bool mutation = false,
  }) => ContactLifecycle.run(scope.accountUuid, () async {
    final previous = _tails[scope] ?? Future<void>.value();
    final done = Completer<void>();
    _tails[scope] = done.future;
    _pending[scope] = (_pending[scope] ?? 0) + 1;
    if (mutation) _generations[scope] = generation(scope) + 1;
    try {
      await previous;
      if (!ContactLifecycle.allowed(scope.accountUuid)) {
        throw const ContactFailure(
          'Contact activity is paused. Start a new review.',
        );
      }
      return await action();
    } finally {
      final remaining = (_pending[scope] ?? 1) - 1;
      if (remaining == 0) {
        _pending.remove(scope);
      } else {
        _pending[scope] = remaining;
      }
      if (identical(_tails[scope], done.future)) _tails.remove(scope);
      done.complete();
      if (mutation) {
        for (final listener in List.of(listeners)) {
          listener(scope, source);
        }
      }
    }
  });
}
