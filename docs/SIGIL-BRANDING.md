# Sigil branding

This document records the bounded first branding pass completed on 13
September 2026. It separates the name shown to users from the compatibility
identifiers that still belong to the Vizor codebase.

## Naming rules

- **Sigil** is the current user-facing product name. Use it for app display
  labels, onboarding and About copy, settings labels, and new product prose.
- Keep **Vizor** in package and application IDs, namespaces, environment keys,
  database and secure-storage identifiers, protocol and deep-link identifiers,
  update endpoints, URLs, paths, filenames, version constants, and internal
  Dart/Rust/native symbols. Those values are compatibility identities, not
  display copy.
- Keep upstream and third-party names accurate. Keplr and Chainapsis remain
  credited where the copy describes their work; Keystone, ZODL, and SimpleX
  keep their product names. **Anomaly** is the wallet’s former working name,
  not a vendor or a separate distribution. Experimental paths may retain it.
- Do not describe an old Vizor URL as a Sigil-owned domain. Existing GitHub,
  website, service, update, and deep-link URLs remain unchanged until their
  ownership and migration are decided.
- Do not create a replacement logo by inference. The existing Vizor SVG and
  banner assets remain in place until approved Sigil artwork is available. The
  current onboarding/About wordmark uses the existing Sigil text treatment and
  does not introduce a new image asset.

## Branding inventory

- The first pass covers launcher and window labels, platform permission copy,
  About and settings surfaces, onboarding and wallet-link guidance, donation
  copy, the iOS sync Live Activity label, store metadata, and the top-level
  product READMEs.
- Remaining Vizor occurrences are concentrated in compatibility identifiers,
  inherited URLs and release filenames, internal symbols and assets, upstream
  protocol payloads, and operational migration, payment, voting, privacy, and
  background-notification copy.
- No first-party wallet branding uses the former Anomaly name. Experimental
  tooling and local evidence may retain that name in temporary paths or
  compatibility identifiers; those references describe local test material,
  not a third-party owner or distributor.

## Completed in this pass

- Root product prose in `README.md` and `README-ZNS.md`, the public ZNS feature
  README, and Android store title/description now use Sigil where they describe
  the wallet.
- Flutter's application and desktop window display titles use Sigil. Linux's
  `APP_DISPLAY_NAME`, Android's manifest label, iOS/macOS display and
  permission copy, and the iOS sync Live Activity label use Sigil.
- Windows and native biometric reset prompts use Sigil while executable names,
  storage prefixes, and application IDs remain unchanged.
- The onboarding/About wordmark uses the existing Sigil text and typography
  treatment; the legacy Vizor SVG and banner assets remain available for a
  later approved artwork pass.
- About, settings, onboarding, Keystone connection guidance, and desktop/mobile
  wallet-link copy use Sigil. About links are labeled as upstream destinations
  because their current targets are still the Chainapsis/Vizor GitHub and
  website URLs.
- The existing donation destination is left intact and is labeled as the
  upstream Vizor beneficiary in the donation flow and root README.
- Linux update notices identify the fetched release as upstream Vizor, while
  Windows update and privacy prompts describe the current app as Sigil. The
  update providers, release URLs, and native identifiers are unchanged.
- Android store copy identifies `functions.vizor.cash` as an existing service;
  no service URL or ownership claim was migrated. Terms and Privacy routes show
  a `Not published yet` notice for this test build and do not present a
  finalized Sigil policy.

## Remaining identity decisions

- Approve Sigil logo artwork and then replace the existing Vizor SVG and banner
  in a dedicated asset pass.
- Decide the canonical Sigil website, GitHub location, service domains, and
  deep-link/update migration plan before changing any URL or endpoint.
- Decide whether macOS/Windows bundle and release artifact names should migrate
  later. This pass leaves `PRODUCT_NAME`, executable/binary names, package IDs,
  and release filenames unchanged for compatibility.
- Decide whether the existing donation address or store signing/release
  identity should ever receive a product-facing Sigil label; until then, the
  donation remains identified as an upstream Vizor destination.
- A later copy sweep can update operational migration, payment, voting,
  notification, and test-fixture wording that still names Vizor. Those strings
  were outside this bounded first pass unless they were part of an app display
  label, About/settings surface, or onboarding flow.

Licensing and notice files are intentionally outside this document and this
branding pass.
