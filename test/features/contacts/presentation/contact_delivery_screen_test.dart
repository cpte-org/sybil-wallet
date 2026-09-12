import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_providers.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_ui_preferences.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_delivery_repository.dart';
import 'package:zcash_wallet/src/features/contacts/data/simplex_native_transport.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_delivery.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_code_widgets.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_connection_binding_panel.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_delivery_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../../fakes/fake_sync_notifier.dart';

const _scope = ContactScope(
  accountUuid: 'delivery-screen-test',
  network: 'regtest',
);

class _Preferences implements ContactUiPreferenceStore {
  _Preferences(this.enabled);
  bool enabled;
  @override
  Future<bool> readAdvancedTools() async => enabled;
  @override
  Future<void> writeAdvancedTools(bool enabled) async => this.enabled = enabled;
}

class _Repository implements ContactDeliveryRepository {
  ContactDeliveryJournal journal = ContactDeliveryJournal();
  @override
  Future<ContactDeliveryJournal> load(ContactScope scope) async => journal;
  @override
  Future<void> save(ContactScope scope, ContactDeliveryJournal value) async {
    journal = value;
  }
}

class _Transport extends SimplexNativeTransport {
  _Transport() : super(scope: _scope, networkAllowed: () => true);
  int sends = 0;
  @override
  Future<List<({String id, String label})>> peers() async => [
    (id: 'connection-1', label: 'Unverified label'),
  ];
  @override
  Future<void> reconcile(ContactDeliveryCoordinator coordinator) async {}
  @override
  Future<void> submit(String peer, String id, String packet) async {
    sends++;
  }
}

Future<void> _show(
  WidgetTester tester, {
  bool advanced = false,
  ContactScope? scope = _scope,
  required Future<SimplexNativeTransport> Function() open,
  _Repository? repository,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final coordinator = ContactDeliveryCoordinator(
    scope: () => scope,
    repository: repository ?? _Repository(),
  );
  addTearDown(coordinator.invalidate);
  final router = GoRouter(
    initialLocation: '/contacts/delivery',
    routes: [
      GoRoute(
        path: '/contacts/delivery',
        builder: (_, _) => const ContactDeliveryScreen(),
      ),
      GoRoute(
        path: '/contacts/exchange',
        builder: (_, _) => const Scaffold(body: Text('exchange route')),
      ),
      GoRoute(
        path: '/settings/contacts',
        builder: (_, _) => const Scaffold(body: Text('contact settings route')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/contacts/delivery',
            initialAccountState: const AccountState(
              accounts: [
                AccountInfo(
                  uuid: 'delivery-screen-test',
                  name: 'Test account',
                  order: 0,
                ),
              ],
              activeAccountUuid: 'delivery-screen-test',
            ),
            initialSyncSnapshot: AppSyncSnapshot.empty,
            network: 'testnet',
            rpcEndpointConfig: defaultRpcEndpointConfig('testnet'),
            themeMode: ThemeMode.light,
            privacyModeEnabled: false,
            isPasswordConfigured: true,
            isUnlocked: true,
            passwordRotationRecoveryFailed: false,
          ),
        ),
        syncProvider.overrideWith(FakeSyncNotifier.new),
        contactUiPreferenceStoreProvider.overrideWithValue(
          _Preferences(advanced),
        ),
        contactDeliveryScopeProvider.overrideWithValue(scope),
        contactDeliveryCoordinatorProvider.overrideWithValue(coordinator),
        simplexNativeTransportProvider.overrideWith((_) => open()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'advanced tools off never opens transport and offers code exchange',
    (tester) async {
      var opens = 0;
      await _show(
        tester,
        open: () async {
          opens++;
          return _Transport();
        },
      );
      expect(opens, 0);
      expect(find.text('Connection tools'), findsOneWidget);
      expect(find.byType(ContactCodeInput), findsNothing);
      expect(find.byType(ContactConnectionBindingPanel), findsNothing);
      await tester.tap(find.text('Exchange a contact code'));
      await tester.pumpAndSettle();
      expect(find.text('exchange route'), findsOneWidget);
    },
  );

  testWidgets(
    'native failure hides connection and send forms and supports retry',
    (tester) async {
      var opens = 0;
      await _show(
        tester,
        advanced: true,
        open: () async {
          opens++;
          throw const ContactFailure('Test runtime is absent.');
        },
      );
      expect(opens, 1);
      expect(find.text('Private delivery isn’t available'), findsOneWidget);
      expect(find.byType(ContactCodeInput), findsNothing);
      expect(find.byType(ContactConnectionBindingPanel), findsNothing);
      expect(find.text('Approve and send code'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(opens, 2);
      await tester.tap(find.text('Exchange a contact code'));
      await tester.pumpAndSettle();
      expect(find.text('exchange route'), findsOneWidget);
    },
  );

  testWidgets('unsupported scope does not open transport and offers settings', (
    tester,
  ) async {
    var opens = 0;
    await _show(
      tester,
      advanced: true,
      scope: null,
      open: () async {
        opens++;
        return _Transport();
      },
    );
    expect(opens, 0);
    expect(find.text('Private delivery is paused'), findsOneWidget);
    await tester.tap(find.text('Contact settings'));
    await tester.pumpAndSettle();
    expect(find.text('contact settings route'), findsOneWidget);
  });

  testWidgets('opening a code never sends before peer selection and approval', (
    tester,
  ) async {
    final transport = _Transport(), repository = _Repository();
    await _show(
      tester,
      advanced: true,
      repository: repository,
      open: () async => transport,
    );
    final input = tester.widget<ContactCodeInput>(
      find.byWidgetPredicate(
        (widget) =>
            widget is ContactCodeInput &&
            widget.title == 'Open the approved contact code',
      ),
    );
    await input.onRead('["test-contact-code"]');
    await tester.pump();
    expect(transport.sends, 0);
    expect(repository.journal.records, isEmpty);
    await tester.ensureVisible(find.text('Refresh connections and inbox'));
    await tester.tap(find.text('Refresh connections and inbox'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButton<String>));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unverified label · connection-1').last);
    await tester.pumpAndSettle();
    expect(transport.sends, 0);
    await tester.ensureVisible(find.text('Approve and send code'));
    await tester.tap(find.text('Approve and send code'));
    await tester.pumpAndSettle();
    expect(transport.sends, 1);
    expect(repository.journal.records.single.packet, '["test-contact-code"]');
    expect(
      repository.journal.records.single.state,
      ContactDeliveryState.submitted,
    );
    expect(tester.takeException(), isNull);
  });
}
