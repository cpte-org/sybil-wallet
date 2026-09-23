# Sybil Wallet · Beta

A self-custody Zcash wallet built around your people. Save someone under the
name you use for them, exchange contact details privately, and send shielded
ZEC. Public `.zec` names are optional.

Sybil is an independent fork of [Vizor by Chainapsis](https://github.com/chainapsis/vizor-wallet),
not an official Chainapsis or Keplr product.

## Download

[Linux x64 and Android ARM64 beta](https://github.com/cpte-org/sybil-wallet/releases/tag/v1.0.0-beta.1)
· [Website](https://sybil.cash) · [Report an issue](https://github.com/cpte-org/sybil-wallet/issues)

This beta uses **Zcash mainnet and real funds**. Start with small amounts and
keep your recovery phrase safe. It has not received an independent security
audit. Release notes include installation instructions, checksums, source
packages and known limitations.

## What you can do

- Create or import a wallet, manage accounts, receive and send shielded ZEC.
- Save a contact with a local name and receiving address; no public username required.
- Exchange contact details by QR or through foreground SimpleX delivery, check
  connection keys, share address updates and exchange introductions.
- Export and restore an encrypted backup of linked contacts and relationship keys.
- Register and manage Public Zcash names on Base, with reviewed funding from
  ZEC through NEAR Intents. Public lookup is off until enabled in Settings.
- Choose Zcash and Base endpoints, control local wallet access, and export
  your seed-recoverable Base account key after authentication.

Public names and introductions are not proof of identity. Confirm important
connections through a channel you trust. Base name records and their receiving
addresses are public.

## Beta limits and backups

The Android app uses `cash.sybil.wallet` and installs separately from Vizor.
Existing app data is not imported automatically. Linux retains its existing
storage identity and the `vizor` executable name for compatibility.

Your recovery phrase restores wallet keys. The separate encrypted connection
backup restores linked contacts and relationship keys; it does not contain
manual contacts, notes, pins, pending exchanges or the SimpleX database.
Hosted backups, mobile background delivery and returning Base funds to ZEC
are not included in this release. SimpleX delivery requires Tor to be off.

Network providers handle the requests needed for sync, prices, swaps and public
names. Shielded transactions are scanned locally, but endpoints can still see
network metadata. Transparent Zcash and Base transactions are public.

## Build and contribute

See [beta build instructions](docs/SYBIL-BETA-BUILD.md) for FVM, native inputs,
release signing and build flags. Use the pinned toolchains and lockfiles.

```sh
fvm install
fvm flutter pub get
fvm flutter test
fvm flutter analyze
```

Use [CONTRIBUTING.md](CONTRIBUTING.md) for development guidance. GitHub Actions
packages Android ARM64, Linux x64, Windows x64, and macOS Apple Silicon.
Windows downloads are unsigned; macOS downloads are ad-hoc signed without
notarization. iOS is not yet a Sybil release target.

## Licenses and attribution

Original wallet components retain their [Apache 2.0 license](LICENSE) and
upstream attribution in [NOTICE](NOTICE). The bundled SimpleX runtime is
AGPL-3.0; its source and build inputs accompany the release. Other dependencies
retain their own licenses. See [the distribution licensing record](docs/SYBIL-LICENSING.md)
and Settings → About → Licenses in the app.
