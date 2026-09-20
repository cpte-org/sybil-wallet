# Sybil licensing and release source

This is the release-facing licensing record for the Sybil wallet beta. It
describes the files and build inputs that are present in this checkout and the
corresponding-source asset prepared for a target that includes SimpleX Chat.
It preserves upstream notices and records source versions and retrieval
evidence without assigning licenses that were not observed.

## Repository boundary

The repository-level `LICENSE` remains Apache License 2.0 for the wallet Work
and its retained upstream notices. The tree is derived from the Chainapsis
Vizor wallet; preserve the upstream copyright, patent, trademark, and
attribution notices that accompany the modified files. `NOTICE` and
`assets/legal/NOTICE` are attribution addenda and do not replace a component's
license. The Sybil name and original geometric artwork are product additions;
the artwork provenance is recorded in `assets/branding/README.md`.

The beta includes the AGPL-3.0 SimpleX runtime. The combined distribution is
provided with its corresponding source under the applicable AGPL requirements,
while preserving the Apache and permissive grants on the original components.
The repository-level Apache license alone does not describe every component
in the distributed binaries.

## Legal files shipped by Flutter

The following paths are explicit assets in `pubspec.yaml` and are registered
with Flutter's legal-notices registry by
`lib/src/core/legal/sybil_legal_notices.dart`:

* `assets/legal/LICENSE` — the repository Apache License 2.0 text;
* `assets/legal/NOTICE` — upstream and Sybil attribution notices;
* `assets/legal/fonts/OFL-1.1.txt` — the retained SIL Open Font License text
  and font-specific notices;
* `assets/legal/THIRD-PARTY-NOTICES.txt` — the retained Dart and Rust package
  license/notice texts for the resolved cache entries;
  the generated file also includes the Android native notice supplement;
* `tools/licensing/SYBIL-DEPENDENCY-LICENSES.md` — the generated Dart/Rust
  lock inventory and cache-backed license-text paths;
* `tools/simplex/licenses/SimpleX-Chat-v7.0.2-LICENSE` — the verbatim upstream
  SimpleX AGPL-3.0 text; and
* `tools/simplex/licenses/SIMPLEX-SOURCE-AND-BUILD.txt` — the source package,
  pinned Git input, Hackage/native boundary, and release access record.

The actual package license texts copied from the inspected Dart and Rust caches
remain under `tools/licensing/licenses/` and are aggregated into the runtime
asset. The generated inventory marks SDK packages and cache entries without a
conventional local license file instead of calling them cleared. It does not
substitute a placeholder expression for a missing declaration.
The upstream SimpleX Haskell/native dependency notices are also retained under
`tools/licensing/licenses/simplex-haskell/` and included in the same aggregate.

## Dart and Rust dependency inventory

`tools/licensing/generate_dependency_inventory.py` reads the checked-in
`pubspec.lock` and `rust/Cargo.lock`. The current generated snapshot records:

* 173 Dart lock packages, including direct, transitive, SDK, path, and Git
  entries, with hosted archive hashes or Git revisions;
* 827 Rust packages from `cargo metadata --locked --offline`, retaining the
  registry checksum or Git revision and the manifest's SPDX expression; and
* 1,668 retained license/notice files, including exact-source Rust supplements.
  The two remaining full-lock entries without retained texts are Windows-only
  import libraries, excluded from both Linux and Android dependency closures.

The inventory is a lockfile/metadata superset, including dev, test, SDK and
platform packages. Supplement provenance, hashes and target exclusions are
recorded in `tools/licensing/rust-source-notices.json`; the generator validates
those retained texts before including them in the runtime notices.
Re-run the generator against the exact release checkout and target before
publishing if lock files or feature selection change.

## SimpleX v7.0.2 corresponding source

The source asset is:

`dist/source/sybil-simplex-source-v7.0.2.tar.gz`

At publication, attach it to the public beta release and keep this exact
AGPL section 6(d) access path live:

* Release: <https://github.com/cpte-org/sybil-wallet/releases/tag/v1.0.0-beta.1>
* Source asset: <https://github.com/cpte-org/sybil-wallet/releases/download/v1.0.0-beta.1/sybil-simplex-source-v7.0.2.tar.gz>

