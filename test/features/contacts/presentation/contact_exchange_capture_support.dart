import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

import '../../../figma_compare/figma_compare_font_loader.dart';
import 'contact_exchange_fixtures.dart';
import 'contact_exchange_test_support.dart';

void runContactExchangeLayoutTests({
  required AppFormFactor formFactor,
  required double width,
}) {
  final scenarios = <String, ContactExchangeState>{
    'unsupported': ContactExchangeFixtures.unavailable,
    'request': ContactExchangeState(
      available: true,
      request: ContactExchangeFixtures.request,
    ),
    'new-contact': ContactExchangeFixtures.newContact,
    'update-contact': ContactExchangeFixtures.updateContact,
    'share-consent': ContactExchangeFixtures.sharing,
    'suspended': ContactExchangeState(
      available: true,
      contacts: [ContactExchangeFixtures.suspendedAlice],
    ),
  };
  for (final scenario in scenarios.entries) {
    testWidgets(
      '${formFactor.name} ${scenario.key} stays within its viewport',
      (tester) async {
        expect(kAppFormFactor, formFactor);
        await loadFigmaCompareFonts();
        final capture = GlobalKey();
        await pumpContactExchange(
          tester,
          scenario.value,
          size: Size(width, 2200),
          captureKey: capture,
          advanced: false,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byKey(capture)).width, width);
        const output = String.fromEnvironment('CONTACT_CAPTURE_DIR');
        if (output.isNotEmpty) {
          await expectLater(
            find.byKey(capture),
            matchesGoldenFile(
              Uri.file('$output/${formFactor.name}-${scenario.key}.png'),
            ),
          );
        }
      },
    );
  }
}
