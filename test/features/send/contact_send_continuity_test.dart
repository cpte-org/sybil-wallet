// The shared send flow resolves wallet paths through the platform plugin.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_exchange_controller.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../contacts/contact_test_fakes.dart';

void main() {
  final rustApi = _RustApiFake();

  setUpAll(() => RustLib.initMock(api: rustApi));
  tearDownAll(RustLib.dispose);

  setUp(() async {
    rustApi.reset();
    FlutterSecureStorage.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('contact_send_test');
    final originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    addTearDown(() async {
      PathProviderPlatform.instance = originalPaths;
      await tempDir.delete(recursive: true);
    });
  });

  testWidgets(
    'contact suspended during proposal await retains proposal ownership',
    (tester) async {
      final h = await _mount(tester);
      final selected = h.contacts.recipientFor('alice');
      await tester.runAsync(() async {
        rustApi.proposalStarted = Completer<void>();
        rustApi.proposalGate = Completer<ProposalResult>();
        final pending = _propose(h.ref, selected);
        await rustApi.proposalStarted.future.timeout(
          const Duration(seconds: 5),
        );
        await h.contacts.suspendContact('alice');
        rustApi.proposalGate!.complete(_proposal());
        final args = await pending;
        expect(args.contactRecipient, same(selected));
      });

      expect(rustApi.proposeCalls, 1);
      expect(rustApi.discardCalls, isEmpty);
      expect(rustApi.executeCalls, 0);
    },
  );

  testWidgets(
    'contact suspended during mnemonic await cannot reach software signing',
    (tester) async {
      final account = _FakeAccountNotifier();
      final h = await _mount(tester, account: account);
      final selected = h.contacts.recipientFor('alice');
      final args = await tester.runAsync(() => _propose(h.ref, selected));
      expect(args!.contactRecipient, same(selected));
      final mnemonic = Uint8List.fromList([1, 2, 3]);

      final outcome = await tester.runAsync(() async {
        account.mnemonicStarted = Completer<void>();
        account.mnemonicGate = Completer<Uint8List?>();
        final pending = runSendBroadcast(
          ref: h.ref,
          args: args,
          confirmSaplingParamsDownload: () async => false,
        );
        await account.mnemonicStarted.future.timeout(
          const Duration(seconds: 5),
        );
        await h.contacts.suspendContact('alice');
        account.mnemonicGate!.complete(mnemonic);
        return pending;
      });

      expect(outcome!.phase, SendBroadcastPhase.failed);
      expect(outcome.error, contains('contact changed'));
      expect(rustApi.proposeCalls, 1);
      expect(rustApi.executeCalls, 0);
      expect(rustApi.discardCalls, [(BigInt.one, _flowId)]);
      expect(mnemonic, everyElement(0));
    },
    // macOS reads its mnemonic inside the native execute call, without the
    // Dart mnemonic await exercised by this regression.
    skip: Platform.isMacOS,
  );
}

const _flowId = 'contact-send-test';

Future<SendReviewArgs> _propose(
  WidgetRef ref,
  ContactRecipientSnapshot selected,
) => proposeSendTransfer(
  ref: ref,
  accountUuid: testContactScope.accountUuid,
  sendFlowId: _flowId,
  address: selected.address,
  addressType: 'unified',
  amountZatoshi: BigInt.from(100000),
  contactRecipient: selected,
  loadDbPath: () async => '/unused-contact-send-test.sqlite',
);

ProposalResult _proposal() => ProposalResult(
  proposalId: BigInt.one,
  feeZatoshi: BigInt.from(10000),
  needsSaplingParams: false,
);

Future<({WidgetRef ref, ContactExchangeController contacts})> _mount(
  WidgetTester tester, {
  _FakeAccountNotifier? account,
}) async {
  late WidgetRef widgetRef;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/send',
            initialAccountState: AccountState(
              accounts: [
                AccountInfo(
                  uuid: testContactScope.accountUuid,
                  name: 'Contact test account',
                  order: 0,
                ),
              ],
              activeAccountUuid: testContactScope.accountUuid,
            ),
            initialSyncSnapshot: AppSyncSnapshot.empty,
            network: testContactScope.network,
            rpcEndpointConfig: defaultRpcEndpointConfig(
              testContactScope.network,
            ),
            themeMode: ThemeMode.system,
            privacyModeEnabled: false,
            isPasswordConfigured: true,
            isUnlocked: true,
            passwordRotationRecoveryFailed: false,
          ),
        ),
        accountProvider.overrideWith(() => account ?? _FakeAccountNotifier()),
        syncProvider.overrideWith(_FakeSyncNotifier.new),
        contactScopeProvider.overrideWithValue(testContactScope),
        contactRepositoryProvider.overrideWithValue(
          FakeContactRepository([testContact()]),
        ),
        contactGatewayProvider.overrideWithValue(FakeContactGateway()),
      ],
      child: Consumer(
        builder: (context, ref, child) {
          widgetRef = ref;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  final contacts = widgetRef.read(contactExchangeProvider.notifier);
  await tester.runAsync(() => pumpEventQueue());
  await tester.pump();
  expect(widgetRef.read(contactExchangeProvider).loading, isFalse);
  return (ref: widgetRef, contacts: contacts);
}

class _FakeAccountNotifier extends AccountNotifier {
  var mnemonicStarted = Completer<void>();
  Completer<Uint8List?>? mnemonicGate;

  @override
  Future<Uint8List?> getMnemonicBytesForAccount(String uuid) {
    mnemonicStarted.complete();
    return mnemonicGate?.future ?? Future.value(Uint8List.fromList([1, 2, 3]));
  }
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: testContactScope.accountUuid,
    hasAccountScopedData: true,
  );

  @override
  Future<T> runWithAuthoritativeSpendable<T>({
    required String accountUuid,
    required Future<T> Function() operation,
  }) => operation();

  @override
  Future<void> refreshAfterSend() async {}
}

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _RustApiFake implements RustLibApi {
  var proposalStarted = Completer<void>();
  Completer<ProposalResult>? proposalGate;
  final discardCalls = <(BigInt, String)>[];
  int proposeCalls = 0, executeCalls = 0;

  void reset() {
    proposalStarted = Completer<void>();
    proposalGate = null;
    discardCalls.clear();
    proposeCalls = 0;
    executeCalls = 0;
  }

  @override
  Future<ProposalResult> crateApiSyncProposeSend({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String sendFlowId,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) {
    proposeCalls++;
    proposalStarted.complete();
    return proposalGate?.future ?? Future.value(_proposal());
  }

  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    discardCalls.add((proposalId, sendFlowId));
  }

  @override
  Future<ExecuteProposalResult> crateApiSyncExecuteProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required BigInt proposalId,
    required String sendFlowId,
    required List<int> mnemonicBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    executeCalls++;
    return const ExecuteProposalResult(
      txids: 'unexpected-signature',
      status: 'broadcasted',
      broadcastedCount: 1,
      totalCount: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
