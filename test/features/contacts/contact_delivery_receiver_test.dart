import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_providers.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_receiver.dart';

void main() {
  testWidgets('serial scans wait for completion and stop on disposal', (
    tester,
  ) async {
    var calls = 0, refreshes = 0, failures = 0;
    final pending = Completer<void>();
    final receiver = ContactDeliveryReceiver(
      allowed: () => true,
      reconcile: () {
        calls++;
        return pending.future;
      },
      onRefresh: () => refreshes++,
      onFailure: () => failures++,
    );
    receiver.start();
    receiver.start();
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 1);
    pending.complete();
    await tester.pump(const Duration(milliseconds: 1));
    expect(refreshes, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 2);
    receiver.stop();
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 2);
    expect(failures, 0);
  });

  testWidgets('lock during scan drops late refresh and all future work', (
    tester,
  ) async {
    var allowed = true, calls = 0, refreshes = 0, failures = 0;
    final pending = Completer<void>();
    final receiver = ContactDeliveryReceiver(
      allowed: () => allowed,
      reconcile: () {
        calls++;
        return pending.future;
      },
      onRefresh: () => refreshes++,
      onFailure: () => failures++,
    )..start();
    await tester.pump(const Duration(milliseconds: 1));
    allowed = false;
    receiver.stop();
    pending.completeError(StateError('native key/packet must not be exposed'));
    await tester.pump(const Duration(milliseconds: 1));
    allowed = true;
    receiver.start();
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 1);
    expect(refreshes, 0);
    expect(failures, 0);
  });

  testWidgets('closed privacy gate never starts a reconciliation', (
    tester,
  ) async {
    var calls = 0;
    final receiver = ContactDeliveryReceiver(
      allowed: () => false,
      reconcile: () async {
        calls++;
      },
      onRefresh: () => fail('unexpected refresh'),
      onFailure: () => fail('unexpected failure'),
    )..start();
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 0);
    receiver.stop();
  });

  testWidgets('failure stops polling and reports once without diagnostics', (
    tester,
  ) async {
    var calls = 0, failures = 0;
    final receiver = ContactDeliveryReceiver(
      allowed: () => true,
      reconcile: () async {
        calls++;
        throw StateError('private native diagnostics');
      },
      onRefresh: () => fail('unexpected refresh'),
      onFailure: () => failures++,
    )..start();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 1);
    expect(failures, 1);
    receiver.stop();
  });

  testWidgets('new transport cannot activate while hidden or paused', (
    tester,
  ) async {
    final container = ProviderContainer();
    final subscription = container.listen(
      contactDeliveryForegroundProvider,
      (_, _) {},
    );
    for (final state in [
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        container.read(contactDeliveryForegroundProvider),
        state == AppLifecycleState.resumed ||
            state == AppLifecycleState.inactive,
      );
    }
    subscription.close();
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
