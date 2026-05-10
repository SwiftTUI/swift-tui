---
adr: "0008"
title: "SwiftTUI is library-only; runners own App.main()"
status: accepted
date: 2026-04-29
sources:
  - docs/HOST_PACKAGES.md
  - docs/ARCHITECTURE.md
  - README.md
---

# ADR-0008: SwiftTUI is library-only; runners own App.main()

## Context

A SwiftUI-shaped framework needs a default `App.main()` story so
authors can write `@main struct MyApp: App { ... }` and run it. The
question is *where that default lives*.

Options considered:

1. **Inside `SwiftTUI`.** The runtime library provides the default
   `App.main()`. Authors who import SwiftTUI get terminal-native
   execution for free.
2. **In a peer runner package.** SwiftTUI stays library-only;
   `Platforms/CLI` provides the default `App.main()`. Authors
   import both.

Option 1 is more convenient for first-time users. It's also a
commitment: every consumer of SwiftTUI inherits a terminal-native
launcher, alternate-screen acquisition, raw-mode setup, signal
handling, scene-discovery sockets, PTY plumbing, and crash-guard
infrastructure. None of those are wanted by:

- consumers running SwiftTUI under WASI (they need the WASI runner's
  manifest mode),
- consumers embedding SwiftTUI inside a SwiftUI macOS / iOS app via
  `Platforms/SwiftUI` (they hand scene sessions to the host's run
  loop),
- consumers embedding SwiftTUI in the browser via `Platforms/Web`
  (they consume a WASI build and surface raster output to a canvas).

For three of the four shipped execution modes, the terminal-native
launcher in option 1 is dead weight at best and active interference at
worst.

## Decision

`SwiftTUI` is **library-only**. Executable launch is owned by peer
runner packages.

Consumers writing terminal-native apps:

```swift
import SwiftTUI
import SwiftTUICLI   // <-- provides the default App.main()

@main
struct MyApp: App { ... }
```

`Platforms/CLI` provides:

- the default `App.main()` story for terminal-native execution,
- `TerminalRunner.run(MyApp.self)` as an explicit launch
  alternative,
- attach / list / scene-management CLI behavior,
- PTY-backed secondary scenes,
- the crash-guard installation (see ADR-0010).

`Platforms/WASI` provides the equivalent for WASI execution.
Embedded host packages (`Platforms/SwiftUI`, `Platforms/Web`) consume hosted
scene sessions directly without involving any default `App.main()` at all.
`Platforms/WebHost` is compound: `SwiftTUIWebHost` provides
`WebHostRunner`, and `SwiftTUIWebHostCLI` composes terminal and WebHost launch
routing.

## Status

Accepted. The terminal-native default `App.main()` lives in
`Platforms/CLI/Sources/SwiftTUICLI/SwiftTUICLI.swift`. The root package's
library products are `SwiftTUIViews`, `SwiftTUI`, `SwiftTUIAnimatedImage`, and
`SwiftTUICharts`.

## Consequences

**Enabled:**

- One-window and multi-window apps share the same runner story; CLI
  scene management is executable-runner policy, not authored-scene
  policy.
- WASI and embedded-host consumers don't pay for raw-mode setup, PTY
  helpers, or signal handlers they'll never use.
- Each runner package's CLI behavior (attach flows, scene discovery,
  socket protocols) evolves on its own surface without touching the
  root library's public API.

**Foreclosed:**

- A consumer cannot import only `SwiftTUI` and get a runnable
  terminal-native binary. The two-import pattern is the supported
  shape.
- Adding new launcher behavior (e.g. a daemon mode, a stdin-only
  test harness) is a runner-package change, not a root-package
  change.

**Discipline imposed:**

- New default-launch behavior must justify itself at the runner level.
  "Add it to SwiftTUI for convenience" is rejected.
- Runner packages must not require modifications to the root package
  to ship new launch behavior. If they do, the root package needs a
  new supported seam first.

The bet: keeping the launcher decision out of the library means the
library never has to apologize for assuming a deployment target. Every
host gets exactly the launch story it needs.
