import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sybil_widgets.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../application/public_name_lookup.dart';
import 'zns_view_data.dart';

class PublicNameLookupCard extends ConsumerStatefulWidget {
  const PublicNameLookupCard({super.key, required this.configuration});
  final ZnsConfigurationInput configuration;
  @override
  ConsumerState<PublicNameLookupCard> createState() =>
      _PublicNameLookupCardState();
}

class _PublicNameLookupCardState extends ConsumerState<PublicNameLookupCard> {
  final _query = TextEditingController();
  final _localName = TextEditingController();
  PublicNameResolution? _result;
  String? _error, _notice;
  bool _busy = false;
  // A dispatched storage write cannot be cancelled. Keep this lock separate
  // from view invalidation so a changed account/configuration cannot overlap it.
  bool _savingContact = false;
  int _epoch = 0;

  String _configurationKey(ZnsConfigurationInput value) =>
      '${value.chainId}|${value.registryAddress}|${value.rpcUrl}|'
      '${value.tokenAddress}|${value.delegateAddress}';

  @override
  void didUpdateWidget(covariant PublicNameLookupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_configurationKey(widget.configuration) !=
        _configurationKey(oldWidget.configuration)) {
      _clear();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _query.dispose();
    _localName.dispose();
    super.dispose();
  }

  void _clear({bool clearInput = false}) {
    _epoch++;
    _result = null;
    _busy = false;
    _error = null;
    _notice = null;
    if (clearInput) {
      _query.clear();
      _localName.clear();
    }
  }

  bool _current(int epoch, PublicNameLookupSession session) =>
      mounted &&
      epoch == _epoch &&
      identical(session, ref.read(publicNameLookupSessionProvider)) &&
      session.available &&
      ref.read(publicNameLookupPreferenceProvider).value == true;

  String _message(Object error) => switch (error) {
    PublicNameLookupFailure() => error.message,
    FormatException() => error.message,
    _ => 'Could not look up this name. Check the registry and try again.',
  };

  Future<void> _setEnabled(bool enabled) async {
    if (_savingContact) return;
    setState(() => _clear(clearInput: true));
    try {
      await ref
          .read(publicNameLookupPreferenceProvider.notifier)
          .setEnabled(enabled);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _lookup({bool save = false}) async {
    if (_busy || _savingContact) return;
    final session = ref.read(publicNameLookupSessionProvider);
    if (!session.available ||
        ref.read(publicNameLookupPreferenceProvider).value != true) {
      return;
    }
    final previous = _result;
    final localName = _localName.text.trim();
    if (save) {
      if (previous == null) return;
      final labelError = validateAddressBookLabel(localName);
      if (labelError != null) {
        setState(() => _error = labelError);
        return;
      }
    }
    final epoch = ++_epoch;
    var committing = false;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      if (!save) _result = null;
    });
    try {
      final result = await ref
          .read(publicNameLookupServiceProvider)
          .lookup(
            configuration: widget.configuration,
            network: session.network,
            name: _query.text,
          );
      if (!_current(epoch, session)) return;
      if (!save) {
        setState(() {
          _result = result;
          // A public label can be longer than the local address-book limit.
          _localName.text = result.name.length <= 20 ? result.name : '';
        });
        return;
      }
      if (!previous!.sameRecipient(result)) {
        setState(() {
          _result = result;
          _notice = 'This name changed. Review the new address before saving.';
        });
        return;
      }
      committing = true;
      setState(() => _savingContact = true);
      await ref
          .read(addressBookProvider.notifier)
          .addContact(
            label: localName,
            network: AddressBookNetwork.zcash,
            address: result.address,
            profilePictureId: kDefaultProfilePictureId,
            beforeWrite: () {
              if (!_current(epoch, session)) {
                throw const PublicNameLookupFailure(
                  'The wallet changed. Look up the name again.',
                );
              }
            },
          );
      if (!_current(epoch, session)) return;
      setState(() {
        _result = null;
        _query.clear();
        _localName.clear();
        _notice = '$localName was added to People.';
      });
    } catch (error) {
      if (_current(epoch, session)) {
        setState(() {
          _result = null;
          _error = _message(error);
        });
      }
    } finally {
      if (committing && mounted) setState(() => _savingContact = false);
      if (_current(epoch, session)) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(publicNameLookupPreferenceProvider);
    final session = ref.watch(publicNameLookupSessionProvider);
    ref.listen(publicNameLookupSessionProvider, (_, _) {
      setState(() => _clear(clearInput: true));
    });
    ref.listen(publicNameLookupPreferenceProvider, (previous, next) {
      if (previous?.value != next.value || next.isLoading) {
        setState(() => _clear(clearInput: true));
      }
    });
    final enabled = preference.value == true;
    final result = _result;
    return SybilCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Resolve .zec names'),
            subtitle: const Text('Find an address and save it in People.'),
            value: enabled,
            onChanged:
                session.available && !preference.isLoading && !_savingContact
                ? _setEnabled
                : null,
          ),
          if (enabled && session.available) ...[
            const SizedBox(height: 16),
            TextField(
              key: const Key('public-name-query'),
              controller: _query,
              enabled: !_savingContact,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Public Zcash name',
                hintText: 'someone.zec',
              ),
              onChanged: (_) => setState(_clear),
              onSubmitted: (_) => _lookup(),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy || _savingContact || _query.text.trim().isEmpty
                  ? null
                  : () => _lookup(),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_busy ? 'Checking name…' : 'Look up name'),
            ),
            if (result != null) ...[
              const SizedBox(height: 20),
              Text('${result.name}.zec', style: AppTypography.headlineSmall),
              const SizedBox(height: 8),
              SelectableText(
                result.address,
                key: const Key('public-name-address'),
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('public-name-local-label'),
                controller: _localName,
                enabled: !_busy && !_savingContact,
                maxLength: 20,
                decoration: const InputDecoration(labelText: 'Name in People'),
              ),
              const SizedBox(height: 8),
              Text(
                'A public name finds an address, not a verified person. '
                'Your saved address will not follow name changes or transfers.',
                style: AppTypography.bodySmall.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('public-name-save'),
                onPressed: _busy || _savingContact
                    ? null
                    : () => _lookup(save: true),
                child: const Text('Add to People'),
              ),
            ],
          ],
          if (!session.available)
            const Text('Unlock a wallet account to look up names.'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(_notice!)),
          ],
        ],
      ),
    );
  }
}
