# Host Packages

## Goal

Make SwiftTUI apps shippable outside a local terminal in two peer embedded
host packages:

- `Platforms/SwiftUI`: a native SwiftUI SPM package that lets a macOS or iOS app host a SwiftTUI scene without a terminal emulator
- `Platforms/Web`: a Bun-based package that lets a SwiftTUI app ship in the browser by drawing SwiftTUI's `web-surface` raster output onto a canvas (no terminal emulator dependency)

The authoring story stays the same:

- app authors continue to write `App`, `Scene`, and `WindowGroup` in the root package
- host packages own terminal-surface hosting, scene selection chrome, and host-local style surfaces
- scene state must survive host-driven scene switches
- resize and host style changes must continue to flow through the same runtime invalidation path as terminal `SIGWINCH`

All Swift build commands in this document assume the repo-default `swiftly`
toolchain story; see [TOOLCHAINS.md](TOOLCHAINS.md) for the full rules.

## Shipped Architecture

### Root package support

The host-facing root work is landed:

- `SwiftTUI` exposes `SceneDescriptor`,
  `SceneManifest`, and `HostedSceneSession`
- `Platforms/CLI` owns terminal-native `App.main()`, attach/list CLI
  behavior, and pty-backed scene management
- `Platforms/WASI` owns manifest-only mode through `TUIGUI_MODE=manifest`
  plus WASI scene launch
- shared control-message parsing lives in
  `Sources/SwiftTUI/TerminalControlMessages.swift`
- embedded hosts use `InjectedTerminalInputReader`; the web host uses
  streaming presentation output (`StreamingTerminalHost`), while the native
  SwiftUI host receives `RasterSurface` values directly
- hosted sessions now accept paired render-style updates so terminal appearance
  and semantic theme move together at runtime
- `SwiftTUI` is now library-only; executable launch is entirely runner-owned

### `Platforms/SwiftUI`

The native SwiftUI host package is landed as a standalone SPM package:

- package root: `Platforms/SwiftUI`
- dependencies:
  - local path dependency on the root package
- key runtime files:
  - `SwiftUIHostAppState.swift`
  - `SwiftUIHostAppView.swift`
  - `SwiftUIHostSceneHost.swift`
  - `NativeSceneBridge.swift`
  - `NativeTerminalSurfaceView.swift`
  - `SwiftUIHostTerminalStyle.swift`
- SwiftUI styles now expose explicit light and dark theme variants, each pairing
  native renderer palette state with SwiftTUI semantic theme tokens
- verification:
  - `SceneRetentionTests.swift`
  - `ResizeBridgeTests.swift`
  - `StyleMappingTests.swift`

### `Platforms/Web`

The web host package is landed:

- package root: `Platforms/Web`
- build stack: Bun plus the repo-managed Swift 6.3.1 toolchain
- transport: SwiftTUI's `web-surface` WASI transport. The Swift runner emits
  structured raster-surface records on stdout, and the browser host draws
  rectangles and text into a canvas. There is no terminal-emulator dependency.
- key runtime and build files:
  - `src/WebHostApp.ts`
  - `src/WebHostSceneRuntime.ts`
  - `src/WebHostSceneManifest.ts`
  - `src/WebHostSurfaceTransport.ts`
  - `src/build/buildAppWasm.ts`
  - `src/build/generateSceneManifest.ts`
- web styles expose explicit light and dark theme variants and can bind them
  to the host color scheme before pushing a full render-style payload into
  the WASI runtime

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

This is intentional. Host packages are peer platform integration packages, not
new products in the root package.

## Current Constraints

- CLI multi-scene management and authored multiple scenes are intentionally
  separate concepts:
  - `Platforms/CLI` can manage multiple native scenes with discovery,
    ptys, and attach flows
  - `Platforms/WASI` still executes one selected scene per wasm process
- Host packages still own scene switching UI and style surfaces. The root package exposes scene manifests and hosted sessions, not a full cross-platform app shell.
- `Platforms/Web` build scripts drive the repo-default `swiftly` toolchain (falling back to plain `swift` when available). See [TOOLCHAINS.md](TOOLCHAINS.md) for the toolchain requirement. The package shares the repo Bun workspace for builds and tests.
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

## Verification Paths

Relevant package-level verification lives in:

```bash
Scripts/test_all.sh
```

`Scripts/test_all.sh` is the canonical full-repo check. From the repo root you
can also invoke the same flow with `bun run test`. The runner verifies the
Swift and Bun environment first, then runs the root, runner-package,
GUI-package, and example-project test suites that are checked into this
repository.

## Out Of Scope

- generating an Xcode project
- building custom desktop or mobile chrome beyond a terminal surface and scene/style control APIs
- adding a terminal-emulator-backed browser host package
- adding tabs, split panes, or session persistence beyond in-memory retained scene sessions
