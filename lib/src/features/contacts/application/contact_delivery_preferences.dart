import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';

/// Local delivery preferences. These never grant contact or payment authority.
abstract interface class ContactDeliveryPreferenceStore {
  Future<bool> readDeliveryEnabled();
  Future<void> writeDeliveryEnabled(bool enabled);
}

class SecureContactDeliveryPreferenceStore
    implements ContactDeliveryPreferenceStore {
  static const _key = 'zcash_simplex_delivery_enabled';

  @override
  Future<bool> readDeliveryEnabled() async =>
      await AppSecureStore.instance.readPlain(_key) != 'false';

  @override
  Future<void> writeDeliveryEnabled(bool enabled) =>
      AppSecureStore.instance.writePlain(_key, enabled ? 'true' : 'false');
}

final contactDeliveryPreferenceStoreProvider =
    Provider<ContactDeliveryPreferenceStore>(
      (_) => SecureContactDeliveryPreferenceStore(),
    );

final simplexDeliveryEnabledProvider =
    AsyncNotifierProvider<SimplexDeliveryEnabled, bool>(
      SimplexDeliveryEnabled.new,
    );

class SimplexDeliveryEnabled extends AsyncNotifier<bool> {
  bool _saving = false;

  @override
  Future<bool> build() =>
      ref.watch(contactDeliveryPreferenceStoreProvider).readDeliveryEnabled();

  Future<void> setEnabled(bool enabled) async {
    if (_saving || state.isLoading) return;
    if (state.hasError || state.asData == null) {
      throw StateError(
        'Read your private delivery setting before changing it.',
      );
    }
    _saving = true;
    final previous = state.requireValue;
    state = const AsyncLoading();
    try {
      await ref
          .read(contactDeliveryPreferenceStoreProvider)
          .writeDeliveryEnabled(enabled);
      state = AsyncData(enabled);
    } catch (_) {
      state = AsyncData(previous);
      throw StateError('Could not save this setting. Try again.');
    } finally {
      _saving = false;
    }
  }
}
