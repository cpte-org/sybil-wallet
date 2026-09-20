# Linux and Android SimpleX transport

The Sybil beta includes optional foreground contact delivery through SimpleX.
The process boundary is not a licensing exemption: preserve the upstream
Apache and AGPL notices and distribute the corresponding source described in
[the release licensing record](../../docs/SYBIL-LICENSING.md).

## Pinned native runtime

- Release: [simplex-chat-libs v7.0.2](https://github.com/simplex-chat/simplex-chat-libs/releases/tag/v7.0.2)
- Asset: `simplex-chat-libs-linux-x86_64.zip`
- Download: https://github.com/simplex-chat/simplex-chat-libs/releases/download/v7.0.2/simplex-chat-libs-linux-x86_64.zip
- SHA-256: `235e8afc1942f098e6ad27b7e2947eced0a670e2ed35f064d802b71bbcfc1610`
- Size: 43,451,028 bytes
- Native API/source: [SimpleX Chat v7.0.2](https://github.com/simplex-chat/simplex-chat/tree/v7.0.2)
- Upstream license: [AGPL](https://github.com/simplex-chat/simplex-chat/blob/v7.0.2/LICENSE)

Verify the archive checksum before extracting it. Keep the complete `libs/`
directory together; `libsimplex.so` depends on its sibling libraries. No binaries
are checked into this repository. The Sybil beta release attaches a separate
source archive containing the pinned source and build inputs.

## Build

The ARM64 Android beta build includes the pinned runtime automatically
(release-signing environment required; see [build instructions](../../docs/SYBIL-BETA-BUILD.md)):

```sh
bash scripts/build-sybil-beta.sh android
```

The script verifies the official APK checksum before extracting its three
native transport libraries. Gradle reads `SIMPLEX_ANDROID_LIBS_DIR` for the
generated `jniLibs/` directory and rejects missing libraries. The private
`:simplex` service loads them in a separate process. Builds without this
optional runtime retain QR/copy-and-paste exchange. See
[Android embedding](ANDROID-EMBEDDING.md) for pinned inputs and qualification.

Linux:

From the wallet repository, using FVM:

```sh
SIMPLEX_LIBS_DIR=/absolute/path/to/extracted/libs fvm flutter build linux \
  --debug --no-pub --dart-define=ZCASH_CONTACTS_EXPERIMENT=true \
  --dart-define=ZCASH_DEFAULT_NETWORK=test
```

CMake builds `simplex-host` from `native_host.c` and installs the optional library
directory at `bundle/lib/simplex`. The first CMake configuration initializes
`SIMPLEX_LIBS_DIR` from the environment and stores it as a cached path. Later
builds retain that choice when the environment variable is absent. A selected
directory must contain `libsimplex.so`; configure fails clearly if it is missing.
The complete directory is installed together, including any runtime notices it
contains.

To change or clear a previously configured runtime, update the CMake cache
explicitly before the next FVM build (use the matching build-mode directory):

```sh
cmake -S linux -B build/linux/x64/debug \
  -DSIMPLEX_LIBS_DIR=/absolute/path/to/extracted/libs
# Opt out again:
cmake -S linux -B build/linux/x64/debug -DSIMPLEX_LIBS_DIR=
```

Without the optional runtime, contact code exchange still works. Private delivery
shows an unavailable state with a path back to code exchange. Developer-only
absolute overrides are `SIMPLEX_NATIVE_HOST` and `SIMPLEX_NATIVE_LIBRARY` Dart
defines.

Turn on advanced contact tools in Contact settings, then open Private delivery.
Create or open a connection code with a second disposable wallet. Connections
and the inbox refresh while private delivery is open in the foreground. Open a contact code produced by the existing contact
workflow and approve sending it. The recipient opens the received code in that
existing workflow for review.
This temporary manual handoff deliberately does not grant trust to a transport
profile name. Submitted means accepted by the local SimpleX core, not accepted
as a contact by the other person.

## Boundary and lifecycle

- Linux communicates over inherited stdin/stdout pipes; Android uses bounded,
  session-scoped Binder calls to a non-exported service in a separate process.
  Neither uses a local TCP control server, shell, Node runtime, seed phrase or
  spending keys.
- The SimpleX database has an independently random encryption key kept in the
  wallet's existing encrypted account/network-scoped secure store.
- The host disables core dumps; lock/account/network/background lifecycle stops
  terminate its process. Dart strings are managed memory, so this does not claim
  guaranteed zeroization of every copy of the database key in the parent VM.
  Android also links the parent Binder's death and removes its service binding
  before termination. Replacement opens wait for confirmed process death.
  Returning from the background requires explicit reopening.
- Direct networking is available only while the wallet privacy state is settled
  to Tor off. Tor and its transitions disable delivery. The native core uses
  `smp-proxy=always smp-proxy-fallback=no` before starting network activity.
- The encrypted wallet journal persists outgoing bytes/IDs before submission.
  Ambiguous attempts retain those IDs for explicit retry. Native chat history
  is reconciled after reopening, and incoming duplicates are suppressed.
- Packets remain untrusted. Signature, audience, freshness, and user consent
  checks remain in the existing contact workflow. Delivery never authorizes a
  payment or accepts an introduction.
- Experiment limits: 100 connections, 100 journal records, 16 KiB packet limit,
  bounded history scans and control output. Full journals stop accepting new
  records instead of silently evicting replay records. This is not a production
  retention/abuse policy.

Account deletion removes scoped secure-store material; encrypted native database
files may remain without their key. Device loss recovery, secure state migration,
automatic backups, and physical cleanup of those orphan files remain work.

## Focused verification

```sh
cc -std=c11 -Wall -Wextra -Werror tools/simplex/native_host.c -ldl \
  -o /tmp/anomaly-simplex-host
SIMPLEX_NATIVE_HOST=/tmp/anomaly-simplex-host \
SIMPLEX_NATIVE_LIBRARY=/absolute/path/to/extracted/libs/libsimplex.so \
  fvm flutter test --no-pub test/features/contacts/contact_delivery_test.dart \
  test/features/contacts/simplex_native_transport_test.dart
```

The opt-in native test uses disposable encrypted profiles and a public test
packet over public SimpleX relays. It verifies connection, delivery, reopening
the encrypted recipient database, history reconciliation, duplicate suppression,
and a disabled-network rejection. Without the two environment variables the live
test skips, while the journal and carrier tests remain local.

New signed introduction invitations last 30 days and can be explicitly resumed
after reopening the wallet. Existing 15-minute requests keep their deadline.
Final acceptance requires a separate short-lived address challenge for the exact
introduced identity/address/revision; resumption never restores user approval.
Contact and introduction reviews now offer inline private inbox selection and
approved sending, including fresh address-check replies. Signature verification
and acceptance remain separate explicit steps.

In Private delivery, open **Verify a contact connection**, select an accepted
wallet contact and a SimpleX connection, and show the security code. Compare it
with that person through an independent trusted channel before approving and
saving. This is a local human attestation, not an automatic signed proof linking
the wallet identity to SimpleX. A matching profile label is not evidence.

Eligible outgoing reviews with a known recipient identity select the saved
connection automatically. Every bound send and queued retry checks that the
contact is still accepted, its identity and saved mapping are unchanged, and the
native security code still matches. Forgetting a mapping blocks its queued sends.
Unknown recipients and unmapped contacts retain explicit manual selection.
An activated foreground session drains bounded native event batches and
reconciles durable history every five seconds after the previous pass completes.
Lock, account/network change, background, privacy-route changes, disposal or a
refresh failure stop it. Failures expose a manual retry; scans never overlap,
and sends are never retried automatically. Sending still requires explicit approval.

Contact exchange → Contact backup now provides a seed-unlocked portable encrypted
text archive. It restores into a fresh contact scope, blocks payments until fresh
independent verification, and retains restored relationship keys as inactive.
It does not back up SimpleX databases or resume their ratchets. Signing-key
reconciliation, automatic hosted backups, iOS transport embedding, Tor support,
background notifications, and automatic handoff to contact review are not yet
implemented by this adapter.

Android ARM64 delivery is included by the test-build script; see
[the native embedding record](ANDROID-EMBEDDING.md) for upstream artifacts,
lifecycle boundaries and validation limits.
The contact archive cannot repair a lost SimpleX database key or restore its
ratchets; the missing-key path preserves the encrypted database and offers
manual contact code exchange.
