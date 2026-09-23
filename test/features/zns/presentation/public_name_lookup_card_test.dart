import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/legacy_material_theme.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/zns/application/public_name_lookup.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_http_transport.dart';
import 'package:zcash_wallet/src/features/zns/data/zns_rpc_client.dart';
import 'package:zcash_wallet/src/features/zns/presentation/public_name_lookup_card.dart';
import 'package:zcash_wallet/src/features/zns/presentation/zns_view_data.dart';

import '../data/zns_rpc_client_test.dart' as fixture;

const _configuration = ZnsConfigurationInput(
  registryAddress: fixture.registry,
  rpcUrl: 'https://rpc.example',
);
const _unlocked = PublicNameLookupSession(
  accountUuid: 'alice',
  network: 'test',
  unlocked: true,
);

class _Session extends Notifier<PublicNameLookupSession> {
  @override
  PublicNameLookupSession build() => _unlocked;
  void change(PublicNameLookupSession value) => state = value;
}

final _sessionProvider = NotifierProvider<_Session, PublicNameLookupSession>(
  _Session.new,
);

class _Configuration extends Notifier<ZnsConfigurationInput> {
  @override
  ZnsConfigurationInput build() => _configuration;
  void change(ZnsConfigurationInput value) => state = value;
}

final _configurationProvider =
    NotifierProvider<_Configuration, ZnsConfigurationInput>(_Configuration.new);

class _Preferences implements PublicNameLookupPreferenceStore {
  bool enabled = false, fail = false;
  @override
  Future<bool> read() async {
    if (fail) throw StateError('storage unavailable');
    return enabled;
  }

  @override
  Future<void> write(bool value) async {
    if (fail) throw StateError('storage unavailable');
    enabled = value;
  }
}

class _Book implements AddressBookRepository {
  List<AddressBookContact> contacts = [];
  Completer<List<AddressBookContact>>? loading;
  Completer<void>? writing;
  int writes = 0;
  @override
  Future<List<AddressBookContact>> loadContacts() async =>
      loading == null ? contacts : await loading!.future;
  @override
  Future<void> saveContacts(List<AddressBookContact> value) async {
    writes++;
    if (writing != null) await writing!.future;
    contacts = value;
  }
}

PublicNameResolution _resolution({String owner = fixture.owner}) =>
    PublicNameResolution(
      name: 'mara',
      address: 'test-only-unified-address',
      owner: owner,
      positionId: BigInt.one,
    );

class _Service extends PublicNameLookupService {
  Future<PublicNameResolution> Function() reply = () async => _resolution();
  int calls = 0;
  @override
  Future<PublicNameResolution> lookup({
    required ZnsConfigurationInput configuration,
    required String network,
    required String name,
  }) async {
    calls++;
    expect(network, 'test');
    return reply();
  }
}

class _RecordRpc extends ZnsRpcClient {
  _RecordRpc() : super(fixture.configuration());
  int expiresAt = 500;
  bool closed = false;
  ZnsDataException? failure;
  @override
  Future<ZnsBlock> block([String tag = 'latest']) async => ZnsBlock(
    number: BigInt.one,
    hash: fixture.blockHash,
    timestamp: BigInt.from(100),
  );
  @override
  Future<ZnsNameRecord> readNameRecord(String name) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return ZnsNameRecord(
      name: name,
      owner: fixture.owner,
      unifiedAddress: 'test-only-unified-address',
      expiresAt: BigInt.from(expiresAt),
      active: true,
      positionId: BigInt.one,
      block: await block(),
    );
  }

  @override
  void close() => closed = true;
}

