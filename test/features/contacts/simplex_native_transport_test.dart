import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/contacts/application/contact_delivery_coordinator.dart';
import 'package:zcash_wallet/src/features/contacts/data/contact_delivery_repository.dart';
import 'package:zcash_wallet/src/features/contacts/data/simplex_native_transport.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_delivery.dart';
import 'package:zcash_wallet/src/features/contacts/domain/contact_models.dart';

class _Journal implements ContactDeliveryRepository {
  String? raw;
  @override
  Future<ContactDeliveryJournal> load(ContactScope scope) async => raw == null
      ? ContactDeliveryJournal()
      : ContactDeliveryJournal.decode(raw!, scope);
  @override
  Future<void> save(ContactScope scope, ContactDeliveryJournal journal) async {
    raw = journal.encode(scope);
  }
}

class _DelayedHistoryTransport extends SimplexNativeTransport {
  _DelayedHistoryTransport()
    : super(
        scope: const ContactScope(
          accountUuid: 'disposable',
          network: 'regtest',
        ),
        networkAllowed: () => true,
      );
  final pending = Completer<void>();
  int reads = 0;
  @override
  Future<List<({String id, String label})>> peers() async {
    reads++;
    await pending.future;
    return [];
  }
}

void main() {
  test(
    'manual and foreground reconciliation share one in-flight scan',
    () async {
      final transport = _DelayedHistoryTransport();
      final coordinator = ContactDeliveryCoordinator(
        scope: () => transport.scope,
        repository: _Journal(),
      );
      final first = transport.reconcile(coordinator);
      final second = transport.reconcile(coordinator);
      expect(identical(first, second), isTrue);
      expect(transport.reads, 1);
      transport.pending.complete();
      await Future.wait([first, second]);
      await transport.reconcile(coordinator);
      expect(transport.reads, 2);
      transport.close();
    },
  );
  test(
    'carrier accepts only bounded incoming direct packets for this network',
    () {
      Map<String, dynamic> carrier({
        String direction = 'directRcv',
        String network = 'regtest',
        String packet = 'public packet',
        bool extra = false,
      }) => {
        'chatDir': {'type': direction},
        'content': {
          'type': 'rcvMsgContent',
          'msgContent': {
            'type': 'text',
            'text': jsonEncode({
              'domain': 'zcash-contact/transport',
              'network': network,
              'id': 'abcdefghijklmnopqrstuvwx',
              'packet': packet,
              if (extra) 'unexpected': true,
            }),
          },
        },
      };
      expect(incomingPacket(carrier(), 'regtest')?.packet, 'public packet');
      for (final invalid in [
        carrier(direction: 'directSnd'),
        carrier(direction: 'groupRcv'),
        carrier(network: 'testnet'),
        carrier(packet: 'a' * (contactDeliveryMaxPacketBytes + 1)),
        carrier(extra: true),
        <String, dynamic>{},
      ]) {
        expect(incomingPacket(invalid, 'regtest'), isNull);
      }
    },
  );
  final host = Platform.environment['SIMPLEX_NATIVE_HOST'];
  final lib = Platform.environment['SIMPLEX_NATIVE_LIBRARY'];
  test(
    'native encrypted profiles connect and carry a packet without TCP API',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'anomaly-native-wallet-',
      );
      var allowed = true;
      final a = SimplexNativeTransport(
        scope: const ContactScope(
          accountUuid: 'disposable-a',
          network: 'regtest',
        ),
        networkAllowed: () => allowed,
      );
      var b = SimplexNativeTransport(
        scope: const ContactScope(
          accountUuid: 'disposable-b',
          network: 'regtest',
        ),
        networkAllowed: () => allowed,
      );
      String key() => base64Url.encode(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      );
      final bKey = key();
      try {
        await a.open(
          hostPath: host!,
          libraryPath: lib!,
          databasePath: '${dir.path}/a',
          databaseKey: key(),
        );
        await b.open(
          hostPath: host,
          libraryPath: lib,
          databasePath: '${dir.path}/b',
          databaseKey: bKey,
        );
        final link = await a.createInvitation();
        await b.connect(link);
        Future<Map<String, dynamic>> connected(SimplexNativeTransport t) async {
          final end = DateTime.now().add(const Duration(seconds: 35));
          while (DateTime.now().isBefore(end)) {
            final event = await t.poll();
            if (event['type'] == 'contactConnected') return event;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          throw StateError('connection timeout');
        }

        final peers = await Future.wait([connected(a), connected(b)]);
        final id = (peers.first['contact'] as Map)['contactId'].toString();
        final bId = (peers.last['contact'] as Map)['contactId'].toString();
        final code = await a.securityCode(id);
        expect(await b.securityCode(bId), code);
        await a.submit(
          id,
          'abcdefghijklmnopqrstuvwx',
          'PUBLIC DISPOSABLE TEST PACKET',
        );
        final end = DateTime.now().add(const Duration(seconds: 20));
        var received = false;
        while (DateTime.now().isBefore(end)) {
          final event = await b.poll();
          if (event['type'] == 'newChatItems' &&
              jsonEncode(event).contains('PUBLIC DISPOSABLE TEST PACKET')) {
            received = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(received, true);
        // Events have been consumed; reopen the encrypted DB and recover from
        // native history, as the wallet must do after its process is stopped.
        final bScope = b.scope;
        b.close();
        b = SimplexNativeTransport(
          scope: bScope,
          networkAllowed: () => allowed,
        );
        await b.open(
          hostPath: host,
          libraryPath: lib,
          databasePath: '${dir.path}/b',
          databaseKey: bKey,
        );
        final coordinator = ContactDeliveryCoordinator(
          scope: () => b.scope,
          repository: _Journal(),
        );
        expect(await b.securityCode(bId), code);
        await b.reconcile(coordinator);
        expect(
          (await coordinator.overview()).single.packet,
          'PUBLIC DISPOSABLE TEST PACKET',
        );
        await b.reconcile(coordinator);
        expect(await coordinator.overview(), hasLength(1));
        allowed = false;
        await expectLater(
          a.submit(id, 'zyxwvutsrqponmlkjihgfedcb', 'blocked'),
          throwsA(isA<ContactFailure>()),
        );
      } finally {
        a.close();
        b.close();
      }
    },
    skip: host == null || lib == null
        ? 'Set explicit native host/library paths for the live disposable test.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
