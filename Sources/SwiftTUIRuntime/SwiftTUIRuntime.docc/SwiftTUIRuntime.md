# ``SwiftTUIRuntime``

Render views, drive interactive terminal sessions, and connect the pure frame pipeline to a real terminal host.

## Overview

The `SwiftTUIRuntime` module is the platform-neutral runtime-facing layer of
SwiftTUI.

Use it when you want to:

- resolve or render a `View` into inspectable frame artifacts
- run an interactive terminal session with `RunLoop`
- parse terminal input and signals
- present rasterized output with capability-aware ANSI rendering and
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
apps. Other platform integrations compose with this module directly:
`SwiftTUICLI`, `SwiftTUIWASI`, `SwiftTUIWebHost`, and `SwiftTUIWebHostCLI`.
Browser deployment uses the `@swifttui/web` package in the sibling
`SwiftTUI/swift-tui-web` repository to consume a `SwiftTUIWASI` build. The
native SwiftUI host (for embedding a SwiftTUI app in a SwiftUI view on
macOS/iOS) now lives in the separate `swift-tui-swiftui` package:
https://github.com/SwiftTUI/swift-tui-swiftui

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
