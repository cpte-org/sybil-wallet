import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/zns/presentation/zns_screen.dart';
import 'package:zcash_wallet/zns_preview.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    ZnsViewData data, {
    ZnsCallbacks callbacks = const ZnsCallbacks(),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppTheme(data: AppThemeData.dark, child: child!),
        home: Scaffold(
          body: ZnsScreen(data: data, callbacks: callbacks),
        ),
      ),
    );
    await tester.pump();
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<AppButton>(find.byKey(Key(key))).onPressed != null;

  testWidgets(
    'multiple names select stable IDs and keep registration available',
    (tester) async {
      String? selected;
      await show(
        tester,
        ZnsPreviewFixtures.active,
        callbacks: ZnsCallbacks(onSelectName: (id) => selected = id),
      );
      await tester.tap(find.byKey(const Key('zns-select-9')));
      expect(selected, '9');
      expect(find.byKey(const Key('zns-name')), findsOneWidget);
    },
  );
  testWidgets(
    'received NFT has no payment address and clears the transfer recipient on selection change',
    (tester) async {
      await show(
        tester,
        ZnsPreviewFixtures.active,
        callbacks: ZnsCallbacks(onTransfer: (_) {}),
      );
      await tester.enterText(
        find.byKey(const Key('zns-transfer-recipient')),
        '0x3333333333333333333333333333333333333333',
      );
      await tester.pump();
      expect(enabled(tester, 'zns-transfer-review'), isTrue);
      await show(
        tester,
        ZnsPreviewFixtures.received,
        callbacks: ZnsCallbacks(onTransfer: (_) {}),
      );
      expect(enabled(tester, 'zns-transfer-review'), isFalse);
      expect(
        find.textContaining('cannot receive payments until'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'NFT transfer review requires explicit consent and discloses all attached funds',
    (tester) async {
      var calls = 0;
      await show(
        tester,
        ZnsPreviewFixtures.transfer,
        callbacks: ZnsCallbacks(onConfirmRegistration: () => calls++),
      );
      expect(enabled(tester, 'zns-confirm'), isFalse);
      expect(find.text('Deposit transferred'), findsOneWidget);
      expect(find.text('Unclaimed rewards transferred'), findsOneWidget);
      expect(
        find.textContaining('Maturity and refresh deadlines stay unchanged'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('zns-review-consent')));
      await tester.tap(find.byKey(const Key('zns-review-consent')));
      await tester.pump();
      expect(enabled(tester, 'zns-confirm'), isTrue);
      await tester.ensureVisible(find.byKey(const Key('zns-confirm')));
      await tester.tap(find.byKey(const Key('zns-confirm')));
      expect(calls, 1);
    },
  );

  testWidgets('unconfigured registry cannot request a lookup', (tester) async {
    var calls = 0;
    await show(
      tester,
      const ZnsViewData(),
      callbacks: ZnsCallbacks(onLookup: (_) => calls++),
    );
    await tester.enterText(find.byKey(const Key('zns-name')), 'river');
    await tester.pump();
    expect(enabled(tester, 'zns-lookup'), isFalse);
    expect(find.text('Name service is not configured'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('registration normalizes name and reviews one deposit', (
    tester,
  ) async {
    ZnsRegistrationInput? request;
    await show(
      tester,
      const ZnsViewData(
        isConfigured: true,
        walletUnifiedAddress: ZnsPreviewFixtures.address,
        lookup: ZnsLookupView(name: 'river', status: ZnsLookupStatus.available),
      ),
      callbacks: ZnsCallbacks(
        onLookup: (_) {},
        onPrepareRegistration: (value) => request = value,
      ),
    );
    await tester.enterText(find.byKey(const Key('zns-name')), 'River.zec');
    await tester.pump();
    expect(find.text('Registration period'), findsNothing);
    await tester.enterText(find.byKey(const Key('zns-budget')), '0');
    await tester.pump();
    expect(
      enabled(tester, 'zns-prepare'),
      isTrue,
      reason:
          'A funded Base account can request a review without new ZEC funding.',
    );
    await tester.enterText(find.byKey(const Key('zns-budget')), '0.12');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('zns-prepare')));
    await tester.tap(find.byKey(const Key('zns-prepare')));
    expect(request?.name, 'river');
    expect(request?.maxZec, '0.12');
    expect(find.textContaining('Earlier exit forfeits'), findsOneWidget);
  });

  testWidgets('hardware accounts can look up but cannot prepare registration', (
    tester,
  ) async {
    await show(
      tester,
      const ZnsViewData(
        isConfigured: true,
        isSoftwareAccount: false,
        walletUnifiedAddress: ZnsPreviewFixtures.address,
        lookup: ZnsLookupView(name: 'river', status: ZnsLookupStatus.available),
      ),
      callbacks: ZnsCallbacks(onLookup: (_) {}, onPrepareRegistration: (_) {}),
    );
    await tester.enterText(find.byKey(const Key('zns-name')), 'river');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('zns-budget')), '0.12');
    await tester.pump();
    expect(enabled(tester, 'zns-lookup'), isTrue);
    expect(enabled(tester, 'zns-prepare'), isFalse);
  });

  testWidgets('maturity and refresh clocks have separate labels', (
    tester,
  ) async {
    await show(
      tester,
      ZnsPreviewFixtures.active,
      callbacks: ZnsCallbacks(
        onRefreshName: () {},
        onClaimRewards: () {},
        onRelease: () {},
        onWithdrawClaims: () {},
      ),
    );
    expect(find.text('Original deposit maturity'), findsOneWidget);
    expect(find.text('Refresh due'), findsOneWidget);
    expect(find.text('Final grace deadline'), findsOneWidget);
    expect(enabled(tester, 'zns-refresh-name'), isTrue);
    expect(enabled(tester, 'zns-claim-rewards'), isFalse);
    expect(enabled(tester, 'zns-release-review'), isTrue);
    expect(enabled(tester, 'zns-withdraw-claims'), isTrue);
    expect(find.textContaining('keeps your current name'), findsOneWidget);
  });

  testWidgets(
    'old claims withdrawal is independent from current name release',
    (tester) async {
      var claims = 0, releases = 0;
      await show(
        tester,
        ZnsPreviewFixtures.active,
        callbacks: ZnsCallbacks(
          onWithdrawClaims: () => claims++,
          onRelease: () => releases++,
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('zns-withdraw-claims')));
      await tester.tap(find.byKey(const Key('zns-withdraw-claims')));
      expect(claims, 1);
      expect(releases, 0);
    },
  );

  testWidgets('release requires exact exit preview and explicit confirmation', (
    tester,
  ) async {
    const review = ZnsReviewView(
      name: 'river',
      unifiedAddress: '',
      deposit: '0.1',
      maxZec: '0',
      gasReserve: '0.0001',
      estimatedDuration: 'A few seconds',
      kind: ZnsReviewKind.release,
      canConfirm: true,
    );
    await show(
      tester,
      const ZnsViewData(isConfigured: true, review: review),
      callbacks: ZnsCallbacks(onConfirmRegistration: () {}),
    );
    await tester.ensureVisible(find.byKey(const Key('zns-review-consent')));
    await tester.tap(find.byKey(const Key('zns-review-consent')));
    await tester.pump();
    expect(
      enabled(tester, 'zns-confirm'),
      isFalse,
      reason: 'A missing exit preview must never approve a release.',
    );
  });

  testWidgets('early exit shows full forfeiture without refundable language', (
    tester,
  ) async {
    await show(tester, ZnsPreviewFixtures.earlyRelease);
    expect(
      find.text('Early exit forfeits your entire deposit'),
      findsOneWidget,
    );
    expect(find.text('Deposit forfeited'), findsOneWidget);
    expect(find.text('Unvested rewards forfeited'), findsOneWidget);
    expect(find.textContaining('Refundable bond'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'paused work is distinct from failure and survives without retry',
    (tester) async {
      await show(
        tester,
        ZnsPreviewFixtures.paused,
        callbacks: ZnsCallbacks(onResume: () {}),
      );
      expect(find.text('Paused'), findsWidgets);
      expect(find.text('Needs attention'), findsNothing);
      expect(find.text('Saved progress'), findsOneWidget);
      expect(enabled(tester, 'zns-resume'), isTrue);
    },
  );
}
