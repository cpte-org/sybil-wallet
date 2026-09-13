#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep the contact experiment and public-name preset together on both platforms.
target="${1:-both}"
case "$target" in
  android|linux|both) ;;
  *) echo 'Usage: bash scripts/build-sigil-testnet.sh [android|linux|both]' >&2; exit 2 ;;
esac
defines=(
  --dart-define=ZCASH_DEFAULT_NETWORK=test
  --dart-define=ZNS_BASE_SEPOLIA=true
  --dart-define=ZCASH_CONTACTS_EXPERIMENT=true
)
if [[ "$target" == android || "$target" == both ]]; then
  fvm flutter build apk --release --target-platform android-arm64 \
    --dart-define=VIZOR_FORM_FACTOR=mobile "${defines[@]}"
  cp build/app/outputs/flutter-apk/app-release.apk \
    build/app/outputs/flutter-apk/sigil-testnet-arm64.apk
fi
if [[ "$target" == linux || "$target" == both ]]; then
  fvm flutter build linux --release "${defines[@]}"
fi
