import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_base_endpoint_screen.dart';
import 'package:zcash_wallet/src/features/zns/presentation/zns_screen.dart';

const recommended = 'https://api.sybil.cash/api/base/rpc';
const custom = 'https://rpc.example/private-key?api_key=private-token';

ZnsViewData view({
  String rpc = custom,
  String account = 'account-1',
  String owner = '0x1111111111111111111111111111111111111111',
  bool busy = false,
  bool locked = false,
  String? error,
}) => ZnsViewData(
  accountId: account,
  baseOwnerAddress: owner,
  isConfigured: true,
  isBusy: busy,
  isLocked: locked,
  configuration: ZnsConfigurationInput(rpcUrl: rpc),
  error: error,
);

void main() {
  Future<void> show(
    WidgetTester tester,
    ZnsViewData data,
    Future<bool> Function(String) save,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppTheme(data: AppThemeData.dark, child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BaseRpcEndpointEditor(data: data, onSave: save),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  bool enabled(WidgetTester tester) =>
      tester
          .widget<AppButton>(find.byKey(const Key('base-rpc-save')))
          .onPressed !=
      null;

  test('compact endpoint labels exclude credentials, paths and query', () {
    expect(baseRpcEndpointLabel(custom), 'rpc.example');
    expect(
      baseRpcEndpointLabel('https://user:password@rpc.example/key'),
      'rpc.example',
    );
    expect(baseRpcEndpointLabel('invalid'), 'Not configured');
  });

  testWidgets('recommended update shows progress and survives owner reload', (
    tester,
  ) async {
    final pending = Completer<bool>();
    String? submitted;
    Future<bool> save(String url) {
      submitted = url;
      return pending.future;
    }

    await show(tester, view(error: 'Previous operation failed.'), save);
    expect(find.text('Previous operation failed.'), findsNothing);
    expect(find.text('Current: rpc.example'), findsOneWidget);
    expect(enabled(tester), isFalse);
    await tester.tap(find.byKey(const Key('base-rpc-recommended')));
    await tester.pump();
    expect(enabled(tester), isTrue);
    await tester.tap(find.byKey(const Key('base-rpc-save')));
    await tester.pump();
    expect(submitted, recommended);
    expect(find.text('Verifying endpoint…'), findsOneWidget);
    expect(enabled(tester), isFalse);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // The real controller clears and rederives Base owner during its reload.
    await show(tester, view(rpc: recommended, owner: '', busy: true), save);
    expect(find.text('Verifying endpoint…'), findsOneWidget);
    await show(tester, view(rpc: recommended), save);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('base-rpc-success')), findsOneWidget);
    expect(find.text('Current: api.sybil.cash'), findsOneWidget);
  });

  testWidgets('custom URL validates HTTPS and preserves path and query', (
    tester,
  ) async {
    String? submitted;
    await show(tester, view(rpc: recommended), (url) async {
      submitted = url;
      return false;
    });
    await tester.tap(find.byKey(const Key('base-rpc-custom')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('base-rpc-url')),
      'http://rpc.example',
    );
    await tester.pump();
    expect(enabled(tester), isFalse);
    expect(find.textContaining('Enter an HTTPS RPC URL'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('base-rpc-url')),
      '  $custom  ',
    );
    await tester.pump();
    expect(enabled(tester), isTrue);
    await tester.tap(find.byKey(const Key('base-rpc-save')));
    await tester.pumpAndSettle();
    expect(submitted, custom);
    expect(find.byKey(const Key('base-rpc-error')), findsOneWidget);
    expect(find.byKey(const Key('base-rpc-success')), findsNothing);
    expect(find.text('Current: api.sybil.cash'), findsOneWidget);
  });

  testWidgets(
    'failed verification displays its error and keeps the selected URL',
    (tester) async {
      final pending = Completer<bool>();
      Future<bool> save(String url) => pending.future;
      await show(tester, view(), save);
      await tester.tap(find.byKey(const Key('base-rpc-recommended')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('base-rpc-save')));
      await tester.pump();
      await show(
        tester,
        view(error: 'The RPC network does not match this deployment.'),
        save,
      );
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(
        find.text('The RPC network does not match this deployment.'),
        findsOneWidget,
      );
      expect(find.text('Current: rpc.example'), findsOneWidget);
      expect(enabled(tester), isTrue);
    },
  );

  testWidgets('account change and lock discard a late success', (tester) async {
    final pending = Completer<bool>();
    Future<bool> save(String url) => pending.future;
    await show(tester, view(), save);
    await tester.tap(find.byKey(const Key('base-rpc-recommended')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('base-rpc-save')));
    await tester.pump();
    await show(tester, view(account: 'account-2', locked: true), save);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('base-rpc-success')), findsNothing);
    expect(enabled(tester), isFalse);
    expect(
      find.text('Unlock your wallet to change this connection.'),
      findsOneWidget,
    );
  });
}
