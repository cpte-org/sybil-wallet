@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_exchange_controller.dart';
import 'package:zcash_wallet/src/features/contacts/application/familiar_people_metadata_provider.dart';
import 'package:zcash_wallet/src/features/contacts/data/familiar_people_metadata_repository.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/familiar_people_screen.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';

import '../contact_test_fakes.dart';
import 'familiar_people_view_test.dart' show pumpPeople;

class _UnlockedSecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

class _EmptyBook implements AddressBookRepository {
  @override
  Future<List<AddressBookContact>> loadContacts() async => const [];
  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async =>
      throw UnimplementedError();
}

class _MetadataRepository extends Fake
    implements FamiliarPeopleMetadataRepository {
  @override
  Future<Map<String, FamiliarPersonMetadata>> load(ContactScope scope) async =>
      const {};
}

void main() {
  testWidgets('small mobile list and restored detail fit without overflow', (
    tester,
  ) async {
    final restored = testContact(status: ContactTrustStatus.restored);
    await pumpPeople(tester, size: const Size(320, 720), people: [restored]);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('person-alice')));
    await tester.tap(find.byKey(const Key('person-alice')));
    await tester.pumpAndSettle();
    expect(find.text('Check current address'), findsOneWidget);
    expect(find.text('Send money'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wallet People adapter sends the authenticated recipient snapshot',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      SendPrefillArgs? prefill;
      final person = testContact(label: 'My friend');
      final container = ProviderContainer(
        overrides: [
          appSecurityProvider.overrideWith(_UnlockedSecurity.new),
          addressBookRepositoryProvider.overrideWithValue(_EmptyBook()),
          contactScopeProvider.overrideWithValue(testContactScope),
          contactRepositoryProvider.overrideWithValue(
            FakeContactRepository([person]),
          ),
          contactGatewayProvider.overrideWithValue(FakeContactGateway()),
          familiarPeopleMetadataRepositoryProvider.overrideWithValue(
            _MetadataRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/people',
        routes: [
          GoRoute(
            path: '/people',
            builder: (_, _) =>
                const Scaffold(body: FamiliarPeopleScreen(contactId: 'alice')),
          ),
          GoRoute(
            path: '/send',
            builder: (_, state) {
              prefill = state.extra! as SendPrefillArgs;
              return const Scaffold(body: Text('Reviewed send route'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData.light(),
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send money'));
      await tester.pumpAndSettle();
      expect(prefill!.address, person.address);
      expect(prefill!.label, 'My friend');
      expect(prefill!.contactRecipient, isNotNull);
      final snapshot = prefill!.contactRecipient!;
      container
          .read(contactExchangeProvider.notifier)
          .validateRecipient(
            snapshot,
            address: prefill!.address,
            accountUuid: testContactScope.accountUuid,
            network: testContactScope.network,
          );
      expect(tester.takeException(), isNull);
    },
  );
}
