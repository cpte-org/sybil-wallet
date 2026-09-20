#!/usr/bin/env bash
# Build the Sybil mainnet beta without changing existing wallet identities/data.
set -euo pipefail
cd "$(dirname "$0")/.."

target="${1:-both}"
if [[ $# -gt 1 ]]; then
  echo 'Usage: bash scripts/build-sybil-beta.sh [android|linux|both]' >&2
  exit 2
fi
case "$target" in
  android|linux|both) ;;
  *) echo 'Usage: bash scripts/build-sybil-beta.sh [android|linux|both]' >&2; exit 2 ;;
esac

# First Sybil beta uses its own release identity. Public APKs must never fall
# back to the Android debug key. Existing developer builds can use Flutter
# directly; this publication script deliberately requires release signing.
export ANDROID_REQUIRE_RELEASE_SIGNING=true
release_version="${SYBIL_RELEASE_VERSION:-1.0.0-beta.1}"
release_build="${SYBIL_RELEASE_BUILD:-1}"

defines=(
  --dart-define=VIZOR_RELEASE_VERSION="$release_version"
  --dart-define=VIZOR_RELEASE_BUILD_NUMBER="$release_build"
  --dart-define=VIZOR_RELEASE_REPOSITORY=cpte-org/sybil-wallet
  --dart-define=VIZOR_UPDATE_CHECK_ENABLED=false
  --dart-define=VIZOR_DEEPLINK_BASE_URL=https://sybil.cash
  --dart-define=ZCASH_DEFAULT_NETWORK=main
  --dart-define=ZNS_BASE_SEPOLIA=false
  --dart-define=ZCASH_CONTACTS_EXPERIMENT=true
  --dart-define=SIGIL_NEAR_INTENTS_BASE_URL=https://api.sybil.cash/api/near-intents/1click
  --dart-define=SIGIL_NEAR_INTENTS_ALLOW_LOOPBACK=false
)

# Base RPC recommendations come from zns_build_defaults.dart (currently dRPC).
# Building never replaces an endpoint the user has already saved.

# Linux CMake remembers the first SimpleX path. Refresh an existing cache so a
# prior build cannot silently omit the requested runtime or retain another one.
if [[ "$target" == linux || "$target" == both ]]; then
  if [[ "$(uname -m)" != x86_64 ]]; then
    echo 'The bundled Linux SimpleX runtime requires an x86_64 build host.' >&2
    exit 1
  fi
  if [[ -z "${SIMPLEX_LIBS_DIR:-}" || ! -f "$SIMPLEX_LIBS_DIR/libsimplex.so" ]]; then
    echo 'Set SIMPLEX_LIBS_DIR to the verified v7.0.2 Linux libs directory; see docs/SYBIL-BETA-BUILD.md.' >&2
    exit 1
  fi
  export SIMPLEX_LIBS_DIR="$(cd "$SIMPLEX_LIBS_DIR" && pwd)"
  if [[ -f linux/FlavorOverrides.cmake ]]; then
    echo 'linux/FlavorOverrides.cmake is present. Finish the other flavor build before building the beta.' >&2
    exit 1
  fi
fi

if [[ "$target" == android || "$target" == both ]]; then
  simplex_android_runtime="${SIMPLEX_ANDROID_DEST_DIR:-$PWD/build/simplex-android/v7.0.2}"
  bash tools/simplex/fetch-android.sh --dest "$simplex_android_runtime"
  simplex_android_libs="$(cd "$simplex_android_runtime/jniLibs" && pwd)"
  SIMPLEX_ANDROID_LIBS_DIR="$simplex_android_libs" \
    fvm flutter build apk --release --target-platform android-arm64 \
    --build-name="$release_version" --build-number="$release_build" \
    --dart-define=VIZOR_FORM_FACTOR=mobile "${defines[@]}"
  mkdir -p dist/android
  cp build/app/outputs/flutter-apk/app-release.apk \
    dist/android/sybil-beta-mainnet-arm64.apk
  echo 'Android beta: dist/android/sybil-beta-mainnet-arm64.apk'
fi

