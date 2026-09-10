# Contact exchange experiment

This is a testnet/regtest wallet integration of the identity-first contact work in
`research/2026-09-10/zcash-contacts` in the parent ZNS workspace. It is disabled
by default. It is not an adopted Zcash standard or a mainnet-ready contact system.
The existing public Names system remains a separate discovery experiment.

## Run and try

Build from the wallet root with the configured FVM SDK:

```sh
fvm flutter build linux --debug --no-pub \
  --dart-define=ZCASH_DEFAULT_NETWORK=test \
  --dart-define=ZCASH_CONTACTS_EXPERIMENT=true
```

On Linux, use the isolated launcher instead of opening the bundle directly. A
testnet Dart define does not change the Linux plugin's compiled secure-storage
namespace. The launcher keeps each test actor's wallet files and real KDE Secret
Service in a separate persistent directory and private D-Bus session.

Requirements: a Wayland desktop session and installed `/usr/bin/python3`,
`bwrap`, `dbus-daemon`, `ksecretd`, and `busctl`. Bubblewrap must be permitted to
create namespaces and bind the private Unix socket. The launcher installs
nothing. Run from the wallet root, supplying absolute bundle and state paths:

```sh
python3 scripts/contact-check/linux_wallet.py \
  --bundle "$PWD/build/linux/x64/debug/bundle" \
  --state-dir /tmp/vizor-contact-alice \
  --probe-only

python3 scripts/contact-check/linux_wallet.py \
  --bundle "$PWD/build/linux/x64/debug/bundle" \
  --state-dir /tmp/vizor-contact-alice
```

Run a second launcher in another terminal with
`--state-dir /tmp/vizor-contact-bob`. Each directory must be absent, empty, or
already carry the exact launcher marker; symlink paths and arbitrary nonempty
directories are rejected. Reuse the same directory to reopen that actor. State
is retained, with process logs in `<state-dir>/logs`; there is no automatic
recursive cleanup. A new private KDE Wallet creation/unlock prompt may appear when the
wallet first uses secure storage. Use only disposable test accounts and their
private test collection.

`--probe-only` checks ownership of `org.freedesktop.secrets` on the private bus;
it does not open Vizor, create a collection, or qualify wallet persistence or an
exchange. The GUI launcher shares the host Wayland display and network for
testnet access. Host home directories and the host filesystem D-Bus socket are
hidden; the host AT-SPI bus is not exposed. Use screenshots and coordinate input
for GUI automation. This is isolation for trusted test binaries, not a sandbox
for hostile code. Close the wallet window normally and wait for the launcher to
exit so pending writes can finish; interrupting or terminating the outer launcher
can force-kill its children.

In each isolated wallet, create or unlock a disposable software testnet account
and choose **Contacts → Contact exchange**. Mobile has the same entry and flow
when built with `VIZOR_FORM_FACTOR=mobile` and the experiment define. Mainnet,
locked and hardware accounts cannot use this flow. The signing identities in
this experiment are not seed-recoverable.

1. The recipient of contact information creates a request and copies it to the
   person they want to add, using a trusted channel. Requests expire after five
   minutes. Switching apps retains the public pending request until expiry;
   locking, changing account/network or restarting the wallet cancels it.
2. The other person pastes the request, reviews a fresh Orchard receiving
   address and the separate contact identity, then approves creating a reply.
   The signing record is encrypted and saved before the reply can be copied.
3. The requester pastes the reply, independently compares the complete identity
   and receiving address through an authenticated channel, chooses a private
   local label, and explicitly accepts. A valid signature alone does not
   identify a person or prove possession of the receiving address's spending key.
4. **Send** uses that exact accepted address through the normal send flow.
   Expiry of the exchanged statement does not invalidate an already accepted
   offline contact. No name lookup or fresh peer response is required to pay it.
5. **Request address update** asks that same contact key for another signed
   address. The receiver reviews and accepts the change; it never applies
   silently. Lower revisions and conflicting equal revisions are rejected.
6. **Suspend** blocks contact payments and signed address updates. This slice
   deliberately has no reactivation, identity replacement or restore action.

