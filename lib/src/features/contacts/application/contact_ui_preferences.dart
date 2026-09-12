import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';

/// Presentation preferences only. These never grant contact or payment authority.
abstract interface class ContactUiPreferenceStore {
  Future<bool> readAdvancedTools();
  Future<void> writeAdvancedTools(bool enabled);
}

class SecureContactUiPreferenceStore implements ContactUiPreferenceStore {
  static const _key = 'zcash_contact_advanced_tools_enabled';

  @override
  Future<bool> readAdvancedTools() async =>
      await AppSecureStore.instance.readPlain(_key) == 'true';

  @override
  Future<void> writeAdvancedTools(bool enabled) =>
      AppSecureStore.instance.writePlain(_key, enabled ? 'true' : 'false');
}

final contactUiPreferenceStoreProvider = Provider<ContactUiPreferenceStore>(
  (_) => SecureContactUiPreferenceStore(),
);

final contactAdvancedToolsProvider =
    AsyncNotifierProvider<ContactAdvancedTools, bool>(ContactAdvancedTools.new);

class ContactAdvancedTools extends AsyncNotifier<bool> {
  bool _saving = false;

  @override
  Future<bool> build() async {
    try {
      return await ref
          .watch(contactUiPreferenceStoreProvider)
          .readAdvancedTools();
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (_saving || state.isLoading) return;
    _saving = true;
    final previous = state.asData?.value ?? false;
    state = const AsyncLoading();
    try {
      await ref
          .read(contactUiPreferenceStoreProvider)
          .writeAdvancedTools(enabled);
      state = AsyncData(enabled);
    } catch (_) {
      state = AsyncData(previous);
      throw StateError('Could not save this setting. Try again.');
    } finally {
      _saving = false;
    }
  }
}
