# Figma visual workflow

The detailed Figma working notes and design-system inventory are maintained in
the private `cpte-org/sybil-internal` repository under
`wallet/figma/`. This public repository keeps the deterministic Flutter
comparison scripts and scenarios used to verify the implementation.

When changing a visual surface, use the relevant scenario under
`lib/figma_compare/` and compare captures at the same form factor, theme,
viewport, locale, content, and state. Figma files are changed only when the
maintainer explicitly requests that work.
