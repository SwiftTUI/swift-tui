# ``SwiftTUIRuntime``

Render views, drive interactive sessions, and connect the pure frame pipeline
to terminal or host-managed presentation surfaces.

## Overview

The `SwiftTUIRuntime` module is the platform-neutral runtime-facing layer of
SwiftTUI.

Use it when you want to:

- resolve or render a `View` into inspectable frame artifacts
- run an interactive terminal session with `RunLoop`
- parse terminal input and signals
- present committed raster and semantic output through terminal or hosted
  surfaces, including capability-aware ANSI rendering and
  presentation-boundary terminal sanitization

`SwiftTUIRuntime` re-exports `SwiftTUIViews` and `SwiftTUICore`. Import it for
shared view packages, explicit host composition, or custom launchers that should
not inherit the batteries-included convenience product.

## Runtime Story

`SwiftTUIRuntime` has two main direct public entry paths:

- ``DefaultRenderer`` for one-shot rendering and frame inspection
- ``RunLoop`` for interactive sessions that own terminal I/O, scheduling, focus, lifecycle staging, and presentation

It also owns the shared scene-hosting APIs that root package platform products
build on.

Scene declarations such as ``App`` and ``WindowGroup`` also live here. The
release-facing `SwiftTUI` product re-exports this module through
`SwiftTUIWebHostCLI` and includes animated GIF/image support for one-import
apps. Other in-package runner and host products, including
`SwiftTUIAndroidHost`, compose with this module directly. Externally packaged
integrations such as `SwiftUIHost` use the same runtime-facing layer. The
canonical product, distribution, and engine-profile boundaries are documented
in [Hosts and Platforms](https://github.com/SwiftTUI/swift-tui/blob/main/docs/HOSTS-AND-PLATFORMS.md).

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
- ``TerminalHandoffAction``

### App And Scene Declarations

- ``App``
- ``Scene``
- ``SceneBuilder``
- ``WindowIdentifier``
- ``WindowGroup``

### Guides

- <doc:Architecture>
- <doc:Runtime-Render-Pipeline>
- <doc:Runtime>
- <doc:Vision>
- <doc:Host-Integration>
- <doc:Running-Apps>
- <doc:TerminalEmbedding>
- <doc:Terminal-Handoffs>
