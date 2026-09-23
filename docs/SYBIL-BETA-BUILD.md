# Sybil mainnet beta builds

The first public Sybil beta can receive ZEC, use the existing exchange flow,
and connect to the verified Base mainnet Names registry. Build the Linux x64
and Android ARM64 beta from the wallet repository with FVM and the existing
native build prerequisites. Linux keeps the existing `vizor` executable and
compatibility identity; Android is a separate Sybil app with application ID
`cash.sybil.wallet` and a new Sybil release-signing key:

```sh
fvm install
fvm flutter pub get
SIMPLEX_LIBS_DIR=/absolute/path/to/verified/simplex/libs \
  bash scripts/build-sybil-beta.sh linux
bash scripts/build-sybil-beta.sh android
```

Use `both` (the default) with `SIMPLEX_LIBS_DIR` set to build both targets. The
Linux runtime is the existing SimpleX v7.0.2 x86_64 bundle; verify the pinned
archive checksum in [the SimpleX build notes](../tools/simplex/README.md) and
keep its complete `libs/` directory together. The script refreshes an existing
CMake runtime path before building and checks the resulting bundle. Android
uses the existing checksum-verified runtime fetch/extraction script and cached
official APK. `SIMPLEX_ANDROID_APK_PATH` and `SIMPLEX_ANDROID_DEST_DIR` remain
available for those cached inputs.

The source includes Ledger account onboarding and signing for Zcash mainnet.
New Ledger accounts require Zcash app v3.9.4 or newer; this build uses USB on
Linux and Bluetooth on Android, subject to platform and device capability
checks. This describes implemented source paths and does not claim physical
device or release qualification for these artifacts.

The beta script fixes these public settings:

| Setting | Value |
| --- | --- |
| `ZCASH_DEFAULT_NETWORK` | `main` |
| `ZNS_BASE_SEPOLIA` | `false` |
| `ZCASH_CONTACTS_EXPERIMENT` | `true` (existing technical feature flag) |
| `SIGIL_NEAR_INTENTS_BASE_URL` | `https://api.sybil.cash/api/near-intents/1click` |
| `SIGIL_NEAR_INTENTS_ALLOW_LOOPBACK` | `false` |
| `VIZOR_FORM_FACTOR` | `desktop` on Linux, `mobile` on Android |
| `VIZOR_RELEASE_VERSION` | `1.0.0-beta.1` |
| `VIZOR_RELEASE_BUILD_NUMBER` | `1` |
| `VIZOR_UPDATE_CHECK_ENABLED` | `false` |

The mainnet registry default is
`0x17ea278fe9bee80449e7e576fb8fa4ec2f0ec3a5` on Base chain 8453. Its deployment
transaction is
`0xd71a2883627ea1ff375fe2b7d4c4b1e450294fe665567afbbe397d63624f28d1`,
confirmed at block 51,543,513 with the expected runtime and canonical
token/oracle/protocol configuration. Existing saved Names configuration takes
precedence over build defaults; the build does not overwrite it.

The default Base RPC for new builds is `https://api.sybil.cash/api/base/rpc`.
The Sybil Worker forwards supported JSON-RPC methods to PublicNode's
archive-enabled Base endpoint; its provider token stays in a Cloudflare secret
and is not compiled into wallet builds. The gateway has separate per-client and
service rate limits from the NEAR routes, and it does not retry signed
transaction submissions. RPC invocation logs and traces are disabled.
Cloudflare and the upstream RPC provider process requests, so this is not
anonymous transport. The client batches contract reads through Multicall3 and
paces shared-endpoint requests across Names clients. Deployment checks remain
fresh; only Multicall3 availability is cached. Chains without Multicall3 use
serialized reads. Free upstream access has no guaranteed capacity.

The dedicated endpoint settings allow an explicit change without discarding
saved registration progress. A keyed or private endpoint keeps its own quota
and spacing. Rate-limited reads retry with bounded backoff, respecting
`Retry-After`; signed transaction submissions are not automatically retried.
Saved RPC overrides remain unchanged. Edit them in Settings → Network and app
→ Base RPC endpoint, also accessible from Public Zcash names. Choose Recommended
to replace an older saved endpoint explicitly, or enter a custom HTTPS URL. The
wallet verifies the same network and registry before saving. This changes only
the RPC; a paused operation retains its saved progress and still requires
review before resuming.

