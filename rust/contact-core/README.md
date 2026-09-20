# Contact core

This library adapts the canonical JSON/base64url and strict Ed25519 profile
from `research/2026-09-10/zcash-contacts/interop-rust` in the parent ZNS workspace.
That research verifier was independently implemented from its written wire
specification. This adaptation is **not another independent implementation**.

The wallet supports direct request/response exchanges on Zcash mainnet,
testnet and regtest, with distinct signed network domains. It uses non-laboratory
domain strings and requires a caller-supplied full Unified Address validator.
The direct exchange parser still rejects introductions. These domains do not designate an
adopted Zcash standard. No wallet seed derivation, transport, backup, replay
storage, or automatic key replacement is implemented here.

The wallet owns pending-request consumption, explicit human acceptance,
revision conflict/rollback checks, trust state, encrypted key persistence and
recipient rechecks before signing. A signature binds a key to its chosen
address; it does not prove control of the Zcash spending authority.

The separate `introduction` module adapts the reviewed
`research/2026-09-10/zcash-contacts/intro-protocol/WIRE.md` format, preserving its
strict signature profile, canonical bytes, 30-day invitations and pinned
verifier roles. It creates and verifies ask, offer, consent and delivery packets.
Its results are candidates only: the caller owns accepted associations, explicit
consent, fresh relationship keys and addresses, all known/retired-key checks,
consumption, cancellation and persistence. The module does not provide these
coordinator guarantees or spend authority.

The copied 315-case public corpus in `tests/fixtures` has no runtime dependency
on the research directory. The standalone core test uses an explicit fixture
address oracle; the wallet API test reruns all cases with the wallet's actual
Unified Address decoder and also rejects checksummed malformed receivers.

Run focused tests with `cargo test --manifest-path rust/contact-core/Cargo.toml
--offline --locked` from the wallet root.