The package contains the pinned SimpleX source archive at commit
`417b4cc4db73b94a98fed5b3204d9d78ce272c7e` (SHA-256
`94ab37f56eb1712190a4539f7e948efe6f03c61fd508678ca347c3e41b87eb3f`), the
`simplex-chat-libs` source/notice archive at commit
`0721dca4504f921f90407b6d0aaf71aedbee35bc` (SHA-256
`0cae121988201a1bb44fedd4213595bcf51c9cc0f843d64bf3578a79eaf1e3df`),
`cabal.project`, `flake.nix`, `flake.lock`, patches, Android build inputs,
upstream dependency license reports, and ten exact Git source archives. The
Git archive hashes and URLs are listed in
`tools/simplex/licenses/SIMPLEX-SOURCE-AND-BUILD.txt`.

The package is the corresponding source and build-input record for the AGPL
upstream component. The Sybil host/JNI adapter, wrapper, and integration
changes remain in the Sybil repository source at the release tag and are not
duplicated into this separate upstream source package.

The 16 runtime versions that differed from the upstream report's visible
license-directory names are covered by exact source inputs in the package: the
non-forked Hackage archives for ansi-terminal, ansi-wl-pprint, constraints,
digest, http2, iso8601-time, monad-loops, optparse-applicative, primitive,
th-lift, th-lift-instances, and uri-bytestring; and the exact Git forks for
direct-sqlcipher, simplexmq, sqlcipher-simple, and zip. The zstd-0.1.3.0
Hackage archive is included as the native compression binding. Hashes and
license evidence are in `tools/simplex/licenses/SIMPLEX-SOURCE-AND-BUILD.txt`
and `manifest/HACKAGE-PINS.tsv` inside the source asset.

## Runtime dependency source coverage

The package includes the observed Linux Haskell runtime's non-forked Hackage
archives, the ten pinned Git forks, and GHC 9.6.3 source (including its runtime
and core libraries). Explicit manifest mappings cover the RTS and attoparsec
internal-library filenames, which do not follow the ordinary package-name
pattern. The Cabal index state remains `2023-12-12T00:00:00Z`.

Native source inputs include OpenSSL 3.0.10, GMP 6.3.0, libffi 3.4.4, libiconv
1.16 and zlib 1.3. The GHC source also retains its bundled GMP/libffi sources.
Pinned Nixpkgs and Haskell.nix source archives preserve the native definitions
and build patches. Download hashes, source URLs, runtime mappings and build
pins are recorded inside the package's `manifest/` directory; upstream notices
are preserved in the runtime legal asset.

The package does not claim a bit-for-bit rebuild of the official native
binaries. Linux system-provided OpenSSL/zstd and operating-system libraries
remain platform dependencies. Recheck the actual native dependency closure
and source manifests when changing the target or upstream binary inputs.

## Binary provenance

The source package records, but does not replace, the official binary inputs:

* Android ARM64 `simplex-aarch64.apk`, upstream SHA-256
  `0a3a0bb7ca1e2411854883ba1ae352b15b11146fe0e137395671fff9ed839871`;
* Linux x86_64 `simplex-chat-libs-linux-x86_64.zip`, upstream SHA-256
  `235e8afc1942f098e6ad27b7e2947eced0a670e2ed35f064d802b71bbcfc1610`; and
* inspected Sybil Linux `libsimplex.so`, SHA-256
  `533766ae2dbbd62bf04e877c7950ac01425043a0e3ee5e4248aad72fea2fa3d5`.

The source/build package must be attached whenever a released Linux or Android
binary contains the runtime. If a target is built without the SimpleX runtime,
the release record must say so and still ship the general wallet, font, Dart,
Rust, and vendored-component notices.

## Release checks

Before publishing `v1.0.0-beta.1`, the release owner should verify:

1. The final target contains `LICENSE`, `NOTICE`, the OFL text, and the
   generated dependency inventory.
2. Modified upstream source retains the Apache section 4(b) change marker and
   original upstream notices; generated and vendored paths have been reviewed
   separately.
3. The release source asset's SHA-256 and manifest match the package recorded
   here, including all ten Git dependency archives.
4. The exact target's native library list and hashes are recorded; a local
   cache is not evidence for a release target.
5. The SimpleX source asset is attached at the designated GitHub release URL
   before any AGPL-covered object code is conveyed.

Useful read-only checks:

```sh
python3 tools/licensing/generate_dependency_inventory.py
sha256sum dist/source/sybil-simplex-source-v7.0.2.tar.gz
git diff --check
```
