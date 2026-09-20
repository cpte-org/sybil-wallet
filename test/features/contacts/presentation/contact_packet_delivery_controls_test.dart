import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_providers.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_delivery_repository.dart';
import 'package:zcash_wallet/src/features/contacts/data/simplex_native_transport.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_delivery.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_packet_kind.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_packet_delivery_controls.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_binding_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_connection_binding.dart';
import '../contact_binding_coordinator_test.dart' show MemoryBindings;
import '../contact_test_fakes.dart';

const scope = ContactScope(accountUuid: 'disposable-ui', network: 'regtest');
const packet = '["zcash-contact/intro-delivery"]';

class _Repository implements ContactDeliveryRepository {
  ContactDeliveryJournal journal = ContactDeliveryJournal();
  Completer<void>? readGate;
  int reads = 0;
  @override
  Future<ContactDeliveryJournal> load(ContactScope scope) async {
    reads++;
    await readGate?.future;
    return journal;
  }

  @override
  Future<void> save(ContactScope scope, ContactDeliveryJournal value) async {
    journal = value;
  }
}

class _ReceivingTransport extends _Transport {
  final updates = StreamController<int>.broadcast();
  @override
  Stream<int> get refreshes => updates.stream;
  @override
  void close() {
    unawaited(updates.close());
    super.close();
  }
}

class _Transport extends SimplexNativeTransport {
  _Transport() : super(scope: scope, networkAllowed: () => true);
  int sends = 0;
  bool hasPeer = true;
  bool hasIncoming = true;
  @override
  Future<String> securityCode(String peer) async =>
      '123456789012345678901234567890';
  @override
  Future<List<({String id, String label})>> peers() async =>
      !hasPeer ? [] : [(id: '1', label: 'Unverified label')];
  @override
  Future<void> reconcile(ContactDeliveryCoordinator coordinator) async {
    if (hasIncoming) {
      await coordinator.receive(scope, '1', 'abcdefghijklmnop', packet);
    }
  }

  @override
  Future<void> submit(String peer, String id, String packet) async {
    sends++;
  }
}

