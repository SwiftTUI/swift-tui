# Platform Integration Products

## Goal

Make every first-party Swift integration surface available from the root
`swift-tui` package. Consumers should add one package dependency and choose the
products they need:

- **runner products** own process startup and launch routing
- **host products** retain SwiftTUI scenes inside another app or runtime
  lifecycle
- **presentation surfaces** are low-level frame sinks used by `RunLoop`

See [TERMINOLOGY.md](TERMINOLOGY.md) for the full vocabulary. The `Platforms/`
directory is now source layout for root package targets, except
`Platforms/Web`, which remains the Bun browser package.

## Root Package Products

The root `Package.swift` exposes the framework and platform products together:

- `SwiftTUI`: one-import terminal app convenience product
- `SwiftTUIRuntime`: platform-neutral authoring/runtime composition product,
  scene declarations, `SceneManifest`, and `HostedSceneSession`
- `SwiftTUICLI`: terminal-native executable runner
- `SwiftTUIArguments`: shared framework flag and environment parsing
- `SwiftTUIWASI`: WASI executable runner and manifest mode
- `WASISurfaceBridge`: pure `web-surface` transport for WASI/Web integrations
- `SwiftUIHost`: native SwiftUI scene host on Apple platforms
- `SwiftTUIWebHost`: localhost browser WebHost runner and bridge
- `SwiftTUIWebHostCLI`: combined terminal/WebHost runner
- `SwiftTUITerminal`: `TerminalView`, terminal emulator, and child-process
  session APIs
- `SwiftTUITerminalWorkspace`: tabs, split panes, workspace state, retained
  terminal sessions, and workspace chrome above `TerminalView`
- `SwiftTUIPTYPrimitives`: pty creation, fd lifecycle, read/write, and resize
  support

The source directories remain useful ownership boundaries:

- `Platforms/CLI`: `SwiftTUICLI`
- `Platforms/Arguments`: `SwiftTUIArguments`
- `Sources/SwiftTUIRuntime`: platform-neutral runtime, scene, terminal
  presentation, and hosted-session seams
- `Platforms/WASI`: `SwiftTUIWASI` and `WASISurfaceBridge`
- `Platforms/SwiftUI`: `SwiftUIHost`
- `Platforms/WebHost`: `SwiftTUIWebHost` and `SwiftTUIWebHostCLI`
- `Platforms/Embedding`: `SwiftTUITerminal`, `SwiftTUITerminalWorkspace`,
  and `SwiftTUIPTYPrimitives`
- `Platforms/Web`: Bun package for deploy-to-browser hosting

## Consumer Composition

Consumers choose one launch composition at compile time:

- terminal-only apps import `SwiftTUI`; `--web` is rejected before raw-mode
  setup and the binary links no server, WebSocket, FlyingFox, or browser-bundle
  code
- custom terminal launchers can compose `SwiftTUIRuntime` with `SwiftTUICLI`
  directly when they do not want the `SwiftTUI` convenience product
- web-only local-browser apps import `SwiftTUIWebHost`; launch is owned by
  `WebHostRunner`
- terminal plus local-browser apps use `SwiftTUIWebHostCLI` as an import
  replacement; normal launches use `TerminalRunner`, while `--web` uses
  `WebHostRunner`
- WASI apps import `SwiftTUIWASI`; transport-only browser consumers can import
  `WASISurfaceBridge`
- native Apple apps import `SwiftUIHost` to retain `HostedSceneSession` values
  inside SwiftUI app lifecycle
- apps that embed external terminal programs import `SwiftTUITerminal`
- apps that need a tabbed/split-pane terminal workspace import
  `SwiftTUITerminalWorkspace`

Example apps remain separate mini packages. They depend on the repo root with:

```swift
.package(name: "swift-tui", path: "../..")
```

and select products with `.product(name: ..., package: "swift-tui")`.

## Shipped Architecture

The platform-integration-facing root work is landed:

- `SwiftTUI` exposes `SceneDescriptor`, `SceneManifest`, and
  `HostedSceneSession` through the terminal convenience import
- `SwiftTUIRuntime` owns the shared runtime, scene declarations,
  `SceneManifest`, and `HostedSceneSession`
- `SwiftTUICLI` owns terminal-native attach/list CLI behavior and explicit
  terminal launch; the `SwiftTUI` convenience product re-exports it for the
  default terminal `App.main()` story
- `SwiftTUIWASI` owns manifest-only mode through `TUIGUI_MODE=manifest` plus
  WASI scene launch
- `SwiftTUIWebHost` owns the opt-in WebHost runner and localhost browser host
  bridge for local binaries that should render in a browser
