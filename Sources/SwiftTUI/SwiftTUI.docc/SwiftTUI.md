# ``SwiftTUI``

Render views, drive interactive terminal sessions, and connect the pure frame pipeline to a real terminal host.

## Overview

The `SwiftTUI` module is the runtime-facing layer of SwiftTUI.

Use it when you want to:

- resolve or render a `View` into inspectable frame artifacts
- run an interactive terminal session with `RunLoop`
- parse terminal input and signals
- present rasterized output with capability-aware ANSI rendering and
  presentation-boundary terminal sanitization

`SwiftTUI` re-exports `View` and `Core`, so importing `SwiftTUI` is the normal entry point for most applications and examples.

## Runtime Story

`SwiftTUI` has two main direct public entry paths:

- ``DefaultRenderer`` for one-shot rendering and frame inspection
- ``RunLoop`` for interactive sessions that own terminal I/O, scheduling, focus, lifecycle staging, and presentation

It also owns the shared scene-hosting APIs that peer platform integration
packages build on.

Scene declarations such as ``App`` and ``WindowGroup`` also live here, but
platform integration lives in peer packages: executable runner packages
`Platforms/CLI` and `Platforms/WASI`, plus embedded host
packages `Platforms/SwiftUI`, `Platforms/Web`, and `GUI/XtermWebHost`.
`SwiftTUI` itself is library-only.

Pointer input policy types such as `TerminalMouseInputResolution`,
`TerminalMouseInputTrustPolicy`, and `TerminalMouseInputCompatibilityMatrix`
are re-exported from the core pipeline layer.

## Topics

### Rendering

- ``DefaultRenderer``
- ``TerminalSurfaceRenderer``
- ``TerminalCapabilityProfile``

### Interactive Runtime

- ``RunLoop``
- ``RunLoopResult``
- ``RunLoopExitReason``
- ``SignalReader``

### App And Scene Declarations

- ``App``
- ``Scene``
- ``SceneBuilder``
- ``WindowIdentifier``
- ``WindowGroup``

### Guides

- <doc:Architecture>
- <doc:Runtime>
- <doc:Vision>
- <doc:Host-Integration>
- <doc:Running-Apps>
- <doc:TerminalEmbedding>