The visible wallet flow implements direct exchange. The introduction foundation
below has programmatic tests but no role screens yet. QR/deep-link transport,
contact backup/restore, automatic delivery and optional mandatory fresh-response
payment mode remain research work. Sending arbitrary pasted Zcash addresses and
ordinary address-book entries retains its existing behavior; an address match
never turns a legacy entry into an authenticated contact.

## Boundaries

- Local labels and accepted contact records are separate from the ordinary
  address book. Legacy imports and wallet-link imports cannot create accepted
  authenticated contacts. There is no merge/import API for this contact store.
- Each new outgoing relationship has a random Ed25519 seed. The wallet seed,
  spending keys, viewing keys and Base account key are not reused. New shares
  and address updates allocate a fresh Orchard-only UA using the wallet's
  existing address-allocation API.
- Rust owns canonical request/response parsing, strict Ed25519 verification and
  real network-specific Unified Address validation. The new domain strings
  `zcash-contact/request`, `zcash-contact/endpoint` and `zcash-contact/exchange`
  distinguish these messages from the synthetic browser laboratory. They are
  experimental identifiers, not a new version of the ZNS contract.
- Encrypted books and signing records are scoped to account UUID and network.
  Existing password rotation re-encrypts them; account removal deletes them
  after draining in-flight contact writes/address allocation. Invalid envelopes
  and malformed books block contact use instead of creating an empty book.
- A selected recipient carries its exact immutable contact record, book instance,
  mutation generation and account/network scope through desktop/mobile compose,
  review and broadcast. It is checked before and after proposal creation and
  immediately before handing signing to Rust. A stale proposal is discarded.
  This does not cancel signing or broadcast already dispatched to Rust.
- Lock/account/network changes invalidate pending work. Backgrounding clears
  private signing material and confirmation state but retains an unexpired public
  request. Mutable Dart/Rust key buffers are cleared on cancellation/use; Dart
  strings, bridge serialization and platform storage can retain copies, so this
  is not a claim of complete process-memory erasure.
- Loss of the local outgoing signing record requires a new independently checked
  identity. It must not reset the counter for an existing key. Complete storage
  loss or restoring a whole older device image cannot be distinguished from
  pristine/older state without an additional recovery design. Contacts are not
  included in seed or wallet-link recovery.
- Exchanged requests and replies are public signed data, not encrypted messages.
  They should be carried over an appropriate private authenticated channel.

## Focused evidence (2026-09-10)

This section records the direct-exchange slice; introduction evidence is recorded
separately below.

The independent Rust research verifier was adapted into `rust/contact-core`;
this adaptation is not a second independent implementation. The wallet format
has real-address validation and direct exchange only, so the earlier 129-case
synthetic browser corpus does not certify this wallet format.

- Nine contact-core tests exercise canonical encodings/signatures, input bounds,
  challenge/network/subject/expiry binding, malformed points/scalars and parser
  rejection. Two wallet Rust tests exercise full UA decoding and the complete
  direct API exchange with a public deterministic regtest address.
- 39 Dart contact tests cover explicit acceptance, replay, revisions, suspension,
  encrypted repository schemas, scope/lifecycle changes, in-flight key cleanup,
  pending-save draining, offline recipients and immutable selection checks.
- Dedicated shared-send tests suspend the contact while proposal creation or
  mnemonic loading is pending: stale proposals are discarded; the latter does
  not execute a send and clears the mnemonic buffer.
- 123 existing/focused desktop send, recipient-resolution and secure-storage
  checks pass, including password rotation, account-scoped deletion and damaged
  encryption-envelope cases. The dedicated race/resolver set passes eight tests
  (six resolver tests overlap that first group).
- The mobile send lane passes 47 tests, including a real screen-generated
  compose → amount → review handoff retaining the identical contact snapshot.
- Both desktop and mobile contact UI lanes pass 19 checks each, covering
  request, acceptance, sharing, updates, suspension, expiry, consent reset and
  unavailable state. Existing Contacts tests also pass (20 desktop, seven
  mobile). Twelve layout captures were checked at desktop/mobile sizes; they
  use explicit presentation fixtures, not live wallet data.

Useful commands:

