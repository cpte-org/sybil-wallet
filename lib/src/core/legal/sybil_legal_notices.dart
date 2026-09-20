import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset paths for the legal files shipped in every Flutter target bundle.
const sybilRootLicenseAsset = 'assets/legal/LICENSE';
const sybilNoticeAsset = 'assets/legal/NOTICE';
const sybilFontLicenseAsset = 'assets/legal/fonts/OFL-1.1.txt';
const sybilThirdPartyNoticesAsset = 'assets/legal/THIRD-PARTY-NOTICES.txt';
const sybilDependencyLicenseAsset =
    'tools/licensing/SYBIL-DEPENDENCY-LICENSES.md';
const sybilSimplexLicenseAsset =
    'tools/simplex/licenses/SimpleX-Chat-v7.0.2-LICENSE';
const sybilSimplexSourceAsset =
    'tools/simplex/licenses/SIMPLEX-SOURCE-AND-BUILD.txt';

bool _sybilLegalNoticesRegistered = false;

/// Registers Sybil's repository and bundled-font notices with Flutter's
/// built-in [LicensePage] registry.
///
/// Call this once during application startup. The registration is lazy: the
/// asset files are read only when a legal-notices view requests
/// [LicenseRegistry.licenses]. Calling this function more than once is safe.
void registerSybilLegalNotices() {
  if (_sybilLegalNoticesRegistered) {
    return;
  }
  _sybilLegalNoticesRegistered = true;

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const <String>[
      'Sybil wallet',
    ], await rootBundle.loadString(sybilRootLicenseAsset));
    yield LicenseEntryWithLineBreaks(const <String>[
      'Sybil wallet attribution notices',
    ], await rootBundle.loadString(sybilNoticeAsset));
    yield LicenseEntryWithLineBreaks(const <String>[
      'Sybil bundled fonts',
    ], await rootBundle.loadString(sybilFontLicenseAsset));
    yield LicenseEntryWithLineBreaks(const <String>[
      'Sybil third-party dependency license texts',
    ], await rootBundle.loadString(sybilThirdPartyNoticesAsset));
    yield LicenseEntryWithLineBreaks(const <String>[
      'Sybil Dart and Rust dependency inventory',
    ], await rootBundle.loadString(sybilDependencyLicenseAsset));
    yield LicenseEntryWithLineBreaks(const <String>[
      'SimpleX Chat native transport',
    ], await rootBundle.loadString(sybilSimplexLicenseAsset));
    yield LicenseEntryWithLineBreaks(const <String>[
      'SimpleX native transport source and build inputs',
    ], await rootBundle.loadString(sybilSimplexSourceAsset));
  });
}
