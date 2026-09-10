import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_lifecycle.dart';

void main() {
  tearDown(() {
    ContactLifecycle.resume(account: 'contact-a');
    ContactLifecycle.resume(account: 'contact-b');
    ContactLifecycle.resume();
    ContactLifecycle.listeners.clear();
  });

  test(
    'account quiescence immediately blocks new work and drains already registered work',
    () async {
      final gate = Completer<int>();
      final notifications = <String>[];
      ContactLifecycle.listeners.add(() => notifications.add('changed'));
      final running = ContactLifecycle.run('contact-a', () => gate.future);
      var drained = false;
      final quiescence = ContactLifecycle.quiesce(
        account: 'contact-a',
      ).then((_) => drained = true);
      expect(ContactLifecycle.allowed('contact-a'), isFalse);
      expect(notifications, ['changed']);
      await expectLater(
        ContactLifecycle.run('contact-a', () async => 1),
        throwsStateError,
      );
      expect(await ContactLifecycle.run('contact-b', () async => 2), 2);
      await pumpEventQueue();
      expect(drained, isFalse);
      gate.complete(7);
      expect(await running, 7);
      await quiescence;
      expect(drained, isTrue);
      ContactLifecycle.resume(account: 'contact-a');
      expect(await ContactLifecycle.run('contact-a', () async => 8), 8);
    },
  );

  test(
    'wallet quiescence drains all accounts and keeps account-specific blocks separate',
    () async {
      final a = Completer<void>(), b = Completer<void>();
      final runA = ContactLifecycle.run('contact-a', () => a.future);
      final runB = ContactLifecycle.run('contact-b', () => b.future);
      var drained = false;
      final quiescence = ContactLifecycle.quiesce().then((_) => drained = true);
      expect(ContactLifecycle.allowed('contact-a'), isFalse);
      expect(ContactLifecycle.allowed('contact-b'), isFalse);
      a.complete();
      await runA;
      await pumpEventQueue();
      expect(drained, isFalse);
      b.complete();
      await runB;
      await quiescence;
      expect(drained, isTrue);
      ContactLifecycle.resume();
      await ContactLifecycle.quiesce(account: 'contact-a');
      await ContactLifecycle.quiesce();
      ContactLifecycle.resume();
      expect(ContactLifecycle.allowed('contact-a'), isFalse);
      expect(ContactLifecycle.allowed('contact-b'), isTrue);
    },
  );

  test(
    'failed operations unregister and do not poison subsequent drain',
    () async {
      await expectLater(
        ContactLifecycle.run<void>(
          'contact-a',
          () async => throw StateError('test failure'),
        ),
        throwsStateError,
      );
      await ContactLifecycle.quiesce(
        account: 'contact-a',
      ).timeout(const Duration(seconds: 1));
      ContactLifecycle.resume(account: 'contact-a');
      expect(
        await ContactLifecycle.run('contact-a', () async => 'recovered'),
        'recovered',
      );
    },
  );
}
