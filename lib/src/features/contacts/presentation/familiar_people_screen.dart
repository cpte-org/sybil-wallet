import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/familiar_widgets.dart';
import '../../send/models/send_prefill_args.dart';
import '../application/contact_exchange_controller.dart';
import 'contact_availability.dart';
import '../application/familiar_people_metadata_provider.dart';
import '../data/familiar_people_metadata_repository.dart';
import '../domain/contact_models.dart';
import '../domain/familiar_person.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../../providers/app_security_provider.dart';
import 'familiar_saved_person_detail.dart';

/// People is a presentation of the real contact book. All payment selections
/// retain the controller's authenticated, account-scoped recipient snapshot.
class FamiliarPeopleScreen extends ConsumerWidget {
  const FamiliarPeopleScreen({super.key, this.contactId});

  final String? contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(contactScopeProvider);
    final book = ref.watch(addressBookProvider);
    final unlocked = ref.watch(appSecurityProvider).isUnlocked;
    final state = ref.watch(contactExchangeProvider);
    final metadata = ref.watch(familiarPeopleMetadataProvider);
    final controller = ref.read(contactExchangeProvider.notifier);
    final available = ref.watch(contactExchangeAvailableProvider);

    void open(String route) {
      controller.cancelTransient();
      context.push(route);
    }

    Future<void> rename(VerifiedContact person, String name) async {
      await controller.renameContact(person.id, name);
      if (scope != ref.read(contactScopeProvider)) {
        throw const ContactFailure('The contact session changed.');
      }
      final updated = ref.read(contactExchangeProvider);
      if (updated.error != null) throw ContactFailure(updated.error!);
      if (!updated.contacts.any(
        (contact) => contact.id == person.id && contact.label == name.trim(),
      )) {
        throw const ContactFailure('The name was not saved. Try again.');
      }
    }

    final content = FamiliarPeopleView(
      // Discard private editing buffers when account, network or lock changes.
      key: ValueKey(scope),
      contactId: contactId,
      savedContacts: unlocked
          ? book.value?.contacts
                    .where((c) => c.network == AddressBookNetwork.zcash)
                    .toList() ??
                const []
          : const [],
      savedLoading: book.isLoading,
      savedError: book.hasError
          ? 'Saved people could not be opened. Reload to try again.'
          : null,
      isLocked: !unlocked,
      onSavedPay: (person) => context.push(
        '/send',
        extra: SendPrefillArgs(
          id: 'saved-${person.id}-${DateTime.now().microsecondsSinceEpoch}',
          source: 'address-book',
          address: person.address,
          label: person.label,
        ),
      ),
      onSavedEdit: (person) => context.push('/people/add', extra: person.id),
      onSavedPin: (person) => ref
          .read(addressBookProvider.notifier)
          .updateContact(
            person.id,
            label: person.label,
            network: person.network,
            address: person.address,
            profilePictureId: person.profilePictureId,
            pinned: !person.pinned,
          ),
      state: available
          ? state
          : ContactExchangeState(
              unavailableReason:
                  ref.watch(contactUnavailableMessageProvider) ??
                  state.unavailableReason ??
                  'People is available for enabled, unlocked software accounts on testnet or regtest.',
            ),
      metadata: metadata.asData?.value ?? const {},
      metadataReady: metadata.asData != null && scope != null,
      metadataError: metadata.hasError
          ? 'Private notes and pins could not be opened. Reload to try again.'
          : null,
      onReload: () async {
        ref.invalidate(familiarPeopleMetadataProvider);
        ref.invalidate(addressBookProvider);
        await controller.reload();
      },
      onAdd: () => context.push('/people/add'),
      onBackup: () => open('/contacts/backup'),
      onRename: rename,
      onSaveMetadata: (person, details) => ref
          .read(familiarPeopleMetadataProvider.notifier)
          .save(person, details),
      onCheckAddress: (person) async {
        await controller.startRequest(contactId: person.id);
        if (!context.mounted || scope != ref.read(contactScopeProvider)) return;
        if (ref.read(contactExchangeProvider).request?.contactId == person.id) {
          context.push('/contacts/exchange');
        }
      },
      onSuspend: (person) => controller.suspendContact(person.id),
      onPay: (person) {
        try {
          final recipient = controller.recipientFor(person.id);
          context.push(
            '/send',
            extra: SendPrefillArgs(
              id: 'contact-${DateTime.now().microsecondsSinceEpoch}',
              source: 'contact',
              address: recipient.address,
              label: recipient.label,
              contactRecipient: recipient,
            ),
          );
        } catch (_) {
          showAppToast(
            context,
            'This contact changed. Reload and review it before sending.',
          );
        }
      },
    );
    if (kAppFormFactor == AppFormFactor.mobile) {
      // The primary mobile route provides AppMobileShell and its tab bar.
      return SafeArea(bottom: false, child: content);
    }
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(padding: EdgeInsets.zero, child: content),
    );
  }
}

