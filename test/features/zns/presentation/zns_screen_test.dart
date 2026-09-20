import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/zns/presentation/zns_screen.dart';
import 'package:zcash_wallet/zns_preview.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    ZnsViewData data, {
    ZnsCallbacks callbacks = const ZnsCallbacks(),
    double height = 2000,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(1000, height);
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

  testWidgets('initial and manual refresh work has visible feedback', (
    tester,
  ) async {
    await show(
      tester,
      const ZnsViewData(isConfigured: true, isBusy: true),
      callbacks: ZnsCallbacks(onRefresh: () async {}, onLookup: (_) {}),
    );
    expect(find.text('Checking name service…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    if (kAppFormFactor == AppFormFactor.desktop) {
      expect(enabled(tester, 'zns-refresh-balances'), isFalse);
    }
  });

  testWidgets(
    'registration preparation shows progress then brings retry failure into view',
    (tester) async {
      const rateLimitError = 'The name service is busy. Try again shortly.';
      const available = ZnsLookupView(
        name: 'river',
        status: ZnsLookupStatus.available,
      );
      const ready = ZnsViewData(
        isConfigured: true,
        walletUnifiedAddress: ZnsPreviewFixtures.address,
        lookup: available,
        error: rateLimitError,
      );
      var reviewCalls = 0;
      final callbacks = ZnsCallbacks(
        onPrepareRegistration: (_) => reviewCalls++,
      );
      await show(tester, ready, callbacks: callbacks, height: 600);
      await tester.enterText(find.byKey(const Key('zns-name')), 'river');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('zns-prepare')));
      await tester.tap(find.byKey(const Key('zns-prepare')));
      expect(reviewCalls, 1);
      await show(
        tester,
        const ZnsViewData(
          isConfigured: true,
          walletUnifiedAddress: ZnsPreviewFixtures.address,
          lookup: available,
          error: rateLimitError,
          isBusy: true,
          isPreparingRegistration: true,
        ),
        callbacks: callbacks,
        height: 600,
      );
      expect(find.text('Preparing review…'), findsOneWidget);
      expect(enabled(tester, 'zns-prepare'), isFalse);
      expect(
        find.descendant(
          of: find.byKey(const Key('zns-prepare')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      // Even the same repeated failure must become visible after a retry.
      await show(tester, ready, callbacks: callbacks, height: 600);
      await tester.pumpAndSettle();
      final errorRect = tester.getRect(find.text(rateLimitError));
      expect(errorRect.top, greaterThanOrEqualTo(0));
      expect(errorRect.bottom, lessThanOrEqualTo(600));
      expect(enabled(tester, 'zns-prepare'), isTrue);
      expect(find.text('Preparing review…'), findsNothing);
    },
  );

  testWidgets(
    'registration review distinguishes the USD minimum floor from extra',
    (tester) async {
      await show(
        tester,
        const ZnsViewData(
          isConfigured: true,
          review: ZnsReviewView(
            name: 'alice',
            unifiedAddress: 'u1synthetic',
            maxZec: '0.01',
            deposit: '0.003',
            gasReserve: '0.0001',
            estimatedDuration: 'A few minutes',
            usdTarget: '100',
            pricingMode: 0,
            minimumDeposit: '0.001',
            extraDeposit: '0.002',
            minimumFloorApplies: true,
          ),
        ),
      );
      expect(find.text('USD pricing · minimum bond floor'), findsOneWidget);
      expect(
        find.textContaining('Its USD value may exceed the target.'),
        findsOneWidget,
      );
      expect(find.text('0.001 cbZEC'), findsOneWidget);
      expect(find.text('0.002 cbZEC'), findsOneWidget);
      expect(find.text('0.003 cbZEC'), findsOneWidget);
      expect(find.text('USD oracle quote'), findsNothing);
    },
  );

  testWidgets(
    'custom receiving address is passed to review and cleared on name change',
    (tester) async {
      String? reviewed;
      final callbacks = ZnsCallbacks(
        onUpdateAddress: (address) => reviewed = address,
      );
      await show(tester, ZnsPreviewFixtures.active, callbacks: callbacks);
      await tester.ensureVisible(find.byKey(const Key('zns-edit-address')));
      await tester.tap(find.byKey(const Key('zns-edit-address')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('zns-receiving-address')),
        '  u1custom-recipient  ',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('zns-review-address')));
      await tester.tap(find.byKey(const Key('zns-review-address')));
      expect(reviewed, 'u1custom-recipient');
      await show(tester, ZnsPreviewFixtures.received, callbacks: callbacks);
      expect(find.byKey(const Key('zns-receiving-address')), findsNothing);
      expect(find.text('Set payment address'), findsOneWidget);
    },
  );

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
    expect(find.byKey(const Key('zns-settings')), findsNothing);
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
    await tester.pump();
    expect(
      enabled(tester, 'zns-prepare'),
      isTrue,
      reason:
          'A funded Base account can request a review without new ZEC funding.',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('zns-prepare')));
    await tester.tap(find.byKey(const Key('zns-prepare')));
    expect(request?.name, 'river');
    expect(find.byKey(const Key('zns-budget')), findsNothing);
    expect(find.textContaining('early-exit fee starts at 10%'), findsOneWidget);
    expect(request?.extraDeposit, '0');
    expect(find.byKey(const Key('zns-extra-deposit')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('zns-extra-toggle')));
    await tester.tap(find.byKey(const Key('zns-extra-toggle')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('zns-extra-deposit')), '0.25');
    await tester.ensureVisible(find.byKey(const Key('zns-prepare')));
    await tester.tap(find.byKey(const Key('zns-prepare')));
    expect(request?.extraDeposit, '0.25');
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

  testWidgets(
    'early exit shows the fee, returned principal and forfeited rewards',
    (tester) async {
      await show(tester, ZnsPreviewFixtures.earlyRelease);
      expect(find.text('Early release fee: 10%'), findsOneWidget);
      expect(find.text('Early-release fee'), findsOneWidget);
      expect(find.text('Unvested rewards forfeited'), findsOneWidget);
      expect(find.textContaining('Refundable bond'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