```sh
cargo test --offline --locked --manifest-path rust/contact-core/Cargo.toml
cargo test --offline --locked --manifest-path rust/Cargo.toml --lib contacts
fvm flutter test --no-pub \
  test/features/contacts/contact_models_test.dart \
  test/features/contacts/contact_repository_test.dart \
  test/features/contacts/contact_lifecycle_test.dart \
  test/features/contacts/contact_exchange_controller_test.dart \
  test/features/send/contact_send_continuity_test.dart
fvm flutter test --no-pub --tags mobile --run-skipped \
  --dart-define=VIZOR_FORM_FACTOR=mobile \
  test/features/send/mobile_send_screen_test.dart
```

The Linux debug bundle was successfully rebuilt with
`ZCASH_DEFAULT_NETWORK=test` and `ZCASH_CONTACTS_EXPERIMENT=true`; source timestamps
were checked against the rebuilt bundle. Focused Flutter analysis found no issues.
Flutter↔Rust bindings were regenerated and the locked Rust library checked.
Most Dart unit/widget tests use fake wallet/storage/send services. The additional
native check below exercises the real built Rust library and real temporary
wallet databases. Neither set establishes a two-device live exchange, a funded
testnet payment, production key recovery, mobile device behavior or mainnet
readiness. No existing user wallet was opened, payment made or contract redeployed.

## Native bridge qualification (2026-09-10)

The opt-in `contact_native_exchange_test.dart` passes against the Linux debug
bundle's actual `librust_lib_zcash_wallet.so`, with normal FRB version/content-hash
verification enabled. It also passes focused analysis. Ordinary test runs skip
this lane; it requires an explicitly supplied absolute library path.

```sh
fvm flutter test --no-pub --tags contact-native --run-skipped \
  --dart-define=CONTACT_NATIVE_LIBRARY="$PWD/build/linux/x64/debug/bundle/lib/librust_lib_zcash_wallet.so" \
  test/features/contacts/contact_native_exchange_test.dart
```

One integrated scenario checks:

- Two distinct software accounts imported into separate temporary SQLite wallet
  databases using a **public BIP39 test vector and public test passphrases**.
- Real Orchard UA allocation and native request/sign/verify through the generated
  Dart bridge. The two controllers exchange actual signed messages; no crypto or
  contact gateway methods are faked. The gateway's DB path alone is redirected to
  each disposable database.
- Explicit acceptance, consumed-request replay rejection, mismatched challenge,
  modified payload, mainnet refusal and wrong-network address rejection.
- Real AppSecureStore encryption over a file-backed **test platform adapter**,
  disk inspection for plaintext labels/addresses, and reopening new controller,
  repository and storage objects from those files.
- Stable contact identity and increasing outgoing revision after reopening;
  a different freshly allocated address remains unaccepted until review approval.
- Offline use after response expiry, rejection of a pre-reopen recipient
  snapshot, real password rotation, suspension persistence and fail-closed
  handling of a damaged encryption envelope.

Both temporary wallet databases and their encrypted contact files are removed at
teardown. Cleanup was checked after the run. There are no network endpoints,
background sync, transactions, OS-keyring calls or real wallet paths in this
harness. It supplies a synthetic local chain tip so the SQLite address allocator
can record exposure height; that is not evidence of chain synchronization.

The sender's known identity/address substitutes for the independent human check.
Reopening Dart objects from disk is not a whole-process or two-device restart
qualification. The platform adapter intentionally does not qualify Linux
Secret Service, Android Keystore or Apple Keychain behavior. The separate Linux
GUI check below exercises the real Secret Service and full app restart.

## Linux GUI evidence (2026-09-10)

Two separately running instances of the testnet debug bundle used the isolated
launcher, separate SQLite files and separate real KDE Secret Services. The user
completed software-wallet setup. Both wallets synced through
`testnet.zec.rocks:443`; no synthetic chain tip was supplied.

- Alice requested Bob's contact using the screen's Copy request action. Bob
  pasted it, reviewed the fresh address and separate identity, and explicitly
  created a signed reply. Alice pasted that reply, compared the full displayed
  identity/address against Bob's screen, and accepted the local label `Bob test`.
- Send opened with that contact and its accepted address selected.
- Alice's window was closed normally and the launcher exited. Relaunching the
  same isolated state, reopening its private keyring and unlocking the wallet
  retained the identical accepted identity/address after the exchange expired.