enum _PeopleFilter { everyone, pinned, needsCheck }

/// Deterministic content used by the wallet adapter and layout/behavior tests.
class FamiliarPeopleView extends StatefulWidget {
  const FamiliarPeopleView({
    super.key,
    required this.state,
    this.contactId,
    this.metadata = const {},
    this.savedContacts = const [],
    this.savedLoading = false,
    this.savedError,
    this.isLocked = false,
    this.onSavedPay,
    this.onSavedEdit,
    this.onSavedPin,
    this.metadataReady = true,
    this.metadataError,
    this.onReload,
    this.onAdd,
    this.onBackup,
    this.onPay,
    this.onRename,
    this.onSaveMetadata,
    this.onCheckAddress,
    this.onSuspend,
  });

  final List<AddressBookContact> savedContacts;
  final bool savedLoading, isLocked;
  final String? savedError;
  final ValueChanged<AddressBookContact>? onSavedPay, onSavedEdit;
  final Future<void> Function(AddressBookContact)? onSavedPin;
  final ContactExchangeState state;
  final String? contactId, metadataError;
  final Map<String, FamiliarPersonMetadata> metadata;
  final bool metadataReady;
  final Future<void> Function()? onReload;
  final VoidCallback? onAdd, onBackup;
  final ValueChanged<VerifiedContact>? onPay;
  final Future<void> Function(VerifiedContact, String)? onRename;
  final Future<void> Function(VerifiedContact, FamiliarPersonMetadata)?
  onSaveMetadata;
  final Future<void> Function(VerifiedContact)? onCheckAddress, onSuspend;

  @override
  State<FamiliarPeopleView> createState() => _FamiliarPeopleViewState();
}

