import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/widgets/base_key_export_dialog.dart';

void main() {
  Future<void> show(
    WidgetTester t,
    Future<Uint8List> Function(String) load, {
    String session = 'a',
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: BaseKeyExportDialog(
            session: session,
            owner: '0xPublicTestAccount',
            enabled: true,
            exportKey: load,
          ),
        ),
      ),
    );
  }

  Future<void> authenticate(WidgetTester t) async {
    await t.enterText(
      find.byKey(const Key('zns-export-password')),
      'test-password',
    );
    await t.tap(find.byKey(const Key('zns-export-authenticate')));
    await t.pump();
  }

  testWidgets('key loads only after authentication, stays hidden and expires', (
    t,
  ) async {
    final bytes = Uint8List.fromList(List.filled(32, 7));
    var calls = 0;
    await show(t, (password) async {
      calls++;
      expect(password, 'test-password');
      return bytes;
    });
    expect(calls, 0);
    await authenticate(t);
    expect(calls, 1);
    expect(find.byKey(const Key('zns-export-secret')), findsNothing);
    await t.tap(find.byKey(const Key('zns-export-reveal')));
    await t.pump();
    expect(find.byKey(const Key('zns-export-secret')), findsOneWidget);
    await t.pump(const Duration(minutes: 1));
    expect(find.byKey(const Key('zns-export-secret')), findsNothing);
    expect(bytes.every((b) => b == 0), isTrue);
  });
  testWidgets('account change discards an in-flight key export', (t) async {
    final pending = Completer<Uint8List>();
    final bytes = Uint8List.fromList(List.filled(32, 7));
    await show(t, (_) => pending.future);
    await authenticate(t);
    await show(t, (_) => pending.future, session: 'b');
    pending.complete(bytes);
    await t.pump();
    expect(find.byKey(const Key('zns-export-reveal')), findsNothing);
    expect(bytes.every((b) => b == 0), isTrue);
  });
  testWidgets('backgrounding clears the exported byte buffer', (t) async {
    final bytes = Uint8List.fromList(List.filled(32, 7));
    await show(t, (_) async => bytes);
    await authenticate(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    expect(bytes.every((b) => b == 0), isTrue);
    expect(find.byKey(const Key('zns-export-reveal')), findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('export errors never display raw exception content', (t) async {
    await show(t, (_) async => throw StateError('SENSITIVE_SENTINEL'));
    await authenticate(t);
    expect(find.textContaining('SENSITIVE_SENTINEL'), findsNothing);
    expect(find.textContaining('Could not export'), findsOneWidget);
  });
}
