import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_providers.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_delivery_repository.dart';
import 'package:zcash_wallet/src/features/contacts/data/simplex_native_transport.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_delivery.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_packet_kind.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/contact_packet_delivery_controls.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_binding_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_connection_binding.dart';
import '../contact_binding_coordinator_test.dart' show MemoryBindings;
import '../contact_test_fakes.dart';

const scope = ContactScope(accountUuid: 'disposable-ui', network: 'regtest');
const packet = '["zcash-contact/intro-delivery"]';

class _Repository implements ContactDeliveryRepository {
  ContactDeliveryJournal journal = ContactDeliveryJournal();
  @override
  Future<ContactDeliveryJournal> load(ContactScope scope) async => journal;
  @override
  Future<void> save(ContactScope scope, ContactDeliveryJournal value) async {
    journal = value;
  }
}

class _Transport extends SimplexNativeTransport {
  _Transport() : super(scope: scope, networkAllowed: () => true);
  int sends = 0;
  @override
  Future<String> securityCode(String peer) async =>
      '123456789012345678901234567890';
  @override
  Future<List<({String id, String label})>> peers() async => [
    (id: '1', label: 'Unverified label'),
  ];
  @override
  Future<void> reconcile(ContactDeliveryCoordinator coordinator) async {
    await coordinator.receive(scope, '1', 'abcdefghijklmnop', packet);
  }

  @override
  Future<void> submit(String peer, String id, String packet) async {
    sends++;
  }
}

void main() {
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
      await tester.tap(find.text('Approve and send packet'));
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
    await tester.tap(find.text('Approve and send packet'));
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
      await tester.tap(find.text('Review delivery · connection 1'));
      await tester.pumpAndSettle();
      expect(selected, packet);
      expect(transport.sends, 0);
      expect(repo.journal.records.single.state, ContactDeliveryState.received);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
