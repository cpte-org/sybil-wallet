# Familiar in the wallet

The visual starting point was `../sigil-UI/sigil-24-big-2`. The Flutter wallet
uses its cream and forest palette, rounded surfaces, personal avatars and
People-first navigation, with a corresponding dark theme. The real wallet now
drives interaction decisions; the HTML prototype is no longer maintained.
Native package identifiers, the executable name and version are unchanged; the desktop sidebar displays the Sigil wordmark.

## Implemented

- Wallet, People and Activity are the primary destinations. Settings sits below
  the desktop account selector and remains the fourth mobile tab. More and Sign
  out are removed. Swap, Pay and voting entry points are hidden, including during
  migration; their existing routes, services and activity history remain intact.
- The shared Wallet dashboard shows available shielded funds, with pending,
  locked and transparent holdings under Balance details. It respects privacy
  mode, completed-sync snapshots and the existing Ironwood presentation policy.
  Sync status sits above the amount, including Tor connection and failure states;
  the desktop sidebar no longer carries a sync indicator. Import/migration screens
  retain their dedicated progress presentation. Its shortcuts include both
  manually saved addresses and accepted connections.
- People combines saved Zcash addresses and connected contacts in one list.
  Add someone offers name/address entry without requiring private connections,
  or Connect privately for a guided code exchange. Saved addresses never acquire
  authenticated relationship authority.
- People supports search, pinned contacts, contacts needing an address check,
  private label changes, notes, suspension and connection backup. A restored,
  suspended or retired
  contact cannot be selected as a payable contact. A label change invalidates
  old payment selections so review uses the current record.
- Private exchange defaults to one step at a time, with QR display, Scan, Paste
  and Copy code. These carry the exact protocol packets; the user still explicitly
  approves sharing a receiving address and reviewing/saving a person or update.
  If scanning is unavailable or a packet cannot fit a QR, Copy code and Paste
  remain available. Technical packet contents stay out of the normal flow.
- Settings → Contact options keeps connections, introductions and backup
  discoverable. Advanced contact tools is a persisted, default-off preference
  exposing manual key pairing, packet delivery and other-network addresses.
  Introductions normally show the available people and unmet prerequisites;
  the raw protocol form requires advanced mode. People no longer has Invitations
  or delivery-console shortcuts.
- Send opens a person picker, and an existing recipient is shown by name on the
  desktop amount screen. Address details expand on demand. Manual destinations
  still go through normal proposal and payment validation.
- The desktop shell uses the reference's narrower, flush sidebar, account menu
  at the bottom, open paper background and rounded-rectangle controls.
- Desktop security and recovery opens as a separate page. Settings groups wallet
  options, security and recovery, Public Zcash names, and network connections.
  Base / Ethereum private key export keeps
  its existing password gate, session checks, clearing and background handling.
- Public Zcash names lives in Settings. Manage my names stays available whether
  lookup is on or off. Resolve .zec names is a separate, persisted, default-off
  preference; enabling it exposes an explicit lookup and Add to People flow.
  There is no automatic .zec parsing in Send. Lookups check the configured registry,
  active record and receiving-address network without requiring registration-policy
  compatibility or deriving a Base key. Before saving, the record is reread; changes
  to ownership, registration or address require another review. Saved entries are
  ordinary local address-book contacts: they neither verify identity nor follow
  subsequent public-name changes. Lock, account/network/configuration changes and
  disabling lookup invalidate pending results and saves before storage begins.
- Payment receipts show the receiving address, network fee and total debit.
  Transaction details can expand after submission. Desktop Receive uses a fluid
  card while preserving the real address/QR, transparent warning and renewal.

## Deliberate boundaries

Manually saved addresses work through the existing wallet address book and do
not require the private contact experiment. They retain its wallet-wide storage
semantics. Notes and pins on these entries persist with the saved address.

Private connections remain restricted to enabled, unlocked software accounts
on testnet/regtest. This presentation work does not change transport, signed
contact protocol, registry contracts, proposals, signing or recovery policy.
QR exchange is not automatically mutual: saving someone does not mean they have
saved you or that reciprocal keys are paired. Guided screens do not remove those
prerequisites or make the experiment production-ready.

**Connection backups include connected contacts and relationship keys only.**
They do not include manually saved addresses, notes or pins. The backup screen
and contact details disclose this limitation. Connected-contact notes/pins use
a separate encrypted account/network-scoped record. Unifying backup coverage
remains necessary before calling this a complete People recovery experience.

Import and migration guidance retains its existing layout and action gates.
Guided contact screens use the existing review and authorization paths; advanced
tools retain manual controls. The mockup's simulated interactions have not been
substituted for wallet operations.

## Validation and trying it

Scoped Flutter analysis passes. Focused checks passed for the new balance
display, theme, private metadata, rename and recipient continuity, existing
contact controller, desktop Home/migration and sidebar, mobile routes, settings,
Base key export, receive and payment review/status. These were targeted widget
and controller runs, not a full repository suite or live payment qualification.

The latest navigation and lookup pass also checked default-off persistence,
record changes before saving, expiry and network rejection, stale session
results, overlapping-save prevention, and mobile balance/settings presentation.
Lookup RPCs were mocked for these checks; this is not live registry qualification.

The guided-contact pass adds source changes plus focused widget/provider checks
for advanced-tool persistence, consent and contact-action availability. Scanner
and transport fixtures are simulated. These are separate from physical camera,
device-to-device exchange and native transport end-to-end validation, which this
pass does not claim.

The reported Linux delivery failure was traced to missing SimpleX runtime
packaging. Linux CMake now caches the optional `SIMPLEX_LIBS_DIR` and bundles its
libraries. This fixes the packaging path; successful loading and live delivery
remain separate checks. The runtime must match the pinned build described in
[tools/simplex/README.md](tools/simplex/README.md).

Build the Linux test bundle with the prepared runtime directory:

```sh
SIMPLEX_LIBS_DIR=/absolute/path/to/prepared/simplex/libs \
  fvm flutter build linux --debug --no-pub \
  --dart-define=ZCASH_DEFAULT_NETWORK=test \
  --dart-define=ZCASH_CONTACTS_EXPERIMENT=true
```

The directory must contain `libsimplex.so` and its sibling libraries. CMake
retains the configured directory for subsequent builds. Without this optional
runtime, code exchange still works manually and delivery shows its unavailable
state instead of implying that a private connection is ready.

Reopen the existing isolated test wallet using the launcher described in
[CONTACT-EXPERIMENT.md](CONTACT-EXPERIMENT.md#run-and-try), reusing its state
directory. The launcher preserves the separate test wallet and keyring. For the prototype's default cream palette, choose Light under Appearance; existing
user theme preferences are retained. Interactive desktop testing and physical mobile validation remain user-led.

Useful first checks are People → Add someone → Enter name and address, selecting
that saved person from Wallet or Send, editing their name/note, and Settings →
Security and recovery → Base / Ethereum private key, and Settings → Public Zcash
names → Resolve .zec names / Manage my names. No new payment is needed just to
review the interface. For private connections, try Add someone → Connect
privately; manual diagnostic tools are under Settings → Contact options.