void main() {
  testWidgets(
    'fresh inbox offers setup instead of waiting for an impossible reply',
    (tester) async {
      final transport = _Transport()
        ..hasPeer = false
        ..hasIncoming = false;
      final coordinator = ContactDeliveryCoordinator(
        scope: () => scope,
        repository: _Repository(),
      );
      addTearDown(coordinator.invalidate);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contactDeliveryScopeProvider.overrideWithValue(scope),
            contactDeliveryCoordinatorProvider.overrideWithValue(coordinator),
            simplexNativeTransportProvider.overrideWith((_) async => transport),
          ],
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: Scaffold(
                body: ContactPacketDeliveryControls.inbox(
                  kinds: const {ContactPacketKind.delivery},
                  onSelected: (_) async =>
                      fail('Empty inbox cannot select a packet'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Load from private inbox'));
      await tester.pumpAndSettle();
      expect(find.text('Connect with someone'), findsOneWidget);
      expect(find.text('No private delivery connections yet.'), findsOneWidget);
      expect(
        find.text('Waiting for a reply. This inbox updates while open.'),
        findsNothing,
      );
      expect(transport.sends, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty connections offer setup and return to the original send review',
    (tester) async {
      final repository = _Repository(),
          transport = _Transport()..hasPeer = false;
      final coordinator = ContactDeliveryCoordinator(
        scope: () => scope,
        repository: repository,
      );
      addTearDown(coordinator.invalidate);
      final reviewKey = GlobalKey();
      final expiresAt = DateTime.now().add(const Duration(minutes: 5));
      final router = GoRouter(
        initialLocation: '/review',
        routes: [
          GoRoute(
            path: '/review',
            builder: (_, _) => Scaffold(
              body: ContactPacketDeliveryControls.send(
                key: reviewKey,
                packet: packet,
                expiresAt: expiresAt,
              ),
            ),
          ),
          GoRoute(
            path: '/contacts/delivery',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () {
                  transport.hasPeer = true;
                  context.pop();
                },
                child: const Text('Finish test setup'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contactDeliveryScopeProvider.overrideWithValue(scope),
            contactDeliveryCoordinatorProvider.overrideWithValue(coordinator),
            simplexNativeTransportProvider.overrideWith((_) async => transport),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.dark, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reviewState = reviewKey.currentState;
      await tester.tap(find.text('Choose private delivery connection'));
      await tester.pumpAndSettle();
      expect(find.text('Connect with this person'), findsOneWidget);
      expect(find.text('Approve and send'), findsNothing);
      await tester.tap(find.text('Connect with this person'));
      await tester.pumpAndSettle();
      expect(find.text('Finish test setup'), findsOneWidget);
      expect(transport.sends, 0);
      await tester.tap(find.text('Finish test setup'));
      await tester.pumpAndSettle();
      expect(identical(reviewKey.currentState, reviewState), isTrue);
      expect(find.text('Connect with this person'), findsNothing);
      expect(find.text('Approve and send'), findsOneWidget);
      expect(transport.sends, 0);
      expect(repository.journal.records, isEmpty);
      // Existing connections must not block setting up a different person.
      await tester.tap(find.text('Connect with someone new'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish test setup'));
      await tester.pumpAndSettle();
      expect(identical(reviewKey.currentState, reviewState), isTrue);
      expect(transport.sends, 0);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unverified label · 1').last);
      await tester.pumpAndSettle();
      expect(transport.sends, 0);
      await tester.tap(find.text('Approve and send'));
      await tester.pumpAndSettle();
      expect(transport.sends, 1);
      expect(repository.journal.records.single.packet, packet);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('pending inbox read preserves a newer receiver failure', (
    tester,
  ) async {
    final updates = StreamController<int>();
    addTearDown(updates.close);
    final repo = _Repository(), transport = _Transport();
    final coordinator = ContactDeliveryCoordinator(
      scope: () => scope,
      repository: repo,
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          contactDeliveryScopeProvider.overrideWith((_) => scope),
          contactDeliveryCoordinatorProvider.overrideWith((_) => coordinator),
          simplexNativeTransportProvider.overrideWith((_) async => transport),
          contactDeliveryRefreshProvider.overrideWith((_) => updates.stream),
        ],
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Scaffold(
              body: ContactPacketDeliveryControls.inbox(
                kinds: const {ContactPacketKind.delivery},
                onSelected: (_) async =>
                    fail('Receiver must not select a packet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Load from private inbox'));
    await tester.pumpAndSettle();
    repo.journal = ContactDeliveryJournal();
    repo.readGate = Completer<void>();
    final readsBefore = repo.reads;
    updates.add(1);
    await tester.pump();
    expect(repo.reads, readsBefore + 1);
    updates.addError(const ContactFailure('Receiver stopped'));
    await tester.pumpAndSettle();
    const paused = 'Inbox updates paused. Load the inbox again to retry.';
    expect(find.text(paused), findsOneWidget);
    repo.readGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text(paused), findsOneWidget);
    expect(
      find.text('Waiting for a reply. This inbox updates while open.'),
      findsNothing,
    );
    expect(repo.reads, readsBefore + 1);
    expect(transport.sends, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'send connection explicitly reopens after receiver failure without autosend',
    (tester) async {
      final repo = _Repository();
      final sessions = <_ReceivingTransport>[];
      addTearDown(() {
        for (final session in sessions) {
          session.close();
        }
      });
      final coordinator = ContactDeliveryCoordinator(
        scope: () => scope,
        repository: repo,
      );
      var opens = 0;
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            contactDeliveryScopeProvider.overrideWith((_) => scope),
            contactDeliveryCoordinatorProvider.overrideWith((_) => coordinator),
            simplexNativeTransportProvider.overrideWith((_) async {
              opens++;
              final transport = _ReceivingTransport();
              sessions.add(transport);
              return transport;
            }),
          ],
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: Scaffold(
                body: ContactPacketDeliveryControls.send(
                  packet: packet,
                  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose private delivery connection'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unverified label · 1').last);
      await tester.pumpAndSettle();
      final openedBeforeFailure = opens;
      final first = sessions.last;
      first.updates.addError(const ContactFailure('Receiver stopped'));
      await tester.pumpAndSettle();
      const paused =
          'Private delivery paused. Prepare the connection again to retry.';
      expect(find.text(paused), findsOneWidget);
      final sendButton = find.ancestor(
        of: find.text('Approve and send'),
        matching: find.byType(AppButton),
      );
      expect(tester.widget<AppButton>(sendButton).onPressed, isNull);
      expect(opens, openedBeforeFailure);
      expect(first.sends, 0);
      expect(repo.journal.records, isEmpty);
      await tester.tap(find.text('Choose private delivery connection'));
      await tester.pumpAndSettle();
      expect(opens, openedBeforeFailure + 1);
      final second = sessions.last;
      expect(identical(first, second), isFalse);
      expect(find.text(paused), findsNothing);
      expect(first.sends, 0);
      expect(second.sends, 0);
      expect(repo.journal.records, isEmpty);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unverified label · 1').last);
      await tester.pumpAndSettle();
      expect(second.sends, 0);
      await tester.tap(find.text('Approve and send'));
      await tester.pumpAndSettle();
      expect(first.sends, 0);
      expect(second.sends, 1);
      expect(repo.journal.records.single.state, ContactDeliveryState.submitted);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'open inbox shows newly received details without accepting them and clears on lock',
    (tester) async {
      final updates = StreamController<int>();
      addTearDown(updates.close);
      final repo = _Repository(), transport = _Transport();
      ContactScope? current = scope;
      final coordinator = ContactDeliveryCoordinator(
        scope: () => current,
        repository: repo,
      );
      final container = ProviderContainer(
        overrides: [
          contactDeliveryScopeProvider.overrideWith((_) => current),
          contactDeliveryCoordinatorProvider.overrideWith((_) => coordinator),
          simplexNativeTransportProvider.overrideWith((_) async => transport),
          contactDeliveryRefreshProvider.overrideWith((_) => updates.stream),
        ],
      );
      addTearDown(container.dispose);
      var selections = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: Scaffold(
                body: ContactPacketDeliveryControls.inbox(
                  kinds: const {ContactPacketKind.delivery},
                  onSelected: (_) async {
                    selections++;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Load from private inbox'));
      await tester.pumpAndSettle();
      await coordinator.receive(
        scope,
        '2',
        'ponmlkjihgfedcba',
        '["zcash-contact/intro-delivery","later"]',
      );
      updates.add(1);
      await tester.pumpAndSettle();
      expect(find.text('Review introduction · connection 2'), findsOneWidget);
      expect(selections, 0);
      expect(transport.sends, 0);
      current = null;
      container.invalidate(contactDeliveryScopeProvider);
      updates.add(2);
      await tester.pumpAndSettle();
      expect(find.text('Review introduction · connection 2'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'an intended verified contact gets its pinned connection without choosing a label',
    (tester) async {
      final repo = _Repository(), transport = _Transport();
      final saved = MemoryBindings()
        ..values = [
          ContactConnectionBinding(
            contactId: 'alice',
            identity: testIdentity(7),
            peer: '1',
            code: '123456789012345678901234567890',
          ),
        ];
      final bindings = ContactBindingCoordinator(
        scope: () => scope,
        repository: saved,
        contacts: FakeContactRepository([
          testContact(id: 'alice', label: 'Alice', identityByte: 7),
        ]),
      );
      final coordinator = ContactDeliveryCoordinator(
        scope: () => scope,
        repository: repo,
        validateBinding: bindings.checkForSend,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contactDeliveryScopeProvider.overrideWith((_) => scope),
            contactBindingCoordinatorProvider.overrideWith((_) => bindings),
            contactDeliveryCoordinatorProvider.overrideWith((_) => coordinator),
            simplexNativeTransportProvider.overrideWith((_) async => transport),
          ],
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: Scaffold(
                body: ContactPacketDeliveryControls.send(
                  packet: packet,
                  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
                  contactId: 'alice',
                  recipientIdentity: testIdentity(7),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Prepare contact delivery'));
      await tester.pumpAndSettle();
      expect(transport.sends, 0);
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        '1',
      );
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .onChanged,
        isNull,
      );
      await tester.tap(find.text('Approve and send'));
      await tester.pumpAndSettle();
      expect(transport.sends, 1);
      expect(repo.journal.records.single.binding!.identity, testIdentity(7));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('sending waits for explicit connection selection and approval', (
    tester,
  ) async {
    final repo = _Repository(), transport = _Transport();
    final coordinator = ContactDeliveryCoordinator(
      scope: () => scope,
      repository: repo,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactDeliveryScopeProvider.overrideWith((_) => scope),
          contactDeliveryCoordinatorProvider.overrideWith((_) => coordinator),
          simplexNativeTransportProvider.overrideWith((_) async => transport),
        ],
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Scaffold(
              body: ContactPacketDeliveryControls.send(
                packet: packet,
                expiresAt: DateTime.now().add(const Duration(minutes: 5)),
              ),
            ),
          ),
        ),
      ),
    );
    expect(transport.sends, 0);
    await tester.tap(find.text('Choose private delivery connection'));
    await tester.pumpAndSettle();
    expect(transport.sends, 0);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unverified label · 1').last);
    await tester.pumpAndSettle();
    expect(transport.sends, 0);
    await tester.tap(find.text('Approve and send'));
    await tester.pumpAndSettle();
    expect(transport.sends, 1);
    expect(repo.journal.records.single.packet, packet);
    expect(repo.journal.records.single.state, ContactDeliveryState.submitted);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'inline inbox imports exact bytes without submitting or accepting',
    (tester) async {
      final repo = _Repository(), transport = _Transport();
      final coordinator = ContactDeliveryCoordinator(
        scope: () => scope,
        repository: repo,
      );
      String? selected;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contactDeliveryScopeProvider.overrideWith((_) => scope),
            contactDeliveryCoordinatorProvider.overrideWith((_) => coordinator),
            simplexNativeTransportProvider.overrideWith((_) async => transport),
          ],
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: Scaffold(
                body: ContactPacketDeliveryControls.inbox(
                  kinds: const {ContactPacketKind.delivery},
                  onSelected: (value) async {
                    selected = value;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Load from private inbox'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.tap(find.text('Review introduction · connection 1'));
      await tester.pumpAndSettle();
      expect(selected, packet);
      expect(transport.sends, 0);
      expect(repo.journal.records.single.state, ContactDeliveryState.received);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
