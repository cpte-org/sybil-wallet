// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

/// Copy and link targets shared by the desktop and mobile About /
/// legal screens, so the two form factors cannot drift apart.
class AboutParagraph {
  const AboutParagraph({required this.heading, required this.body});

  final String heading;
  final String body;
}

const kSybilGithubUrl = 'https://github.com/cpte-org/sybil-wallet';
const kSybilWebsiteUrl = 'https://sybil.cash';

const kAboutParagraphs = [
  AboutParagraph(
    heading: 'Independent fork of Vizor',
    body:
        'Sybil is an independent fork of Vizor, originally developed by '
        'Chainapsis, the team behind Keplr. Sybil is maintained separately '
        'and is not an official Keplr product.',
  ),
  AboutParagraph(
    heading: 'Designed for shielded Zcash',
    body:
        'Sybil is built around shielded transactions, where the sender, '
        'recipient, and amount stay private. Transparent Zcash works too, but '
        'private is the default.',
  ),
  AboutParagraph(
    heading: 'Open source, self-custodied',
    body:
        'Sybil is open source. See the repository license and notice files for '
        'applicable license terms and bundled dependency attribution details. '
        'Your signing keys stay on your device. Network providers process '
        'requests needed to sync, swap and use public names.',
  ),
];

const _legalPlaceholderParagraph = AboutParagraph(
  heading: 'Not published yet',
  body:
      'This beta does not provide a finalized Sybil privacy policy or '
      'terms of usage.',
);

const kLegalParagraphs = [_legalPlaceholderParagraph];

Future<void> launchAboutUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } on Exception {
    // External links are best-effort from these utility pages.
  }
}
