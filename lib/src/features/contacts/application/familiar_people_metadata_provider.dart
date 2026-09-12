import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/familiar_people_metadata_repository.dart';
import '../domain/contact_models.dart';
import 'contact_exchange_controller.dart';
import 'contact_lifecycle.dart';

final familiarPeopleMetadataRepositoryProvider =
    Provider<FamiliarPeopleMetadataRepository>(
      (ref) => FamiliarPeopleMetadataRepository(),
    );

final familiarPeopleMetadataProvider =
    AsyncNotifierProvider<
      FamiliarPeopleMetadataController,
      Map<String, FamiliarPersonMetadata>
    >(FamiliarPeopleMetadataController.new);

class FamiliarPeopleMetadataController
    extends AsyncNotifier<Map<String, FamiliarPersonMetadata>> {
  int _epoch = 0;
  bool _saving = false;

  @override
  Future<Map<String, FamiliarPersonMetadata>> build() async {
    final epoch = ++_epoch;
    _saving = false;
    final scope = ref.watch(contactScopeProvider);
    void onLifecycleChange() => ref.invalidateSelf();
    ContactLifecycle.listeners.add(onLifecycleChange);
    ref.onDispose(() {
      ContactLifecycle.listeners.remove(onLifecycleChange);
      if (epoch == _epoch) _epoch++;
    });
    if (scope == null || !ContactLifecycle.allowed(scope.accountUuid)) {
      return const {};
    }
    return ContactLifecycle.run(scope.accountUuid, () async {
      final result = await ref
          .read(familiarPeopleMetadataRepositoryProvider)
          .load(scope);
      _check(scope, epoch);
      return result;
    });
  }

  void _check(ContactScope scope, int epoch) {
    if (epoch != _epoch ||
        scope != ref.read(contactScopeProvider) ||
        !ContactLifecycle.allowed(scope.accountUuid)) {
      throw const ContactFailure(
        'The contact session changed. Open this person again.',
      );
    }
  }

  Future<void> save(
    VerifiedContact contact,
    FamiliarPersonMetadata metadata,
  ) async {
    final scope = ref.read(contactScopeProvider);
    final previous = state.asData?.value;
    if (scope == null || previous == null || _saving) {
      throw const ContactFailure('Wait for private contact details to load.');
    }
    final epoch = _epoch;
    void check() {
      _check(scope, epoch);
      final current = ref.read(contactExchangeProvider).contacts;
      if (!current.any(
        (candidate) =>
            candidate.id == contact.id &&
            candidate.identity == contact.identity,
      )) {
        throw const ContactFailure('This person changed. Open them again.');
      }
    }

    metadata.validate();
    check();
    final next = Map<String, FamiliarPersonMetadata>.unmodifiable({
      ...previous,
      contact.identity: metadata,
    });
    _saving = true;
    try {
      await ContactLifecycle.run(scope.accountUuid, () async {
        check();
        await ref
            .read(familiarPeopleMetadataRepositoryProvider)
            .save(scope, next, beforeWrite: check);
        check();
      });
      state = AsyncData(next);
    } finally {
      if (epoch == _epoch) _saving = false;
    }
  }
}
