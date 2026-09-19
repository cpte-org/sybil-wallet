# ZNS in Sigil

Sigil includes a Names screen for registering, resolving and managing Zcash names through a Base registry. The integration supports software accounts and has desktop and mobile layouts; Linux is the first build target qualified in this work. Hardware-account signing is not implemented.

**Current policy checkpoint: 12 September 2026.** The tiered bond schedule is defined, but no production registry or funded ZEC → ETH → cbZEC registration route is qualified. The existing Base Sepolia deployment uses older economics and is incompatible with the current signing policy. The Base mainnet fork test was declined and was not run. See the current [Names feature notes](lib/src/features/zns/README.md) for pricing, recovery and signing bounds.

The canonical contracts are [../ZNS-contract/contracts/ZcashNameService.sol](../ZNS-contract/contracts/ZcashNameService.sol) and the optional [../ZNS-contract/contracts/ZnsBatchAccount.sol](../ZNS-contract/contracts/ZnsBatchAccount.sol). See the [contract interface](../ZNS-contract/README-ZNS.md) and [agreed economics](../ZNS-contract/ZNS-ECONOMICS.md).

Registration uses a length-based USD minimum, minimum cbZEC floor, automatic fixed fallback and optional extra principal. Floors for labels of 1–2 / 3 / 4 / 5–8 / 9–63 characters are 0.02 / 0.005 / 0.002 / 0.001 / 0.0005 cbZEC. They correspond to a $100,000 floor price and apply before extra principal; fixed fallbacks remain 20 / 5 / 2 / 1 / 0.5 cbZEC. A floor quote stays in USD pricing mode and can exceed the tier's USD target. The actual bond is recorded at registration and never repriced. Original maturity is 365 days; the early fee declines from 10% to zero, and an early release retains an increasing fraction of accrued rewards. Rewards are proportional to bonded principal. Owner-authorized refresh keeps the name current for another 365 days plus 90 days of grace. Address updates and mature claims also refresh it; none resets maturity. Undistributed fees and unretained rewards remain in reserve when no participants remain. There is no treasury or administrator revenue. All names use `.zec`; registration does not verify identity.

After grace, resolution and reward participation stop; the last NFT owner's funds remain claimable. A reused name gets a new position ID. Old-claims withdrawal is separate from releasing a current name. Releases and withdrawals return **cbZEC on Base**; there is no automatic conversion back to native or shielded ZEC.

An account can register and hold multiple ERC-721 name NFTs. The Names inventory fetches 20 per page and binds management to the selected registration ID. Register influencer names normally, then use **Review name transfer** to donate them to a Base address.

Transfer gives the recipient control, the full locked deposit and all unclaimed rewards, including fractions. Maturity and refresh/grace dates stay unchanged. The old Zcash address clears; the recipient sets their own before receiving payments. A mature gift can be released immediately; an immature gift retains the ordinary early-release penalty. Expired NFTs have an individual withdrawal action. Materialized old claims and previously withdrawn rewards are separate from the gift.

Pending work retains its own ID or exact registration label independently of the inventory. Recovery binds the floor-protected NFT protocol and recipient; earlier prototype journals are rejected. The delegated account accepts safe ERC-721 gifts through its receiver callback.

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

Open **Settings → Public Zcash names**. Unlock a software account and enter the verified deployment in the Names configuration:

| Setting | Current behavior |
| --- | --- |
| Registry address | Required; initially empty. Registration is disabled until configured and verified. |
| RPC URL | Defaults to `https://mainnet.base.org`. Remote endpoints require HTTPS. |
| Chain ID | Defaults to Base `8453`. Explicit test configurations support `31337` and Base Sepolia `84532`; HTTP is allowed only for loopback test endpoints. |
| cbZEC token address | Base requires `0xB2000000000000000000008501b13360000cb2EC`, with eight decimals. Test deployments require their own eight-decimal token. |
| Delegated executor address | Optional. Leave empty for ordinary transactions. A configured executor must match the compiled `ZnsBatchAccount` runtime. |

Select **Verify & save settings**. Deployment settings are saved locally. The test-build script sets `ZCASH_DEFAULT_NETWORK=test` and `ZNS_BASE_SEPOLIA=true` to select the published Base Sepolia preset without overwriting another deployment’s settings. The client verifies chain, protocol ID, registry/token compatibility and canonical snapshot blocks. Test accounts need test ETH/tokens supplied separately; live funding requires Zcash and Base mainnet.

A review identifies when the cbZEC minimum floor applies and shows the minimum bond, optional extra, maximum cbZEC deposit and pricing mode, existing balances to use, gas reserve and maximum ZEC/ETH budgets. One unlocked-session confirmation authorizes the bounded sequence: fund native Base ETH through the 1Click adapter if needed, commit, wait, acquire the cbZEC shortfall through Kyber, and register. Each registration signature gets a fresh ten-minute execution deadline. A pricing-mode change or higher required bond needs another review. Optional EIP-7702 execution batches destination calls; delegation persists. Cross-chain funding remains separate. RPC and quote requests follow wallet network policy, including Tor, without a direct-network fallback.

Intent, commitment secret, funding plan and signed transactions are persisted before external actions. Lock, restart, account switch or pause removes signing/payment permission; resume requires review. Signed transactions may still confirm. Ambiguous funding is reconciled using the saved deposit without automatic repayment. Recovery exports/imports the account-scoped journal; keep its commitment secret private. Base identity derives from the mnemonic, BIP-39 passphrase and recorded ZIP32 account index at `m/44'/60'/<index>'/0/0`, surviving a database UUID change.

Names holdings show remaining ETH/cbZEC and old deposits/rewards to withdraw. Converted assets stay in that Base account if registration fails. Name payments re-resolve and bind the current position identity before the ordinary Zcash send review.

The floor-policy client update passed **17 offline Rust tests**, **89 focused Flutter tests** covering recovery, engine, RPC and review behavior, scoped analysis and the Linux release build. These checks did not rerun the full wallet or mobile suites. The registration signature gas ceiling is six million, with actual estimation and the reviewed total fee budget still enforced. Local Solidity tests measured a sparse-deadline maximum-length registration above the previous three-million ceiling. See [the current handoff](../ZNS-IMPLEMENTATION.md) for evidence and limits.

Historical validation passed **14 offline Rust core tests**, **2 native wallet identity tests**, and **10 local runtime checks**. The historical report is [scripts/zns/output/qualification.json](scripts/zns/output/qualification.json); it predates tiered pricing and has not been rerun for this policy. It covers earlier commitment, batch, rollback and recovery behavior, not current oracle pricing or weighted economics, paid funding or live liquidity.

The earlier NFT update passed **94 Flutter main-suite tests**, **six mobile layout checks**, scoped analysis and a Linux debug build. Those counts describe the historical checkpoint; current changes additionally cover quote bounds, extra principal, actual deposited amounts and favorable early-release aging.

The local runtime check can be reproduced without a fork:

```sh
cargo build --manifest-path rust/zns-core/Cargo.toml --example local_sign --offline
npm ci --prefix scripts/zns
npm test --prefix scripts/zns
```

That script starts an ephemeral local Anvil, compiles the canonical sibling contracts and regenerates the wallet's checked executor bytecode. The Cargokit change in this branch makes installed-target discovery lazy for the selected Rust toolchain, so an unrelated incomplete toolchain installation cannot block a healthy Linux build.
