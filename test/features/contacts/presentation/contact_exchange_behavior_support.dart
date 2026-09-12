import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_exchange_screen.dart';

import 'contact_exchange_fixtures.dart';
import 'contact_exchange_test_support.dart';

Future<void> _openConnectedPeople(WidgetTester tester) async {
  // A rebuilt exchange may retain this expansion's state between fixtures.
  if (find.byKey(const Key('contacts-send-alice')).evaluate().isEmpty) {
    final heading = find.text('Your connected people');
    await tester.ensureVisible(heading);
    await tester.tap(heading);
    await tester.pumpAndSettle();
  }
}

void runContactExchangeBehaviorTests() {
  _runContactReviewSafetyTests();
  testWidgets('accessibility tap grants explicit acceptance consent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpContactExchange(
        tester,
        ContactExchangeState(
          available: true,
          candidate: ContactCandidateView(
            identity: ContactExchangeFixtures.identity,
            address: ContactExchangeFixtures.newAddress,
            label: 'Alice',
            sequence: 1,
            expiresAt: ContactExchangeFixtures.expiry,
          ),
        ),
        callbacks: ContactExchangeCallbacks(
          onAcceptResponse:
              ({required label, required independentlyVerified}) async {},
        ),
      );
      final consent = find.byKey(const Key('contacts-verify-acceptance'));
      final checkbox = find.descendant(
        of: consent,
        matching: find.byType(Checkbox),
      );
      await tester.ensureVisible(consent);
      await tester.pump();
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      expect(contactButtonEnabled(tester, 'contacts-accept-response'), isFalse);
      final node = tester.getSemantics(checkbox);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      expect(contactButtonEnabled(tester, 'contacts-accept-response'), isTrue);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('unsupported accounts cannot start an exchange', (tester) async {
    var requests = 0;
    await pumpContactExchange(
      tester,
      ContactExchangeFixtures.unavailable,
      callbacks: ContactExchangeCallbacks(
        onStartRequest: ({String? contactId}) async {
          requests++;
        },
      ),
    );
    expect(
      find.text('This account cannot use experimental contact exchange.'),
      findsOneWidget,
    );
    final request = find.byKey(const Key('contacts-new-request'));
    if (request.evaluate().isNotEmpty) {
      expect(contactButtonEnabled(tester, 'contacts-new-request'), isFalse);
    }
    expect(find.byKey(const Key('contacts-accept-response')), findsNothing);
    expect(find.byKey(const Key('contacts-confirm-share')), findsNothing);
    expect(requests, 0);
  });

  testWidgets(
    'new acceptance requires a local label and independent verification',
    (tester) async {
      String? acceptedLabel;
      bool? verified;
      await pumpContactExchange(
        tester,
        ContactExchangeFixtures.newContact,
        callbacks: ContactExchangeCallbacks(
          onAcceptResponse:
              ({required label, required independentlyVerified}) async {
                acceptedLabel = label;
                verified = independentlyVerified;
              },
        ),
      );
      expect(contactButtonEnabled(tester, 'contacts-accept-response'), isFalse);
      await tester.enterText(
        find.byKey(const Key('contacts-label')),
        '  Alice  ',
      );
      await tester.pump();
      expect(contactButtonEnabled(tester, 'contacts-accept-response'), isFalse);
      await tapContactControl(tester, 'contacts-verify-acceptance');
      expect(contactButtonEnabled(tester, 'contacts-accept-response'), isTrue);
      await tapContactControl(tester, 'contacts-accept-response');
      expect(acceptedLabel, 'Alice');
      expect(verified, isTrue);
    },
  );

  testWidgets(
    'the 20-character local label limit is enforced before acceptance',
    (tester) async {
      var accepts = 0;
      await pumpContactExchange(
        tester,
        ContactExchangeFixtures.newContact,
        callbacks: ContactExchangeCallbacks(
          onAcceptResponse:
              ({required label, required independentlyVerified}) async {
                accepts++;
              },
        ),
      );
      await tapContactControl(tester, 'contacts-verify-acceptance');
      await tester.enterText(find.byKey(const Key('contacts-label')), 'x' * 20);
      await tester.pump();
      expect(contactButtonEnabled(tester, 'contacts-accept-response'), isTrue);
      await tester.enterText(find.byKey(const Key('contacts-label')), 'x' * 21);
      await tester.pump();
      expect(contactButtonEnabled(tester, 'contacts-accept-response'), isFalse);
      expect(accepts, 0);
    },
  );

  testWidgets(
    'an address update discloses the existing and proposed addresses',
    (tester) async {
      await pumpContactExchange(tester, ContactExchangeFixtures.updateContact);
      expect(find.text(ContactExchangeFixtures.oldAddress), findsWidgets);
      expect(find.text(ContactExchangeFixtures.newAddress), findsOneWidget);
      expect(find.text(ContactExchangeFixtures.identity), findsWidgets);
      expect(find.byKey(const Key('contacts-accept-response')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sharing a response requires explicit disclosure consent', (
    tester,
  ) async {
    bool? sharedConsent;
    await pumpContactExchange(
      tester,
      ContactExchangeFixtures.sharing,
      callbacks: ContactExchangeCallbacks(
        onConfirmShare: ({required bool consent}) async {
          sharedConsent = consent;
        },
      ),
    );
    expect(find.text(ContactExchangeFixtures.newAddress), findsOneWidget);
    expect(find.text(ContactExchangeFixtures.identity), findsOneWidget);
    expect(contactButtonEnabled(tester, 'contacts-confirm-share'), isFalse);
    await tapContactControl(tester, 'contacts-share-consent');
    expect(contactButtonEnabled(tester, 'contacts-confirm-share'), isTrue);
    await tapContactControl(tester, 'contacts-confirm-share');
    expect(sharedConsent, isTrue);
  });

  testWidgets(
    'restored contacts can request verification while payments remain blocked',
    (tester) async {
      var sends = 0;
      var requests = 0;
      for (final contact in [
        ContactExchangeFixtures.suspendedAlice,
        ContactExchangeFixtures.restoredAlice,
      ]) {
        await pumpContactExchange(
          tester,
          ContactExchangeState(available: true, contacts: [contact]),
          callbacks: ContactExchangeCallbacks(
            onSend: (_) => sends++,
            onStartRequest: ({String? contactId}) async {
              requests++;
            },
          ),
        );
        await _openConnectedPeople(tester);
        expect(contactButtonEnabled(tester, 'contacts-send-alice'), isFalse);
        expect(
          contactButtonEnabled(tester, 'contacts-update-alice'),
          contact.status == ContactTrustStatus.restored,
        );
      }
      expect(sends, 0);
      expect(requests, 0);
    },
  );

  testWidgets(
    'accepted contact actions preserve its stable ID and require suspend confirmation',
    (tester) async {
      String? sent;
      String? updated;
      String? suspended;
      await pumpContactExchange(
        tester,
        const ContactExchangeState(
          available: true,
          contacts: [ContactExchangeFixtures.alice],
        ),
        callbacks: ContactExchangeCallbacks(
          onSend: (id) => sent = id,
          onStartRequest: ({String? contactId}) async {
            updated = contactId;
          },
          onSuspend: (id) async {
            suspended = id;
          },
        ),
      );
      await _openConnectedPeople(tester);
      await tapContactControl(tester, 'contacts-send-alice');
      expect(sent, 'alice');
      await tapContactControl(tester, 'contacts-update-alice');
      expect(updated, 'alice');
      await tapContactControl(tester, 'contacts-suspend-alice');
      expect(suspended, isNull);
      await tapContactControl(tester, 'contacts-confirm-suspend-alice');
      expect(suspended, 'alice');
    },
  );

  for (final input in ['response', 'share']) {
    testWidgets(
      '$input payloads reject oversized paste without silent truncation',
      (tester) async {
        String? previewed;
        final state = ContactExchangeState(
          available: true,
          request: input == 'response' ? ContactExchangeFixtures.request : null,
        );
        await pumpContactExchange(
          tester,
          state,
          callbacks: ContactExchangeCallbacks(
            onPreviewResponse: (text) async {
              previewed = text;
            },
            onPrepareShare: (text) async {
              previewed = text;
            },
          ),
        );
        final inputKey = 'contacts-$input-input';
        final actionKey = input == 'response'
            ? 'contacts-preview-response'
            : 'contacts-prepare-share';
        final exactLimit = 'x' * 32768;
        await tester.enterText(find.byKey(Key(inputKey)), exactLimit);
        await tester.pump();
        expect(contactButtonEnabled(tester, actionKey), isTrue);
        await tester.enterText(find.byKey(Key(inputKey)), '$exactLimit!');
        await tester.pump();
        final editable = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(Key(inputKey)),
            matching: find.byType(EditableText),
          ),
        );
        expect(editable.controller.text, exactLimit);
        expect(
          find.text('Use a contact exchange of at most 32,768 characters.'),
          findsOneWidget,
        );
        expect(contactButtonEnabled(tester, actionKey), isFalse);
        expect(previewed, isNull);
        await tester.enterText(
          find.byKey(Key(inputKey)),
          ContactExchangeFixtures.responseJson,
        );
        await tester.pump();
        expect(contactButtonEnabled(tester, actionKey), isTrue);
        await tapContactControl(tester, actionKey);
        expect(previewed, ContactExchangeFixtures.responseJson);
      },
    );
  }
}

