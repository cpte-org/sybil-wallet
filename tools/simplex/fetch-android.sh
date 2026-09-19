#!/usr/bin/env bash
# Fetch and extract the pinned official SimpleX Android ARM64 native bundle.
#
# This script only downloads a release APK and copies verified ELF assets.  It
# never executes anything from the APK or from the extracted libraries.
set -euo pipefail

readonly VERSION="v7.0.2"
readonly APK_NAME="simplex-aarch64.apk"
readonly APK_URL="https://github.com/simplex-chat/simplex-chat/releases/download/${VERSION}/${APK_NAME}"
readonly APK_SHA256="0a3a0bb7ca1e2411854883ba1ae352b15b11146fe0e137395671fff9ed839871"
readonly APK_BYTES="87466500"
readonly LICENSE_ASSET="tools/simplex/licenses/SimpleX-Chat-v7.0.2-LICENSE"
readonly LICENSE_SHA256="8486a10c4393cee1c25392769ddd3b2d6c242d6ec7928e1414efff7dfb2f07ef"
readonly LICENSE_BYTES="34523"

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)"

cache_dir="${SIMPLEX_ANDROID_CACHE_DIR:-${REPO_ROOT}/build/simplex-android/cache/${VERSION}}"
dest_dir="${SIMPLEX_ANDROID_DEST_DIR:-${REPO_ROOT}/build/simplex-android/${VERSION}}"
apk_path="${SIMPLEX_ANDROID_APK_PATH:-${cache_dir}/${APK_NAME}}"
refresh=0

usage() {
  cat <<'EOF'
Usage: tools/simplex/fetch-android.sh [options]

Downloads the official SimpleX Chat v7.0.2 ARM64 APK, verifies its exact
size and SHA-256, and extracts the native assets needed by the Android bridge.

Options:
  --apk PATH       Cache/download APK at PATH.
  --dest PATH      Extract verified assets below PATH.
  --refresh        Replace an existing APK only after the replacement verifies.
  -h, --help       Show this help.

Environment overrides are SIMPLEX_ANDROID_APK_PATH,
SIMPLEX_ANDROID_CACHE_DIR, and SIMPLEX_ANDROID_DEST_DIR.  Defaults stay below
build/simplex-android, which is ignored by this repository.
EOF
}

