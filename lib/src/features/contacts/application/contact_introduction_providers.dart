import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/contact_introduction_gateway.dart';
import '../data/contact_introduction_repository.dart';
import '../domain/contact_models.dart';
import 'contact_exchange_controller.dart';
import 'contact_introduction_coordinator.dart';
import 'contact_lifecycle.dart';
import 'contact_mutation_gate.dart';

final contactIntroductionRepositoryProvider =
    Provider<ContactIntroductionRepository>(
      (ref) => SecureContactIntroductionRepository(),
    );
final contactIntroductionGatewayProvider = Provider<ContactIntroductionGateway>(
  (ref) => RustContactIntroductionGateway(),
);

// Lazily created behind the same unlocked software test-network scope as direct
// exchange. The next UI slice can use this without inventing another authority.
final contactIntroductionCoordinatorProvider =
    Provider<ContactIntroductionCoordinator>((ref) {
      final coordinator = ContactIntroductionCoordinator(
        scope: () => ref.read(contactScopeProvider),
        repository: ref.read(contactIntroductionRepositoryProvider),
        directRepository: ref.read(contactRepositoryProvider),
        gateway: ref.read(contactIntroductionGatewayProvider),
        directGateway: ref.read(contactGatewayProvider),
        clock: ref.read(contactClockProvider),
      );
      ref.listen(contactScopeProvider, (previous, next) {
        if (previous != next) coordinator.invalidate();
      });
      void bookChanged(ContactScope scope, Object? source) {
        if (scope == ref.read(contactScopeProvider) &&
            !identical(source, coordinator)) {
          coordinator.pauseReview();
        }
      }

      ContactMutationGate.listeners.add(bookChanged);
      ContactLifecycle.listeners.add(coordinator.invalidate);
      final lifecycle = AppLifecycleListener(
        onHide: coordinator.pauseReview,
        onPause: coordinator.pauseReview,
      );
      ref.onDispose(() {
        lifecycle.dispose();
        ContactLifecycle.listeners.remove(coordinator.invalidate);
        ContactMutationGate.listeners.remove(bookChanged);
        coordinator.dispose();
      });
      return coordinator;
    });
