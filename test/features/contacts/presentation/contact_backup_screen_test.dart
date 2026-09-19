import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import '../contact_test_fakes.dart'
    show FakeContactGateway, FakeContactRepository, testContactScopeProvider;
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_backup_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_backup_providers.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_exchange_controller.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_introduction_models.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_backup_screen.dart';
import '../contact_backup_test.dart'
    show MemoryBackupStore, FixtureCrypto, sourceScope, targetScope;
import '../contact_test_fixtures.dart';

void main() {
  testWidgets(
    'details start collapsed and recovery refreshes on resume and account change',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryBackupStore()
        ..book = ContactBook(
          contacts: [testContact(status: ContactTrustStatus.restored)],
        );
      late ProviderContainer container;
      final coordinator = ContactBackupCoordinator(
        scope: () => container.read(contactScopeProvider),
        store: store,
        crypto: FixtureCrypto(),
      );
      container = ProviderContainer(
        overrides: [
          contactScopeProvider.overrideWith(
            (ref) => ref.watch(testContactScopeProvider),
          ),
          contactBackupCoordinatorProvider.overrideWithValue(coordinator),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(coordinator.invalidate);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: ContactBackupScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check Alice'), findsOneWidget);
      expect(find.textContaining('Includes connected contacts'), findsNothing);
      await tester.tap(find.text('What this backup includes'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Includes connected contacts'),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      store.book = ContactBook(
        contacts: [
          testContact(
            label: 'Alice resumed',
            status: ContactTrustStatus.restored,
          ),
        ],
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Check Alice'), findsNothing);
      expect(find.text('Check Alice resumed'), findsOneWidget);
      container.read(testContactScopeProvider.notifier).change(null);
      await tester.pumpAndSettle();
      expect(find.text('Check Alice'), findsNothing);
      expect(find.text('Check Alice resumed'), findsNothing);
      store.book = ContactBook(
        contacts: [
          testContact(
            id: 'bob',
            label: 'Bob',
            identityByte: 2,
            status: ContactTrustStatus.restored,
          ),
        ],
      );
      container.read(testContactScopeProvider.notifier).change(targetScope);
      await tester.pumpAndSettle();
      expect(find.text('Check Alice'), findsNothing);
      expect(find.text('Check Bob'), findsOneWidget);
    },
  );

  testWidgets(
    'recovery action starts an identity-bound check and opens exchange',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final contact = testContact(status: ContactTrustStatus.restored);
      final target = MemoryBackupStore()
        ..book = ContactBook(contacts: [contact]);
      final coordinator = ContactBackupCoordinator(
        scope: () => targetScope,
        store: target,
        crypto: FixtureCrypto(),
      );
      addTearDown(coordinator.invalidate);
      final gateway = FakeContactGateway();
      final router = GoRouter(
        initialLocation: '/contacts/backup',
        routes: [
          GoRoute(
            path: '/contacts/backup',
            builder: (_, _) => const ContactBackupScreen(),
          ),
          GoRoute(
            path: '/contacts/exchange',
            builder: (_, _) => const Scaffold(body: Text('Exchange opened')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contactScopeProvider.overrideWithValue(targetScope),
            contactBackupCoordinatorProvider.overrideWithValue(coordinator),
            contactRepositoryProvider.overrideWithValue(
              FakeContactRepository([contact]),
            ),
            contactGatewayProvider.overrideWithValue(gateway),
            contactClockProvider.overrideWithValue(() => testContactNow),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.dark, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check Alice'));
      await tester.tap(find.text('Check Alice'));
      await tester.pumpAndSettle();
      expect(gateway.requestedSubject, contact.identity);
      expect(find.text('Exchange opened'), findsOneWidget);
    },
  );

  testWidgets(
    'restore stays gated by review and consent; editing discards approval',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = MemoryBackupStore()
        ..book = ContactBook(contacts: [testContact()]);
      final target = MemoryBackupStore(), crypto = FixtureCrypto();
      final exporter = ContactBackupCoordinator(
        scope: () => sourceScope,
        store: source,
        crypto: crypto,
      );
      final importer = ContactBackupCoordinator(
        scope: () => targetScope,
        store: target,
        crypto: crypto,
      );
      addTearDown(importer.invalidate);
      final archive = await exporter.export();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contactScopeProvider.overrideWithValue(targetScope),
            contactBackupCoordinatorProvider.overrideWithValue(importer),
          ],
          child: const MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: ContactBackupScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), archive);
      await tester.tap(find.text('Review restoration'));
      await tester.pumpAndSettle();
      expect(target.occupied, isFalse);
      await tester.tap(find.text('Restore contacts'));
      await tester.pumpAndSettle();
      expect(target.occupied, isFalse);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '$archive ');
      await tester.pumpAndSettle();
      expect(find.text('Restore contacts'), findsNothing);
      await tester.tap(find.text('Review restoration'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore contacts'));
      await tester.pumpAndSettle();
      expect(target.book.contacts.single.status, ContactTrustStatus.restored);
      expect(find.textContaining('Contacts restored.'), findsOneWidget);
      expect(find.text('1 contacts need a fresh check.'), findsOneWidget);
      expect(find.text('Check Alice'), findsOneWidget);
    },
  );
}
