import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/legacy_material_theme.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_exchange_controller.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/familiar_add_person_screen.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/familiar_people_screen.dart';
import 'package:zcash_wallet/src/features/contacts/presentation/familiar_choose_recipient_screen.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import '../../../fakes/fake_sync_notifier.dart';
import '../contact_test_fixtures.dart';

const _account = AccountState(
  accounts: [AccountInfo(uuid: 'test-account', name: 'Test', order: 0)],
  activeAccountUuid: 'test-account',
);

class _Accounts extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _account;
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  void unlocked(bool value) => state = state.copyWith(isUnlocked: value);
}

class _Repository implements AddressBookRepository {
  List<AddressBookContact> contacts = [];
  @override
  Future<List<AddressBookContact>> loadContacts() async => contacts;
  @override
  Future<void> saveContacts(List<AddressBookContact> value) async {
    contacts = value;
  }
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/people',
  initialAccountState: _account,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
AddressBookContact saved({String label = 'Mara'}) => AddressBookContact(
  id: 'manual',
  label: label,
  network: AddressBookNetwork.zcash,
  address: 'test-only-address',
  profilePictureId: 'pfp-01',
  createdAtMs: 1,
  updatedAtMs: 1,
  pinned: true,
  note: 'From our book club',
);

Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('FAMILIAR_CAPTURE')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('familiar-capture')),
  );
  await t.runAsync(() async {
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final entry in {
      'Geist': 'assets/fonts/Geist-Regular.ttf',
      'Young Serif': 'assets/fonts/YoungSerif-Regular.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value));
      await loader.load();
    }
  });
  test('saved metadata round trips without becoming a connected contact', () {
    final restored = SecureStorageAddressBookRepository.decodeContactsJson(
      jsonEncode([saved().toJson()]),
    ).single;
    expect(restored.note, 'From our book club');
    expect(restored.pinned, isTrue);
    expect(restored.toJson().containsKey('identity'), isFalse);
  });
  testWidgets(
    'one list includes saved and connected people without merging identities',
    (t) async {
      t.view.physicalSize = Size(
        kAppFormFactor == AppFormFactor.mobile ? 390 : 1200,
        1000,
      );
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      AddressBookContact? selected;
      await t.pumpWidget(
        MaterialApp(
          theme: buildLegacyLightTheme(),
          home: RepaintBoundary(
            key: const Key('familiar-capture'),
            child: AppTheme(
              data: AppThemeData.light,
              child: Scaffold(
                body: FamiliarPeopleView(
                  state: ContactExchangeState(
                    available: true,
                    contacts: [testContact(label: 'Connected Mara')],
                  ),
                  savedContacts: [saved()],
                  onSavedPay: (p) => selected = p,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Mara'), findsOneWidget);
      expect(find.text('Connected Mara'), findsOneWidget);
      await t.pumpAndSettle();
      await capture(t, 'familiar-unified-people');
      await t.tap(find.byKey(const Key('person-saved:manual')));
      await t.pumpAndSettle();
      await t.tap(find.text('Send money'));
      expect(selected?.id, 'manual');
      expect(find.text('Request fresh details'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  Future<ProviderContainer> show(
    WidgetTester t,
    _Repository repo,
    Future<bool> Function(String) validate, {
    ValueChanged<SendPrefillArgs>? onSend,
  }) async {
    t.view.physicalSize = Size(
      kAppFormFactor == AppFormFactor.mobile ? 390 : 1200,
      1000,
    );
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        accountProvider.overrideWith(_Accounts.new),
        appSecurityProvider.overrideWith(_Security.new),
        syncProvider.overrideWith(FakeSyncNotifier.new),
        contactScopeProvider.overrideWithValue(null),
        addressBookRepositoryProvider.overrideWithValue(repo),
        familiarAddressValidatorProvider.overrideWithValue(validate),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: onSend == null ? '/people' : '/send',
      routes: [
        GoRoute(
          path: '/people',
          builder: (c, _) => Scaffold(
            body: TextButton(
              onPressed: () => c.push('/people/add'),
              child: const Text('Add'),
            ),
          ),
        ),
        GoRoute(
          path: '/people/add',
          builder: (_, _) => const FamiliarAddPersonScreen(),
        ),
        GoRoute(
          path: '/send',
          builder: (_, state) {
            if (state.extra case final SendPrefillArgs args) {
              onSend?.call(args);
              return const Scaffold(body: Text('Amount screen'));
            }
            return const FamiliarChooseRecipientScreen();
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: buildLegacyLightTheme(),
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );
    await t.pumpAndSettle();
    return container;
  }

  Future<void> fill(WidgetTester t) async {
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    await t.tap(find.text('Enter name and address'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('manual-person-name')), 'Mara');
    await t.enterText(
      find.byKey(const Key('manual-person-address')),
      'test-only-address',
    );
    await t.ensureVisible(find.text('Save person'));
    await t.pump();
    await t.tap(find.text('Save person'));
  }

  testWidgets('manual entry works without the private connection experiment', (
    t,
  ) async {
    final repo = _Repository();
    final c = await show(t, repo, (_) async => true);
    await fill(t);
    await t.pumpAndSettle();
    expect(repo.contacts.single.label, 'Mara');
    expect(c.read(contactExchangeProvider).contacts, isEmpty);
    expect(find.text('Add'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('invalid receiving address is not saved', (t) async {
    final repo = _Repository();
    await show(t, repo, (_) async => false);
    await fill(t);
    await t.pumpAndSettle();
    expect(repo.contacts, isEmpty);
    expect(find.text('Enter a valid Zcash receiving address.'), findsOneWidget);
  });
  testWidgets('lock and unlock during validation cancels the pending save', (
    t,
  ) async {
    final repo = _Repository(), gate = Completer<bool>();
    final c = await show(t, repo, (_) => gate.future);
    await fill(t);
    await t.pump();
    (c.read(appSecurityProvider.notifier) as _Security).unlocked(false);
    await t.pump();
    (c.read(appSecurityProvider.notifier) as _Security).unlocked(true);
    await t.pump();
    gate.complete(true);
    await t.pumpAndSettle();
    expect(repo.contacts, isEmpty);
  });
  testWidgets(
    'saved recipient handoff uses an address without authenticated authority',
    (t) async {
      final repo = _Repository()..contacts = [saved()];
      SendPrefillArgs? result;
      await show(t, repo, (_) async => true, onSend: (args) => result = args);
      await t.tap(find.text('Mara'));
      await t.pumpAndSettle();
      expect(result?.address, 'test-only-address');
      expect(result?.label, 'Mara');
      expect(result?.source, 'address-book');
      expect(result?.contactRecipient, isNull);
    },
  );
}