The batch-account default is
`0x4f93112eb41dbec6fada4494272d3d410187a942`, deployed by transaction
`0x7ccd28b3f09d7e1dd1e8adaa6615e7afd8cacdd0e85c8f155737d770a7c1d7b0`
with its exact runtime verified. Configuring this address enables the existing
atomic-registration path, which checks the delegate's complete runtime before
authorization. Deployment alone does not delegate a wallet account. These
deployment/runtime checks are separate from explorer source verification;
consult the contract repository's mainnet reports for its current status.

No JWT, upstream API secret, client fee or referral is embedded. The beta does
not select Base Sepolia. Registry configuration enables the existing reviewed
Names flows; there is no separate build flag that bypasses transaction review.
A wallet-driven mainnet run completed the full reviewed registration flow and
confirmed the active name in an independent readback. This is live integration
evidence for that run; it is not an independent security audit or qualification
of funds-return, release/refund handling, mobile background delivery, or every
physical device. Public-name lookup remains optional and default-off.

Artifacts are:

- `dist/linux/sybil-beta-mainnet-linux-x64.tar.gz`: extract into an empty
  directory and launch `./vizor`; retain its sibling `lib/` and `data/` folders.
- `dist/android/sybil-beta-mainnet-arm64.apk`: Android ARM64 release APK.

Linux keeps the existing `vizor` executable and compatibility identifiers.
Android uses application ID `cash.sybil.wallet`, version `1.0.0-beta.1` / code
`1`, and the newly provisioned Sybil release key. The beta script sets
`ANDROID_REQUIRE_RELEASE_SIGNING=true`; it refuses to publish an APK when
`ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
or `ANDROID_KEY_PASSWORD` is missing. Set those values securely in the build
environment. The separate application ID lets Android users keep Vizor
installed, and there is no automatic wallet-data migration. Preserve the
upstream notices and the SimpleX source/build and license materials described
in [Sybil licensing](SYBIL-LICENSING.md).

## Wallet data and upgrades

An existing mainnet wallet can use a rebuilt Linux beta without clearing its
data. The Android beta is a separate application and does not automatically
migrate Vizor data; import recovery material explicitly into a disposable test
wallet when appropriate. The build scripts do not wipe storage or migrate
testnet accounts. A saved testnet wallet remains a testnet wallet; setting up a
fresh mainnet wallet is an explicit user action.

## GitHub Actions releases

The `Sybil beta release` workflow builds Android ARM64, Linux x64, Windows x64, and macOS Apple Silicon on
GitHub-hosted Linux, Windows, and macOS runners. Run it manually with a version (without
`v`) to test builds without publishing, or push a `v*` version tag to prepare a
draft prerelease. Manual runs can select a single target to retry platform-specific changes.
Draft creation is available only with all targets selected. Existing releases are
never overwritten. All four builds must pass before a draft is created; publishing
that draft remains a manual step.

Configure these repository Actions secrets using the existing Android signing
identity, not a newly generated key:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded existing PKCS12 keystore.
- `ANDROID_KEYSTORE_PASSWORD`: its store password.
- `ANDROID_KEY_ALIAS`: the signing key alias.
- `ANDROID_KEY_PASSWORD`: its key password.

Secrets are provided only to the Android signing/build step, never to pull
requests. The temporary keystore is removed when that step finishes. Only
trusted maintainers should be able to change or dispatch release workflows.
No NEAR or Base provider credentials are needed: clients use the public Sybil
Worker endpoint.

Flutter comes from `.fvmrc`; FVM is pinned to 4.3.0 and Rust comes from
`scripts/release-config/android-reproducible-rust-version.txt`. Android keeps
the explicit SDK/NDK versions in Gradle. Android version codes are the workflow
run number plus one (the original beta used code 1); reruns retain their code.
Keep this workflow's run numbering when releasing updates, or explicitly plan
a higher version-code baseline before replacing it.

Each draft includes all four platform bundles, `SHA256SUMS`, the exact wallet source tree,
and the checksum-verified SimpleX corresponding-source archive from the first
beta. Update the pinned source asset and its checksum whenever bundled SimpleX
inputs change. Windows bundles are unsigned; macOS apps are ad-hoc signed, not notarized.
Beta users provide device feedback. CI checks compilation and packaging; it
does not establish on-device feature qualification.

Desktop bundles include the official checksum-pinned SimpleX v7.0.2 runtime
and the private-pipe host. No public TCP listener is exposed. Lock, account,
foreground, and Tor gates are unchanged. macOS currently targets Apple Silicon;
the upstream Intel runtime is available for a future build lane. Build locally
with `python scripts/build-sybil-desktop.py` after installing pinned FVM/Rust.
The Windows runtime uses OpenSSL 3.0.15; its corresponding source archive is
also attached to each draft.