- `SwiftTUIWebHostCLI` composes terminal and WebHost launch routing without
  adding WebHost dependencies to terminal-only binaries
- `SwiftUIHost` owns the native SwiftUI retained-scene surface
- `SwiftTUITerminal` owns terminal-program embedding through `TerminalView`
- shared control-message parsing lives in
  `Sources/SwiftTUIRuntime/Terminal/TerminalControlMessages.swift`
- embedded hosts use `InjectedTerminalInputReader` where they need
  wrapper-managed byte or event delivery; WebHost uses streaming presentation
  output, while the native SwiftUI host receives `RasterSurface` values
  directly
- hosted sessions accept paired render-style updates so terminal appearance and
  semantic theme move together at runtime
- composed host products depend on `SwiftTUIRuntime` instead of the `SwiftTUI`
  terminal convenience product

## Responsibilities

The current boundary is:

- `SwiftTUI` terminal convenience product:
  - one-import terminal app authoring
  - standard argument parsing
  - default terminal `App.main()` through `SwiftTUICLI`
- platform-neutral runtime product:
  - app authoring
  - scene collection
  - retained hosted runtime sessions
  - manifest generation
  - control-message contract for resize and render-style updates
- runner products:
  - default `App.main()` or explicit launcher entry points
  - launch routing, argv/env parsing, and runtime-configuration construction
  - process-level setup such as raw mode, signal/crash handling, or manifest
    output where applicable
- host products:
  - window or browser shell integration
  - native surface or canvas surface embedding
  - scene tabs, pickers, or other host-local chrome
  - host-specific style mapping and host-owned theme swapping
- terminal embedding products:
  - pty management
  - emulator-backed foreign-surface snapshots
  - child process lifecycle and input forwarding
  - terminal workspace state, pane commands, and session retention

Runner and host responsibilities are explicit external concepts; `Platforms/`
is only the source directory that contains their target implementations.

## Current Constraints

- CLI multi-scene management and authored multiple scenes are intentionally
  separate concepts:
  - `SwiftTUICLI` can manage multiple native scenes with discovery, ptys, and
    attach flows
  - `SwiftTUIWASI` still executes one selected scene per wasm process
- Host products still own scene switching UI and style surfaces. The root
  runtime exposes scene manifests and hosted sessions, not a full
  cross-platform app shell.
- `Platforms/Web` build scripts drive the repo-default `swiftly` toolchain
  and the repo Bun workspace. See [TOOLCHAINS.md](TOOLCHAINS.md) for the
  toolchain requirement.
- `SwiftTUIWebHost` serves a single scene in v1. Multi-scene browser chrome,
  multi-viewer control transfer, TLS, QR codes, and recording remain follow-up
  work.
- `SwiftTUIWebHost` and `SwiftTUIWebHostCLI` are the only first-party products
  that link the embedded HTTP/WebSocket server dependency and browser
  resources. Terminal-only `SwiftTUI` binaries never weak-link or discover
  that code at runtime.

## Non-Negotiable Decisions

1. Swift platform integration products live in the root package.
2. Example apps stay as separate mini packages that depend on the root package.
3. `Platforms/` remains an ownership map for source files, not a set of nested
   SwiftPM packages.
4. The root runtime exposes first-class scene manifest and hosted-session APIs
   so platform products do not rely on package-only internals.
5. Each scene gets its own retained runtime session. Switching scenes changes
   which hosted session is visible; it does not rebuild the app body from
   scratch.
6. Scene switching is host-managed. It is not a new terminal escape-sequence
   protocol.
7. Terminal style is host-owned. The Swift package and the Bun package expose
   mirrored style concepts, not a shared cross-language source file, and hosts
   choose the active theme variant.
8. The web package keeps one wasm module instance per scene and one canvas
   surface per scene so scene state survives switches without a more complex
   protocol.
9. The existing resize control-message contract stays the foundation for all
   non-POSIX resize behavior and is extended with paired render-style updates.

## Verification Paths

Relevant verification lives in:

```bash
Scripts/test_all.sh
```

`Scripts/test_all.sh` is the canonical full-repo check. From the repo root you
can also invoke the same flow with `bun run test`. The runner verifies the
Swift and Bun environment first, then runs the root products, example packages,
and web tooling that are checked into this repository.

The compile-time WebHost boundary is also checked directly:

```bash
./Scripts/check_webhost_package_boundary.sh
```

## Out Of Scope

- generating an Xcode project
- building custom desktop or mobile chrome beyond a terminal surface and
  scene/style control APIs
- adding a terminal-emulator-backed browser host product
- adding tabs, split panes, or session persistence beyond in-memory retained
  scene sessions
