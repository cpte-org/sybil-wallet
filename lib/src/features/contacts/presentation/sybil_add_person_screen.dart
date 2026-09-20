import '../../../providers/rpc_endpoint_failover_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/widgets/sybil_widgets.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../application/contact_exchange_controller.dart';
import 'contact_availability.dart';

final sybilAddressValidatorProvider =
    Provider<Future<bool> Function(String)>(
      (ref) =>
          (address) async => (await rust_sync.validateAddress(
            address: address,
            network: ref.read(rpcEndpointFailoverProvider).current.networkName,
          )).isValid,
    );

/// A reusable focused page, with the prototype's compact header and open paper.
class SybilFlowPage extends StatelessWidget {
  const SybilFlowPage({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final palette = SybilPalette.of(context);
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/people'),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 660),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
    if (kAppFormFactor == AppFormFactor.mobile) {
      return Scaffold(
        backgroundColor: palette.paper,
        body: SafeArea(child: body),
      );
    }
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(padding: EdgeInsets.zero, child: body),
    );
  }
}

class SybilAddPersonScreen extends ConsumerStatefulWidget {
  const SybilAddPersonScreen({super.key, this.savedId});
  final String? savedId;
  @override
  ConsumerState<SybilAddPersonScreen> createState() =>
      _SybilAddPersonScreenState();
}

class _SybilAddPersonScreenState
    extends ConsumerState<SybilAddPersonScreen> {
  final _name = TextEditingController(),
      _address = TextEditingController(),
      _note = TextEditingController();
  bool _manual = false, _busy = false, _loaded = false;
  String? _error;
  int _sessionGeneration = 0;

  Future<void> _pasteAddress() async {
    final generation = _sessionGeneration;
    final account = ref.read(accountProvider).value?.activeAccountUuid;
    try {
      final text = (await Clipboard.getData(
        Clipboard.kTextPlain,
      ))?.text?.trim();
      if (!mounted ||
          generation != _sessionGeneration ||
          !ref.read(appSecurityProvider).isUnlocked ||
          ref.read(accountProvider).value?.activeAccountUuid != account) {
        return;
      }
      setState(() {
        if (text == null || text.isEmpty) {
          _error = 'Copy their Zcash address first, then paste it here.';
        } else {
          _address.text = text;
          _error = null;
        }
      });
    } catch (_) {
      if (mounted && generation == _sessionGeneration) {
        setState(
          () => _error =
              'Could not read the clipboard. Enter the address instead.',
        );
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _name.text.trim(), address = _address.text.trim();
    final labelError = validateAddressBookLabel(name);
    if (labelError != null || address.isEmpty || _note.text.length > 2000) {
      setState(
        () => _error =
            labelError ??
            (address.isEmpty
                ? 'Enter their receiving address.'
                : 'Use a note of at most 2,000 characters.'),
      );
      return;
    }
    final generation = _sessionGeneration;
    final account = ref.read(accountProvider).value?.activeAccountUuid;
    bool current() =>
        mounted &&
        generation == _sessionGeneration &&
        ref.read(appSecurityProvider).isUnlocked &&
        account == ref.read(accountProvider).value?.activeAccountUuid;
    if (account == null || !current()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final valid = await ref.read(sybilAddressValidatorProvider)(address);
      if (!current()) return;
      if (!valid) {
        setState(() => _error = 'Enter a valid Zcash receiving address.');
        return;
      }
      final book = ref.read(addressBookProvider.notifier);
      if (widget.savedId == null) {
        await book.addContact(
          label: name,
          network: AddressBookNetwork.zcash,
          address: address,
          profilePictureId: kDefaultProfilePictureId,
          note: _note.text.trim(),
        );
      } else {
        final existing = ref
            .read(addressBookProvider)
            .value
            ?.contacts
            .where((c) => c.id == widget.savedId)
            .firstOrNull;
        if (existing == null) {
          setState(() => _error = 'This person was removed. Return to People.');
          return;
        }
        await book.updateContact(
          existing.id,
          label: name,
          network: existing.network,
          address: address,
          profilePictureId: existing.profilePictureId,
          note: _note.text.trim(),
        );
      }
      if (mounted && current()) context.pop();
    } catch (_) {
      if (current()) {
        setState(
          () => _error = 'Could not save this person. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SybilPalette.of(context);
    final connectedAvailable = ref.watch(contactExchangeAvailableProvider);
    final unavailableMessage = connectedAvailable
        ? null
        : ref.watch(contactUnavailableMessageProvider);
    final book = ref.watch(addressBookProvider);
    final account = ref.watch(accountProvider).value?.activeAccountUuid;
    final unlocked = ref.watch(appSecurityProvider).isUnlocked;
    // Clear editors on lock or an account switch, even during address validation.
    ref.listen(appSecurityProvider.select((s) => s.isUnlocked), (_, next) {
      if (!next) {
        _sessionGeneration++;
        _name.clear();
        _address.clear();
        _note.clear();
      }
    });
    ref.listen(accountProvider.select((s) => s.value?.activeAccountUuid), (
      old,
      next,
    ) {
      if (old != next) {
        _sessionGeneration++;
        _name.clear();
        _address.clear();
        _note.clear();
        _loaded = false;
      }
    });
    if (widget.savedId != null && !_loaded && book.hasValue) {
      final saved = book.value!.contacts
          .where((c) => c.id == widget.savedId)
          .firstOrNull;
      if (saved != null) {
        _name.text = saved.label;
        _address.text = saved.address;
        _note.text = saved.note;
      }
      _loaded = true;
      _manual = true;
    }
    final ready = unlocked && account != null && !_busy && book.hasValue;
    return SybilFlowPage(
      title: widget.savedId == null ? 'Add someone' : 'Name and address',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SybilPageHeader(
            eyebrow: 'Your private address book',
            title: _manual ? 'What do you call them?' : 'Start with someone.',
          ),
          const SizedBox(height: 28),
          if (!_manual) ...[
            SybilCard(
              color: palette.peach,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Enter name and address'),
                subtitle: const Text('Works with any Zcash wallet.'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: ready ? () => setState(() => _manual = true) : null,
              ),
            ),
            const SizedBox(height: 16),
            SybilCard(
              color: palette.lilac,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link),
                    title: const Text('Connect privately'),
                    subtitle: const Text('Scan or share a contact code.'),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: connectedAvailable
                        ? () => context.push('/contacts/exchange')
                        : null,
                  ),
                  if (unavailableMessage != null)
                    Text(
                      unavailableMessage,
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
          ] else ...[
            SybilCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('manual-person-name'),
                    controller: _name,
                    enabled: ready,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: 'Your name for them',
                      hintText: 'Mara',
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const Key('manual-person-address'),
                    controller: _address,
                    enabled: ready,
                    minLines: 2,
                    maxLines: 5,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Zcash receiving address',
                      hintText: 'Paste their address',
                      suffixIcon: IconButton(
                        tooltip: 'Paste address',
                        onPressed: ready ? _pasteAddress : null,
                        icon: const Icon(Icons.content_paste, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Add a private note'),
                    children: [
                      TextField(
                        controller: _note,
                        enabled: ready,
                        maxLength: 2000,
                        minLines: 2,
                        maxLines: 5,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Get the address from the person you want to pay. The name stays in your wallet.',
                    style: TextStyle(color: palette.muted, fontSize: 13),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: ready ? _save : null,
                    child: Text(_busy ? 'Saving…' : 'Save person'),
                  ),
                ],
              ),
            ),
          ],
          if (book.hasError)
            const Text(
              'Your saved people could not be opened. Try reopening People.',
            ),
        ],
      ),
    );
  }
}
