---
adr: "0016"
title: "Platform integration products live in the root package"
status: accepted
date: 2026-05-11
sources:
  - Package.swift
  - docs/HOST_PACKAGES.md
  - docs/SOURCE_LAYOUT.md
  - docs/PUBLIC_SURFACE_POLICY.md
---

# ADR-0016: Platform integration products live in the root package

## Context

ADR-0007 originally kept platform integrations as peer SwiftPM packages so
terminal apps would not inherit unrelated host dependencies. That split was
convenient for development, but it made the external consumer story worse: a
SwiftTUI app had to discover several local package manifests under `Platforms/`
instead of depending on one package and selecting products.

The repo now needs a single Swift package surface for framework consumers while
preserving compile-time opt-in boundaries between terminal-only, WebHost, WASI,
native host, and terminal-embedding code.

## Decision

All first-party Swift platform integrations with consumer-facing import
surfaces are root `Package.swift` products: `SwiftTUICLI`,
`SwiftTUIArguments`, `SwiftTUIWASI`, `SwiftUIHost`, `SwiftTUIWebHost`,
`SwiftTUIWebHostCLI`, `SwiftTUITerminal`, and `SwiftTUIPTYPrimitives`.
Low-level shared transport targets that are only used inside the root package,
such as `WASISurfaceBridge`, stay as package-only targets rather than exported
library products.

The source directories stay under `Platforms/` as ownership boundaries, not as
nested SwiftPM packages. `Platforms/Web` remains a Bun package because it is a
browser build system rather than a Swift package product. Example apps remain
separate mini packages that depend on the root `swift-tui` package and import
the products they need.

## Status

Accepted. This supersedes ADR-0007. Amended on 2026-05-16 to keep
`WASISurfaceBridge` as package-only shared transport plumbing instead of a
consumer-facing library product.

## Consequences

Consumers now add one Swift package dependency and choose product dependencies
explicitly. Terminal-only binaries still do not depend on `SwiftTUIWebHost`,
FlyingFox, or browser resources; that boundary is enforced by
`Scripts/check_webhost_package_boundary.sh` and package graph tests.

The root manifest is now the canonical package graph for framework
functionality. Documentation should describe runners, hosts, and terminal
embedding as products, and reserve `Platforms/` language for source layout.
Historical plans may still mention the previous nested-package shape as records
of the implementation path.
