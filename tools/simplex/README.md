# Experimental Linux SimpleX transport

This is a local test integration, not a production distribution. The user approved
an AGPL-compatible Anomaly distribution on 2026-09-11. Preserve upstream notices
and prepare corresponding sources/build instructions for the combined release;
the private-process boundary is not a licensing exemption. Do not remove or
replace the wallet's existing Apache notices.

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
are checked into this repository. The archive is a prototype dependency, not a
completed license/SBOM/corresponding-source release package.

## Build

From the wallet repository, using FVM:

```sh
SIMPLEX_LIBS_DIR=/absolute/path/to/extracted/libs fvm flutter build linux \
  --debug --no-pub --dart-define=ZCASH_CONTACTS_EXPERIMENT=true \
  --dart-define=ZCASH_DEFAULT_NETWORK=testnet
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
Create or open a connection code with a second disposable wallet, then refresh
connections and the inbox. Open a contact code produced by the existing contact
workflow and approve sending it. The recipient opens the received code in that
existing workflow for review.
This temporary manual handoff deliberately does not grant trust to a transport
profile name. Submitted means accepted by the local SimpleX core, not accepted
as a contact by the other person.

## Boundary and lifecycle

- The wallet communicates over inherited stdin/stdout pipes, with no local TCP
  control server, shell, Node runtime, seed phrase, or spending keys.
- The SimpleX database has an independently random encryption key kept in the
  wallet's existing encrypted account/network-scoped secure store.
- The host disables core dumps; lock/account/network/background lifecycle stops
  terminate its process. Dart strings are managed memory, so this does not claim
  guaranteed zeroization of every copy of the database key in the parent VM.
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
Unknown recipients and unmapped contacts retain explicit manual selection;
inbox refresh remains manual. Sending still requires explicit approval.

Contact exchange → Contact backup now provides a seed-unlocked portable encrypted
text archive. It restores into a fresh contact scope, blocks payments until fresh
independent verification, and retains restored relationship keys as inactive.
It does not back up SimpleX databases or resume their ratchets. Signing-key
reconciliation, automatic hosted backups, mobile transport embedding, Tor support,
background notifications, and automatic handoff to contact review are not yet
implemented by this adapter.