- A subsequent address-update request reused Bob's signing identity and produced
  revision 2 with a different address. Alice's original address remained saved
  throughout review. Only explicit acceptance replaced it; Send then selected
  the updated address under the same local label.
- The user funded Alice with 0.1 TAZ. The wallet displayed the incoming funds;
  a 0.01 TAZ compose initially remained blocked while the wallet's six-confirmation
  incoming-funds policy had not yet made them spendable.

A 0.01 TAZ payment to the accepted revision-2 address was broadcast through the
normal contact Send and review flow with a 0.0001 TAZ fee. Both wallets recorded
transaction `ef14abeb93ddef899b21db1860d587e499070f300a99c2abfef167c537d4beac`;
Bob detected the incoming 0.01 TAZ in the mempool and Alice showed 0.0899 TAZ
remaining. Both databases subsequently recorded mining at block 4,337,324; Bob's
receipt screen showed `Received successfully`, 0.01 TAZ and `Completed`.

Observed UI follow-ups: the waiting-for-confirmations state says `Insufficient
shielded balance`; the full-address dialog says `Unknown shielded address` for
this valid testnet destination; and Bob's receipt displays the transaction ID
in database byte order (`acbed437...ebab14ef`) while Alice's immediate send screen
uses conventional display order (`ef14abeb...37d4beac`). These do not negate the
matching mined transaction, but transaction-ID formatting needs correction.
Reproduction steps and expected behavior are tracked in [UI-FOLLOWUPS.md](UI-FOLLOWUPS.md).
No live suspension or mobile-device check was added in this session.

This GUI evidence does not qualify
mobile device storage, introductions, backup/restore, or mainnet readiness.
The isolated state directories are retained under `/tmp/zcash-contact-live.ovSzLn`
for continuation; they contain disposable test wallets and must not be committed.

## Introduction foundation (2026-09-10)

The wallet now implements the reviewed consenting relay behind the same unlocked
testnet/regtest software-account scope. This foundation added coordinator, encrypted storage
and native bridge integration. The subsequent functional UI slice is documented
below. See the parent workspace's
[introduction design](../research/2026-09-10/zcash-contacts/INTRODUCTIONS.md) and
[wire review](../research/2026-09-10/zcash-contacts/intro-protocol/README.md).

- Reciprocal setup explicitly pairs a locally accepted incoming contact key with
  the exact outgoing key independently checked by that peer. It neither infers
  a pairing from a name/address nor permits silently replacing a pairing.
- Carol creates a 15-minute request. Alice selects her accepted Bob, Bob approves
  a newly allocated Orchard address and dedicated signing key, Alice endorses
  those exact details, and Carol explicitly accepts under a private local label.
  Alice can see the fresh address, as agreed for this experiment. No network
  delivery or public directory is added.
- A bounded encrypted contact-book envelope now contains associations, role
  sessions, published introduction signers and attribution. Existing direct
  books remain readable, and direct writes preserve the additional records.
  Bob's reply and fresh signing record are saved in one write before export.
  Carol's accepted contact, consumed request and provenance likewise use one
  write, followed by readback verification.
- Direct and introduction controllers share a process-local queue around the
  entire read/validate/write action. Queued mutations invalidate recipient
  generations. Suspension cannot overwrite a just-accepted contact with an old
  whole-book snapshot. Password rotation and account deletion drain registered
  work; nested lifecycle pauses cannot resume one another prematurely.
- Lock/account/network changes invalidate pending challenges. Restart never
  revives Carol's old request. Bob can explicitly review and resend the same
  persisted reply without allocating another key or resetting its revision;
  Alice can explicitly review and resend the same saved endorsement. A changed
  offer for the same request is a conflict. Cancellation records a tombstone,
  including for a reviewed request not yet published.
- Backgrounding clears consent and mutable loaded, fresh and pending-write key
  buffers immediately. An already dispatched storage write may finish, but no
  late result is exported; a later explicit review reconciles a saved reply.
  Copying mutable keys before an asynchronous repository read also prevents
  caller cleanup from accidentally persisting a zeroed signer. This does not
  erase Dart strings, platform copies or bridge serialization.

Focused evidence for this slice:

