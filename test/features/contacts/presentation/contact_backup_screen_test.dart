import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    },
  );
}
