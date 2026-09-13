# Zcash testnet and Public Zcash names

The September 12, 2026 test builds select Zcash testnet (`TAZ`) and opt into the
fresh Base Sepolia deployment. This is mock cbZEC with no asset backing.

| Setting | Value |
| --- | --- |
| RPC | `https://sepolia.base.org` |
| Chain ID | `84532` |
| Registry | `0x402c249649ccb865fe4f16bd26e61007244b2102` |
| Mock cbZEC | `0xd8d322f879ff945f35ec355e021f3a6ad1cc0f88` |
| Delegated executor | `0xe1c5701477af9345d88dd25af41721f7d60e9cb2` |

The sources are verified on Sourcify. Deployment receipts and the five live
fallback-tier quote checks are in the sibling `ZNS-contract/deployments` folder.
Sepolia lacks the canonical Base oracle feeds, so registration uses the fixed
fallback: 20 / 5 / 2 / 1 / 0.5 mock cbZEC for lengths 1–2 / 3 / 4 / 5–8 / 9–63.

Build from this repository with FVM:

`bash scripts/build-sigil-testnet.sh` builds both platforms with contacts enabled.
Pass `android` or `linux` to build only one. Equivalent individual commands:

```sh
fvm flutter build apk --release --target-platform android-arm64 \
  --dart-define=VIZOR_FORM_FACTOR=mobile \
  --dart-define=ZCASH_CONTACTS_EXPERIMENT=true \
  --dart-define=ZCASH_DEFAULT_NETWORK=test --dart-define=ZNS_BASE_SEPOLIA=true
fvm flutter build linux --release \
  --dart-define=ZCASH_CONTACTS_EXPERIMENT=true \
  --dart-define=ZCASH_DEFAULT_NETWORK=test --dart-define=ZNS_BASE_SEPOLIA=true
```

The preset has a deployment-specific configuration storage key. Older settings
and operation journals remain intact. Names and mock tokens from the previous
registry do not migrate to this deployment. Custom settings saved in these new
builds still take precedence over the preset. Public name resolution remains
opt-in; managing names is available in Settings → Public Zcash names.

The Zcash flag changes the default for a fresh wallet installation; an existing
saved network selection still takes precedence. These builds keep the current
application IDs and launcher names. The Android APK uses local development
signing unless release signing credentials are explicitly configured.
