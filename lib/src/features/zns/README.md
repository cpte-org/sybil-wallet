# Public Zcash names in Sybil

The wallet uses a single `.zec` namespace. Public lookup says that identity has
not been checked. Saving a public result stores its reviewed Zcash address as an
ordinary local contact; it does not subscribe the contact to a transferable NFT.
Before saving, the wallet rechecks the label, address, Base owner and position ID.

Registration uses the deployed registry's `quoteRegistration(name)` at a canonical
block. Targets are whole USD dollars and cbZEC amounts use 8 decimal places:

| Label length | USD bond target | Minimum floor (cbZEC) | Fixed fallback (cbZEC) |
| --- | ---: | ---: | ---: |
| 1–2 | 2000 | 0.02 | 20 |
| 3 | 500 | 0.005 | 5 |
| 4 | 200 | 0.002 | 2 |
| 5–8 | 100 | 0.001 | 1 |
| 9–63 | 50 | 0.0005 | 0.5 |

The normal quote uses the contract's fixed oracle policy and cannot go below the
length-based cbZEC floor. The floors correspond to `FLOOR_PRICE_USD = 100000` and
apply before optional extra. A floor quote remains USD pricing mode 0, and its
USD value may exceed the tier target. The review labels the floor when the
quoted minimum equals it. This disclosure uses the pinned `usdTarget * 1000`
base-unit mapping; all spending limits still come from `quoteRegistration`.
`minimumBond(nameLength)` exposes the floor; the four quote outputs, two
`bondTerms` outputs and seven registration arguments are unchanged. Fallback is
a distinct pricing mode, never presented as a fresh USD conversion. The review displays the
USD target, active pricing mode, minimum bond, optional extra and total maximum.
Optional extra starts at zero in a collapsed control and is available only at
registration. The contract receives `maxDeposit`, `extraDeposit`,
`expectedPricingMode` and a deadline. A cheaper quote in the same mode can deposit
less than the maximum; `positionInfo.principal` supplies the actual locked amount.

Rewards accrue proportionally to actual principal. The principal exit fee starts
at 10% and decreases linearly to zero over the original 365 days. Early release
returns the elapsed fraction of accrued rewards and forfeits the rest. Separate
reward claims become available at original maturity. Refresh and transfer retain
that original maturity; transfer also preserves the refresh deadline and clears
the payment address. There are no later top-ups or automatic compounding.

The engine checks the live quote before approval, funding and each new signature.
An increased bond or a switch between USD and fallback pricing pauses the flow
for a fresh review. Resuming preserves the commitment, signed transactions and
past funding limits. Existing signed bytes can still be reconciled if pricing
has changed. Each newly signed registration gets an execution deadline ten
minutes after the current chain timestamp; that deadline remains in the exact
saved signed bytes. It does not expire the persisted capped authorization itself. The contract repeats
the pricing-mode, deadline and deposit-ceiling checks at inclusion.

Release uses `exitPreview`. Favorable changes from aging are accepted only while
the maturity status is unchanged, returned amounts do not decrease and neither
forfeiture increases. Other changes require a new review. This remains a current
preview; `release(positionId)` does not encode a minimum-refund constraint.

The protocol fingerprint and journal policy bind these economics. Journal schema
version remains 1, but the semantic policy now includes `floor100k`. Previous
policies and missing pricing fields are rejected; old recovery data is retained
rather than silently upgraded. Approval is always
local to the current unlocked account session.

Focused validation uses `fvm flutter analyze lib/src/features/zns` and
`fvm flutter test test/features/zns`. Run the tagged mobile layout test with
`--tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile`.
