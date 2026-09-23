import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/base_key_export.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_base_key_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

class _MutableAccountNotifier extends AccountNotifier {
  _MutableAccountNotifier(this.initial);
  final AccountState initial;
  @override
  FutureOr<AccountState> build() => initial;
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/settings/base-key',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1basekeyscreenaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

void main() {
  Future<void> show(
    WidgetTester t, {
    required Future<Uint8List> Function(String) load,
    BaseKeyExportAccess? Function()? access,
    AccountState account = const AccountState(
      accounts: [
        AccountInfo(
          uuid: 'account-1',
          name: 'Account 1',
          order: 0,
          isSeedAnchor: true,
        ),
      ],
      activeAccountUuid: 'account-1',
    ),
  }) async {
    final router = GoRouter(
      initialLocation: '/settings/base-key',
      routes: [
        GoRoute(
          path: '/settings/base-key',
          builder: (_, _) => const SettingsBaseKeyScreen(),
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap),
          syncProvider.overrideWith(FakeSyncNotifier.new),
          accountProvider.overrideWith(() => _MutableAccountNotifier(account)),
          baseKeyExportAccessProvider.overrideWith(
            (ref) async => access != null
                ? access()
                : BaseKeyExportAccess('0xPublicTestAccount', load),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
        ),
      ),
    );
  }

  Future<void> authenticate(WidgetTester t) async {
    await t.enterText(find.byType(TextField), 'test-password');
    // The submit button enables in response to the text change, so a frame
    // must build before the tap can reach its gesture handlers.
    await t.pump();
    await t.tap(find.bySemanticsLabel('Confirm password'));
    await t.pump();
  }

  testWidgets('key loads only after authentication', (t) async {
    final bytes = Uint8List.fromList(List.filled(32, 7));
    var calls = 0;
    await show(
      t,
      load: (password) async {
        calls++;
        expect(password, 'test-password');
        return bytes;
      },
    );
    await t.pumpAndSettle();
    expect(calls, 0);
    expect(find.byKey(const ValueKey('settings_base_key_value')), findsNothing);
    await authenticate(t);
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(
      find.byKey(const ValueKey('settings_base_key_value')),
      findsOneWidget,
    );
    expect(find.text('Base account'), findsOneWidget);
    expect(find.text('0xPublicTestAccount'), findsOneWidget);
  });

  testWidgets('exported key expires and is zeroed after one minute', (t) async {
    final bytes = Uint8List.fromList(List.filled(32, 7));
    await show(t, load: (_) async => bytes);
    await t.pumpAndSettle();
    await authenticate(t);
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings_base_key_value')),
      findsOneWidget,
    );
    await t.pump(const Duration(minutes: 1));
    expect(find.byKey(const ValueKey('settings_base_key_value')), findsNothing);
    expect(bytes.every((b) => b == 0), isTrue);
  });

  testWidgets('revoked export access clears a revealed key', (t) async {
    final bytes = Uint8List.fromList(List.filled(32, 7));
    BaseKeyExportAccess? access = BaseKeyExportAccess(
      '0xPublicTestAccount',
      (_) async => bytes,
    );
    await show(t, load: (_) async => bytes, access: () => access);
    await t.pumpAndSettle();
    await authenticate(t);
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings_base_key_value')),
      findsOneWidget,
    );
    access = null;
    final container = ProviderScope.containerOf(
      t.element(find.byType(SettingsBaseKeyScreen)),
    );
    container.invalidate(baseKeyExportAccessProvider);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings_base_key_value')), findsNothing);
    expect(bytes.every((b) => b == 0), isTrue);
  });

  testWidgets('account change discards an in-flight key export', (t) async {
    final pending = Completer<Uint8List>();
    final bytes = Uint8List.fromList(List.filled(32, 7));
    await show(t, load: (_) => pending.future);
    await t.pumpAndSettle();
    await authenticate(t);
    await t.pump();
    final container = ProviderScope.containerOf(
      t.element(find.byType(SettingsBaseKeyScreen)),
    );
    container.read(accountProvider.notifier).state = AsyncData(
      const AccountState(
        accounts: [
          AccountInfo(
            uuid: 'account-2',
            name: 'Account 2',
            order: 1,
            isSeedAnchor: true,
          ),
        ],
        activeAccountUuid: 'account-2',
      ),
    );
    await t.pump();
    pending.complete(bytes);
    await t.pump();
    expect(find.byKey(const ValueKey('settings_base_key_value')), findsNothing);
    expect(
      find.text('Selected account changed. Enter your password again.'),
      findsOneWidget,
    );
    expect(bytes.every((b) => b == 0), isTrue);
  });

  testWidgets('backgrounding clears the exported byte buffer', (t) async {
    final bytes = Uint8List.fromList(List.filled(32, 7));
    await show(t, load: (_) async => bytes);
    await t.pumpAndSettle();
    await authenticate(t);
    await t.pumpAndSettle();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    expect(bytes.every((b) => b == 0), isTrue);
    expect(find.byKey(const ValueKey('settings_base_key_value')), findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('export errors never display raw exception content', (t) async {
    await show(t, load: (_) async => throw StateError('SENSITIVE_SENTINEL'));
    await t.pumpAndSettle();
    await authenticate(t);
    await t.pumpAndSettle();
    expect(find.textContaining('SENSITIVE_SENTINEL'), findsNothing);
    expect(find.textContaining('Could not export'), findsOneWidget);
  });
}
