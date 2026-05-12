---
adr: "0017"
title: "SwiftTUI is the terminal convenience product over SwiftTUIRuntime"
status: accepted
date: 2026-05-11
sources:
  - Package.swift
  - docs/proposals/PUBLIC_PRODUCTS_DRAFT.md
  - docs/HOST_PACKAGES.md
  - docs/PUBLIC_SURFACE_POLICY.md
  - docs/SOURCE_LAYOUT.md
---

# ADR-0017: SwiftTUI is the terminal convenience product over SwiftTUIRuntime

## Context

ADR-0008 kept `SwiftTUI` library-only so native, WASI, WebHost, and embedding
consumers would not inherit terminal-runner dependencies. That protected host
purity but left ordinary terminal apps with a two-import story: `SwiftTUI` for
authoring plus `SwiftTUICLI` for `App.main()`.

The package now has explicit root products for each host. That lets the shared
runtime move to a differently named product while reserving `SwiftTUI` for the
most common release-facing app shape.

## Decision

`SwiftTUIRuntime` is the platform-neutral authoring/runtime product. It owns
`App`, `Scene`, `DefaultRenderer`, `RunLoop`, `SceneManifest`, and
`HostedSceneSession`, and it re-exports the lower-level core and view products.

`SwiftTUI` is a thin terminal app convenience product that re-exports
`SwiftTUIRuntime`, `SwiftTUIArguments`, and `SwiftTUICLI`. A terminal-only app
can depend on `SwiftTUI`, write only `import SwiftTUI`, and get standard
framework arguments plus the default terminal `App.main()`.

Host products and custom launchers depend on `SwiftTUIRuntime` directly. They
do not depend on the `SwiftTUI` convenience product.

## Status

Accepted. This supersedes ADR-0008.

## Consequences

The common terminal app path is one import without moving WebHost, SwiftUI host,
WASI, charts, animated images, or terminal-program embedding into the default
binary. `SwiftTUI` must remain server-free and must reject WebHost flags before
raw mode unless the app imports the explicit combined product.

`SwiftTUIWebHostCLI` is the import replacement for binaries that intentionally
support both terminal and `--web` launch. It re-exports `SwiftTUIRuntime`,
`SwiftTUIArguments`, and `SwiftTUIWebHost`, and it calls `TerminalRunner`
internally without depending on the `SwiftTUI` convenience product.

Public docs should teach `SwiftTUI` first for terminal apps, `SwiftTUIRuntime`
for shared runtime composition, and explicit host/domain products for all other
packaging choices.
