import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_exchange_controller.dart';
import 'package:zcash_wallet/src/features/home/widgets/sybil_home_dashboard.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';

Future<void> pumpDashboard(
  WidgetTester tester,
  SyncState sync, {
  bool hidden = false,
  bool ironwoodOnly = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [contactScopeProvider.overrideWithValue(null)],
      child: MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Scaffold(
            body: SybilHomeDashboard(
              sync: sync,
              ironwoodOnly: ironwoodOnly,
              privacyModeEnabled: hidden,
              activityRows: const [],
              isActivityLoading: false,
              onSend: () {},
              onReceive: () {},
              onActivity: () {},
              onTogglePrivacyMode: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String? headline(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('sybil_available_balance')))
    .data;

void main() {
  testWidgets(
    'sync status sits above the amount and hidden tools stay absent',
    (tester) async {
      await pumpDashboard(
        tester,
        SyncState(
          hasBalanceData: true,
          isSyncComplete: true,
          scannedHeight: 100,
          chainTipHeight: 100,
        ),
      );
      expect(find.text('Synced'), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('sybil_balance_sync')))
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('sybil_available_balance')),
              )
              .dy,
        ),
      );
      for (final label in [
        'Swap',
        'Swap and Pay',
        'Coinholder voting',
        'Public discovery',
        'Public Zcash names',
      ]) {
        expect(find.text(label), findsNothing);
      }
    },
  );

  testWidgets(
    'idle or partial state never claims synced from percentage alone',
    (tester) async {
      await pumpDashboard(tester, SyncState(percentage: 1));
      expect(find.text('Waiting to sync'), findsOneWidget);
      expect(find.text('Synced'), findsNothing);
      await pumpDashboard(tester, SyncState(isSyncing: true, percentage: 1));
      expect(find.text('Syncing · 99%'), findsOneWidget);
    },
  );

  testWidgets('Tor connection failures override previously synced state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Scaffold(
            body: SybilBalanceSyncStatus(
              sync: SyncState(
                isSyncComplete: true,
                scannedHeight: 100,
                chainTipHeight: 100,
              ),
              networkPrivacy: const NetworkPrivacyState(
                torEnabled: true,
                status: NetworkPrivacyConnectionStatus.failed,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Sync needs attention'), findsOneWidget);
    expect(find.text('Synced'), findsNothing);
  });

  testWidgets('available funds exclude pending, locked and transparent funds', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      SyncState(
        hasBalanceData: true,
        // A loaded balance need not wait for activity history to load.
        hasRecentTransactionsData: false,
        spendableBalance: BigInt.from(125000000),
        orchardPendingBalance: BigInt.from(200000000),
        orchardLockedBalance: BigInt.from(300000000),
        transparentBalance: BigInt.from(400000000),
        totalBalance: BigInt.from(1025000000),
      ),
    );
    expect(headline(tester), '1.25 ZEC');
    expect(find.text('2 ZEC awaiting confirmations'), findsOneWidget);
    await tester.tap(find.text('Balance details'));
    await tester.pumpAndSettle();
    expect(find.text('10.25 ZEC'), findsOneWidget);
    expect(find.text('Locked Orchard funds'), findsOneWidget);
    expect(find.text('3 ZEC'), findsOneWidget);
    expect(find.text('4 ZEC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('last completed balance never mixes in a partial breakdown', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      SyncState(
        hasAccountScopedData: true,
        isSyncing: true,
        spendableBalance: BigInt.from(700000000),
        displaySpendableBalance: BigInt.from(125000000),
        displayTotalBalance: BigInt.from(325000000),
        displaySpendableFreshness: SpendableBalanceFreshness.lastCompletedSync,
        orchardPendingBalance: BigInt.from(900000000),
      ),
    );
    expect(headline(tester), '1.25 ZEC');
    expect(find.text('Last available balance'), findsOneWidget);
    expect(find.text('9 ZEC awaiting confirmations'), findsNothing);
    await tester.tap(find.text('Balance details'));
    await tester.pumpAndSettle();
    expect(find.text('3.25 ZEC'), findsOneWidget);
    expect(find.text('The breakdown updates after syncing.'), findsOneWidget);
    expect(find.text('Awaiting confirmations'), findsNothing);
  });

  testWidgets('unloaded account data does not display placeholder balances', (
    tester,
  ) async {
    await pumpDashboard(tester, SyncState());
    expect(headline(tester), 'Loading…');
    expect(find.text('0 ZEC awaiting confirmations'), findsNothing);
    expect(find.text('Balance details'), findsNothing);
  });

  testWidgets(
    'privacy mode masks the headline, pending and expanded balances',
    (tester) async {
      await pumpDashboard(
        tester,
        SyncState(
          hasAccountScopedData: true,
          spendableBalance: BigInt.from(125000000),
          totalBalance: BigInt.from(325000000),
          orchardPendingBalance: BigInt.from(200000000),
        ),
        hidden: true,
      );
      expect(headline(tester), '****** ZEC');
      await tester.tap(find.text('Balance details'));
      await tester.pumpAndSettle();
      expect(find.text('****** ZEC awaiting confirmations'), findsOneWidget);
      expect(find.text('1.25 ZEC'), findsNothing);
      expect(find.text('2 ZEC'), findsNothing);
      expect(find.text('3.25 ZEC'), findsNothing);
    },
  );

  testWidgets(
    'completed migration keeps available balance limited to Ironwood',
    (tester) async {
      await pumpDashboard(
        tester,
        SyncState(
          hasAccountScopedData: true,
          displayIronwoodBalance: BigInt.from(125000000),
          displaySpendableBalance: BigInt.from(135000000),
        ),
        ironwoodOnly: true,
      );
      expect(headline(tester), '1.25 ZEC');
      expect(find.text('Yours to spend (Ironwood)'), findsOneWidget);
    },
  );
}
