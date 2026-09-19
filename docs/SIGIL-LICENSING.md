# Sigil licensing and attribution

This document is the release-facing licensing record for the Sigil wallet
tree. It records what is observable in the repository and in the locally
available build inputs; it does not turn an unresolved ownership or license
question into a clearance. The release owner must resolve the open decisions
before distributing a binary or a source archive.

The audit below was refreshed on 2026-09-18 against commit `94a168e0`
(`fixes`) in `/home/besudo/Git/ZNS/vizor-wallet`. The working tree contains
concurrent branding and integration work. The committed comparison base used
for fork evidence is `upstream/main` at `80feec73`; uncommitted files are not
included in the historical counts below. No full build or dependency
installation was run for this packaging update.

## Release gate

The current tree is not ready for a licensing-complete binary or source
release. The parent/release owner must decide or complete each of these gates:

* confirm the copyright authority for the fork additions and non-font artwork,
  preserve any applicable upstream mark notices, and review the Sigil name and
  any former internal Anomaly identifiers that remain in files being shipped;
* satisfy Apache 2.0 section 4(b) for modified upstream files that ship;
* replace the `desktop_window_bootstrap` package's placeholder license;
* verify the bundled OFL text and font notices in each final target artifact;
* generate a complete target/feature-specific Dart and Rust notice inventory;
  and
* if a Linux or Android SimpleX runtime is enabled, ship its AGPL notices and
  corresponding source using a conveyance method permitted by AGPL section 6;
  document the selected method and maintain any offer required by that method.

The evidence and exact release actions for each gate are below. The September 18 Linux test build enables the verified, pinned SimpleX runtime.
It includes the AGPL text and source/build references; a complete public-release
corresponding-source package and dependency notice inventory remain outstanding.

## Current license boundary

The repository-level `LICENSE` declares the Apache License 2.0 for the Work
identified by its notices and currently names
“Vizor contributors” in its appendix. It is byte-for-byte the same root license
as the inspected `upstream/main` tree. The license history shows an earlier MIT
license at `cd43ada4`, followed by the Apache 2.0 change at `7f1cbf95`.
Keep the original file and its copyright/license grant; do not relabel the
wallet wholesale as AGPL because one optional component is AGPL. This root
declaration does not clear every fork addition, dependency, asset, product
mark, or optional runtime for redistribution.

The inspected upstream tree has no root `NOTICE` or `COPYING` file. Its
component-specific notices are retained in the files called out below. This
audit adds `NOTICE` deliberately as a new attribution addendum, so future
derivative distributions must preserve the applicable readable attribution
content under Apache 2.0 section 4(d).

The committed fork differs from `upstream/main` in 257 paths, with 63,883
added and 10,198 deleted lines. The fork contains wallet, ZNS, contact,
platform, test, and documentation changes. That history establishes a
derivative-work review requirement; it does not identify a legal rights holder
for every new file, branding item, or exported design asset. The current
copyright line is evidence of repository policy, not evidence that a new
product name or every asset has been cleared for redistribution.

The NOTICE does not modify the license and does not replace component license
texts.

## Runtime legal assets

The root legal files remain the source-archive copies. The Flutter bundle now
also includes exact, byte-for-byte copies at these paths:

* `assets/legal/LICENSE` — the root Apache License 2.0 text;
* `assets/legal/NOTICE` — the attribution addendum;
* `assets/legal/fonts/OFL-1.1.txt` — the standard OFL 1.1 text and font-specific
  notices; and
* `tools/simplex/licenses/SimpleX-Chat-v7.0.2-LICENSE` and
  `tools/simplex/licenses/SIMPLEX-SOURCE-AND-BUILD.txt` — the pinned native
  transport's AGPL text and source/build references, also available from About.

`pubspec.yaml` lists each file explicitly so test and release target bundles
retain readable legal text. `lib/src/core/legal/sigil_legal_notices.dart`
exposes `registerSigilLegalNotices()`, which registers the three files lazily
with Flutter's `LicenseRegistry`. The application startup owner must call that
function once before a legal-notices view is opened. This packaging pass does
not claim a rebuilt client until the target bundle is inspected for those three
paths and the runtime legal view has been exercised.

## Apache modified-file audit

