import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset paths for the legal files shipped in every Flutter target bundle.
const sigilRootLicenseAsset = 'assets/legal/LICENSE';
const sigilNoticeAsset = 'assets/legal/NOTICE';
const sigilFontLicenseAsset = 'assets/legal/fonts/OFL-1.1.txt';
const sigilSimplexLicenseAsset =
    'tools/simplex/licenses/SimpleX-Chat-v7.0.2-LICENSE';
const sigilSimplexSourceAsset =
    'tools/simplex/licenses/SIMPLEX-SOURCE-AND-BUILD.txt';

bool _sigilLegalNoticesRegistered = false;

/// Registers Sigil's repository and bundled-font notices with Flutter's
/// built-in [LicensePage] registry.
///
/// Call this once during application startup. The registration is lazy: the
/// asset files are read only when a legal-notices view requests
/// [LicenseRegistry.licenses]. Calling this function more than once is safe.
void registerSigilLegalNotices() {
  if (_sigilLegalNoticesRegistered) {
    return;
  }
  _sigilLegalNoticesRegistered = true;

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const <String>[
      'Sigil wallet',
    ], await rootBundle.loadString(sigilRootLicenseAsset));
    yield LicenseEntryWithLineBreaks(const <String>[
      'Sigil wallet attribution notices',
    ], await rootBundle.loadString(sigilNoticeAsset));
    yield LicenseEntryWithLineBreaks(const <String>[
      'Sigil bundled fonts',
    ], await rootBundle.loadString(sigilFontLicenseAsset));
    yield LicenseEntryWithLineBreaks(const <String>[
      'SimpleX Chat native transport',
    ], await rootBundle.loadString(sigilSimplexLicenseAsset));
    yield LicenseEntryWithLineBreaks(const <String>[
      'SimpleX native transport source and build inputs',
    ], await rootBundle.loadString(sigilSimplexSourceAsset));
  });
}
