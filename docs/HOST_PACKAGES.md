# Host Packages

Last updated: April 11, 2026

## Goal

Make TerminalUI apps shippable outside a local terminal in two peer embedded
host packages:

- `GUI/SwiftUITUIGUI`: an SPM package that lets a macOS or iOS app host a TerminalUI scene inside SwiftUI
- `GUI/WebTUIGUI`: a Bun-based package that lets a TerminalUI app ship in the browser on top of `ghostty-web`

The authoring story stays the same:

- app authors continue to write `App`, `Scene`, and `WindowGroup` in the root package
- host packages own terminal-surface hosting, scene selection chrome, and host-local style surfaces
- scene state must survive host-driven scene switches
- resize and host style changes must continue to flow through the same runtime invalidation path as terminal `SIGWINCH`

All Swift build commands in this document assume the repo-default `swiftly`
toolchain story. Use `swiftly run swift ...` directly, or the shorter `swift`
form only from a shell where `swift` already resolves to the `swiftly`-managed
Swift 6.3.0 toolchain.

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
- embedded hosts use `InjectedTerminalInputReader` and
  `StreamingTerminalHost`
- hosted sessions now accept paired render-style updates so terminal appearance
  and semantic theme move together at runtime
- `TerminalUI` is now library-only; executable launch is entirely runner-owned

### `GUI/SwiftUITUIGUI`

The SwiftUI host package is landed as a standalone SPM package:

- package root: `GUI/SwiftUITUIGUI`
- dependencies:
  - local path dependency on the root package
  - published `libghostty-spm`
- key runtime files:
  - `SwiftUITUIAppState.swift`
  - `SwiftUITUIAppView.swift`
  - `SwiftUITUISceneHost.swift`
  - `GhosttySceneBridge.swift`
  - `SwiftUITUITerminalStyle.swift`
- SwiftUI styles now expose explicit light and dark theme variants, each pairing
  Ghostty palette state with TerminalUI semantic theme tokens
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
  - terminal widget embedding
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
- `GUI/WebTUIGUI` build scripts prefer `swiftly run swift` when `swiftly` is installed and fall back to plain `swift` otherwise, so Bun-driven builds still need either the repo-default `swiftly` setup or a shell where `swift` already resolves to the matching Swift 6.3.0 toolchain.
- Executable runner packages and embedded host packages are intentionally outside the root package products. Consumers opt into them separately.

## Non-Negotiable Decisions

1. GUI host packages are peer packages, not new top-level products in the root package.
2. The root package exposes first-class scene manifest and hosted-session APIs so peer packages do not rely on package-only internals.
3. Each scene gets its own retained runtime session. Switching scenes changes which hosted session is visible; it does not rebuild the app body from scratch.
4. Scene switching is host-managed. It is not a new terminal escape-sequence protocol.
5. Terminal style is host-owned. The Swift package and the Bun package expose mirrored style concepts, not a shared cross-language source file, and host packages choose the active theme variant.
6. The web package keeps one wasm module instance per scene and one `ghostty-web` terminal per scene so scene state survives switches without a more complex protocol.
7. The existing resize control-message contract stays the foundation for all non-POSIX resize behavior and is now extended with paired render-style updates.

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
- replacing `ghostty-web` or `libghostty-spm` with a custom terminal implementation
- adding tabs, split panes, or session persistence beyond in-memory retained scene sessions
