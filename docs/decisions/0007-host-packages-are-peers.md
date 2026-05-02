---
adr: "0007"
title: "Embedded host packages are peers, not root products"
status: accepted
date: 2026-04-29
sources:
  - docs/HOST_PACKAGES.md
  - docs/ARCHITECTURE.md
  - docs/SOURCE_LAYOUT.md
---

# ADR-0007: Embedded host packages are peers, not root products

## Context

A SwiftTUI app eventually has to render somewhere concrete: a
terminal process, a SwiftUI macOS / iOS surface, a Bun-served browser
canvas, or a WASI runtime. Each of those targets has different platform
chrome, different scene-switching UI conventions, different theme
surfaces, and different toolchain dependencies.

The naive shape would be to fold all of these into the root
`swift-tui` package — exporting library products like
`SwiftTUI`, `SwiftUIHost`, `WebHost`,
`SwiftTUICLI`, etc., from a single Package.swift. That keeps everything
in one place and makes "import what you need" feel uniform.

It also drags every consumer through every host-platform's transitive
dependency tree, makes it impossible to ship a SwiftUI host without
also shipping a Bun build configuration in the workspace, and forces
host-platform UX choices (scene tabs, picker chrome, style mapping)
into the same review surface as the core library's public API.

## Decision

Host packages live as **peer SwiftPM packages** alongside the root
package, not as products inside it:

```
swift-tui/
├── Sources/                  ← root package products
├── Runners/
│   ├── SwiftTUICLI/        ← peer executable runner package
│   └── SwiftTUIWASI/       ← peer executable runner package
└── GUI/
    ├── SwiftUIHost/        ← peer embedded host package
    └── WebHost/            ← peer embedded host package
```

The root package exposes scene-manifest and hosted-session APIs
(`SceneDescriptor`, `SceneManifest`,
`HostedSceneSession`) so peer packages can build on supported types
without reaching into package-only internals. Each peer owns:

- its window-or-browser-shell integration,
- native or canvas surface embedding,
- scene tabs, pickers, and other host-local chrome,
- host-specific style mapping and theme swapping.

The root package does not own any of those.

## Status

Accepted. The current peer set is `Runners/SwiftTUICLI`,
`Runners/SwiftTUIWASI`, `GUI/SwiftUIHost`, and `GUI/WebHost`.
Each is a standalone SPM package with its own Package.swift, its own
test target, and its own dependency graph.

## Consequences

**Enabled:**

- Consumers opt into the host they need without paying the cost of
  the others. A pure terminal-native app does not transitively pull
  Bun, WASM SDKs, or SwiftUI dependencies.
- Each host package can evolve its UX (scene picker chrome, theme
  handling) independently of the root package's public-surface
  policy review.
- New hosts (e.g. an Android JNI host, a TipTap-style web embedding)
  can be added as new peer packages without touching the root
  package or its review checklist.

**Foreclosed:**

- The root package does not generate Xcode project files, host
  custom desktop chrome, or own a single cross-platform app shell.
  Those concerns belong to consumers.
- A consumer cannot import "SwiftTUI" and get a SwiftUI host for
  free — they pick the runner or host package explicitly.

**Discipline imposed:**

- Host packages cannot introduce dependencies on root-package
  package-only internals. If they need something, the root package
  exposes it as supported API.
- The control-message contract for resize and render-style updates
  is the supported boundary. Hosts that need new behavior either
  use the existing contract or propose an extension to it.

The bet: small, focused root products plus opinionated peer hosts
scale better than one large package that has to please every
deployment target. Five years from now this matters more than today.
