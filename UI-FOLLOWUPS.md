# UI follow-ups

Open issues observed during the Linux testnet contact/payment check on
2026-09-10. Recorded for later repair; no implementation changes are included.
See [CONTACT-EXPERIMENT.md](CONTACT-EXPERIMENT.md#linux-gui-evidence-2026-09-10)
for the full test context.

## Incoming funds incorrectly described as insufficient balance

- [ ] Fix the Send validation message when sufficient incoming funds are still
  awaiting confirmations.
- Reproduce: receive 0.1 TAZ, then compose a 0.01 TAZ payment before the wallet's
  six-confirmation policy makes the incoming funds spendable.
- Observed: Home shows 0.1 TAZ, but Send says `Insufficient shielded balance`.
- Expected: explain that funds are awaiting confirmations, while keeping Review
  disabled until the normal spending requirements are satisfied. Preserve the
  insufficient-balance message when the amount and fee actually exceed funds.
- Verify both pending and genuinely insufficient cases, including automatic
  transition to an enabled Review button after confirmations arrive.

## Valid testnet destination labeled unknown

- [ ] Correct the full-address dialog's address-type label.
- Reproduce: send to the accepted revision-2 contact address and choose
  `Show full address` on the review screen.
- Observed: the dialog says `Unknown shielded address` for a valid `utest1...`
  destination. The payment subsequently reached Bob successfully.
- Expected: use an accurate network/address-type label derived from supported
  address decoding. Do not infer verified personal identity from address validity.
- Verify the actual receiver classification before choosing replacement wording;
  the precise cause has not been diagnosed.

## Receipt transaction ID uses reversed byte order

- [ ] Normalize transaction-ID presentation consistently across send, receipt,
  activity, copy actions and explorer links.
- Reproduce: open Bob's received transaction after Alice sends through Contacts.
- Observed: Alice's immediate send screen shows `ef14abeb...37d4beac`, while
  Bob's receipt shows `acbed437...ebab14ef`, the same bytes in reverse order.
- Conventional display transaction ID:
  `ef14abeb93ddef899b21db1860d587e499070f300a99c2abfef167c537d4beac`.
- Evidence: both isolated wallet databases recorded the same transaction mined
  at block 4,337,324, transferring 0.01 TAZ with a 0.0001 TAZ fee.
- Expected: all user-facing surfaces use conventional display order. Inspect
  conversion boundaries before changing anything; do not reverse canonical
  database bytes or already-normalized IDs indiscriminately.
- Verify full IDs and explorer/copy outputs, not only shortened labels. Explorer
  link and clipboard behavior were not checked in this live session.