class _FamiliarPeopleViewState extends State<FamiliarPeopleView> {
  final _search = TextEditingController();
  _PeopleFilter _filter = _PeopleFilter.everyone;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.contactId;
  }

  @override
  void didUpdateWidget(FamiliarPeopleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contactId != widget.contactId) {
      _selected = widget.contactId;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  FamiliarPersonMetadata _details(VerifiedContact person) =>
      widget.metadata[person.identity] ?? const FamiliarPersonMetadata();

  bool get _ready =>
      widget.state.available && !widget.state.loading && !widget.state.busy;

  @override
  Widget build(BuildContext context) {
    final palette = FamiliarPalette.of(context);
    final people = [
      if (widget.state.available)
        ...widget.state.contacts.map(FamiliarPerson.connected),
      ...widget.savedContacts.map(FamiliarPerson.saved),
    ];
    final selected = people
        .where((person) => person.id == _selected)
        .firstOrNull;
    final query = _search.text.trim().toLowerCase();
    bool pinned(FamiliarPerson p) =>
        p.saved?.pinned ?? _details(p.connected!).pinned;
    String note(FamiliarPerson p) =>
        p.saved?.note ?? _details(p.connected!).notes;
    final filtered =
        people
            .where(
              (person) =>
                  (person.label.toLowerCase().contains(query) ||
                      note(person).toLowerCase().contains(query)) &&
                  switch (_filter) {
                    _PeopleFilter.everyone => true,
                    _PeopleFilter.pinned => pinned(person),
                    _PeopleFilter.needsCheck =>
                      person.connected?.status == ContactTrustStatus.restored,
                  },
            )
            .toList()
          ..sort((a, b) {
            final order = (pinned(b) ? 1 : 0) - (pinned(a) ? 1 : 0);
            return order != 0
                ? order
                : a.label.toLowerCase().compareTo(b.label.toLowerCase());
          });

    return ColoredBox(
      color: palette.paper,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 600;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              narrow ? 20 : 40,
              narrow ? 28 : 40,
              narrow ? 20 : 40,
              kAppFormFactor == AppFormFactor.mobile ? 120 : 40,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: selected == null ? 1120 : 660,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (selected == null) ...[
                      const FamiliarPageHeader(
                        title: 'People, in your words.',
                        eyebrow: 'Your private address book',
                        subtitle: 'A name you know. A person you chose.',
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _PeopleButton(
                            label: 'Add someone',
                            icon: Icons.add,
                            primary: true,
                            onPressed: !widget.isLocked ? widget.onAdd : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _selected = null),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('All people'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (widget.isLocked)
                      const _PeopleNotice(
                        title: 'Unlock your wallet',
                        body: 'Your people will be here when you return.',
                      ),
                    if (widget.savedError != null)
                      _PeopleNotice(
                        title: 'Saved people need attention',
                        body: widget.savedError!,
                      ),
                    if (widget.state.loading || widget.savedLoading) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 20),
                      const Text('Opening your people…'),
                    ],
                    if (widget.state.error != null) ...[
                      _PeopleNotice(
                        title: 'Contact action needs attention',
                        body: widget.state.error!,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (widget.metadataError != null) ...[
                      _PeopleNotice(
                        title: 'Private details are unavailable',
                        body: widget.metadataError!,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (selected?.saved != null)
                      FamiliarSavedPersonDetail(
                        person: selected!.saved!,
                        onPay: widget.onSavedPay,
                        onEdit: widget.onSavedEdit,
                        onPin: widget.onSavedPin,
                      )
                    else if (selected?.connected != null)
                      _PersonDetail(
                        key: ValueKey(selected!.avatarIdentity),
                        person: selected.connected!,
                        metadata: _details(selected.connected!),
                        ready: _ready,
                        metadataReady: widget.metadataReady,
                        onPay: widget.onPay,
                        onRename: widget.onRename,
                        onSaveMetadata: widget.onSaveMetadata,
                        onCheckAddress: widget.onCheckAddress,
                        onSuspend: widget.onSuspend,
                        onAdd: widget.onAdd,
                      )
                    else if (!widget.isLocked) ...[
                      TextField(
                        key: const Key('people-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Find someone you know',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: palette.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: palette.line),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (filter, label) in [
                            (_PeopleFilter.everyone, 'Everyone'),
                            (_PeopleFilter.pinned, 'Pinned'),
                            (_PeopleFilter.needsCheck, 'Needs a check'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _filter == filter,
                              selectedColor: palette.lime,
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      if (filtered.isEmpty &&
                          !widget.savedLoading &&
                          !widget.state.loading)
                        FamiliarCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 38,
                                color: palette.forest,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                people.isEmpty
                                    ? 'Start with someone you know.'
                                    : 'No people match this view.',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                people.isEmpty
                                    ? 'Save a name and address, or connect through an invitation.'
                                    : _filter == _PeopleFilter.pinned
                                    ? 'Pin someone from their contact card, or try another search.'
                                    : 'Try another name or filter.',
                                style: TextStyle(color: palette.muted),
                              ),
                            ],
                          ),
                        )
                      else if (filtered.isNotEmpty)
                        FamiliarCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (
                                var index = 0;
                                index < filtered.length;
                                index++
                              ) ...[
                                if (index > 0)
                                  Divider(height: 1, color: palette.line),
                                _PersonRow(
                                  person: filtered[index],
                                  metadata: filtered[index].saved == null
                                      ? _details(filtered[index].connected!)
                                      : FamiliarPersonMetadata(
                                          notes: filtered[index].saved!.note,
                                          pinned: filtered[index].saved!.pinned,
                                        ),
                                  narrow: narrow,
                                  onPressed: () => setState(
                                    () => _selected = filtered[index].id,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 6,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _ready ? widget.onBackup : null,
                          icon: const Icon(Icons.lock_outline, size: 18),
                          label: const Text('Connection backup'),
                        ),
                        TextButton.icon(
                          onPressed: widget.state.busy ? null : widget.onReload,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Reload'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.metadata,
    required this.narrow,
    required this.onPressed,
  });

  final FamiliarPerson person;
  final FamiliarPersonMetadata metadata;
  final bool narrow;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = FamiliarPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('person-${person.id}'),
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.all(narrow ? 16 : 22),
          child: Row(
            children: [
              FamiliarAvatar(
                label: person.label,
                identity: person.avatarIdentity,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metadata.notes.isEmpty
                          ? person.saved != null
                                ? 'Saved address'
                                : 'Connected privately'
                          : metadata.notes,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted),
                    ),
                    if (narrow &&
                        person.connected != null &&
                        !person.canPay) ...[
                      const SizedBox(height: 8),
                      _StatusBadge(status: person.connected!.status),
                    ],
                  ],
                ),
              ),
              if (metadata.pinned)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.star_rounded,
                    semanticLabel: 'Pinned',
                    color: palette.forest,
                    size: 20,
                  ),
                ),
              if (!narrow && person.connected != null && !person.canPay) ...[
                const SizedBox(width: 16),
                _StatusBadge(status: person.connected!.status),
              ],
              const SizedBox(width: 12),
              const Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonDetail extends StatefulWidget {
  const _PersonDetail({
    super.key,
    required this.person,
    required this.metadata,
    required this.ready,
    required this.metadataReady,
    this.onPay,
    this.onRename,
    this.onSaveMetadata,
    this.onCheckAddress,
    this.onSuspend,
    this.onAdd,
  });

  final VerifiedContact person;
  final FamiliarPersonMetadata metadata;
  final bool ready, metadataReady;
  final ValueChanged<VerifiedContact>? onPay;
  final Future<void> Function(VerifiedContact, String)? onRename;
  final Future<void> Function(VerifiedContact, FamiliarPersonMetadata)?
  onSaveMetadata;
  final Future<void> Function(VerifiedContact)? onCheckAddress, onSuspend;
  final VoidCallback? onAdd;

  @override
  State<_PersonDetail> createState() => _PersonDetailState();
}

class _PersonDetailState extends State<_PersonDetail> {
  final _name = TextEditingController(), _notes = TextEditingController();
  bool _editingName = false, _editingNotes = false, _working = false;
  bool _confirmSuspend = false;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() operation,
    String success, {
    bool closeEditors = true,
  }) async {
    if (_working) return;
    setState(() {
      _working = true;
      _notice = null;
    });
    try {
      await operation();
      if (mounted) {
        setState(() {
          _notice = success;
          if (closeEditors) {
            _editingName = false;
            _editingNotes = false;
            _name.clear();
            _notes.clear();
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _notice = error is ContactFailure
              ? error.message
              : 'Private details could not be saved. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final palette = FamiliarPalette.of(context);
    final ready = widget.ready && !_working;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              FamiliarAvatar(
                label: person.label,
                identity: person.identity,
                size: 96,
              ),
              const SizedBox(height: 20),
              Text(
                'Your name for this person',
                style: TextStyle(color: palette.muted),
              ),
              const SizedBox(height: 8),
              Text(
                person.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              _StatusBadge(status: person.status),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (person.canPay)
                    _PeopleButton(
                      label: 'Send money',
                      icon: Icons.north_east,
                      primary: true,
                      onPressed: ready && widget.onPay != null
                          ? () => widget.onPay!(person)
                          : null,
                    )
                  else if (person.canRequestUpdate)
                    _PeopleButton(
                      label: 'Check current address',
                      icon: Icons.verified_user_outlined,
                      primary: true,
                      onPressed: ready && widget.onCheckAddress != null
                          ? () => widget.onCheckAddress!(person)
                          : null,
                    )
                  else
                    _PeopleButton(
                      label: 'Add a replacement',
                      icon: Icons.person_add_outlined,
                      primary: true,
                      onPressed: ready ? widget.onAdd : null,
                    ),
                  _PeopleButton(
                    label: widget.metadata.pinned ? 'Unpin' : 'Pin',
                    icon: widget.metadata.pinned
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    onPressed:
                        ready &&
                            widget.metadataReady &&
                            widget.onSaveMetadata != null
                        ? () => _run(
                            () => widget.onSaveMetadata!(
                              person,
                              widget.metadata.copyWith(
                                pinned: !widget.metadata.pinned,
                              ),
                            ),
                            widget.metadata.pinned
                                ? 'Person unpinned.'
                                : 'Person pinned.',
                            closeEditors: false,
                          )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (!person.canPay) ...[
          _PeopleNotice(
            title: switch (person.status) {
              ContactTrustStatus.restored => 'Check before paying',
              ContactTrustStatus.suspended => 'Payments are paused',
              ContactTrustStatus.retired => 'This identity is retired',
              ContactTrustStatus.accepted => 'Ready for your review',
            },
            body: _statusDescription(person.status),
          ),
          const SizedBox(height: 20),
        ],
        if (_notice != null) ...[
          Text(_notice!, key: const Key('person-notice')),
          const SizedBox(height: 16),
        ],
        FamiliarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Private to you',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),

              if (_editingName) ...[
                TextField(
                  key: const Key('person-name'),
                  controller: _name,
                  maxLength: 20,
                  enabled: ready,
                  decoration: const InputDecoration(
                    labelText: 'Your name for them',
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _PeopleButton(
                      label: 'Save name',
                      onPressed: ready && widget.onRename != null
                          ? () => _run(
                              () => widget.onRename!(person, _name.text),
                              'Name saved.',
                            )
                          : null,
                    ),
                    TextButton(
                      onPressed: _working
                          ? null
                          : () => setState(() {
                              _editingName = false;
                              _name.clear();
                            }),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ] else
                _DetailAction(
                  title: 'Name',
                  subtitle: person.label,
                  onTap: ready && widget.onRename != null
                      ? () => setState(() {
                          _name.text = person.label;
                          _editingName = true;
                          _editingNotes = false;
                        })
                      : null,
                ),
              Divider(height: 32, color: palette.line),
              if (_editingNotes) ...[
                TextField(
                  key: const Key('person-notes'),
                  controller: _notes,
                  maxLength: 2000,
                  minLines: 3,
                  maxLines: 8,
                  enabled: ready,
                  decoration: const InputDecoration(labelText: 'Private note'),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _PeopleButton(
                      label: 'Save note',
                      onPressed:
                          ready &&
                              widget.metadataReady &&
                              widget.onSaveMetadata != null
                          ? () => _run(
                              () => widget.onSaveMetadata!(
                                person,
                                widget.metadata.copyWith(notes: _notes.text),
                              ),
                              'Note saved.',
                            )
                          : null,
                    ),
                    TextButton(
                      onPressed: _working
                          ? null
                          : () => setState(() {
                              _editingNotes = false;
                              _notes.clear();
                            }),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ] else
                _DetailAction(
                  title: 'Note',
                  subtitle: widget.metadata.notes.isEmpty
                      ? 'Add something you want to remember.'
                      : widget.metadata.notes,
                  onTap:
                      ready &&
                          widget.metadataReady &&
                          widget.onSaveMetadata != null
                      ? () => setState(() {
                          _notes.text = widget.metadata.notes;
                          _editingNotes = true;
                          _editingName = false;
                        })
                      : null,
                ),
              const SizedBox(height: 16),
              Text(
                'Notes and pins stay on this device. They are not included in the connection backup.',
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FamiliarCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ExpansionTile(
            title: const Text('Address and identity'),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            children: [
              _IdentityValue(label: 'Identity', value: person.identity),
              const SizedBox(height: 16),
              _IdentityValue(label: 'Receiving address', value: person.address),
              const SizedBox(height: 16),
              _IdentityValue(
                label: 'Address sequence',
                value: '${person.sequence}',
              ),
              if (person.canRequestUpdate) ...[
                const SizedBox(height: 16),
                _PeopleButton(
                  label: 'Request fresh details',
                  icon: Icons.refresh,
                  onPressed: ready && widget.onCheckAddress != null
                      ? () => widget.onCheckAddress!(person)
                      : null,
                ),
              ],
            ],
          ),
        ),
        if (person.canPay) ...[
          const SizedBox(height: 20),
          FamiliarCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ExpansionTile(
              title: const Text('Contact controls'),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
              children: [
                Text(
                  'Pause payments if you no longer trust this identity. An incoming message cannot undo a pause.',
                  style: TextStyle(color: palette.muted),
                ),
                const SizedBox(height: 12),
                if (_confirmSuspend) ...[
                  const Text('Pause payments for this person?'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      _PeopleButton(
                        label: 'Confirm pause',
                        onPressed: ready && widget.onSuspend != null
                            ? () => widget.onSuspend!(person)
                            : null,
                      ),
                      TextButton(
                        onPressed: ready
                            ? () => setState(() => _confirmSuspend = false)
                            : null,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ] else
                  _PeopleButton(
                    label: 'Pause payments',
                    onPressed: ready
                        ? () => setState(() => _confirmSuspend = true)
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String title, subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.edit_outlined, size: 18),
    onTap: onTap,
  );
}

class _IdentityValue extends StatelessWidget {
  const _IdentityValue({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: FamiliarPalette.of(context).muted)),
        const SizedBox(height: 5),
        SelectableText(
          value,
          style: const TextStyle(fontFamily: 'Geist Mono', fontSize: 12),
        ),
      ],
    ),
  );
}

class _PeopleButton extends StatelessWidget {
  const _PeopleButton({
    required this.label,
    this.icon,
    this.primary = false,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = FamiliarPalette.of(context);
    final style = FilledButton.styleFrom(
      backgroundColor: primary ? palette.forest : palette.surface,
      foregroundColor: primary ? palette.paper : palette.ink,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: primary ? palette.forest : palette.line),
      ),
    );
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }
}

class _PeopleNotice extends StatelessWidget {
  const _PeopleNotice({required this.title, required this.body});

  final String title, body;

  @override
  Widget build(BuildContext context) => FamiliarCard(
    color: FamiliarPalette.of(context).peach,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(body),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ContactTrustStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = FamiliarPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: switch (status) {
          ContactTrustStatus.accepted => palette.lime,
          ContactTrustStatus.restored => palette.peach,
          ContactTrustStatus.suspended => palette.lilac,
          ContactTrustStatus.retired => palette.line,
        },
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(switch (status) {
        ContactTrustStatus.accepted => 'Accepted',
        ContactTrustStatus.restored => 'Restored · needs a check',
        ContactTrustStatus.suspended => 'Suspended',
        ContactTrustStatus.retired => 'Retired',
      }, style: TextStyle(color: palette.ink, fontSize: 12)),
    );
  }
}

String _statusDescription(ContactTrustStatus status) => switch (status) {
  ContactTrustStatus.accepted => 'Receiving details accepted by you',
  ContactTrustStatus.restored =>
    'A backup may contain an old address. Request fresh details and complete the recovery check before paying.',
  ContactTrustStatus.suspended =>
    'Payments are paused. Add a separately verified replacement if this identity is unsafe.',
  ContactTrustStatus.retired =>
    'Kept for history. This identity cannot be reactivated; a new person must be added deliberately.',
};
