import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/legacy_material_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_code_widgets.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_identity_code.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_introduction_screen.dart';
import '../contact_introduction_test_fixtures.dart';
import '../contact_test_fakes.dart' show testIdentity;
import '../contact_test_fixtures.dart' show testContact;
import 'sybil_people_view_test.dart' show pumpPeople;

void main() {
  test(
    'connection codes retain full canonical identities, reject summaries',
    () {
      final identity = testIdentity(12);
      expect(readContactIdentityCode('  $identity\n'), identity);
      for (final invalid in [
        identity.substring(0, 20),
        '1234 5678',
        '{"identity":"$identity"}',
        '${identity}x',
      ]) {
        expect(() => readContactIdentityCode(invalid), throwsFormatException);
      }
    },
  );

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<IntroductionTestActor> guided(WidgetTester tester) async {
    final actor = IntroductionTestActor('guided-identity-check');
    await actor.peer('Alice', 11, 12, paired: false);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1500);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLegacyDarkTheme(),
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
        home: Scaffold(
          body: ContactIntroductionView(coordinator: actor.coordinator),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'Check a connection');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tap(tester, 'Alice');
    return actor;
  }

  testWidgets(
    'guided paste checks exact local key and still requires consent',
    (tester) async {
      final actor = await guided(tester);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': testIdentity(12)};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Scan code'), findsOneWidget);
      await tap(tester, 'Paste code');
      await tap(tester, 'Review details');
      expect(find.text(testIdentity(11)), findsOneWidget);
      expect(find.text(testIdentity(12)), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(
              find.widgetWithText(AppButton, 'Confirm pairing'),
            )
            .onPressed,
        isNull,
      );
      expect((await actor.coordinator.overview()).associations, isEmpty);
      await tap(tester, 'I independently checked both exact keys with Alice.');
      await tap(tester, 'Confirm pairing');
      final associations = (await actor.coordinator.overview()).associations;
      expect(associations.single.incomingIdentity, testIdentity(11));
      expect(associations.single.outgoingIdentity, testIdentity(12));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'replacing a scan clears review and unknown full key cannot pair',
    (tester) async {
      final actor = await guided(tester);
      await tester
          .widget<ContactCodeInput>(find.byType(ContactCodeInput))
          .onRead(testIdentity(12));
      await tester.pumpAndSettle();
      await tap(tester, 'Review details');
      await tap(tester, 'I independently checked both exact keys with Alice.');
      await tester
          .widget<ContactCodeInput>(find.byType(ContactCodeInput))
          .onRead(testIdentity(13));
      await tester.pumpAndSettle();
      expect(find.text('Confirm pairing'), findsNothing);
      await tap(tester, 'Review details');
      expect(find.text('Confirm pairing'), findsNothing);
      expect((await actor.coordinator.overview()).associations, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('People shows a full-identity QR in Check connection', (
    tester,
  ) async {
    final person = testContact();
    await pumpPeople(tester, people: [person], selected: person.id);
    await tap(tester, 'Check connection');
    final code = tester.widget<ContactCodeOutput>(
      find.byType(ContactCodeOutput),
    );
    expect(code.data, person.identity);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Copy code'), findsOneWidget);
    expect(find.textContaining('does not prove a person'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copyable verification code is the complete accepted identity', (
    tester,
  ) async {
    String? copied;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ContactIdentityCode(
              identity: testIdentity(11),
              personLabel: 'Alice',
              onCopy: (value) async => copied = value,
            ),
          ),
        ),
      ),
    );
    await tap(tester, 'Copy code');
    expect(copied, testIdentity(11));
  });
}
