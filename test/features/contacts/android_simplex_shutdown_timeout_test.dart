import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/data/simplex_embedded_host.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

// This file owns an isolated Dart host state: an unconfirmed native teardown
// intentionally disables further opens for the lifetime of that isolate.
void main() {
  testWidgets('unconfirmed shutdown times out and blocks every replacement', (
    tester,
  ) async {
    const channel = MethodChannel('com.keplr.vizor/simplex');
    final pending = Completer<Object?>();
    var opens = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'close') return pending.future;
      opens++;
      return '{"type":"ok"}';
    });
    addTearDown(() {
      pending.complete(null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    final first = AndroidSimplexHost();
    await first.open('/private/one', 'key');
    final closing = first.close();
    final rejected = expectLater(
      AndroidSimplexHost().open('/private/two', 'key'),
      throwsA(isA<ContactFailure>()),
    );
    await tester.pump(const Duration(seconds: 11));
    await closing;
    await rejected;
    await expectLater(
      AndroidSimplexHost().open('/private/three', 'key'),
      throwsA(isA<ContactFailure>()),
    );
    expect(opens, 1);
  });
}
