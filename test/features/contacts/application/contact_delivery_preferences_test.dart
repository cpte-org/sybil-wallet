import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_preferences.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_providers.dart';

class _PreferenceStore implements ContactDeliveryPreferenceStore {
  bool enabled = true;
  bool failReads = false;
  bool failWrites = false;
  int writes = 0;

  @override
  Future<bool> readDeliveryEnabled() async {
    if (failReads) throw StateError('Unavailable');
    return enabled;
  }

  @override
  Future<void> writeDeliveryEnabled(bool value) async {
    writes++;
    if (failWrites) throw StateError('Unavailable');
    enabled = value;
  }
}

ProviderContainer _container(_PreferenceStore store) => ProviderContainer(
  retry: (_, _) => null,
  overrides: [contactDeliveryPreferenceStoreProvider.overrideWithValue(store)],
);

void main() {
  test(
    'private delivery starts enabled and remembers an explicit choice',
    () async {
      final store = _PreferenceStore();
      final first = _container(store);
      addTearDown(first.dispose);
      expect(await first.read(simplexDeliveryEnabledProvider.future), isTrue);
      await first
          .read(simplexDeliveryEnabledProvider.notifier)
          .setEnabled(false);
      expect(first.read(simplexDeliveryEnabledProvider).requireValue, isFalse);

      final restarted = _container(store);
      addTearDown(restarted.dispose);
      expect(
        await restarted.read(simplexDeliveryEnabledProvider.future),
        isFalse,
      );
      await restarted
          .read(simplexDeliveryEnabledProvider.notifier)
          .setEnabled(true);
      expect(store.enabled, isTrue);
    },
  );

  test('unreadable opt-out pauses delivery until retry reads it', () async {
    final store = _PreferenceStore()
      ..enabled = false
      ..failReads = true;
    final container = _container(store);
    addTearDown(container.dispose);
    await expectLater(
      container.read(simplexDeliveryEnabledProvider.future),
      throwsStateError,
    );
    expect(
      container.read(simplexDeliveryStatusProvider),
      isA<SimplexDeliveryPreferenceUnavailable>(),
    );
    expect(container.read(contactDeliveryScopeProvider), isNull);
    await expectLater(
      container.read(simplexDeliveryEnabledProvider.notifier).setEnabled(true),
      throwsStateError,
    );
    expect(store.writes, 0);
    expect(store.enabled, isFalse);

    store.failReads = false;
    container.invalidate(simplexDeliveryEnabledProvider);
    expect(
      await container.read(simplexDeliveryEnabledProvider.future),
      isFalse,
    );
    expect(
      container.read(simplexDeliveryStatusProvider),
      isA<SimplexDeliveryTurnedOff>(),
    );
    expect(container.read(contactDeliveryScopeProvider), isNull);
  });

  test('failed writes do not claim a preference change succeeded', () async {
    final store = _PreferenceStore()..failWrites = true;
    final container = _container(store);
    addTearDown(container.dispose);
    await container.read(simplexDeliveryEnabledProvider.future);
    await expectLater(
      container.read(simplexDeliveryEnabledProvider.notifier).setEnabled(false),
      throwsStateError,
    );
    expect(container.read(simplexDeliveryEnabledProvider).requireValue, isTrue);
    expect(store.enabled, isTrue);
  });

  test(
    'a disabled preference reports private delivery as turned off',
    () async {
      final store = _PreferenceStore()..enabled = false;
      final container = _container(store);
      addTearDown(container.dispose);
      await container.read(simplexDeliveryEnabledProvider.future);
      final status = container.read(simplexDeliveryStatusProvider);
      expect(status, isA<SimplexDeliveryTurnedOff>());
      expect(
        (status as SimplexDeliveryTurnedOff).message,
        'Private delivery is turned off. Turn it on in Contact options.',
      );
    },
  );
}
