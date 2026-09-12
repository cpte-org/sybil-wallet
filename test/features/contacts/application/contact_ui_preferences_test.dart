import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_ui_preferences.dart';

class _PreferenceStore implements ContactUiPreferenceStore {
  bool enabled = false;
  bool failReads = false;
  bool failWrites = false;

  @override
  Future<bool> readAdvancedTools() async {
    if (failReads) throw StateError('Unavailable');
    return enabled;
  }

  @override
  Future<void> writeAdvancedTools(bool value) async {
    if (failWrites) throw StateError('Unavailable');
    enabled = value;
  }
}

ProviderContainer _container(_PreferenceStore store) => ProviderContainer(
  overrides: [contactUiPreferenceStoreProvider.overrideWithValue(store)],
);

void main() {
  test('advanced tools start hidden and remember an explicit choice', () async {
    final store = _PreferenceStore();
    final first = _container(store);
    addTearDown(first.dispose);
    expect(await first.read(contactAdvancedToolsProvider.future), isFalse);
    await first.read(contactAdvancedToolsProvider.notifier).setEnabled(true);
    expect(first.read(contactAdvancedToolsProvider).requireValue, isTrue);

    final restarted = _container(store);
    addTearDown(restarted.dispose);
    expect(await restarted.read(contactAdvancedToolsProvider.future), isTrue);
    await restarted
        .read(contactAdvancedToolsProvider.notifier)
        .setEnabled(false);
    expect(store.enabled, isFalse);
  });

  test('unavailable preference storage keeps advanced tools hidden', () async {
    final store = _PreferenceStore()
      ..enabled = true
      ..failReads = true;
    final container = _container(store);
    addTearDown(container.dispose);
    expect(await container.read(contactAdvancedToolsProvider.future), isFalse);
  });

  test('failed writes do not claim a preference change succeeded', () async {
    final store = _PreferenceStore()..failWrites = true;
    final container = _container(store);
    addTearDown(container.dispose);
    await container.read(contactAdvancedToolsProvider.future);
    await expectLater(
      container.read(contactAdvancedToolsProvider.notifier).setEnabled(true),
      throwsStateError,
    );
    expect(container.read(contactAdvancedToolsProvider).requireValue, isFalse);
    expect(store.enabled, isFalse);
  });
}
