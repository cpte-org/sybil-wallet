import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/zns/presentation/zns_screen.dart';
import 'package:zcash_wallet/zns_preview.dart';

import '../../../figma_compare/figma_compare_font_loader.dart';

void runZnsLayoutTests({
  required AppFormFactor formFactor,
  required double width,
}) {
  for (final scenario in <String, ZnsViewData>{
    'active': ZnsPreviewFixtures.active,
    'review': ZnsPreviewFixtures.registration,
    'early-release': ZnsPreviewFixtures.earlyRelease,
    'transfer': ZnsPreviewFixtures.transfer,
    'received': ZnsPreviewFixtures.received,
    'paused': ZnsPreviewFixtures.paused,
  }.entries) {
    testWidgets('${formFactor.name} ${scenario.key} has no layout overflow', (
      tester,
    ) async {
      expect(kAppFormFactor, formFactor);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 2200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await loadFigmaCompareFonts();
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
          home: RepaintBoundary(
            key: capture,
            child: Scaffold(
              backgroundColor: AppThemeData.dark.colors.background.ground,
              body: ZnsScreen(
                data: scenario.value,
                callbacks: const ZnsCallbacks(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      const output = String.fromEnvironment('ZNS_CAPTURE_DIR');
      if (output.isNotEmpty) {
        await expectLater(
          find.byKey(capture),
          matchesGoldenFile(
            Uri.file('$output/${formFactor.name}-${scenario.key}.png'),
          ),
        );
      }
    });
  }
}