- Rust contact-core tests pass, including the copied 315-case reviewed corpus.
  Three wallet API tests pass, including those same 315 cases with the real
  Unified Address decoder, full signing/verification, mainnet refusal and
  malformed-receiver rejection. Repeating the corpus is not 630 independent cases.
- 77 Dart checks pass across introduction coordination/storage, signer
  persistence, existing direct contacts, send continuity and password rotation.
  The new coordinator cases cover explicit consent, conflicting retries,
  cancellation/restart/expiry, observed clock rollback, uncertain writes,
  in-flight key clearing and acceptance/suspension ordering. These state tests
  use fake signatures and storage adapters, not cryptographic evidence.
- The opt-in native introduction scenario exercises three disposable SQLite
  wallets through the actual Rust bridge, real reciprocal direct exchanges,
  real Orchard allocation and AppSecureStore encryption over the file-backed
  test adapter. It accepts only after Carol's approval, retains provenance and
  consumed-request state, refuses a pending request after reopen, and uses Bob's
  saved introduction key for a subsequent direct address update. Alice reopens
  her encrypted store/coordinator and can return only the identical saved
  endorsement after a new explicit approval; refusal exports nothing.
- Flutter/Rust bindings were regenerated and the Linux Rust library rebuilt.
  Focused analysis of contacts, the affected security provider and their tests
  reports no issues.
  The existing GUI bundle and retained live test-wallet directories were not
  replaced or opened for this slice.

Reproduce the additional focused and native checks from the wallet root:

```sh
fvm flutter test --no-pub \
  test/features/contacts/contact_introduction_coordinator_test.dart \
  test/features/contacts/contact_introduction_repository_test.dart \
  test/features/contacts/contact_signer_persistence_test.dart
cargo build --offline --locked --manifest-path rust/Cargo.toml
fvm flutter test --no-pub --tags contact-native --run-skipped \
  --dart-define=CONTACT_NATIVE_LIBRARY="$PWD/rust/target/debug/librust_lib_zcash_wallet.so" \
  test/features/contacts/contact_native_introduction_test.dart
```

The native scenario uses public test seeds, no RPC endpoints, synthetic local
chain tips for address allocation, and temporary encrypted files. It makes no
payment and does not test the OS keyring or actual process/device restart.
Programmatic confirmation substitutes for the independent human pairing check.
The queue protects one wallet process, not concurrent processes or rollback of
an entire encrypted store. Books have size/count limits and fail closed when
full; automatic expiry pruning and backup restore are not implemented. The
coordinator detects backwards clock observations during its lifetime, not a
trusted clock across restart. The tests are not an exhaustive crash matrix.

The functional role screens below are now implemented. Next are three isolated
live wallets, restart, a signed address update and a small testnet payment to the
introduced contact. The earlier direct payment does not qualify
the introduction relay. An accepted dishonest Alice can still endorse an
attacker; the contact records her attributed claim, not proof of a person's
identity or spending authority. No mainnet readiness is claimed.


## Functional introduction UI (2026-09-10)

The experimental direct-contact screen now opens reciprocal setup and the
introduction steps in the existing desktop/mobile wallet shells. Every signing,
pairing, acceptance and saved-packet recovery action calls the introduction
coordinator. The UI shows both full reciprocal keys, actual selected local
participants in approval text, explicitly shareable suggestions, fresh identity
and address, expiry, and immutable historical attribution after acceptance.
Suggestions start empty; private local labels are not silently shared. Accepted
contacts refresh the direct-contact controller and use its existing normal Send
snapshot path from the contact list.

One narrow read-only coordinator API (`overview`) supplies public contact,
pairing and provenance records plus request hashes for available saved
endorsements. It uses the existing scoped serialized read and clears loaded
signer buffers. It does not expose saved packets or secrets. No Rust or protocol
semantics changed in this UI slice.

Executed functional checks:

- 53 focused desktop checks pass: nine introduction widget cases, introduction
  coordination/storage, existing direct-contact UI, and immutable Send continuity.
- The same nine introduction widget cases pass in the mobile lane with
  `--tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile`.
