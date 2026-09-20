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
import '../data/simplex_embedded_host.dart';
import '../domain/contact_models.dart';
import 'contact_delivery_coordinator.dart';
import 'contact_binding_coordinator.dart';
import 'contact_delivery_preferences.dart';
import 'contact_exchange_controller.dart';
import 'contact_lifecycle.dart';
import 'contact_mutation_gate.dart';

({String host, String library}) _simplexPaths() {
  const hostOverride = String.fromEnvironment('SIMPLEX_NATIVE_HOST');
  const libraryOverride = String.fromEnvironment('SIMPLEX_NATIVE_LIBRARY');
  final bundle = File(Platform.resolvedExecutable).parent.path;
  return (
    host: hostOverride.isEmpty ? '$bundle/simplex-host' : hostOverride,
    library: libraryOverride.isEmpty
        ? '$bundle/lib/simplex/libsimplex.so'
        : libraryOverride,
  );
}

final androidSimplexAvailabilityProvider = FutureProvider<bool>(
  (ref) => AndroidSimplexHost.available(),
);

/// Installation availability only. This does not open storage or start network
/// activity; lock, lifecycle and privacy still gate every transport operation.
final contactDeliveryUnavailableReasonProvider = Provider<String?>((ref) {
  if (Platform.isAndroid) {
    final available = ref.watch(androidSimplexAvailabilityProvider);
    if (available.asData?.value == true) return null;
    return available.isLoading
        ? 'Checking the Android private delivery component.'
        : 'The SimpleX native component is not installed in this Android build. Exchange contact codes with QR or copy and paste.';
  }
  if (!Platform.isLinux) {
    return 'Private delivery is available only in supported Linux and Android builds. Manual exchange is available.';
  }
  final paths = _simplexPaths();
  if (!File(paths.host).existsSync() || !File(paths.library).existsSync()) {
    return 'The SimpleX native component is not installed in this Linux build. Manual exchange is available.';
  }
  return null;
});

// Direct networking is enabled only after wallet routing has settled to off.
// Native SOCKS integration must be qualified before enabling the Tor lane.
final contactDeliveryForegroundProvider = Provider.autoDispose<bool>((ref) {
  final listener = AppLifecycleListener(
    onStateChange: (_) => ref.invalidateSelf(),
  );
  ref.onDispose(listener.dispose);
  final state = WidgetsBinding.instance.lifecycleState;
  return state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;
});

/// Why private delivery is usable or not right now. Presentation-only: every
/// transport operation is still gated by [contactDeliveryScopeProvider].
sealed class SimplexDeliveryStatus {
  const SimplexDeliveryStatus();

  String get message => switch (this) {
    SimplexDeliveryChecking() => 'Checking private delivery availability.',
    SimplexDeliveryPreferenceUnavailable() =>
      'Could not read your private delivery setting. Retry in Contact options.',
    SimplexDeliveryTurnedOff() =>
      'Private delivery is turned off. Turn it on in Contact options.',
    SimplexDeliveryNotInstalled(:final reason) => reason,
    SimplexDeliveryTorBlocked() =>
      'Private delivery is unavailable while Tor is enabled.',
    SimplexDeliveryForegroundOnly() =>
      'Private delivery is paused while the wallet is in the background.',
    SimplexDeliveryReady() => '',
  };
}

class SimplexDeliveryChecking extends SimplexDeliveryStatus {
  const SimplexDeliveryChecking();
}

class SimplexDeliveryTurnedOff extends SimplexDeliveryStatus {
  const SimplexDeliveryTurnedOff();
}

class SimplexDeliveryPreferenceUnavailable extends SimplexDeliveryStatus {
  const SimplexDeliveryPreferenceUnavailable();
}

class SimplexDeliveryNotInstalled extends SimplexDeliveryStatus {
  const SimplexDeliveryNotInstalled(this.reason);

  final String reason;
}

class SimplexDeliveryTorBlocked extends SimplexDeliveryStatus {
  const SimplexDeliveryTorBlocked();
}

class SimplexDeliveryForegroundOnly extends SimplexDeliveryStatus {
  const SimplexDeliveryForegroundOnly();
}

class SimplexDeliveryReady extends SimplexDeliveryStatus {
  const SimplexDeliveryReady();
}

final simplexDeliveryStatusProvider = Provider<SimplexDeliveryStatus>((ref) {
  final preference = ref.watch(simplexDeliveryEnabledProvider);
  if (preference.isLoading) return const SimplexDeliveryChecking();
  if (preference.hasError) {
    return const SimplexDeliveryPreferenceUnavailable();
  }
  if (preference.asData?.value != true) {
    return const SimplexDeliveryTurnedOff();
  }
  final installation = ref.watch(contactDeliveryUnavailableReasonProvider);
  if (installation != null) return SimplexDeliveryNotInstalled(installation);
  final privacy = ref.watch(networkPrivacyProvider);
  if (privacy.torEnabled ||
      privacy.targetTorEnabled == true ||
      privacy.status != NetworkPrivacyConnectionStatus.off) {
    return const SimplexDeliveryTorBlocked();
  }
  if (!ref.watch(contactDeliveryForegroundProvider)) {
    return const SimplexDeliveryForegroundOnly();
  }
  return const SimplexDeliveryReady();
});

/// Delivery transport is allowed only while private delivery is ready and the
/// contact scope itself is available.
final contactDeliveryScopeProvider = Provider<ContactScope?>((ref) {
  final status = ref.watch(simplexDeliveryStatusProvider);
  if (status is! SimplexDeliveryReady) return null;
  return ref.watch(contactScopeProvider);
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
  final coordinator = ref.watch(contactDeliveryCoordinatorProvider);
  final unavailable = ref.watch(contactDeliveryUnavailableReasonProvider);
  if (unavailable != null) throw ContactFailure(unavailable);
  if (scope == null) {
    throw const ContactFailure(
      'Private delivery needs an unlocked software account and a supported network route.',
    );
  }
  final paths = _simplexPaths();
  var disposed = false;
  late final SimplexNativeTransport session;
  session = SimplexNativeTransport(
    scope: scope,
    embeddedHost: Platform.isAndroid ? AndroidSimplexHost() : null,
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
            'The private delivery database key is missing. A contact backup cannot restore SimpleX connections. Manual contact code exchange is still available.',
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
        hostPath: paths.host,
        libraryPath: paths.library,
        databasePath: database,
        databaseKey: key,
      );
      check();
      session.startReceiving(coordinator);
      return session;
    });
  } catch (_) {
    stop();
    rethrow;
  }
});

/// Watch while displaying the private inbox to reload its persisted journal
/// and connection list after a foreground reconciliation pass. This starts no
/// session unless the caller explicitly watches private delivery.
final contactDeliveryRefreshProvider = StreamProvider.autoDispose<int>((
  ref,
) async* {
  final transport = await ref.watch(simplexNativeTransportProvider.future);
  yield* transport.refreshes;
});
