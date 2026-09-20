import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/sybil_widgets.dart';
import '../../../core/widgets/app_toast.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../send/models/send_prefill_args.dart';
import '../application/contact_exchange_controller.dart';
import '../domain/sybil_person.dart';
import 'sybil_add_person_screen.dart';

class SybilChooseRecipientScreen extends ConsumerStatefulWidget {
  const SybilChooseRecipientScreen({super.key});
  @override
  ConsumerState<SybilChooseRecipientScreen> createState() =>
      _SybilChooseRecipientScreenState();
}

class _SybilChooseRecipientScreenState
    extends ConsumerState<SybilChooseRecipientScreen> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(contactExchangeProvider);
    final saved = ref.watch(addressBookProvider);
    final people =
        [
              if (connected.available && !connected.loading)
                ...connected.contacts
                    .where((c) => c.canPay)
                    .map(SybilPerson.connected),
              ...?saved.value?.contacts
                  .where((c) => c.network == AddressBookNetwork.zcash)
                  .map(SybilPerson.saved),
            ]
            .where((p) => p.label.toLowerCase().contains(_query.toLowerCase()))
            .toList()
          ..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
          );
    void choose(SybilPerson p) {
      try {
        final snapshot = p.connected == null
            ? null
            : ref
                  .read(contactExchangeProvider.notifier)
                  .recipientFor(p.connected!.id);
        context.push(
          '/send',
          extra: SendPrefillArgs(
            id: 'person-${p.id}-${DateTime.now().microsecondsSinceEpoch}',
            source: snapshot == null ? 'address-book' : 'contact',
            address: snapshot?.address ?? p.address,
            label: snapshot?.label ?? p.label,
            contactRecipient: snapshot,
          ),
        );
      } catch (_) {
        showAppToast(
          context,
          'This person changed. Open People and review their address.',
        );
      }
    }

    return SybilFlowPage(
      title: 'Send',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '1  Person    ·    2  Amount    ·    3  Review',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 24),
          const SybilPageHeader(eyebrow: 'Send ZEC', title: 'Who’s it for?'),
          const SizedBox(height: 24),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Find someone you know',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 20),
          if (saved.isLoading || connected.loading)
            const LinearProgressIndicator(),
          if (saved.hasError || connected.error != null)
            const Text(
              'Some people could not be loaded. Open People to reload.',
            ),
          if (people.isNotEmpty)
            SybilCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final p in people)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      leading: SybilAvatar(
                        label: p.label,
                        identity: p.avatarIdentity,
                      ),
                      title: Text(p.label),
                      subtitle: Text(
                        p.saved != null
                            ? 'Saved address'
                            : 'Connected privately',
                      ),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () => choose(p),
                    ),
                ],
              ),
            )
          else
            const Text('Choose a saved person, or use a receiving address.'),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.push(
                  '/send',
                  extra: SendPrefillArgs(
                    id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
                    source: 'manual',
                    address: '',
                  ),
                ),
                icon: const Icon(Icons.content_paste),
                label: const Text('Use an address'),
              ),
              TextButton(
                onPressed: () => context.push('/people/add'),
                child: const Text('Add someone'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