- Widget checks exercise request creation/copy and offer publication through both
  contact selectors; fresh-detail approval and identical saved reply recovery;
  local-label acceptance with provenance and contact refresh callback; exact-key
  pairing; editing, backgrounding and suspension invalidation; expiry before
  copying; and peer-list reload after external mutation during a busy action.
  Request/offer interaction also runs at 844px height with a keyboard inset.
- Focused analysis of `lib/src/features/contacts` and `test/features/contacts`
  reports no issues.
- Linux debug build passes with `--no-pub`,
  `--dart-define=ZCASH_DEFAULT_NETWORK=test` and
  `--dart-define=ZCASH_CONTACTS_EXPERIMENT=true`, producing
  `build/linux/x64/debug/bundle/vizor`. The built app was not launched.

These widget cases use the existing fake-signature coordinator fixtures, no
wallet data, RPC, OS keyring or funds. They are functional UI evidence, not a
live three-wallet introduction or payment qualification. Deterministic review
captures were generated under `/tmp/zns-introduction-ui-captures`. Desktop
captures include the initial typography/single-line-field corrections; the mobile
captures predate those corrections and are superseded. Cosmetic iteration and
full current-source visual qualification were stopped at the user's request
because the wallet design is still changing. No running wallet was launched,
and the retained funded test-wallet directories were not opened.

Reproduce the introduction UI checks:

```sh
fvm flutter test --no-pub \
  test/features/contacts/presentation/contact_introduction_view_test.dart
fvm flutter test --no-pub --tags mobile --run-skipped \
  --dart-define=VIZOR_FORM_FACTOR=mobile \
  test/features/contacts/presentation/contact_introduction_mobile_test.dart
```

### Live introduction check (2026-09-10)

The three isolated Linux wallets have now been opened. Alice is the funded
requester, Bob the introducer, and Carol the subject (these names differ from
the fixed role names in the experimental UI). Bob and Carol completed direct
exchanges in both directions; Bob also accepted Alice, whose existing Bob
contact survived restart. An expired direct reply was correctly rejected
before retrying with a fresh request.

Opening Introductions exposed a real desktop navigation failure: a raw
MaterialPageRoute did not provide GoRouterState to AppMainSidebar. Introductions
now uses a registered GoRouter route on desktop and mobile. The focused routed
sidebar/back-navigation regression test passes, analysis of the six changed
files is clean, and the Linux testnet bundle rebuild passes. Reopening the
rebuilt app verified that the Introductions screen retains its working sidebar.

All four reciprocal associations were confirmed through the UI. A manually
transcribed key with `1` instead of lowercase `l` was rejected; copying the
exact public key from the saved contact allowed the correct pairing.

The live signed introduction completed: Alice requested it, Bob offered Carol,
Carol approved a fresh per-recipient identity and address, Bob endorsed those
exact details, and Alice saved the local label `Carol via Bob`. The UI records
acceptance at `2026-09-10T09:01:57.012Z`, Bob's introducer key, and his shared
suggestion `Carol`. The request expired at `2026-09-10T09:02:21Z`; acceptance
occurred before expiry. The new address was disclosed only through the reviewed
packets, including to Bob as authorized for this experiment.

Alice was restarted and the introduced contact remained accepted. A direct
signed update from Carol then advanced its address to revision 2 while retaining
identity `ed25519:_GPEutFDqGQir2oIISthzUxbfipwfUO6pz4J1tC5PbI` and local label
`Carol via Bob`. Alice explicitly reviewed the old/new addresses before accepting.

Normal Send was opened from that saved contact. Review shows 0.01 TAZ and a
0.0001 TAZ fee. The full destination matches the signed revision-2 endpoint:
`utest164g995unymsgqssld49p95qcpu3nujq9uudwguyaz3e7e2p4ea3mu6uh0u9pmpv5rw7t6e67e5rz4pe0n7kyupw6kzj7e7tl4vc8qsjz`.
The known `Unknown shielded address` wording issue remains deferred.

No new payment was sent. Automatic approval review initially blocked submission;
the user then approved the exact test payment but subsequently requested that
testing stop before submission. Payment delivery through this introduced contact
therefore remains unverified. The live introduction, restart persistence and
signed address update checks above passed. Further testing and UI polishing are
deferred at the user's request. Earlier build-only statements above describe
the preceding UI implementation slice, not this run.