void _runContactReviewSafetyTests() {
  testWidgets(
    'changing a candidate identity or address clears acceptance consent',
    (tester) async {
      final callbacks = ContactExchangeCallbacks(
        onAcceptResponse:
            ({required label, required independentlyVerified}) async {},
      );
      ContactExchangeState candidateState(String identity, String address) =>
          ContactExchangeState(
            available: true,
            candidate: ContactCandidateView(
              identity: identity,
              address: address,
              label: 'Alice',
              sequence: 1,
              expiresAt: ContactExchangeFixtures.expiry,
            ),
          );
      await pumpContactExchange(
        tester,
        candidateState(
          ContactExchangeFixtures.identity,
          ContactExchangeFixtures.newAddress,
        ),
        callbacks: callbacks,
      );
      await tapContactControl(tester, 'contacts-verify-acceptance');
      expect(contactButtonEnabled(tester, 'contacts-accept-response'), isTrue);
      const otherIdentity =
          'ed25519:CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
      for (final replacement in [
        candidateState(otherIdentity, ContactExchangeFixtures.newAddress),
        candidateState(otherIdentity, ContactExchangeFixtures.oldAddress),
      ]) {
        await pumpContactExchange(tester, replacement, callbacks: callbacks);
        final consent = tester.widget<Checkbox>(
          find.descendant(
            of: find.byKey(const Key('contacts-verify-acceptance')),
            matching: find.byType(Checkbox),
          ),
        );
        expect(consent.value, isFalse);
        // The label remains valid, so it cannot mask a stale-consent defect.
        final label = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(const Key('contacts-label')),
            matching: find.byType(EditableText),
          ),
        );
        expect(label.controller.text, 'Alice');
        expect(
          contactButtonEnabled(tester, 'contacts-accept-response'),
          isFalse,
        );
        await tapContactControl(tester, 'contacts-verify-acceptance');
        expect(
          contactButtonEnabled(tester, 'contacts-accept-response'),
          isTrue,
        );
      }
    },
  );

  testWidgets(
    'request, reply and share actions stop at the exact expiry boundary',
    (tester) async {
      var calls = 0;
      final callbacks = ContactExchangeCallbacks(
        onPreviewResponse: (_) async {
          calls++;
        },
        onAcceptResponse:
            ({required label, required independentlyVerified}) async {
              calls++;
            },
        onConfirmShare: ({required consent}) async {
          calls++;
        },
        onCopy: (_, _) async {
          calls++;
        },
      );
      await pumpContactExchange(
        tester,
        ContactExchangeState(
          available: true,
          request: ContactRequestView(
            json: ContactExchangeFixtures.requestJson,
            expiresAt: contactTestNow,
          ),
        ),
        callbacks: callbacks,
      );
      await tester.enterText(
        find.byKey(const Key('contacts-response-input')),
        ContactExchangeFixtures.responseJson,
      );
      await tester.pump();
      expect(
        contactButtonEnabled(tester, 'contacts-preview-response'),
        isFalse,
      );
      expect(contactButtonEnabled(tester, 'contacts-copy-request'), isFalse);

      await pumpContactExchange(
        tester,
        ContactExchangeState(
          available: true,
          candidate: ContactCandidateView(
            identity: ContactExchangeFixtures.identity,
            address: ContactExchangeFixtures.newAddress,
            label: 'Alice',
            sequence: 1,
            expiresAt: contactTestNow,
          ),
        ),
        callbacks: callbacks,
      );
      expect(contactButtonEnabled(tester, 'contacts-accept-response'), isFalse);
      final acceptance = tester.widget<Checkbox>(
        find.descendant(
          of: find.byKey(const Key('contacts-verify-acceptance')),
          matching: find.byType(Checkbox),
        ),
      );
      expect(acceptance.onChanged, isNull);

      await pumpContactExchange(
        tester,
        ContactExchangeState(
          available: true,
          shareReview: ContactShareReview(
            identity: ContactExchangeFixtures.identity,
            address: ContactExchangeFixtures.newAddress,
            audience: ContactExchangeFixtures.share.audience,
            expiresAt: contactTestNow,
          ),
        ),
        callbacks: callbacks,
      );
      expect(contactButtonEnabled(tester, 'contacts-confirm-share'), isFalse);
      final sharing = tester.widget<Checkbox>(
        find.descendant(
          of: find.byKey(const Key('contacts-share-consent')),
          matching: find.byType(Checkbox),
        ),
      );
      expect(sharing.onChanged, isNull);
      expect(calls, 0);
    },
  );

  testWidgets(
    'losing availability clears typed exchanges and hides contact actions',
    (tester) async {
      final callbacks = ContactExchangeCallbacks(
        onSend: (_) {},
        onStartRequest: ({String? contactId}) async {},
        onSuspend: (_) async {},
        onPreviewResponse: (_) async {},
        onPrepareShare: (_) async {},
      );
      for (final input in ['response', 'share']) {
        ContactExchangeState state(bool available) => ContactExchangeState(
          available: available,
          contacts: const [ContactExchangeFixtures.alice],
          request: input == 'response' ? ContactExchangeFixtures.request : null,
          unavailableReason: available ? null : 'Account is locked.',
        );
        await pumpContactExchange(tester, state(true), callbacks: callbacks);
        final inputKey = Key('contacts-$input-input');
        await tester.enterText(
          find.byKey(inputKey),
          ContactExchangeFixtures.responseJson,
        );
        await tester.pump();
        await _openConnectedPeople(tester);
        expect(contactButtonEnabled(tester, 'contacts-send-alice'), isTrue);

        // Keep the request and contacts present in the supplied state to prove
        // availability itself invalidates the view's local inputs and controls.
        await pumpContactExchange(tester, state(false), callbacks: callbacks);
        expect(find.text('Account is locked.'), findsOneWidget);
        for (final action in ['send', 'update', 'suspend']) {
          expect(find.byKey(Key('contacts-$action-alice')), findsNothing);
        }
        expect(find.byKey(inputKey), findsNothing);

        await pumpContactExchange(tester, state(true), callbacks: callbacks);
        final editable = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(inputKey),
            matching: find.byType(EditableText),
          ),
        );
        expect(editable.controller.text, isEmpty);
        final previewKey = input == 'response'
            ? 'contacts-preview-response'
            : 'contacts-prepare-share';
        expect(contactButtonEnabled(tester, previewKey), isFalse);
      }
    },
  );
}
