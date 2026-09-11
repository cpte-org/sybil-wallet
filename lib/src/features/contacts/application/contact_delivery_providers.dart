import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/app_secure_store.dart';
import '../../../providers/network_privacy_provider.dart';
import '../data/contact_delivery_repository.dart';
import '../data/contact_binding_repository.dart';
import '../data/simplex_native_transport.dart';
import '../domain/contact_models.dart';
import 'contact_delivery_coordinator.dart';
import 'contact_binding_coordinator.dart';
import 'contact_exchange_controller.dart';
import 'contact_lifecycle.dart';
import 'contact_mutation_gate.dart';

// Direct networking is enabled only after wallet routing has settled to off.
// Native SOCKS integration must be qualified before enabling the Tor lane.
final contactDeliveryScopeProvider = Provider<ContactScope?>((ref) {
  final current = ref.watch(contactScopeProvider);
  final privacy = ref.watch(networkPrivacyProvider);
  if (!Platform.isLinux ||
      privacy.torEnabled ||
      privacy.targetTorEnabled == true ||
      privacy.status != NetworkPrivacyConnectionStatus.off) {
    return null;
  }
  return current;
});

final contactBindingCoordinatorProvider = Provider.autoDispose((ref) {
  final coordinator = ContactBindingCoordinator(
    scope: () => ref.read(contactDeliveryScopeProvider),
    repository: SecureContactBindingRepository(),
    contacts: ref.read(contactRepositoryProvider),
  );
  ref.listen(contactDeliveryScopeProvider, (_, _) => coordinator.invalidate());
  ContactLifecycle.listeners.add(coordinator.invalidate);
  final lifecycle = AppLifecycleListener(
    onHide: coordinator.invalidate,
    onPause: coordinator.invalidate,
  );
  ref.onDispose(() {
    coordinator.invalidate();
    lifecycle.dispose();
    ContactLifecycle.listeners.remove(coordinator.invalidate);
  });
  return coordinator;
});

final contactDeliveryCoordinatorProvider = Provider.autoDispose((ref) {
  final bindings = ref.watch(contactBindingCoordinatorProvider);
  final coordinator = ContactDeliveryCoordinator(
    scope: () => ref.read(contactDeliveryScopeProvider),
    repository: SecureContactDeliveryRepository(),
    validateBinding: bindings.checkForSend,
  );
  ref.listen(contactDeliveryScopeProvider, (_, _) => coordinator.invalidate());
  ContactLifecycle.listeners.add(coordinator.invalidate);
  final lifecycle = AppLifecycleListener(
    onHide: coordinator.invalidate,
    onPause: coordinator.invalidate,
  );
  ref.onDispose(() {
    coordinator.invalidate();
    lifecycle.dispose();
    ContactLifecycle.listeners.remove(coordinator.invalidate);
  });
  return coordinator;
});

final simplexNativeTransportProvider = FutureProvider.autoDispose<SimplexNativeTransport>((
  ref,
) async {
  final scope = ref.watch(contactDeliveryScopeProvider);
  if (scope == null) {
    throw const ContactFailure(
      'Private delivery needs an unlocked test account and a supported network route.',
    );
  }
  const hostOverride = String.fromEnvironment('SIMPLEX_NATIVE_HOST');
  const libraryOverride = String.fromEnvironment('SIMPLEX_NATIVE_LIBRARY');
  final bundle = File(Platform.resolvedExecutable).parent.path;
  final host = hostOverride.isEmpty ? '$bundle/simplex-host' : hostOverride;
  final library = libraryOverride.isEmpty
      ? '$bundle/lib/simplex/libsimplex.so'
      : libraryOverride;
  if (!File(host).existsSync() || !File(library).existsSync()) {
    throw const ContactFailure(
      'The SimpleX native component is not installed in this experimental build. Manual exchange is available.',
    );
  }
  var disposed = false;
  late final SimplexNativeTransport session;
  session = SimplexNativeTransport(
    scope: scope,
    networkAllowed: () =>
        !disposed && ref.read(contactDeliveryScopeProvider) == scope,
  );
  void stop() {
    disposed = true;
    session.close();
  }

  final lifecycle = AppLifecycleListener(onHide: stop, onPause: stop);
  ContactLifecycle.listeners.add(stop);
  ref.onDispose(() {
    stop();
    lifecycle.dispose();
    ContactLifecycle.listeners.remove(stop);
  });
  void check() {
    if (disposed || ref.read(contactDeliveryScopeProvider) != scope) {
      throw const ContactFailure(
        'Private delivery was paused. Reopen it after unlocking.',
      );
    }
  }

  try {
    return await ContactMutationGate.run(scope, () async {
      check();
      final dir = await getApplicationSupportDirectory();
      check();
      final folder = Directory(
        '${dir.path}/contact-delivery/${Uri.encodeComponent(scope.accountUuid)}/${scope.network}',
      );
      await folder.create(recursive: true);
      check();
      final database = '${folder.path}/simplex';
      final store = AppSecureStore.instance,
          keyName = '${scope.storagePrefix}simplex_database_key';
      var key = await store.readSecretStringWithOptions(
        keyName,
        requireUnlockedSession: true,
        rejectInvalidEnvelope: true,
      );
      check();
      if (key == null) {
        if (await File('${database}_chat.db').exists() ||
            await File('${database}_agent.db').exists()) {
          throw const ContactFailure(
            'The delivery recovery key is missing. Restore your encrypted backup before reconnecting.',
          );
        }
        check();
        key = base64Url.encode(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        );
        await store.writeSecretString(keyName, key);
        check();
      }
      await session.open(
        hostPath: host,
        libraryPath: library,
        databasePath: database,
        databaseKey: key,
      );
      check();
      return session;
    });
  } catch (_) {
    stop();
    rethrow;
  }
});
