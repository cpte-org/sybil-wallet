# Vizor upstream integration — 2026-09-12

Integrated `chainapsis/vizor-wallet:main` at
`80feec736470fd4a5f2cf82190369b4c3e0dd1b0` (217 upstream-only commits).
Sigil's complete working interface was checkpointed first at
`bf23138e0efa5c08f162f0867c0e8bfc802296ec`. Integration used a separate
worktree and preserves both histories.

## Resolutions

- Retained Wallet / People / Activity navigation, bottom Settings, the Sigil
  dashboard, local contact workflows, and optional Public Zcash names in
  Settings. Voting, Swap, Pay and Gift Cards have no new primary entry points.
  Their underlying upstream mechanisms and compatibility routes remain.
- Combined Linux keyring recovery/session serialization with contact-secret
  rotation, contact lifecycle draining and ZNS account-removal guards.
- Kept upstream payment-request memo handling, network-aware validation,
  cancellation reconciliation and busy-surface protection. Contact snapshots
  travel through desktop/mobile proposal and review routes, and are checked
  before signing. A newly reserved proposal is handed to its review/cancellation
  owner rather than losing its ID when a contact changes during preparation.
- Imported payment-request labels do not get the saved-contact presentation.
- Swap cleanup uses shared idempotent proposal release and balance refresh.
- Regenerated Rust/Dart bindings from the combined APIs.
- Released the Linux keyring queue's completed tail when idle. This avoids
  retaining a previous asynchronous zone while preserving pending-operation
  serialization; Linux widget tests exposed the cross-zone failure.

## Validation

- Linux release build and full Dart static analysis passed.
- ZNS Rust: 17 tests; contact Rust: 13 tests plus the introduction corpus test.
- Storage/ZNS recovery/contact preferences: 107 Flutter tests.
- Session security/Linux secret consumers/keyring: 38 Flutter tests after the
  queue change; coordinator suite then passed 17 tests including the new
  cross-zone regression.
- Desktop compose and review presentation: 60 tests; review lifecycle: 44 tests.
- Settings: 18 desktop and 36 mobile tests; payment-request pane layout: 5 tests.
- Mobile routes: 17 tests; mobile send: 95 tests; manual contacts: 6 mobile tests;
  contact send continuity: 2 desktop tests. The focused mobile Home lane passed.

Tests assert Sigil's deliberate replacement layout instead of upstream's
removed voting/dashboard presentation. No regtest network, real payment,
mainnet deployment, macOS build or physical mobile-device test was run as part
of this integration. The Linux bundle is compiled evidence; interactive wallet
validation remains a separate step.
