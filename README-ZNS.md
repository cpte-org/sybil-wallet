# ZNS in Vizor

Vizor includes a Names screen for registering, resolving and managing Zcash names through a Base registry. The integration supports software accounts and has desktop and mobile layouts; Linux is the first build target qualified in this work. Hardware-account signing is not implemented.

**No public registry or production deposit amount has been selected. No funded ZEC → ETH → cbZEC registration route has been qualified.** The Base mainnet fork test was explicitly declined and was not run. Local results below use synthetic accounts and tokens.

The canonical contracts are [../ZNS-contract/contracts/ZcashNameService.sol](../ZNS-contract/contracts/ZcashNameService.sol) and the optional [../ZNS-contract/contracts/ZnsBatchAccount.sol](../ZNS-contract/contracts/ZnsBatchAccount.sol). See the [contract interface](../ZNS-contract/README-ZNS.md) and [agreed economics](../ZNS-contract/ZNS-ECONOMICS.md).

Registration locks one fixed cbZEC deposit, read from the registry, with 365-day initial maturity. Owner-authorized refresh keeps the name current for another 365 days plus 90 days of grace. Updating the address or claiming vested rewards also refreshes it; none resets maturity. Names accrue reward credits immediately, including during grace, and can claim after maturity. Early release forfeits the entire deposit and unvested rewards to other participating names. Without other participants, forfeitures remain in reserve until a later early exit can distribute them. There is no treasury or administrator revenue.

After grace, resolution and reward participation stop; the original owner's funds remain claimable. A reused name gets a new position ID. Old-claims withdrawal is separate from releasing a current name. Releases and withdrawals return **cbZEC on Base**; there is no automatic conversion back to native or shielded ZEC.

Use FVM with the pinned Flutter **3.41.6** SDK and the repository's normal native build prerequisites:

```sh
fvm install
fvm flutter pub get
fvm flutter run -d linux --dart-define=ZCASH_DEFAULT_NETWORK=main
```

Desktop is the default. Mobile runs must select a mobile device and also pass `--dart-define=VIZOR_FORM_FACTOR=mobile`; physical Android/iOS devices remain unqualified. This UI-only fixture uses no wallet storage, Rust calls or network:

```sh
fvm flutter run -d linux -t lib/zns_preview.dart
```

Open **Names** in the desktop sidebar, or **Settings → Zcash names** on mobile. Unlock a software account, open the Names settings, and enter the verified deployment:

| Setting | Current behavior |
| --- | --- |
| Registry address | Required; initially empty. Registration is disabled until configured and verified. |
| RPC URL | Defaults to `https://mainnet.base.org`. Remote endpoints require HTTPS. |
| Chain ID | Defaults to Base `8453`. Explicit test configurations support `31337` and Base Sepolia `84532`; HTTP is allowed only for loopback test endpoints. |
| cbZEC token address | Base requires `0xB2000000000000000000008501b13360000cb2EC`, with eight decimals. Test deployments require their own eight-decimal token. |
| Delegated executor address | Optional. Leave empty for ordinary transactions. A configured executor must match the compiled `ZnsBatchAccount` runtime. |

Select **Verify & save settings**. Deployment settings are local; there are no `ZNS_*` build defines. The client verifies chain, protocol ID, registry/token compatibility and canonical snapshot blocks. Test accounts need test ETH/tokens supplied separately; live funding requires Zcash and Base mainnet.

A review shows the deposit, existing balances to use, gas reserve and maximum ZEC/ETH budgets. One unlocked-session confirmation authorizes the bounded sequence: fund native Base ETH through Vizor's 1Click adapter if needed, commit, wait, acquire the cbZEC shortfall through Kyber, and register. Optional EIP-7702 execution batches destination calls; delegation persists. Cross-chain funding remains separate. RPC and quote requests follow wallet network policy, including Tor, without a direct-network fallback.

Intent, commitment secret, funding plan and signed transactions are persisted before external actions. Lock, restart, account switch or pause removes signing/payment permission; resume requires review. Signed transactions may still confirm. Ambiguous funding is reconciled using the saved deposit without automatic repayment. Recovery exports/imports the account-scoped journal; keep its commitment secret private. Base identity derives from the mnemonic, BIP-39 passphrase and recorded ZIP32 account index at `m/44'/60'/<index>'/0/0`, surviving a database UUID change.

Names holdings show remaining ETH/cbZEC and old deposits/rewards to withdraw. Converted assets stay in that Base account if registration fails. Name payments re-resolve and bind the current position identity before the ordinary Zcash send review.

Validation passed **13 offline Rust core tests**, **2 native wallet identity tests**, and **8 local runtime checks**. The runtime report is [scripts/zns/output/qualification.json](scripts/zns/output/qualification.json); it covers Rust/Solidity commitment parity, EIP-7702 registration and rollback, reorg recovery, management operations, maximum-length registration and executor authorization. It does not exercise paid Zcash funding, live liquidity, Base fees or the complete Flutter signing flow.

After the final recovery, fee and quote-expiry fixes, **82 Flutter tests** passed: 36 engine, 10 recovery, 8 confirmed-transaction decoder, 16 data, 8 UI behavior and 4 desktop captures. A separate **4 mobile captures** passed. Scoped analysis was clean, including touched entrypoints and the swap sender; the final **Linux debug build configured for regtest passed**.

The local runtime check can be reproduced without a fork:

```sh
cargo build --manifest-path rust/zns-core/Cargo.toml --example local_sign --offline
npm ci --prefix scripts/zns
npm test --prefix scripts/zns
```

That script starts an ephemeral local Anvil, compiles the canonical sibling contracts and regenerates the wallet's checked executor bytecode. The Cargokit change in this branch makes installed-target discovery lazy for the selected Rust toolchain, so an unrelated incomplete toolchain installation cannot block a healthy Linux build.
