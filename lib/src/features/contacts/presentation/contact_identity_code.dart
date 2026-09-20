import 'package:flutter/material.dart';

import '../domain/contact_models.dart';
import 'contact_code_widgets.dart';

/// A QR carries the existing complete relationship identity, not a new trust
/// token or a shortened fingerprint. Association review still belongs to the
/// coordinator, including finding the exact locally owned outgoing key.
String readContactIdentityCode(String value) {
  try {
    return contactIdentity(value.trim());
  } on ContactFailure {
    throw const FormatException(
      'Use the full connection code from People > you > Check connection.',
    );
  }
}

class ContactIdentityCode extends StatelessWidget {
  const ContactIdentityCode({
    super.key,
    required this.identity,
    required this.personLabel,
    this.enabled = true,
    this.onCopy,
  });

  final String identity, personLabel;
  final bool enabled;
  final Future<void> Function(String)? onCopy;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'This is the full connection key you accepted for $personLabel. '
        'Let them scan it in person, or share it over an independently trusted channel. '
        'Ask them to show you the code they accepted for you, too.',
      ),
      const SizedBox(height: 16),
      ContactCodeOutput(
        data: identity,
        title: 'The connection you accepted',
        enabled: enabled,
        onCopy: onCopy,
      ),
      if (enabled)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Full connection key'),
          children: [SelectableText(identity)],
        ),
      const Text(
        'Matching both full keys checks this connection. It does not prove a person’s identity.',
      ),
    ],
  );
}