The authoritative Apache 2.0 text is the [Apache License 2.0 text](https://www.apache.org/licenses/LICENSE-2.0.txt).
Section 4 requires all of
the following when a derivative is distributed:

* Section 4(a): give recipients a copy of the Apache license.
* Section 4(b): cause each modified file to carry a prominent notice stating
  that it was changed.
* Section 4(c): retain applicable copyright, patent, trademark, and
  attribution notices from the upstream source.
* Section 4(d): if the distributed Work contains a NOTICE file, carry its
  readable attribution notices into the derivative distribution. The NOTICE
  text is informational and cannot change the license.

On September 18, the fork applied prominent modification notices to 123
changed upstream source files, preserving their original contents and notices.
The marker identifies changes by the Sigil fork and does not invent copyright
ownership or replace any license. Generated files, vendored files, and non-source
metadata remain separately listed for release review. The lightwalletd protocol
files retain their original MIT notices.

The maintainable review list is generated by
`tools/licensing/apache_modified_files.py`:

```sh
python3 tools/licensing/apache_modified_files.py \
  --base upstream/main --head WORKTREE \
  --output docs/SIGIL-APACHE-MODIFIED-FILES.md
```

The snapshot in `docs/SIGIL-APACHE-MODIFIED-FILES.md` compares the actual
`upstream/main` tree (`80feec73`) with tracked working changes. Counts and exact
notice coverage are recorded there. Untracked additions are outside Git's diff
and must be included in the release inventory after staging. The writer accepts
an explicit reviewed path list; rerunning it is idempotent.

For later changes, use the writer with
`--apply --paths-file <reviewed-list>`. It accepts only explicitly listed
modified upstream source files, skips generated and vendored paths, preserves
shebangs, encoding declarations, and XML prologs, and inserts the neutral
comment `Apache-2.0 section 4(b): modified from upstream by the Sigil fork.`
It does not add a copyright owner, alter a license, or touch added files.

## Existing component notices

The following notices are present in the source tree and must remain with the
corresponding component:

| Component | Evidence in this tree | License or notice boundary |
| --- | --- | --- |
| Cargokit | `rust_builder/cargokit/LICENSE` | Contains the original MIT and Apache 2.0 texts and its copyright notice. |
| Windows secure-storage fork | `third_party/flutter_secure_storage_windows/LICENSE` and `VIZOR_FORK.md` | BSD 3-Clause text is retained; fork-specific behavior is described separately. |
| Zcash lightwalletd protos | `protos/compact_formats.proto` and `protos/service.proto` | Existing headers identify The Zcash developers and the MIT license. |
| Mobile Scanner | `pubspec.lock` pins Chainapsis’ git package at `7224aa38c18459159acde0ae2f22685fbe46ceb4`; the package `LICENSE` is BSD 3-Clause | This covers the inspected package source. Its platform-native dependencies still belong in the target release inventory. |
| Desktop window bootstrap | `pubspec.lock` pins Chainapsis’ git package at `16b1b30e08004e91521cc511db098f9561dfeb0a`; the [pinned upstream LICENSE](https://github.com/chainapsis/desktop_window_bootstrap/blob/16b1b30e08004e91521cc511db098f9561dfeb0a/LICENSE) and current `main` both say `TODO: Add your license here.` The [official repository metadata](https://api.github.com/repos/chainapsis/desktop_window_bootstrap) reports `Other` / `NOASSERTION` with no license URL. | **Blocked.** No clear license grant or copyright authority is available at the pinned source. Do not copy the wallet's Apache terms onto this package; obtain an upstream grant or remove it from a distributed target. |

The pinned git package URLs and revisions are recorded in `pubspec.lock`:

* `https://github.com/chainapsis/mobile_scanner.git`
* `https://github.com/chainapsis/desktop_window_bootstrap.git`

### Direct Dart and Flutter packages

This is a bounded inventory of direct production packages from the locked
Flutter graph. The license family below is based on each package’s local
`LICENSE` text in the package cache observed during this audit; it is not an
exhaustive transitive dependency clearance.

| Observed package license | Locked direct packages |
| --- | --- |
| MIT | `cupertino_icons` 1.0.9, `flutter_riverpod` 3.3.1, `flutter_rust_bridge` 2.11.1, `flutter_svg` 2.2.4, `pretty_qr_code` 3.6.0, `window_manager` 0.5.1 |
| BSD 3-Clause | `characters` 1.4.1, `crypto` 3.0.7, `file_selector` 1.1.0, `fixnum` 1.1.1, `flutter_secure_storage` 10.0.0, `go_router` 17.1.0, `mobile_scanner` 7.2.0, `path_provider` 2.1.5, `protobuf` 6.0.0, `qr_flutter` 4.1.0, `share_plus` 12.0.2, `shared_preferences` 2.5.5, `url_launcher` 6.3.2 |
| Apache 2.0 | `cryptography` 2.9.0, `grpc` 5.1.0 |
| BSD 3-Clause, local fork | `flutter_secure_storage_windows` 4.1.0+vizor.1, selected by the root path override |
| Unknown | `desktop_window_bootstrap` 0.0.1; its pinned package has a placeholder license file |

Flutter generated a gzip-compressed `NOTICES.Z` in the inspected build assets.
The uncompressed payload was 1,478,347 bytes and included package and engine
notices, including the desktop bootstrap placeholder. The payload is useful
build evidence but is not a complete source-tree inventory: it does not replace
the Rust license inventory, does not provide the font OFL text, and must be
made reachable through the release’s normal legal-notice path. The inspected
Android APKs contained `assets/flutter_assets/NOTICES.Z` and the 11 app font
files, but no root `LICENSE`, root `NOTICE`, or standalone OFL file. The
inspected Linux release bundle likewise contained `NOTICES.Z` and the fonts,
but no standalone license/notice files.

## Native Rust dependency boundary

`cargo metadata --manifest-path rust/Cargo.toml --locked --offline` succeeded
read-only and reported 827 packages. The following entries are the notable
license cases observed in the normal graph or lockfile; the list is bounded and
does not claim that every package has been cleared.

| Package and version | Observed graph/license fact | Release action |
| --- | --- | --- |
| `option-ext` 0.2.0 | In the normal graph through `dirs`/`directories`/Tor; declared MPL-2.0. | Preserve the MPL 2.0 text and any applicable file notices. |
| `priority-queue` 2.7.0 | In the normal graph through `tor-rtmock`/Tor; declared `LGPL-3.0-or-later OR MPL-2.0`. | Record the license choice used for distribution and carry the relevant license text; do not collapse the expression to “Apache.” |
| `rustls` 0.23.43, `ring` 0.17.14, `aws-lc-rs` 1.18.0 | Present in the Linux normal graph; metadata gives Apache/ISC choices or combinations. | Preserve the package license and third-party notices selected by the exact feature graph. |
| `webpki-roots` 1.0.9 | Present in the Linux normal graph; its package license is CDLA-Permissive-2.0, a data license. | Include the [CDLA-Permissive 2.0 text](https://cdla.dev/permissive-2-0/) when redistributing the root data. |
| `fastrlp` 0.3.1 and 0.4.0 | Present in `Cargo.lock` with MPL-2.0 but no normal reverse dependency under the selected features; they are optional `ruint` entries. | Recheck if features change; do not report them as linked runtime code from this audit. |
| `r-efi` 5.3.0 and 6.0.0 | Target-specific lock entries with `MIT OR Apache-2.0 OR LGPL-2.1-or-later`; not observed in the Linux normal output. | Recheck each release target and retain the permissive-choice evidence if that target uses it. |
| `zakura-*` Zcash packages | The pinned Zakura library/wallet packages report `MIT OR Apache-2.0` in Cargo metadata. | Keep their exact git/registry revisions and package license texts in the release SBOM. |
| `zcash_voting` `v3.1.0-rc.16` | Pinned git package reports `MIT OR Apache-2.0`. | Preserve the revision and the selected license path. |
| `ur` and `ur-registry` | Pinned Keystone/Valargroup packages report MIT. | Preserve their source revisions and MIT texts. |
| `zcash_script` 0.4.5 | Reports Apache-2.0. | Carry the Apache text and any source notices. |

The local `rust/zns-core` and `rust/contact-core` packages do not declare a
crate-level `license` field. They are private path packages and currently rely
on the repository policy; the release owner should make that scope explicit
before treating either crate as independently redistributable. A full Rust
SBOM and license-text assembly remains required for every target and feature
set.

Primary license references for this graph include the [Mozilla Public License
2.0](https://www.mozilla.org/en-US/MPL/2.0/), the [CDLA-Permissive 2.0
agreement](https://cdla.dev/permissive-2-0/), and the upstream [Zcash Rust
libraries](https://github.com/zcash/librustzcash). Package-declared SPDX
expressions are evidence of the package metadata; they are not a substitute
for checking source headers and included license files.

## Bundled fonts and other assets

The tracked `assets/` tree contains 386 files: 261 PNGs, 114 SVGs, and 11 TTF
files. The 11 TTFs are the following bundled fonts:

* `Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf`,
  `Inter-Bold.ttf` — the files contain metadata identifying Copyright (c) 2016
  The Inter Project Authors and SIL OFL 1.1. The [upstream Inter
  license](https://github.com/rsms/inter/blob/master/LICENSE.txt) identifies
  “Inter” as a Reserved Font Name.
* `Geist-Regular.ttf`, `Geist-Medium.ttf`, `Geist-SemiBold.ttf`,
  `Geist-Bold.ttf`, `GeistMono-Regular.ttf`, `GeistMono-Medium.ttf` — the
  files contain metadata identifying Copyright 2024 The Geist Project Authors
  and SIL OFL 1.1. The [upstream Geist OFL file](https://github.com/vercel/geist-font/blob/main/OFL.txt)
  supplies the copyright notice and license.
* `YoungSerif-Regular.ttf` — the file contains metadata identifying Copyright
  2023 The Young Serif Project Authors and SIL OFL 1.1. The [upstream Young
  Serif OFL file](https://github.com/noirblancrouge/YoungSerif/blob/master/OFL.txt)
  identifies the font as developed by NoirBlancRouge Type Foundry and
  originally distributed by Uplaod.

The [official OFL 1.1 text](https://openfontlicense.org/open-font-license-official-text/)
allows bundling a font with software, while requiring the font copyright notice
and license to accompany each copy, prohibiting sale of the font by itself,
and imposing Reserved Font Name and attribution restrictions on modified font
versions. `third_party/fonts/OFL-1.1.txt` carries the standard text and the
three font-specific notices, and the exact same text is now bundled at
`assets/legal/fonts/OFL-1.1.txt`. A release must include the source file or an
equivalent human-readable legal-notice view. The font files’ embedded metadata
alone was not treated as a sufficient release notice.

A bounded text scan found no license, copyright, attribution, or source record
alongside the non-font PNG/SVG assets. Commit messages refer to Figma exports,
icons, illustrations, and token/chain artwork, but a commit message is not a
copyright grant. The origin and redistribution rights for these assets,
including the current branding artwork, remain an owner decision. Do not add a
made-up artist, company, domain, or license to close this gap.

## Optional SimpleX distribution

The SimpleX integration is optional in Linux and Android builds. `linux/CMakeLists.txt` always
builds the small `simplex-host`, but copies the AGPL runtime only when
`SIMPLEX_LIBS_DIR` is non-empty and contains `libsimplex.so`. The pinned
runtime is SimpleX Chat v7.0.2:

* Release archive: [`simplex-chat-libs-linux-x86_64.zip`](https://github.com/simplex-chat/simplex-chat/releases/download/v7.0.2/simplex-chat-libs-linux-x86_64.zip)
* SHA-256: `235e8afc1942f098e6ad27b7e2947eced0a670e2ed35f064d802b71bbcfc1610`
* Size: 43,451,028 bytes
* Source tree: [SimpleX Chat v7.0.2](https://github.com/simplex-chat/simplex-chat/tree/v7.0.2)
* License: [upstream AGPL license](https://github.com/simplex-chat/simplex-chat/blob/v7.0.2/LICENSE)

The ARM64 Android test-build script now verifies the pinned official
`simplex-aarch64.apk` and extracts its unmodified `libsimplex.so`,
`libsupport.so` and `libapp-lib.so`. Its provenance and build process are in
`tools/simplex/ANDROID-EMBEDDING.md`. Android's private service and JNI adapter
are part of this checkout. Flutter bundles the upstream AGPL text and the
source/build references listed above. This is an implementation and packaging
record; the complete public-distribution source/dependency package remains a
release task.

The [GNU AGPL v3 text](https://www.gnu.org/licenses/agpl-3.0.html) and the
upstream SimpleX license are the primary sources for this boundary. AGPL
section 6 requires corresponding source when an object-code covered work is
conveyed, and permits several conveyance methods, including providing the
corresponding source with the object code or using an access method; a written
offer is required only when that is the method selected under the applicable
section 6 option. The v7.0.2 text defines corresponding source to include
required dynamically linked subprograms in the circumstances described there.
That rule is conditional on the runtime being part of the covered work; the
`dlopen` process boundary alone neither decides that classification nor creates
a licensing exemption.

The wallet's root Apache 2.0 grant remains the grant for the repository Work.
Including an optional AGPL runtime does not automatically relicense the wallet
or its host under AGPL. Apache 2.0 and AGPL-3.0 can remain separate license
boundaries when separate independent works are distributed as an aggregate,
but the classification depends on the actual integration and distribution. If
the host, adapter, and runtime are treated as one covered work, the AGPL's
source, modification, notice, and licensing conditions apply to that covered
work. Whether this wallet/runtime arrangement is an aggregate or a combined
work needs an owner/legal determination; this document does not make that
conclusion and does not put the AGPL terms into the wallet's root LICENSE.

Observed local artifacts distinguish the two build configurations:

| Artifact | Observation |
| --- | --- |
| `build/linux/x64/debug/CMakeCache.txt` | `SIMPLEX_LIBS_DIR=/tmp/anomaly-simplex-lab/native/libs`; `anomaly-simplex-lab` is a local path retaining the former internal Anomaly codename. The debug bundle has 161 files under `bundle/lib/simplex`, including `libsimplex.so` (SHA-256 `533766ae2dbbd62bf04e877c7950ac01425043a0e3ee5e4248aad72fea2fa3d5`) and sibling Haskell libraries. |
| `build/linux/x64/release/CMakeCache.txt` | `SIMPLEX_LIBS_DIR` is empty; the release bundle has `simplex-host` but no `lib/simplex` runtime directory. |
| `/tmp/anomaly-simplex-lab/native.zip` | The observed archive matches the pinned SHA-256 and size. Its listing and extracted directory contained no file named `LICENSE`, `NOTICE`, `COPYING`, or `README`. The path is local prototype evidence, not a vendor or a claim about every upstream release asset. |

The repository’s `tools/simplex/README.md` already records that this is a local
test integration and not a completed license/SBOM/corresponding-source release
package. If an AGPL-enabled bundle is ever conveyed, the release package must
include, at minimum:

1. the exact upstream AGPL license and all upstream copyright/attribution
   notices for the runtime and its sibling libraries;
2. machine-readable corresponding source for the covered runtime, including
   the source/build inputs needed to reproduce the shipped libraries and the
   adapter/host modifications that are covered by the selected arrangement;
3. a documented AGPL section 6 conveyance method for the machine-readable
   corresponding source, such as supplying it alongside the object code or
   providing access from the designated place; if a written-offer method is
   selected, maintain the offer for the period that method requires;
4. a readable legal-notice path for the runtime’s interactive interfaces, if
   the selected AGPL terms require it; and
5. a target-specific SBOM showing the archive hash, every shipped `.so`, and
   each component’s license text.

The public GitHub source URL in the experiment README identifies upstream
provenance. A bare provenance link is not by itself evidence that the exact
corresponding source and a selected section 6 conveyance method are available
for the shipped binary; a maintained designated-place access method can satisfy
the license when it actually meets the applicable option. The current
AGPL-enabled debug bundle and the archive observed in `/tmp` are therefore
release blockers. A release built with an empty `SIMPLEX_LIBS_DIR` is not an
AGPL runtime bundle, but it still needs the general Apache, Dart, Rust, font,
and asset notices.

## Distribution checklist

Before publishing a source archive or binary, the release owner should mark
each item complete with evidence for the exact tag and target:

- [ ] Confirm the legal rights holder and copyright wording for the wallet,
  fork changes, Sigil branding, former internal Anomaly identifiers that ship,
  and all new original files.
- [x] Add change notices to the 123 reviewed non-generated upstream source
  files modified by this fork.
- [ ] Finish modified-file review of generated outputs, metadata and other
  non-source distribution files; rerun the inventory for the release tag.
- [ ] Ship the root `LICENSE`, this root `NOTICE`, all retained vendored
  license files, and a complete, human-readable third-party license inventory.
- [ ] Resolve the `desktop_window_bootstrap` placeholder license before any
  target that includes that direct package is distributed.
- [ ] Generate the Dart/Flutter inventory from the exact `pubspec.lock` and
  verify that users can reach the generated notices; include platform-native
  package notices as well.
- [ ] Generate the Rust inventory from the exact `Cargo.lock`, `cargo metadata`,
  target, and feature set. Include MPL, CDLA, Apache, MIT, BSD, ISC, and any
  other license texts actually present; do not claim “all dependencies
  cleared” from package metadata alone.
- [ ] Ship `third_party/fonts/OFL-1.1.txt` or an equivalent legal-notice view
  with the font-specific notices, and confirm no modified font uses a
  Reserved Font Name without permission.
- [ ] Obtain provenance and redistribution rights for every non-font PNG/SVG
  and for any replacement branding artwork.
- [ ] Inspect every final target bundle for the actual native libraries and
  legal files. A local debug cache is not evidence for a release target.
- [ ] If `SIMPLEX_LIBS_DIR` is non-empty, complete the AGPL source,
  notice, selected section 6 conveyance, UI (if applicable), and SBOM package
  before conveying the binary. If it is empty, record that the release does
  not contain the SimpleX runtime.
- [ ] Re-run this audit after the concurrent branding changes settle, before
  committing a release.

## Read-only evidence used

The repository and package evidence above came from these bounded checks; no
build was started:

```sh
git show upstream/main:LICENSE
git diff --stat upstream/main...HEAD
git diff --name-status upstream/main...HEAD
git grep -n -I -E 'Apache License|SPDX-License-Identifier: Apache|Licensed under the Apache' -- ':!LICENSE' ':!build'
cargo metadata --manifest-path rust/Cargo.toml --locked --offline --format-version=1
cargo tree --manifest-path rust/Cargo.toml --locked --offline -e normal -i option-ext@0.2.0
cargo tree --manifest-path rust/Cargo.toml --locked --offline -e normal -i priority-queue@2.7.0
file build/linux/x64/release/CMakeCache.txt
file build/flutter_assets/NOTICES.Z
unzip -l build/app/outputs/flutter-apk/sigil-mainnet-arm64.apk
sha256sum /tmp/anomaly-simplex-lab/native.zip
```

Package cache contents and build directories are local observations. Re-run
the checks against the exact release checkout and target before relying on
them for a distribution decision.

## Primary sources

* [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.txt)
* [Chainapsis Vizor wallet upstream](https://github.com/chainapsis/vizor-wallet)
* [Pinned desktop window bootstrap LICENSE](https://github.com/chainapsis/desktop_window_bootstrap/blob/16b1b30e08004e91521cc511db098f9561dfeb0a/LICENSE)
* [SimpleX Chat v7.0.2 source](https://github.com/simplex-chat/simplex-chat/tree/v7.0.2)
* [SimpleX Chat v7.0.2 license](https://github.com/simplex-chat/simplex-chat/blob/v7.0.2/LICENSE)
* [GNU Affero General Public License v3](https://www.gnu.org/licenses/agpl-3.0.html)
* [SIL Open Font License official text](https://openfontlicense.org/open-font-license-official-text/)
* [Inter source and license](https://github.com/rsms/inter)
* [Geist source and OFL](https://github.com/vercel/geist-font)
* [Young Serif source and OFL](https://github.com/noirblancrouge/YoungSerif)
* [Mozilla Public License 2.0](https://www.mozilla.org/en-US/MPL/2.0/)
* [CDLA-Permissive 2.0](https://cdla.dev/permissive-2-0/)
* [Zcash Rust libraries](https://github.com/zcash/librustzcash)
* [Keystone UR Rust](https://github.com/KeystoneHQ/ur-rs/tree/0.3.3)
* [Valargroup Keystone SDK Rust](https://github.com/valargroup/keystone-sdk-rust/tree/c2119436f5246be05b1ba877a7e6b63f51c01339)
* [Valargroup zcash_voting](https://github.com/valargroup/zcash_voting/tree/v3.1.0-rc.16)
