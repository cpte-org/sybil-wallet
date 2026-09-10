import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_exchange_screen.dart';

import '../../../figma_compare/figma_compare_font_loader.dart';

final contactTestNow = DateTime.utc(2026, 9, 10, 12);

Future<void> pumpContactExchange(
  WidgetTester tester,
  ContactExchangeState state, {
  ContactExchangeCallbacks callbacks = const ContactExchangeCallbacks(),
  Size? size,
  GlobalKey? captureKey,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize =
      size ?? Size(kAppFormFactor == AppFormFactor.mobile ? 390 : 1000, 2200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await loadFigmaCompareFonts();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) =>
          AppTheme(data: AppThemeData.dark, child: child!),
      home: RepaintBoundary(
        key: captureKey,
        child: Scaffold(
          backgroundColor: AppThemeData.dark.colors.background.ground,
          body: ContactExchangeView(
            state: state,
            callbacks: callbacks,
            now: () => contactTestNow,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

bool contactButtonEnabled(WidgetTester tester, String key) =>
    tester.widget<AppButton>(find.byKey(Key(key))).onPressed != null;

Future<void> tapContactControl(WidgetTester tester, String key) async {
  final control = find.byKey(Key(key));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pump();
}
