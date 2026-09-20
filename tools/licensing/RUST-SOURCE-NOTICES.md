# Rust missing-license-text supplement

Resolved text coverage: 111/113 original rows. Every missing-text package in the Linux/Android normal-or-build dependency union has retained text.

## Deliverables

- `rust-source-notices.json`: exact package, source revision, target relevance, text provenance and SHA-256.
- `licenses/rust-supplement/`: retained upstream notices plus explicit grant evidence for special cases.
- Runtime aggregate: `assets/legal/THIRD-PARTY-NOTICES.txt`, generated with the other dependency notices.
- The two Windows import-library exclusions are recorded in the mapping and generated inventory.

## Special cases

- ed25519-consensus 2.1.0, impl-trait-for-tuples 0.2.3, valar-spiral-rs 0.5.2: exact source genuinely omits standalone licenses. Preserved their published Cargo/README grant and canonical Apache-2.0 text from apache.org; selected an expressly offered Apache option. No copyright holder invented.
- void 1.0.2: published package lacks VCS metadata. Retrieved upstream resolved HEAD `a6e061227f47ba8798b7e828ed0ac4e25382eb15`; its only Rust source file is byte-identical to the published crate. Recovered upstream MIT copyright/permission notice; retained original published MIT option and Cargo/README.
- Three local workspace crates inherit the existing repository root LICENSE/NOTICE; this does not invent a new crate-level declaration.
- Nine packages use retained notices from a cached sibling at the same repository and exact published VCS commit; provenance is explicit.
- Nonstandard legal names recovered include BLAKE3 LICENSE_A2/CC0, crc-catalog LICENSES, priority-queue MPL/LGPL, and r-efi AUTHORS (which contains full MIT permission and actual copyright notices).

## Scope and remaining rows

Offline `cargo metadata --locked --filter-platform ...` succeeded for x86_64-unknown-linux-gnu and aarch64-linux-android. Traversed root normal/build edges, omitted dev edges. This is a conservative source/build dependency classification, not proof of final binary inclusion; preserve build feature parity.
Of the 113 original missing-text rows, 107 are in the Linux normal/build
closure and 106 are in the Android closure. These are supplement counts,
not the size of either complete dependency graph.

Unresolved full-lock rows: winapi-i686-pc-windows-gnu 0.4.0 and winapi-x86_64-pc-windows-gnu 0.4.0. They lack published VCS revisions and retained license texts and are excluded from both requested target closures. Their declared MIT/Apache grants remain recorded; no target release notice gap is asserted from these Windows-only rows.

The inventory generator validates every retained supplement text against the mapping before including it in the runtime notices. Recheck target relevance if release targets or dependency features change.
