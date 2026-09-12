import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/legacy_material_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_introduction_screen.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_code_widgets.dart';
import '../contact_introduction_test_fixtures.dart';
import '../contact_test_fakes.dart';
import '../../../figma_compare/figma_compare_font_loader.dart';

void introductionWidgetTests(AppFormFactor formFactor) {
  Future<void> pump(
    WidgetTester tester,
    IntroductionTestActor actor, {
    GlobalKey? capture,
    bool advanced = true,
    List<String>? copies,
    double height = 1500,
    Future<void> Function()? onAccepted,
    Future<void> Function(String)? onCopy,
    Widget Function(Future<void> Function(String))? inboxBuilder,
  }) async {
    expect(kAppFormFactor, formFactor);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(
      formFactor == AppFormFactor.mobile ? 390 : 1000,
      height,
    );
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await loadFigmaCompareFonts();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLegacyDarkTheme(),
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
        home: RepaintBoundary(
          key: capture,
          child: Scaffold(
            body: SafeArea(
              child: ContactIntroductionView(
                coordinator: actor.coordinator,
                advanced: advanced,
                onConnect: () {},
                onSettings: () {},
                inboxBuilder: inboxBuilder,
                onAccepted: onAccepted,
                onCopy: (packet) async {
                  copies?.add(packet);
                  await onCopy?.call(packet);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label).last;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> step(WidgetTester tester, IntroductionTask task) async {
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<IntroductionTask>),
    );
    await tester.tap(find.byType(DropdownButtonFormField<IntroductionTask>));
    await tester.pumpAndSettle();
    await tap(tester, task.label);
  }

  Future<void> peer(WidgetTester tester, String name) async {
    final finder = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tap(tester, name);
  }

  Future<void> input(WidgetTester tester, int index, String value) async {
    final finder = find.byType(TextField).at(index);
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pump();
  }

  bool enabled(WidgetTester tester, String label) =>
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, label))
          .onPressed !=
      null;
  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    expect(tester.takeException(), isNull);
    const dir = String.fromEnvironment('CONTACT_CAPTURE_DIR');
    if (dir.isNotEmpty) {
      await expectLater(
        find.byKey(key),
        matchesGoldenFile(
          Uri.file('$dir/${formFactor.name}-introduction-$name.png'),
        ),
      );
    }
  }

  testWidgets(
    'normal introductions hide technical pairing and explain the prerequisite',
    (tester) async {
      final actor = IntroductionTestActor('guided-empty');
      await actor.peer('Alice', 11, 12, paired: false);
      final key = GlobalKey();
      await pump(tester, actor, advanced: false, capture: key, height: 844);
      await capture(tester, key, 'guided-overview');
      expect(find.text('Connect before introducing'), findsOneWidget);
      expect(
        find.byType(DropdownButtonFormField<IntroductionTask>),
        findsNothing,
      );
      expect(
        find.text('Your outgoing key accepted by this peer'),
        findsNothing,
      );
      expect(find.widgetWithText(ListTile, 'Ask someone I know'), findsNothing);
      expect(
        find.widgetWithText(ListTile, 'Introduce two people'),
        findsNothing,
      );
      await tap(tester, 'Open an invitation');
      expect(find.byType(ContactCodeInput), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'normal invitation import chooses its stage without accepting or signing',
    (tester) async {
      final ceremony = IntroductionTestCeremony();
      await ceremony.throughOffer();
      await pump(tester, ceremony.bob, advanced: false);
      await tap(tester, 'Open an invitation');
      await tester
          .widget<ContactCodeInput>(find.byType(ContactCodeInput))
          .onRead('["zcash-contact/intro-offer-package",null,null]');
      await tester.pumpAndSettle();
      expect(find.text('Review your introduction'), findsOneWidget);
      expect(find.text('Invitation ready to review'), findsOneWidget);
      expect(
        find.byType(DropdownButtonFormField<IntroductionTask>),
        findsNothing,
      );
      expect(find.text('Approve and continue'), findsNothing);
      await peer(tester, 'Alice');
      await tap(tester, 'Review details');
      expect(find.text('Approve and continue'), findsNothing);
      expect(
        find.text(
          'Could not complete this introduction. Review the details and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('New recipient identity'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('guided request shows a share code only after approval', (
    tester,
  ) async {
    final ceremony = IntroductionTestCeremony();
    await ceremony.setup();
    await pump(tester, ceremony.carol, advanced: false);
    await tap(tester, 'Ask someone I know');
    await peer(tester, 'Alice');
    expect(enabled(tester, 'Approve and continue'), isFalse);
    expect(find.byType(ContactCodeOutput), findsNothing);
    await tap(tester, 'I authorize Alice to arrange this introduction.');
    await tap(tester, 'Approve and continue');
    expect(find.byType(ContactCodeOutput), findsOneWidget);
    expect(find.text('Copy packet'), findsNothing);
    expect(
      find.byType(DropdownButtonFormField<IntroductionTask>),
      findsNothing,
    );
    expect(ceremony.carol.wire.signatures, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'inbox response fills the pending introduction without accepting it',
    (tester) async {
      final ceremony = IntroductionTestCeremony();
      await ceremony.throughDelivery();
      final review = await ceremony.carol.coordinator.reviewDelivery(
        ceremony.delivery,
      );
      await ceremony.carol.prepareFreshCheck(review);
      late Future<void> Function(String) importPacket;
      await pump(
        tester,
        ceremony.carol,
        inboxBuilder: (selected) {
          importPacket = selected;
          return const SizedBox();
        },
      );
      const response = '["zcash-contact/exchange",null,null]';
      await importPacket(response);
      await tester.pump();
      final texts = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .map((w) => w.controller.text);
      expect(texts, contains(ceremony.delivery));
      // The response is retained for a fresh review; it is not trusted on import.
      expect((await ceremony.carol.book()).contacts, hasLength(1));
      expect(find.text('Accept contact'), findsNothing);
      await tap(tester, 'Review details');
      expect(
        tester
            .widgetList<EditableText>(find.byType(EditableText))
            .map((w) => w.controller.text),
        contains(response),
      );
      expect(enabled(tester, 'Accept contact'), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'request and offer selectors publish only after both UI approvals',
    (tester) async {
      final ceremony = IntroductionTestCeremony();
      await ceremony.setup();
      final copies = <String>[];
      await pump(tester, ceremony.carol, copies: copies, height: 844);
      await step(tester, IntroductionTask.request);
      await peer(tester, 'Alice');
      expect(enabled(tester, 'Approve and create packet'), isFalse);
      await tap(tester, 'I authorize Alice to arrange this introduction.');
      await tap(tester, 'Approve and create packet');
      await tap(tester, 'Copy packet');
      expect(copies, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await pump(tester, ceremony.alice, copies: copies, height: 844);
      await step(tester, IntroductionTask.offer);
      await peer(tester, 'Carol');
      final subject = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(subject);
      await tester.tap(subject);
      await tester.pumpAndSettle();
      await tap(tester, 'Bob');
      // Empty suggestion proves private labels are not prefilled.
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await input(tester, 0, 'Public Carol');
      await input(tester, 1, copies.first);
      tester.view.resetViewInsets();
      await tester.pump();
      await tap(tester, 'Review details');
      expect(enabled(tester, 'Approve and create packet'), isFalse);
      await tap(
        tester,
        'I approve asking Bob to be introduced to Carol using this shareable suggestion.',
      );
      await tap(tester, 'Approve and create packet');
      await tap(tester, 'Copy packet');
      expect(copies, hasLength(2));
      final verified = await ceremony.bob.coordinator.reviewOffer(
        'Alice',
        copies.last,
      );
      expect(verified.suggestion, 'Public Carol');
      ceremony.bob.coordinator.pauseReview();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'request selected contact suspension clears selection without a build failure',
    (tester) async {
      final ceremony = IntroductionTestCeremony();
      await ceremony.setup();
      await pump(tester, ceremony.carol);
      await step(tester, IntroductionTask.request);
      await peer(tester, 'Alice');
      await ceremony.carol.suspend('Alice');
      await tester.pumpAndSettle();
      expect(find.text('Selected introducer key'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'copy refuses a packet after expiry even before its UI timer runs',
    (tester) async {
      final ceremony = IntroductionTestCeremony();
      await ceremony.setup();
      final copies = <String>[];
      await pump(tester, ceremony.carol, copies: copies);
      await step(tester, IntroductionTask.request);
      await peer(tester, 'Alice');
      await tap(tester, 'I authorize Alice to arrange this introduction.');
      await tap(tester, 'Approve and create packet');
      ceremony.carol.now = ceremony.carol.now.add(const Duration(minutes: 16));
      await tap(tester, 'Copy packet');
      expect(copies, isEmpty);
      expect(find.text('Copy packet'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'book change while busy reloads peers after the pending action finishes',
    (tester) async {
      final ceremony = IntroductionTestCeremony();
      await ceremony.setup();
      await ceremony.carol.peer('Other', 31, 32);
      final gate = Completer<void>();
      await pump(tester, ceremony.carol, onCopy: (_) => gate.future);
      await step(tester, IntroductionTask.request);
      await peer(tester, 'Alice');
      await tap(tester, 'I authorize Alice to arrange this introduction.');
      await tap(tester, 'Approve and create packet');
      await tester.ensureVisible(find.text('Copy packet'));
      await tester.tap(find.text('Copy packet'));
      await tester.pump();
      await ceremony.carol.suspend('Alice');
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      await peer(tester, 'Other');
      expect(
        find.text('I authorize Other to arrange this introduction.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pairing shows both exact keys and editing clears independent consent',
    (tester) async {
      final actor = IntroductionTestActor('pair-ui');
      await actor.peer('Alice', 11, 12, paired: false);
      final key = GlobalKey();
      await pump(tester, actor, capture: key);
      await peer(tester, 'Alice');
      await input(tester, 0, testIdentity(12));
      await tap(tester, 'Review details');
      expect(find.text(testIdentity(11)), findsOneWidget);
      expect(find.text(testIdentity(12)), findsWidgets);
      expect(enabled(tester, 'Confirm pairing'), isFalse);
      await capture(tester, key, 'pairing');
      await tap(tester, 'I independently checked both exact keys with Alice.');
      expect(enabled(tester, 'Confirm pairing'), isTrue);
      await input(tester, 0, testIdentity(13));
      expect(find.text('Confirm pairing'), findsNothing);
      expect((await actor.coordinator.overview()).associations, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Bob approves fresh details and re-export uses same saved identity', (
    tester,
  ) async {
    final ceremony = IntroductionTestCeremony();
    await ceremony.throughOffer();
    final key = GlobalKey(), copies = <String>[];
    await pump(tester, ceremony.bob, capture: key, copies: copies);
    await step(tester, IntroductionTask.consent);
    await peer(tester, 'Alice');
    await input(tester, 0, ceremony.offer);
    await tap(tester, 'Review details');
    expect(find.text('New recipient identity'), findsOneWidget);
    expect(
      find.text('New receiving address (visible to the introducer)'),
      findsOneWidget,
    );
    expect(enabled(tester, 'Approve and create packet'), isFalse);
    await capture(tester, key, 'bob-review');
    await tap(
      tester,
      'I approve sharing this fresh identity and address through Alice with the person Alice describes as “Carol”.',
    );
    await tap(tester, 'Approve and create packet');
    await tap(tester, 'Copy packet');
    expect(copies.length, 1);
    final allocations = ceremony.bob.direct.identityCreates;
    await tap(tester, 'Review details');
    expect(
      find.text(
        'Review to resend the same saved packet. No new identity or signature is created.',
      ),
      findsOneWidget,
    );
    await tap(
      tester,
      'I approve sharing this fresh identity and address through Alice with the person Alice describes as “Carol”.',
    );
    await tap(tester, 'Approve and create packet');
    await tap(tester, 'Copy packet');
    expect(copies.last, copies.first);
    expect(ceremony.bob.direct.identityCreates, allocations);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Carol chooses local label and explicitly accepts attributed provenance',
    (tester) async {
      final ceremony = IntroductionTestCeremony();
      await ceremony.throughDelivery();
      final key = GlobalKey();
      var acceptedCalls = 0;
      await pump(
        tester,
        ceremony.carol,
        capture: key,
        onAccepted: () async {
          acceptedCalls++;
        },
      );
      await step(tester, IntroductionTask.accept);
      await input(tester, 0, ceremony.delivery);
      await tap(tester, 'Review details');
      expect(find.text(ceremony.carol.current!.network), findsNothing);
      expect(enabled(tester, 'Accept contact'), isFalse);
      final addressReview = await ceremony.carol.coordinator.reviewDelivery(
        ceremony.delivery,
      );
      ceremony.carol.configureFreshResponse(addressReview);
      // Rebuild the UI's identical coordinator review before requesting a check.
      await tap(tester, 'Review details');
      await tap(tester, 'Create fresh address check');
      await input(tester, 1, 'fake-fresh-response');
      await input(tester, 2, 'My Bob');
      await tap(
        tester,
        'I accept these exact details based on Alice’s claim that this is Bob.',
      );
      await input(tester, 2, 'Private Bob');
      expect(enabled(tester, 'Accept contact'), isFalse);
      await capture(tester, key, 'carol-review');
      await tap(
        tester,
        'I accept these exact details based on Alice’s claim that this is Bob.',
      );
      await tap(tester, 'Accept contact');
      final view = await ceremony.carol.coordinator.overview();
      expect(view.contacts.any((c) => c.label == 'Private Bob'), isTrue);
      expect(view.provenance, hasLength(1));
      expect(acceptedCalls, 1);
      expect(
        find.textContaining('Historical introduction for Private Bob'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'background and book mutation discard displayed review and consent',
    (tester) async {
      final ceremony = IntroductionTestCeremony();
      await ceremony.throughOffer();
      await pump(tester, ceremony.bob);
      await step(tester, IntroductionTask.consent);
      await peer(tester, 'Alice');
      await input(tester, 0, ceremony.offer);
      await tap(tester, 'Review details');
      await tap(
        tester,
        'I approve sharing this fresh identity and address through Alice with the person Alice describes as “Carol”.',
      );
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(find.text('Approve and create packet'), findsNothing);
      await input(tester, 0, ceremony.offer);
      await tap(tester, 'Review details');
      await ceremony.bob.suspend('Alice');
      await tester.pump();
      expect(find.text('Approve and create packet'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Alice endorsement exposes exact fresh endpoint and requires separate approval',
    (tester) async {
      final ceremony = IntroductionTestCeremony();
      await ceremony.throughConsent();
      final key = GlobalKey();
      await pump(tester, ceremony.alice, capture: key);
      await step(tester, IntroductionTask.endorse);
      await input(tester, 0, 'Public Bob');
      await input(tester, 1, ceremony.consent);
      await tap(tester, 'Review details');
      expect(enabled(tester, 'Approve and create packet'), isFalse);
      await capture(tester, key, 'alice-review');
      await input(tester, 0, 'Changed Bob');
      expect(find.text('Approve and create packet'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
