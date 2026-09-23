import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/contacts/data/sybil_people_metadata_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/sybil_people_screen.dart';

import '../contact_test_fixtures.dart';

Future<void> pumpPeople(
  WidgetTester tester, {
  List<VerifiedContact>? people,
  Map<String, SybilPersonMetadata> metadata = const {},
  String? selected,
  ValueChanged<VerifiedContact>? onPay,
  Future<void> Function(VerifiedContact, String)? onRename,
  Future<void> Function(VerifiedContact, SybilPersonMetadata)? onSaveMetadata,
  bool available = true,
  bool showAdvancedTools = false,
  VoidCallback? onIntroductions,
  Size size = const Size(1100, 1000),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(),
      builder: (context, child) =>
          AppTheme(data: AppThemeData.light, child: child!),
      home: Scaffold(
        body: SybilPeopleView(
          state: ContactExchangeState(
            available: available,
            contacts: people ?? [testContact()],
          ),
          metadata: metadata,
          contactId: selected,
          onPay: onPay,
          onRename: onRename,
          onSaveMetadata: onSaveMetadata,
          showAdvancedTools: showAdvancedTools,
          onIntroductions: onIntroductions,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'People hosts introductions and hides advanced tools by default',
    (tester) async {
      var introductions = 0;
      await pumpPeople(
        tester,
        people: [testContact()],
        onIntroductions: () => introductions++,
      );
      expect(find.widgetWithText(ListTile, 'Introductions'), findsOneWidget);
      // Adding someone (manual or connect privately) lives in the add flow.
      expect(find.widgetWithText(ListTile, 'Connect privately'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Connection backup'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Manual key pairing'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Private delivery'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Other networks'), findsNothing);
      expect(find.text('Reload'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'Introductions'));
      expect(introductions, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('advanced tools reveal delivery, other networks and reload', (
    tester,
  ) async {
    await pumpPeople(tester, people: [testContact()], showAdvancedTools: true);
    expect(find.widgetWithText(ListTile, 'Introductions'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Private delivery'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Other networks'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Manual key pairing'), findsNothing);
    expect(find.text('Reload'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search and filters preserve distinct contact states', (
    tester,
  ) async {
    await pumpPeople(
      tester,
      people: [
        testContact(),
        testContact(
          id: 'bea',
          label: 'Bea',
          identityByte: 2,
          status: ContactTrustStatus.restored,
        ),
        testContact(
          id: 'cam',
          label: 'Cam',
          identityByte: 3,
          status: ContactTrustStatus.suspended,
        ),
        testContact(
          id: 'dan',
          label: 'Dan',
          identityByte: 4,
          status: ContactTrustStatus.retired,
        ),
      ],
      metadata: {testIdentity(1): const SybilPersonMetadata(pinned: true)},
    );
    for (final status in ['Restored · needs a check', 'Suspended', 'Retired']) {
      expect(find.text(status), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(ChoiceChip, 'Needs a check'));
    await tester.pumpAndSettle();
    expect(find.text('Bea'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pinned'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bea'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Everyone'));
    await tester.enterText(find.byKey(const Key('people-search')), 'cAm');
    await tester.pumpAndSettle();
    expect(find.text('Cam'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepted payment selection retains exact contact', (
    tester,
  ) async {
    final person = testContact();
    VerifiedContact? selected;
    await pumpPeople(
      tester,
      people: [person],
      selected: person.id,
      onPay: (value) => selected = value,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send money'));
    expect(selected, same(person));
  });

  testWidgets(
    'restored, suspended and retired detail never offers payment or trust toggle',
    (tester) async {
      for (final status in ContactTrustStatus.values.where(
        (status) => status != ContactTrustStatus.accepted,
      )) {
        await pumpPeople(
          tester,
          people: [testContact(status: status)],
          selected: 'alice',
        );
        expect(find.text('Send money'), findsNothing);
        expect(find.text('Mark trusted'), findsNothing);
        expect(
          find.text(
            status == ContactTrustStatus.restored
                ? 'Check current address'
                : 'Add a replacement',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('name and local note edits use separate save callbacks', (
    tester,
  ) async {
    String? name;
    SybilPersonMetadata? saved;
    await pumpPeople(
      tester,
      selected: 'alice',
      onRename: (_, value) async => name = value,
      onSaveMetadata: (_, value) async => saved = value,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('person-name')), 'My friend');
    await tester.ensureVisible(find.text('Save name'));
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();
    expect(name, 'My friend');
    expect(saved, isNull);
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Note'));
    await tester.tap(find.widgetWithText(ListTile, 'Note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('person-notes')),
      'Met at a concert.',
    );
    await tester.ensureVisible(find.text('Save note'));
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();
    expect(saved!.notes, 'Met at a concert.');
    expect(
      find.text(
        'Notes and pins stay on this device. They are not included in the connection backup.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unavailable state hides contacts even if stale data was supplied',
    (tester) async {
      await pumpPeople(tester, available: false, selected: 'alice');
      expect(find.text('Alice'), findsNothing);
      expect(
        find.text('People is not available for this account'),
        findsNothing,
      );
      expect(find.text('Send money'), findsNothing);
    },
  );
}
