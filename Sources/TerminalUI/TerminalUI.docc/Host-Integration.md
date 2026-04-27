# Host Integration

How TerminalUI apps run inside non-terminal hosts: native SwiftUI on macOS and iOS, and a Bun-based browser host that draws raster surfaces onto a canvas.

## Overview

TerminalUI's authored ``App``, ``Scene``, and ``WindowGroup`` values can run in three execution modes. The same body code runs unchanged across all three:

- **Terminal-native**, via the executable runner package `Runners/TerminalUICLI`
- **WASI**, via the executable runner package `Runners/TerminalUIWASI`
- **Embedded host**, via peer host packages `GUI/SwiftUITUIGUI` (native SwiftUI) and `GUI/WebTUIGUI` (browser canvas)

This article documents how the embedded-host story fits together, and what contract the host packages and the root package each own.

The authoring story stays the same:

- app authors continue to write ``App``, ``Scene``, and ``WindowGroup`` in the root package
- host packages own terminal-surface hosting, scene selection chrome, and host-local style surfaces
- scene state must survive host-driven scene switches
- resize and host style changes must continue to flow through the same runtime invalidation path as terminal `SIGWINCH`

## Shipped Architecture

### Root Package Support

The host-facing root work is landed:

- `TerminalUI` exposes `TerminalUISceneDescriptor`, `TerminalUISceneManifest`, and ``HostedSceneSession``
- `Runners/TerminalUICLI` owns terminal-native `App.main()`, attach/list CLI behavior, and pty-backed scene management
- `Runners/TerminalUIWASI` owns manifest-only mode through `TUIGUI_MODE=manifest` plus WASI scene launch
- shared control-message parsing lives in `TerminalControlMessages`
- embedded hosts use an injected terminal input reader; the web host uses streaming presentation output, while the native SwiftUI host receives `RasterSurface` values directly
- hosted sessions accept paired render-style updates so terminal appearance and semantic theme move together at runtime
- `TerminalUI` is library-only; executable launch is entirely runner-owned

### `GUI/SwiftUITUIGUI`

The native SwiftUI host package is a standalone SPM package:

- package root: `GUI/SwiftUITUIGUI`
- dependencies: a local path dependency on the root package
- key runtime files: `SwiftUITUIAppState`, `SwiftUITUIAppView`, `SwiftUITUISceneHost`, `NativeSceneBridge`, `NativeTerminalSurfaceView`, `SwiftUITUITerminalStyle`
- SwiftUI styles expose explicit light and dark theme variants, each pairing native renderer palette state with TerminalUI semantic theme tokens
- verification: `SceneRetentionTests`, `ResizeBridgeTests`, `StyleMappingTests`

### `GUI/WebTUIGUI`

The web host package:

- package root: `GUI/WebTUIGUI`
- build stack: Bun plus the repo-managed Swift 6.3.1 toolchain
- transport: TerminalUI's `web-surface` WASI transport. The Swift runner emits structured raster-surface records on stdout, and the browser host draws rectangles and text into a canvas. There is no terminal-emulator dependency.
- key runtime and build files: `src/WebTUIApp.ts`, `src/WebTUISceneRuntime.ts`, `src/WebTUISceneManifest.ts`, `src/WebTUISurfaceTransport.ts`, `src/build/buildAppWasm.ts`, `src/build/generateSceneManifest.ts`
- web styles expose explicit light and dark theme variants and can bind them to the host color scheme before pushing a full render-style payload into the WASI runtime

## Responsibilities Split

The current boundary is:

- root package:
  - app authoring
  - scene collection
  - retained hosted runtime sessions
  - manifest generation
  - control-message contract for resize and render-style updates
- host packages:
  - window or browser shell integration
  - native surface or canvas surface embedding
  - scene tabs, pickers, or other host-local chrome
  - host-specific style mapping and host-owned theme swapping

This is intentional. Host packages are peer platform integration packages, not new products in the root package.

## Current Constraints

- CLI multi-scene management and authored multiple scenes are intentionally separate concepts:
  - `Runners/TerminalUICLI` can manage multiple native scenes with discovery, ptys, and attach flows
  - `Runners/TerminalUIWASI` still executes one selected scene per wasm process
- Host packages still own scene switching UI and style surfaces. The root package exposes scene manifests and hosted sessions, not a full cross-platform app shell.
- `GUI/WebTUIGUI` build scripts drive the repo-default `swiftly` toolchain (falling back to plain `swift` when available). The package shares the repo Bun workspace for builds and tests.
- Executable runner packages and embedded host packages are intentionally outside the root package products. Consumers opt into them separately.

## Non-Negotiable Decisions

1. GUI host packages are peer packages, not new top-level products in the root package.
2. The root package exposes first-class scene manifest and hosted-session APIs so peer packages do not rely on package-only internals.
3. Each scene gets its own retained runtime session. Switching scenes changes which hosted session is visible; it does not rebuild the app body from scratch.
4. Scene switching is host-managed. It is not a new terminal escape-sequence protocol.
5. Terminal style is host-owned. The Swift package and the Bun package expose mirrored style concepts, not a shared cross-language source file, and host packages choose the active theme variant.
6. The Apple host package owns the native SwiftUI surface without a terminal-emulator dependency.
7. The web package keeps one wasm module instance per scene and one canvas surface per scene so scene state survives switches without a more complex protocol.
8. The existing resize control-message contract stays the foundation for all non-POSIX resize behavior and is now extended with paired render-style updates.

## Out Of Scope

- generating an Xcode project
- building custom desktop or mobile chrome beyond a terminal surface and scene/style control APIs
- adding a terminal-emulator-backed browser host package
- adding tabs, split panes, or session persistence beyond in-memory retained scene sessions

## Topics

### Related Articles

- <doc:Architecture>
- <doc:Runtime>
- <doc:Vision>
- <doc:Running-Apps>