die() {
  printf 'fetch-android: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

while (($# > 0)); do
  case "$1" in
    --apk)
      (($# >= 2)) || die "--apk requires a path"
      apk_path="$2"
      shift 2
      ;;
    --dest)
      (($# >= 2)) || die "--dest requires a path"
      dest_dir="$2"
      shift 2
      ;;
    --refresh)
      refresh=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

require_command curl
require_command sha256sum
require_command stat
require_command unzip
require_command awk
require_command grep
require_command install
require_command mktemp

verify_file() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  local bytes
  bytes="$(stat -c '%s' -- "$path")"
  [[ "$bytes" == "$APK_BYTES" ]] || return 1
  local digest
  digest="$(sha256sum -- "$path" | awk '{print $1}')"
  [[ "$digest" == "$APK_SHA256" ]]
}

download_verified() {
  local output="$1"
  local parent
  parent="$(dirname -- "$output")"
  mkdir -p -- "$parent"
  local temporary
  temporary="$(mktemp "${parent}/.${APK_NAME}.download.XXXXXX")"
  trap 'rm -f -- "${temporary}"' RETURN
  curl --fail --location --retry 3 --output "$temporary" "$APK_URL"
  verify_file "$temporary" || die "download failed verification: $temporary"
  mv -- "$temporary" "$output"
  trap - RETURN
}

if [[ -e "$apk_path" ]]; then
  if ! verify_file "$apk_path"; then
    ((refresh == 1)) || die "existing APK failed pinned verification; use --refresh or remove it: $apk_path"
    download_verified "$apk_path"
  fi
else
  download_verified "$apk_path"
fi

verify_file "$apk_path" || die "APK failed pinned verification: $apk_path"

license_path="${REPO_ROOT}/${LICENSE_ASSET}"
[[ -f "$license_path" ]] || die "missing committed license asset: $license_path"
[[ "$(stat -c '%s' -- "$license_path")" == "$LICENSE_BYTES" ]] || die "license asset size mismatch: $license_path"
[[ "$(sha256sum -- "$license_path" | awk '{print $1}')" == "$LICENSE_SHA256" ]] || die "license asset hash mismatch: $license_path"

parent_dir="$(dirname -- "$dest_dir")"
mkdir -p -- "$parent_dir"
stage_dir="$(mktemp -d "${parent_dir}/.${VERSION}.stage.XXXXXX")"
cleanup() {
  rm -rf -- "$stage_dir"
}
trap cleanup EXIT

required_dir="${stage_dir}/jniLibs/arm64-v8a"
app_dir="${stage_dir}/official-app-libs/arm64-v8a"
mkdir -p -- "$required_dir" "$app_dir"

extract_entry() {
  local entry="$1"
  local output="$2"
  # Drain the listing: grep -q can SIGPIPE unzip under pipefail and falsely
  # report a missing entry, depending on pipe scheduling.
  unzip -Z1 "$apk_path" | grep -Fx "$entry" >/dev/null || die "APK is missing expected entry: $entry"
  unzip -p "$apk_path" "$entry" > "$output"
}

# libsimplex.so and libsupport.so are the core/support pair.  The official
# app-lib wrapper is kept beside them because a private wrapper may use its
# JNI-compatible exports and compatibility shims.  The remaining APK JNI
# libraries are app UI/camera support and are kept separately for provenance.
for name in libsimplex.so libsupport.so libapp-lib.so; do
  extract_entry "lib/arm64-v8a/${name}" "${required_dir}/${name}"
done
for name in libandroidx.graphics.path.so libimage_processing_util_jni.so libsurface_util_jni.so; do
  extract_entry "lib/arm64-v8a/${name}" "${app_dir}/${name}"
done

mkdir -p -- "${dest_dir}/jniLibs/arm64-v8a" "${dest_dir}/official-app-libs/arm64-v8a"
install -m 0644 "${required_dir}/libsimplex.so" "${dest_dir}/jniLibs/arm64-v8a/libsimplex.so"
install -m 0644 "${required_dir}/libsupport.so" "${dest_dir}/jniLibs/arm64-v8a/libsupport.so"
install -m 0644 "${required_dir}/libapp-lib.so" "${dest_dir}/jniLibs/arm64-v8a/libapp-lib.so"
for name in libandroidx.graphics.path.so libimage_processing_util_jni.so libsurface_util_jni.so; do
  install -m 0644 "${app_dir}/${name}" "${dest_dir}/official-app-libs/arm64-v8a/${name}"
done

mkdir -p -- "${dest_dir}/licenses"
install -m 0644 "$license_path" "${dest_dir}/licenses/SimpleX-Chat-v7.0.2-LICENSE"

cat > "${dest_dir}/ARTIFACT-METADATA.txt" <<EOF
SimpleX Android ARM64 artifact bundle
Release: ${VERSION}
Source APK: ${APK_URL}
APK bytes: ${APK_BYTES}
APK SHA-256: ${APK_SHA256}
APK cache: ${apk_path}
License bytes: ${LICENSE_BYTES}
License SHA-256: ${LICENSE_SHA256}
Extraction: verified APK entries only; no downloaded code was executed

Required core bridge assets:
  jniLibs/arm64-v8a/libsimplex.so
  jniLibs/arm64-v8a/libsupport.so
  jniLibs/arm64-v8a/libapp-lib.so (official JNI wrapper; only needed by wrappers that use it)

Official APK app-only JNI assets kept for provenance:
  official-app-libs/arm64-v8a/libandroidx.graphics.path.so
  official-app-libs/arm64-v8a/libimage_processing_util_jni.so
  official-app-libs/arm64-v8a/libsurface_util_jni.so

License asset:
  licenses/SimpleX-Chat-v7.0.2-LICENSE
EOF

printf 'verified %s (%s bytes)\n' "$apk_path" "$APK_BYTES"
printf 'extracted SimpleX ARM64 assets under %s\n' "$dest_dir"
