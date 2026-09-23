#!/usr/bin/env bash
# Set up clean GitHub-hosted Linux workers; no signing secrets are used here.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RUNNER_TEMP:?This helper is for GitHub Actions}"
: "${GITHUB_PATH:?Missing GitHub Actions path file}"
: "${GITHUB_ENV:?Missing GitHub Actions environment file}"
flutter_version=$(python3 -c 'import json; print(json.load(open(".fvmrc"))["flutter"])')
[[ "$flutter_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
git clone --depth 1 --branch "$flutter_version" https://github.com/flutter/flutter.git "$RUNNER_TEMP/flutter-bootstrap"
export PATH="$RUNNER_TEMP/flutter-bootstrap/bin:$HOME/.pub-cache/bin:$PATH"
flutter --version
dart pub global activate fvm 4.3.0
fvm install "$flutter_version"
printf '%s\n' "$HOME/.pub-cache/bin" "$RUNNER_TEMP/flutter-bootstrap/bin" >> "$GITHUB_PATH"
rust_version=$(cat scripts/release-config/android-reproducible-rust-version.txt)
[[ "$rust_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
rustup toolchain install "$rust_version" --profile minimal
rustup target add --toolchain "$rust_version" aarch64-linux-android
printf 'RUSTUP_TOOLCHAIN=%s\nVIZOR_RUST_TOOLCHAIN=%s\n' "$rust_version" "$rust_version" >> "$GITHUB_ENV"
