# Sigil test builds — September 18, 2026

The user confirmed that the prior rewind fix restored syncing. This pass keeps
that fix and the existing wallet/application identities, network presets and
version. No mainnet deployment, live payment, commit or push was performed.

## Changes

- Foreground SimpleX reconciliation on Linux and Android ARM64, with lifecycle/privacy shutdown,
  visible disconnect errors and explicit retry. Receiving never accepts a
  contact or sends a payment automatically.
- Android uses a non-exported service in a separate process, bounded Binder
  messages and a pinned native runtime. Reopening waits for process death;
  returning from the background requires explicit reopening. The test-build
  script verifies and bundles the runtime automatically.
- Restored-contact verification checklist and guided new-identity reconnect;
  restored signing keys remain inactive. Backup detail is collapsed by default.
- Specific connection-unavailable messages and a Paste address control.
- Sigil display copy and the existing Sigil text wordmark on onboarding/About.
  About opens bundled license notices on both layouts.
- Modification notices on reviewed upstream source files, including the new
  Android integration changes; exact Apache,
  attribution and font-license assets packaged in both clients.
- Corrected the Names funding guard to use the wallet's canonical `main`
  network name, with test networks still excluded from live funding.

## Build and verification

Built with `scripts/build-sigil-testnet.sh` using the pinned FVM SDK:
Zcash testnet, Base Sepolia preset and the contact experiment enabled;
Android also uses `VIZOR_FORM_FACTOR=mobile`.

- Linux: `build/linux/x64/release/bundle/vizor` (keep the entire bundle together).
- Android: `build/app/outputs/flutter-apk/sigil-testnet-arm64.apk`.
- Android application ID remains `com.keplr.vizor`; display label is `Sigil`.
  APK Signature Scheme v2 verification passed. This is a sideload test build.
- Both compiled clients contain registry
  `0x402c249649ccb865fe4f16bd26e61007244b2102`.
- Linux bundles the verified SimpleX v7.0.2 runtime: all 161 upstream files
  match the pinned archive, plus AGPL text and source/build references.
- Both release builds, focused analysis, contact/recovery/transport tests,
  mobile contact-layout checks, About checks, funding-network regression and
  whitespace checks passed. Two final inbox-disconnect/retry regressions passed.
  The Android follow-up passed 16 focused adapter/lifecycle/widget tests and a
  focused JVM UTF-8/bounds test. Focused analysis and whitespace checks passed.
- Real Android execution used an isolated API 35 Google APIs emulator with
  ARM64 native translation (`libndk_translation.so`) on an x86_64 KVM host.
  Five exercised native tests passed: encrypted create/wrong-key rejection/
  reopen, close during open, unbind termination, stale-session close protection,
  and keeping the core outside the wallet process. The default relay case did
  not run without its explicit invitation; it was then executed separately.
- A disposable Linux-to-Android SimpleX connection passed a live public-relay
  test: matching connection security codes, packet delivery in both directions,
  native process termination, and recovering the received reply from encrypted
  history after reopening. The reopened test was corrected to perform the same
  `/u`, route configuration and `/_start` sequence as the real adapter.
  No wallet funds, actual contacts or payment were involved.
- Android packaging contains only ARM64 libraries. All three extracted SimpleX
  ELF files match the verified upstream APK byte for byte. The final APK passes
  Signature Scheme v2 verification; package ID and version remain unchanged.
  Both clients bundle the exact AGPL text and source/build references in About.

APK SHA-256:
`8943090274ddb1c8da5bc55b47dc619ce146c88e3318f07cee7788ecf2a238fd`

Linux `lib/libapp.so` SHA-256:
`8f2fde7fd8f827075c7bd30f2feacc706d92952c9026b4024aacd20b094c2bb1`

## Remaining boundaries

Linux and Android ARM64 private delivery are available in advanced contact
tools for unlocked software test/regtest accounts. They operate in the
foreground with direct networking while Tor is off. QR and copy/paste remain
available. iOS embedding, Tor routing and background notifications remain
outside this implementation. Native isolation is documented in
`tools/simplex/ANDROID-EMBEDDING.md`.

Emulator evidence does not replace testing on the user's physical phone or
across Android/OEM releases. ELF alignment was inspected for 16 KiB compatibility;
a physical 16 KiB-page device was not tested. Parent Binder-death shutdown is
implemented and source-reviewed; the runtime suite did not separately kill the
wallet parent process. Wallet-lock/privacy late-result behavior has focused
Dart coverage, while the native process boundaries have the live evidence above.

Hosted backup provider selection, automatic peer key rotation, production NEAR
funding infrastructure/qualification, and conversion of Base balances back to
shielded ZEC remain outstanding. Public-release licensing also needs the
unresolved `desktop_window_bootstrap` grant, remaining distribution-file and
dependency notice review, and a complete SimpleX corresponding-source package;
see `SIGIL-LICENSING.md`.