void main() {
  test(
    'public reads keep canonical checks without registration economics',
    () async {
      expect(normalizePublicZcashName(' Mara.ZEC '), 'mara');
      expect(
        () => normalizePublicZcashName('mara.other'),
        throwsFormatException,
      );
      final transport = fixture.RpcFixture()..incompatible = true;
      final rpc = ZnsRpcClient(fixture.configuration(), transport: transport);
      expect((await rpc.readNameRecord('mara')).owner, fixture.owner);
      expect(transport.selectors, isNot(contains('0xda1f12ab')));
      await expectLater(
        rpc.lookupName('mara'),
        throwsA(isA<ZnsDataException>()),
      );
      transport.reorganize = true;
      await expectLater(
        rpc.readNameRecord('mara'),
        throwsA(isA<ZnsDataException>()),
      );
    },
  );

  test(
    'expired and wrong-network receiving addresses cannot resolve',
    () async {
      final rpc = _RecordRpc();
      var valid = false;
      final service = PublicNameLookupService(
        rpcFactory: (_) => rpc,
        validateAddress: (network, address) async {
          expect(network, 'test');
          return valid;
        },
      );
      Future<PublicNameResolution> lookup() => service.lookup(
        configuration: _configuration,
        network: 'test',
        name: 'mara.zec',
      );
      await expectLater(lookup(), throwsA(isA<PublicNameLookupFailure>()));
      expect(rpc.closed, isTrue);
      valid = true;
      rpc.expiresAt = 100;
      await expectLater(lookup(), throwsA(isA<PublicNameLookupFailure>()));
    },
  );

  test(
    'a throttled endpoint keeps its own wording instead of blaming the registry',
    () async {
      final rpc = _RecordRpc()
        ..failure = const ZnsRateLimitException(rpcMethod: 'eth_call');
      final service = PublicNameLookupService(
        rpcFactory: (_) => rpc,
        validateAddress: (_, _) async => true,
      );
      await expectLater(
        service.lookup(
          configuration: _configuration,
          network: 'test',
          name: 'mara.zec',
        ),
        throwsA(
          isA<PublicNameLookupFailure>().having(
            (error) => error.message,
            'message',
            'Base RPC eth_call is temporarily busy. Wait a moment, then try again.',
          ),
        ),
      );
      expect(rpc.closed, isTrue);
    },
  );

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    required _Book book,
    required _Service service,
    _Preferences? preferences,
  }) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        publicNameLookupSessionProvider.overrideWith(
          (ref) => ref.watch(_sessionProvider),
        ),
        publicNameLookupPreferenceStoreProvider.overrideWithValue(
          preferences ?? (_Preferences()..enabled = true),
        ),
        publicNameLookupServiceProvider.overrideWithValue(service),
        addressBookRepositoryProvider.overrideWithValue(book),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildLegacyLightTheme(),
          home: AppTheme(
            data: AppThemeData.light,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Consumer(
                  builder: (_, ref, _) => PublicNameLookupCard(
                    configuration: ref.watch(_configurationProvider),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> lookup(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('public-name-query')),
      'mara.zec',
    );
    await tester.pump();
    await tester.tap(find.text('Look up name'));
    await tester.pump();
  }

  testWidgets('lookup is off by default and remains off on storage failure', (
    tester,
  ) async {
    final service = _Service(), preferences = _Preferences()..fail = true;
    await mount(
      tester,
      book: _Book(),
      service: service,
      preferences: preferences,
    );
    expect(find.byKey(const Key('public-name-query')), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('public-name-query')), findsNothing);
    expect(service.calls, 0);
    expect(
      find.text('Could not save this setting. Public lookups are off.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'changed ownership requires review and saves an ordinary local address',
    (tester) async {
      final service = _Service(), book = _Book();
      await mount(tester, book: book, service: service);
      await lookup(tester);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('public-name-local-label')),
        'My Mara',
      );
      service.reply = () async => _resolution(owner: fixture.registry);
      await tester.tap(find.byKey(const Key('public-name-save')));
      await tester.pumpAndSettle();
      expect(book.contacts, isEmpty);
      expect(
        find.text('This name changed. Review the new address before saving.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('public-name-save')));
      await tester.pumpAndSettle();
      expect(service.calls, 3);
      expect(book.contacts.single.label, 'My Mara');
      expect(book.contacts.single.network, AddressBookNetwork.zcash);
      expect(book.contacts.single.address, 'test-only-unified-address');
      expect(book.contacts.single.toJson().containsKey('identity'), isFalse);
    },
  );

  testWidgets('lock and unlock discards a late lookup result', (tester) async {
    final pending = Completer<PublicNameResolution>();
    final service = _Service()..reply = () => pending.future;
    final container = await mount(tester, book: _Book(), service: service);
    await lookup(tester);
    container
        .read(_sessionProvider.notifier)
        .change(
          const PublicNameLookupSession(
            accountUuid: 'alice',
            network: 'test',
            unlocked: false,
          ),
        );
    await tester.pump();
    container.read(_sessionProvider.notifier).change(_unlocked);
    await tester.pump();
    pending.complete(_resolution());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('public-name-save')), findsNothing);
    expect(find.byKey(const Key('public-name-address')), findsNothing);
  });

  testWidgets('disabling lookups discards an in-flight result', (tester) async {
    final pending = Completer<PublicNameResolution>();
    final service = _Service()..reply = () => pending.future;
    final preferences = _Preferences()..enabled = true;
    await mount(
      tester,
      book: _Book(),
      service: service,
      preferences: preferences,
    );
    await lookup(tester);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    pending.complete(_resolution());
    await tester.pumpAndSettle();
    expect(preferences.enabled, isFalse);
    expect(find.byKey(const Key('public-name-query')), findsNothing);
    expect(find.byKey(const Key('public-name-address')), findsNothing);
  });

  testWidgets('account change while loading the address book revokes save', (
    tester,
  ) async {
    final book = _Book()..loading = Completer<List<AddressBookContact>>();
    final container = await mount(tester, book: book, service: _Service());
    await lookup(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('public-name-save')));
    await tester.pump();
    container
        .read(_sessionProvider.notifier)
        .change(
          const PublicNameLookupSession(
            accountUuid: 'bob',
            network: 'test',
            unlocked: true,
          ),
        );
    await tester.pump();
    book.loading!.complete([]);
    await tester.pumpAndSettle();
    expect(book.contacts, isEmpty);
    expect(find.byKey(const Key('public-name-address')), findsNothing);
  });

  testWidgets(
    'configuration changes cannot overlap an already dispatched save',
    (tester) async {
      final book = _Book()..writing = Completer<void>();
      final service = _Service();
      final container = await mount(tester, book: book, service: service);
      await lookup(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('public-name-save')));
      await tester.pump();
      expect(book.writes, 1);
      container
          .read(_configurationProvider.notifier)
          .change(
            const ZnsConfigurationInput(
              registryAddress: fixture.registry,
              rpcUrl: 'https://different.example',
            ),
          );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('public-name-query')))
            .enabled,
        isFalse,
      );
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(find.byKey(const Key('public-name-save')), findsNothing);
      await tester.tap(find.text('Look up name'));
      await tester.pump();
      expect(service.calls, 2);
      expect(book.writes, 1);
      book.writing!.complete();
      await tester.pumpAndSettle();
      expect(book.contacts, hasLength(1));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('public-name-query')))
            .enabled,
        isTrue,
      );
    },
  );
}
