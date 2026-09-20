import 'package:flutter/material.dart';
import '../../../core/widgets/sybil_widgets.dart';
import '../../address_book/models/address_book_contact.dart';

class SybilSavedPersonDetail extends StatefulWidget {
  const SybilSavedPersonDetail({
    super.key,
    required this.person,
    this.onPay,
    this.onEdit,
    this.onPin,
  });
  final AddressBookContact person;
  final ValueChanged<AddressBookContact>? onPay, onEdit;
  final Future<void> Function(AddressBookContact)? onPin;
  @override
  State<SybilSavedPersonDetail> createState() =>
      _SybilSavedPersonDetailState();
}

class _SybilSavedPersonDetailState extends State<SybilSavedPersonDetail> {
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final person = widget.person, palette = SybilPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Column(
            children: [
              SybilAvatar(
                label: person.label,
                identity: 'saved:${person.id}',
                size: 96,
              ),
              const SizedBox(height: 20),
              Text(
                'Your name for this person',
                style: TextStyle(fontSize: 12, color: palette.muted),
              ),
              const SizedBox(height: 10),
              Text(
                person.label,
                style: TextStyle(
                  fontFamily: 'Young Serif',
                  fontSize: 38,
                  color: palette.ink,
                ),
              ),
              if (person.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(person.note, textAlign: TextAlign.center),
                ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: widget.onPay == null
                        ? null
                        : () => widget.onPay!(person),
                    icon: const Icon(Icons.north_east),
                    label: const Text('Send money'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || widget.onPin == null
                        ? null
                        : () async {
                            setState(() {
                              _busy = true;
                              _error = null;
                            });
                            try {
                              await widget.onPin!(person);
                            } catch (_) {
                              if (mounted) {
                                setState(
                                  () => _error =
                                      'Could not save the pin. Try again.',
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    icon: Icon(person.pinned ? Icons.star : Icons.star_outline),
                    label: Text(person.pinned ? 'Unpin' : 'Pin'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        if (_error != null) Text(_error!),
        SybilCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Name and note'),
            subtitle: const Text('Private to you'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: widget.onEdit == null ? null : () => widget.onEdit!(person),
          ),
        ),
        const SizedBox(height: 24),
        SybilCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Receiving address'),
            children: [
              SelectableText(
                person.address,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              Text(
                'You saved this address yourself. It does not update automatically and is not included in connection backups.',
                style: TextStyle(fontSize: 13, color: palette.muted),
              ),
              TextButton(
                onPressed: widget.onEdit == null
                    ? null
                    : () => widget.onEdit!(person),
                child: const Text('Edit address'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