if [[ "$target" == linux || "$target" == both ]]; then
  export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-2}"
  linux_build_dir='build/linux/x64/release'
  linux_cmake_cache="$linux_build_dir/CMakeCache.txt"
  linux_generated_config='linux/flutter/ephemeral/generated_config.cmake'
  project_dir="$(pwd -P)"
  expected_linux_source="$project_dir/linux"
  expected_install_prefix="$project_dir/$linux_build_dir/bundle"
  refresh_cmake_cache=false

  # A renamed checkout can leave the generated CMake tree pointing at the old
  # source and bundle paths. Preserve that generated metadata in a scoped
  # temporary backup, but leave the existing bundle and native dependency
  # caches in place for the next Flutter configuration.
  if [[ -f "$linux_cmake_cache" ]]; then
    cached_linux_source="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$linux_cmake_cache")"
    cached_install_prefix="$(sed -n 's/^CMAKE_INSTALL_PREFIX:PATH=//p' "$linux_cmake_cache")"
    if [[ "$cached_linux_source" != "$expected_linux_source" ||
      "$cached_install_prefix" != "$expected_install_prefix" ]]; then
      refresh_cmake_cache=true
    fi
    if [[ -f "$linux_generated_config" ]]; then
      cached_project_dir="$(sed -n 's/^file(TO_CMAKE_PATH "\(.*\)" PROJECT_DIR)$/\1/p' "$linux_generated_config")"
      if [[ -n "$cached_project_dir" && "$cached_project_dir" != "$project_dir" ]]; then
        refresh_cmake_cache=true
      fi
    fi
  fi

  if [[ "$refresh_cmake_cache" == true ]]; then
    cmake_backup_dir="$(mktemp -d /tmp/sybil-linux-cmake-stale.XXXXXX)"
    if [[ -f "$linux_cmake_cache" ]]; then
      mv -- "$linux_cmake_cache" "$cmake_backup_dir/CMakeCache.txt"
    fi
    if [[ -d "$linux_build_dir/CMakeFiles" ]]; then
      mv -- "$linux_build_dir/CMakeFiles" "$cmake_backup_dir/CMakeFiles"
    fi
    echo "Moved stale Linux CMake metadata to $cmake_backup_dir" >&2
  fi

  # FetchContent also creates independent CMake caches. Reconfigure stale
  # population subbuilds after a checkout move, retaining downloaded sources
  # and compiled dependency artifacts in their sibling directories.
  for dependency_cache in "$linux_build_dir"/_deps/*-subbuild/CMakeCache.txt; do
    [[ -f "$dependency_cache" ]] || continue
    dependency_subbuild="${dependency_cache%/CMakeCache.txt}"
    cached_dependency_dir="$(sed -n 's/^CMAKE_CACHEFILE_DIR:INTERNAL=//p' "$dependency_cache")"
    if [[ "$cached_dependency_dir" != "$project_dir/$dependency_subbuild" ]]; then
      if [[ -z "${cmake_backup_dir:-}" ]]; then
        cmake_backup_dir="$(mktemp -d /tmp/sybil-linux-cmake-stale.XXXXXX)"
      fi
      mv -- "$dependency_subbuild" \
        "$cmake_backup_dir/${dependency_subbuild##*/}"
      echo "Moved stale dependency CMake metadata to $cmake_backup_dir" >&2
    fi
  done

  # Keep an existing runtime choice explicit. On a fresh cache, Flutter's
  # configure sees the exported SIMPLEX_LIBS_DIR directly.
  if [[ -f "$linux_cmake_cache" && -f "$linux_generated_config" ]]; then
    cmake -S linux -B "$linux_build_dir" \
      -DSIMPLEX_LIBS_DIR="$SIMPLEX_LIBS_DIR"
  fi
  fvm flutter build linux --release --target-platform linux-x64 \
    --build-name="$release_version" --build-number="$release_build" \
    --dart-define=VIZOR_FORM_FACTOR=desktop "${defines[@]}"
  bundle="$linux_build_dir/bundle"
  if [[ ! -x "$bundle/vizor" || ! -x "$bundle/simplex-host" || ! -f "$bundle/lib/simplex/libsimplex.so" ]]; then
    echo 'The Linux beta bundle is missing the wallet or bundled SimpleX runtime.' >&2
    exit 1
  fi
  scanner_plugin="$bundle/lib/libmobile_scanner_plugin.so"
  scanner_runpath="$(readelf -d "$scanner_plugin" 2>/dev/null | sed -n 's/.*Library runpath: \[\(.*\)\]/\1/p')"
  if [[ ! -f "$bundle/lib/libZXing.so.3" || "$scanner_runpath" != '$ORIGIN' ]]; then
    echo 'The Linux beta bundle has a non-relocatable mobile_scanner/ZXing runtime path.' >&2
    exit 1
  fi
  mkdir -p dist/linux
  tar -C "$bundle" -czf dist/linux/sybil-beta-mainnet-linux-x64.tar.gz .
  echo 'Linux beta: dist/linux/sybil-beta-mainnet-linux-x64.tar.gz (launch vizor)'
fi
