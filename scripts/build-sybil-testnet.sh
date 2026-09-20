#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep the contact experiment and public-name preset together on both platforms.
target="${1:-both}"
case "$target" in
  android|linux|both) ;;
  *) echo 'Usage: bash scripts/build-sybil-testnet.sh [android|linux|both]' >&2; exit 2 ;;
esac
defines=(
  --dart-define=ZCASH_DEFAULT_NETWORK=test
  --dart-define=ZNS_BASE_SEPOLIA=true
  --dart-define=ZCASH_CONTACTS_EXPERIMENT=true
)
if [[ "$target" == android || "$target" == both ]]; then
  simplex_android_runtime="${SIMPLEX_ANDROID_DEST_DIR:-$PWD/build/simplex-android/v7.0.2}"
  bash tools/simplex/fetch-android.sh --dest "$simplex_android_runtime"
  simplex_android_libs="$(cd "$simplex_android_runtime/jniLibs" && pwd)"
  SIMPLEX_ANDROID_LIBS_DIR="$simplex_android_libs" \
    fvm flutter build apk --release --target-platform android-arm64 \
    --dart-define=VIZOR_FORM_FACTOR=mobile "${defines[@]}"
  cp build/app/outputs/flutter-apk/app-release.apk \
    build/app/outputs/flutter-apk/sybil-testnet-arm64.apk
fi
if [[ "$target" == linux || "$target" == both ]]; then
  fvm flutter build linux --release "${defines[@]}"
fi
