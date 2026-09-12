import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_code_widgets.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_exchange_screen.dart';

import 'contact_exchange_fixtures.dart';
import 'contact_exchange_test_support.dart';

void main() {
  Future<void> codeWidget(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(width: 380, child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'normal exchange offers guided codes without technical controls',
    (tester) async {
      await pumpContactExchange(
        tester,
        const ContactExchangeState(available: true),
        advanced: false,
      );
      expect(find.text('Show invitation'), findsOneWidget);
      expect(find.text('Scan code'), findsOneWidget);
      expect(find.text('Paste code'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Introductions and reciprocal setup'), findsNothing);
      expect(find.text('Full contact identity'), findsNothing);
    },
  );
  testWidgets('request shows QR by default and keeps exact copied packet', (
    tester,
  ) async {
    String? copied;
    await pumpContactExchange(
      tester,
      ContactExchangeState(
        available: true,
        request: ContactExchangeFixtures.request,
      ),
      advanced: false,
      callbacks: ContactExchangeCallbacks(
        onCopy: (code, _) async => copied = code,
      ),
    );
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text(ContactExchangeFixtures.requestJson), findsNothing);
    await tester.tap(find.text('Copy code'));
    await tester.pump();
    expect(copied, ContactExchangeFixtures.requestJson);
    expect(find.text('Have their reply?'), findsOneWidget);
  });
  testWidgets('guided acceptance still requires a name and explicit checking', (
    tester,
  ) async {
    String? name;
    bool? checked;
    await pumpContactExchange(
      tester,
      ContactExchangeFixtures.newContact,
      advanced: false,
      callbacks: ContactExchangeCallbacks(
        onAcceptResponse:
            ({required label, required independentlyVerified}) async {
              name = label;
              checked = independentlyVerified;
            },
      ),
    );
    expect(contactButtonEnabled(tester, 'contacts-accept-response'), isFalse);
    await tester.enterText(find.byKey(const Key('contacts-label')), 'Mara');
    await tester.pump();
    expect(contactButtonEnabled(tester, 'contacts-accept-response'), isFalse);
    await tapContactControl(tester, 'contacts-verify-acceptance');
    await tapContactControl(tester, 'contacts-accept-response');
    expect(name, 'Mara');
    expect(checked, isTrue);
  });
  testWidgets('guided sharing never creates a reply before consent', (
    tester,
  ) async {
    var calls = 0;
    await pumpContactExchange(
      tester,
      ContactExchangeFixtures.sharing,
      advanced: false,
      callbacks: ContactExchangeCallbacks(
        onConfirmShare: ({required consent}) async {
          expect(consent, isTrue);
          calls++;
        },
      ),
    );
    expect(contactButtonEnabled(tester, 'contacts-confirm-share'), isFalse);
    await tapContactControl(tester, 'contacts-share-consent');
    expect(contactButtonEnabled(tester, 'contacts-confirm-share'), isTrue);
    await tapContactControl(tester, 'contacts-confirm-share');
    expect(calls, 1);
  });
  testWidgets(
    'oversize QR has usable copying fallback without rendering failure',
    (tester) async {
      final packet = 'x' * 4000;
      String? copied;
      await codeWidget(
        tester,
        ContactCodeOutput(
          data: packet,
          onCopy: (value) async => copied = value,
        ),
      );
      expect(find.byType(QrImageView), findsNothing);
      expect(find.textContaining('too large for one QR'), findsOneWidget);
      await tester.tap(find.text('Copy code'));
      await tester.pump();
      expect(copied, packet);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('inactive code is neither displayed nor copyable', (
    tester,
  ) async {
    await codeWidget(
      tester,
      const ContactCodeOutput(
        data: 'private-code',
        enabled: false,
        advanced: true,
      ),
    );
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('private-code'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
  });
  testWidgets('paste is explicit, bounded and does not need manual editor', (
    tester,
  ) async {
    String clipboard = '  exact invitation  ';
    String? opened;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': clipboard} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await codeWidget(
      tester,
      ContactCodeInput(onRead: (code) async => opened = code),
    );
    expect(opened, isNull);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Paste code'));
    await tester.pump();
    expect(opened, 'exact invitation');
    clipboard = 'x' * (contactCodeByteLimit + 1);
    opened = null;
    await tester.tap(find.text('Paste code'));
    await tester.pump();
    expect(opened, isNull);
    expect(find.textContaining('too large'), findsOneWidget);
  });
  testWidgets('advanced code editor is opt in', (tester) async {
    await codeWidget(
      tester,
      ContactCodeInput(advanced: true, onRead: (_) async {}),
    );
    await tester.tap(find.text('Enter code manually'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('guided storage error offers a working retry', (tester) async {
    var reloads = 0;
    await pumpContactExchange(
      tester,
      const ContactExchangeState(
        available: true,
        error: 'Could not load contacts.',
      ),
      advanced: false,
      callbacks: ContactExchangeCallbacks(onReload: () async => reloads++),
    );
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(reloads, 1);
  });

  testWidgets('backgrounding cancels a code waiting to open a review', (
    tester,
  ) async {
    var reviews = 0;
    await pumpContactExchange(
      tester,
      const ContactExchangeState(available: true),
      advanced: false,
      callbacks: ContactExchangeCallbacks(
        onPrepareShare: (_) async => reviews++,
      ),
    );
    final input = tester.widget<ContactCodeInput>(
      find.byType(ContactCodeInput),
    );
    const invitation = '["zcash-contact/request","presentation-only"]';
    final pending = input.onRead(invitation);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await pending;
    expect(reviews, 0);
    final retry = input.onRead(invitation);
    await tester.pump();
    await retry;
    expect(reviews, 1);
  });

  testWidgets('copy completion cannot revive a disabled code notice', (
    tester,
  ) async {
    final completion = Completer<void>();
    var enabled = true;
    late StateSetter rebuild;
    await codeWidget(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return ContactCodeOutput(
            data: 'invitation',
            enabled: enabled,
            onCopy: (_) => completion.future,
          );
        },
      ),
    );
    await tester.tap(find.text('Copy code'));
    rebuild(() => enabled = false);
    await tester.pump();
    completion.complete();
    await tester.pump();
    expect(find.textContaining('Code copied'), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
  });
}
