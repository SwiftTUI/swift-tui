# Host Packages

## Goal

Make TerminalUI apps shippable outside a local terminal in four peer embedded
host packages:

- `GUI/SwiftUITUIGUI`: a native SwiftUI SPM package that lets a macOS or iOS app host a TerminalUI scene without a terminal emulator
- `GUI/SwiftTermTUIGUI`: a SwiftTerm-backed SPM package that lets a macOS or iOS app host a TerminalUI scene inside SwiftUI
- `GUI/WebTUIGUI`: a Bun-based package that lets a TerminalUI app ship in the browser on top of `ghostty-web`
- `GUI/XtermWebTUIGUI`: a Bun-based package that lets a TerminalUI app ship in the browser on top of xterm.js

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

- `TerminalUI` exposes `TerminalUISceneDescriptor`,
  `TerminalUISceneManifest`, and `HostedSceneSession`
- `Runners/TerminalUICLI` owns terminal-native `App.main()`, attach/list CLI
  behavior, and pty-backed scene management
- `Runners/TerminalUIWASI` owns manifest-only mode through `TUIGUI_MODE=manifest`
  plus WASI scene launch
- shared control-message parsing lives in
  `Sources/TerminalUI/TerminalControlMessages.swift`
- embedded hosts use `InjectedTerminalInputReader`; terminal-emulator-backed
  hosts use streaming presentation output, while the native SwiftUI host
  receives `RasterSurface` values directly
- hosted sessions now accept paired render-style updates so terminal appearance
  and semantic theme move together at runtime
- `TerminalUI` is now library-only; executable launch is entirely runner-owned

### `GUI/SwiftUITUIGUI`

The native SwiftUI host package is landed as a standalone SPM package:

- package root: `GUI/SwiftUITUIGUI`
- dependencies:
  - local path dependency on the root package
- key runtime files:
  - `SwiftUITUIAppState.swift`
  - `SwiftUITUIAppView.swift`
  - `SwiftUITUISceneHost.swift`
  - `NativeSceneBridge.swift`
  - `NativeTerminalSurfaceView.swift`
  - `SwiftUITUITerminalStyle.swift`
- SwiftUI styles now expose explicit light and dark theme variants, each pairing
  native renderer palette state with TerminalUI semantic theme tokens
- verification:
  - `SceneRetentionTests.swift`
  - `ResizeBridgeTests.swift`
  - `StyleMappingTests.swift`

### `GUI/SwiftTermTUIGUI`

The SwiftTerm-backed SwiftUI host package is also landed as a standalone SPM
package:

- package root: `GUI/SwiftTermTUIGUI`
- dependencies:
  - local path dependency on the root package
  - published `SwiftTerm`
- key runtime files:
  - `SwiftTermTUIAppState.swift`
  - `SwiftTermTUIAppView.swift`
  - `SwiftTermTUISceneHost.swift`
  - `SwiftTermTUISceneBridge.swift`
  - `SwiftTermTUITerminalStyle.swift`
- the package keeps one persistent `SwiftTerm.TerminalView` per hosted scene so
  the underlying terminal buffer and emulation state survive scene switches
- SwiftUI styles continue to expose explicit light and dark theme variants,
  each pairing SwiftTerm-native palette state with TerminalUI semantic theme
  tokens
- verification:
  - `SceneRetentionTests.swift`
  - `ResizeBridgeTests.swift`
  - `StyleMappingTests.swift`

### `GUI/WebTUIGUI`

The web host package is also landed:

- package root: `GUI/WebTUIGUI`
- build stack: Bun plus the repo-managed Swift 6.3.0 toolchain
- published dependency: npm `ghostty-web`
- key runtime and build files:
  - `src/WebTUIApp.ts`
  - `src/WebTUISceneRuntime.ts`
  - `src/WebTUISceneManifest.ts`
  - `src/build/buildAppWasm.ts`
  - `src/build/generateSceneManifest.ts`
- web styles now expose explicit light and dark theme variants and can bind
  them to the host color scheme before pushing a full render-style payload into
  the WASI runtime
- the Bun pipeline now builds manifest, wasm, and browser assets without
  depending on repo-local Ghostty source snapshots

### `GUI/XtermWebTUIGUI`

The xterm.js-backed browser host package is also landed:

- package root: `GUI/XtermWebTUIGUI`
- build stack: Bun plus the repo-managed Swift 6.3.0 toolchain
- published dependency: npm `@xterm/xterm` plus `@xterm/addon-fit`
- key runtime and build files:
  - `src/WebTUIApp.ts`
  - `src/WebTUISceneRuntime.ts`
  - `src/WebTUISceneManifest.ts`
  - `src/build/buildAppWasm.ts`
  - `src/build/generateSceneManifest.ts`
- web styles now expose explicit light and dark theme variants and can bind
  them to the host color scheme before pushing a full render-style payload into
  the WASI runtime
- the Bun pipeline now builds manifest, wasm, and browser assets without
  depending on repo-local Ghostty source snapshots, and the xterm.js wrapper
  keeps the browser terminal isolated from the GitHub-hosted Ghostty asset path

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
  - native surface, terminal widget, or browser terminal embedding
  - scene tabs, pickers, or other host-local chrome
  - host-specific style mapping and host-owned theme swapping

This is intentional. Host packages are peer platform integration packages, not
new products in the root package.

## Current Constraints

- CLI multi-scene management and authored multiple scenes are intentionally
  separate concepts:
  - `Runners/TerminalUICLI` can manage multiple native scenes with discovery,
    ptys, and attach flows
  - `Runners/TerminalUIWASI` still executes one selected scene per wasm process
- Host packages still own scene switching UI and style surfaces. The root package exposes scene manifests and hosted sessions, not a full cross-platform app shell.
- `GUI/WebTUIGUI` and `GUI/XtermWebTUIGUI` build scripts drive the repo-default `swiftly` toolchain (falling back to plain `swift` when available). See [TOOLCHAINS.md](TOOLCHAINS.md) for the toolchain requirement. Both packages share the repo Bun workspace for builds and tests.
- Executable runner packages and embedded host packages are intentionally outside the root package products. Consumers opt into them separately.

## Non-Negotiable Decisions

1. GUI host packages are peer packages, not new top-level products in the root package.
2. The root package exposes first-class scene manifest and hosted-session APIs so peer packages do not rely on package-only internals.
3. Each scene gets its own retained runtime session. Switching scenes changes which hosted session is visible; it does not rebuild the app body from scratch.
4. Scene switching is host-managed. It is not a new terminal escape-sequence protocol.
5. Terminal style is host-owned. The Swift package and the Bun package expose mirrored style concepts, not a shared cross-language source file, and host packages choose the active theme variant.
6. The Apple host packages intentionally remain backend-specific peer packages rather than one backend-abstracted package. `GUI/SwiftUITUIGUI` owns the native SwiftUI surface and `GUI/SwiftTermTUIGUI` owns SwiftTerm integration.
7. The web packages keep one wasm module instance per scene and one browser terminal per scene so scene state survives switches without a more complex protocol.
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
- replacing the browser terminal stack with a custom implementation
- collapsing the native SwiftUI and SwiftTerm-backed Apple hosts into a single backend-abstracted package
- adding tabs, split panes, or session persistence beyond in-memory retained scene sessions
