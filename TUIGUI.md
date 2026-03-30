# TUIGUI Plan

Last updated: March 30, 2026

## Goal

Make TerminalUI apps shippable outside a local terminal in two peer packages:

- `GUI/SwiftUITUIGUI`: an SPM package that lets an Xcode app host a TerminalUI app inside a SwiftUI view on macOS and iOS.
- `GUI/WebTUIGUI`: a Bun-based package that lets a TerminalUI app ship as a browser app backed by `ghostty-web`.

The canonical authoring story must stay the same:

- app authors continue to write `App`, `Scene`, and `WindowGroup` in the main package
- GUI wrappers own only terminal-surface hosting, scene selection, and terminal-style configuration
- scene state must survive scene switches
- resize must always update the runtime as if `SIGWINCH` fired, even where POSIX signals do not exist

## Inputs Studied

These references are the basis for this plan:

- `reference/libghostty-spm/Sources/GhosttyTerminal/InMemory/InMemoryTerminalSession.swift`
- `reference/libghostty-spm/Sources/GhosttyTerminal/Surface/TerminalSurfaceView.swift`
- `reference/libghostty-spm/Sources/GhosttyTerminal/State/TerminalViewState.swift`
- `reference/libghostty-spm/Sources/GhosttyTerminal/Surface/TerminalSurfaceCoordinator.swift`
- `reference/libghostty-spm/Example/GhosttyTerminalApp/ViewController.swift`
- `reference/libghostty-spm/Example/MobileGhosttyApp/ViewController.swift`
- `reference/ghostling/main.c`
- `reference/ghostling/README.md`
- `reference/ghostty-web/lib/index.ts`
- `reference/ghostty-web/lib/terminal.ts`
- `reference/ghostty-web/lib/addons/fit.ts`
- `reference/ghostty-web/scripts/build-wasm.sh`
- `reference/ghostty-web/demo/index.html`
- `reference/ghostty/example/wasm-vt/README.md`

Reference conclusions:

- `libghostty-spm` proves the right Apple embedding model: host-managed I/O, `InMemoryTerminalSession`, resize callbacks, and a SwiftUI-facing observable view state.
- `ghostling` proves libghostty is only the terminal core. Windowing, scene chrome, resize ownership, and input routing belong in the embedding layer.
- `ghostty-web` proves the right browser terminal model: one terminal instance per hosted session, `FitAddon` for resize, and a JS-side control plane that forwards input and resize separately.
- the Ghostty `wasm-vt` example proves the browser path should treat Ghostty as an embeddable wasm/lib terminal surface, not as a full app shell.

## Current Repo Findings

- `GUI/SwiftUITUIGUI` and `GUI/WebTUIGUI` already exist, but both are stubs.
- `TerminalUIScenes.MultiSceneLauncher` already supports multiple collected scenes on native platforms.
- the WASI path already has the right resize behavior shape:
  - `Sources/TerminalUI/InputReader.swift` supports control messages with `0x1Eresize:<cols>:<rows>\n`
  - `Sources/TerminalUIScenes/MultiSceneLauncher.swift` maps that resize control message to `WebTerminalHost.updateSurfaceSize(...)` plus `SIGWINCH`
  - `Sources/TerminalUI/RunLoop+EventDispatch.swift` already treats `SIGWINCH` as “continue and rerender”
- the current WASI scene path is still single-scene only:
  - `Sources/TerminalUIScenes/SceneRuntime.swift` rejects secondary scenes on WASI
  - `Sources/TerminalUIScenes/MultiSceneLauncher.swift` picks one scene by environment/argv
- the root package is not yet selectable under the installed wasm SDK.

Observed on March 30, 2026:

```bash
xcrun swift build --swift-sdk swift-6.3-RELEASE_wasm --target Core
```

This currently fails with:

```text
unable to create target: 'No available targets are compatible with triple "wasm32-unknown-wasip1"'
```

Project 0 is therefore mandatory.

## Non-Negotiable Decisions

1. GUI wrappers are peer packages, not new top-level products in the root package.
2. The root package must expose a first-class scene manifest and a first-class hosted-session API so peer packages do not rely on package-only internals.
3. Each scene gets its own retained runtime session. Switching scenes changes which hosted session is visible; it does not rebuild the app body from scratch.
4. Scene switching is wrapper-managed. It is not a new terminal escape-sequence protocol.
5. Terminal style is wrapper-owned. The Swift package and the Bun package will expose mirrored style concepts, but not a shared cross-language source file.
6. The web package will keep one wasm module instance per scene and one `ghostty-web` terminal per scene. This preserves state while keeping the runtime contract simple.
7. The existing resize control-message contract stays the foundation for all non-POSIX resize behavior.

## Out of Scope

- generating an Xcode project
- building custom desktop/mobile chrome beyond a terminal surface and scene/style control APIs
- replacing `ghostty-web` or `libghostty-spm` with a custom terminal implementation
- adding tabs, split panes, or session persistence beyond scene retention in memory

## Project 0: Prepare TerminalUI

### Deliverables

- make the root package selectable for `swift-6.3-RELEASE_wasm`
- expose a public scene manifest API
- expose a public hosted-session API for non-terminal hosts
- extract shared terminal control-message parsing so fd-backed and in-memory inputs use the same contract
- add a streaming terminal host for wrapper-driven output sinks
- add manifest mode for wrapper build tooling

### Files To Change

- `Package.swift`
- `Sources/TerminalUI/InputReader.swift`
- `Sources/TerminalUI/TerminalHost.swift`
- `Sources/TerminalUIScenes/MultiSceneLauncher.swift`
- `docs/ARCHITECTURE.md`
- `docs/STATUS.md`
- `docs/SOURCE_LAYOUT.md`
- `README.md`

### Files To Add

- `Sources/TerminalUI/TerminalControlMessages.swift`
- `Sources/TerminalUI/InjectedTerminalInputReader.swift`
- `Sources/TerminalUI/StreamingTerminalHost.swift`
- `Sources/TerminalUIScenes/SceneManifest.swift`
- `Sources/TerminalUIScenes/HostedSceneSession.swift`
- `Tests/TerminalUITests/InjectedTerminalInputReaderTests.swift`
- `Tests/TerminalUITests/StreamingTerminalHostTests.swift`
- `Tests/TerminalUIScenesTests/SceneManifestTests.swift`
- `Tests/TerminalUIScenesTests/HostedSceneSessionTests.swift`

### Public API To Add

Add these in `TerminalUIScenes`:

- `public struct TerminalUISceneDescriptor: Codable, Hashable, Sendable`
  - `id: WindowIdentifier`
  - `title: String?`
  - `isDefault: Bool`
- `public struct TerminalUISceneManifest: Codable, Sendable`
  - `defaultSceneID: WindowIdentifier`
  - `scenes: [TerminalUISceneDescriptor]`
- `@MainActor public static func sceneManifest<A: App>(for app: A) -> TerminalUISceneManifest`
- `@MainActor public static func makeHostedSceneSession<A: App>(for app: A, sceneID: WindowIdentifier, initialSize: Size, appearance: TerminalAppearance, capabilityProfile: TerminalCapabilityProfile = .trueColor, onOutput: @escaping @Sendable (String) -> Void) throws -> HostedSceneSession`
- `@MainActor public final class HostedSceneSession`
  - `descriptor: TerminalUISceneDescriptor`
  - `start() async throws -> RunLoopExitReason`
  - `sendInput(_ bytes: [UInt8])`
  - `resize(to size: Size)`
  - `updateAppearance(_ appearance: TerminalAppearance)`
  - `stop()`

### Runtime Design

- `HostedSceneSession` wraps one collected `WindowSceneConfiguration`.
- It owns:
  - one `StreamingTerminalHost`
  - one `InjectedTerminalInputReader`
  - one `InProcessSignalReader`
  - one `RunLoop<MultiSceneRuntimeState>`
- `StreamingTerminalHost` mirrors the mutable parts of `WebTerminalHost` but writes terminal output to a closure instead of an fd.
- `InjectedTerminalInputReader` accepts pushed byte chunks and runs the same parser/control-message logic that `InputReader` uses today.
- `resize(to:)` must:
  - update host surface size
  - emit `SIGWINCH` through the in-process signal reader
- `updateAppearance(_:)` must:
  - update the host’s `TerminalAppearance`
  - schedule a new frame through the same synthetic `SIGWINCH` path

### Manifest Mode

`MultiSceneLauncher.run(Self())` must gain a manifest-only mode that prints JSON and exits before launching any runtime.

Use these environment variables:

- `TUIGUI_MODE=manifest`
- `TUIGUI_SCENE=<scene-id>`
- `TUIGUI_COLUMNS=<cols>`
- `TUIGUI_ROWS=<rows>`

Keep these current names as backward-compatible aliases for one landing cycle:

- `WEBAPP_SCENE`
- `WEBAPP_COLUMNS`
- `WEBAPP_ROWS`

Manifest JSON shape:

```json
{
  "defaultSceneID": "dashboard",
  "scenes": [
    { "id": "dashboard", "title": "Dashboard", "isDefault": true },
    { "id": "controls", "title": "Controls", "isDefault": false }
  ]
}
```

### Verification Checkpoints

Checkpoint P0.1:

- `xcrun swift build --swift-sdk swift-6.3-RELEASE_wasm --target Core` succeeds
- `xcrun swift build --swift-sdk swift-6.3-RELEASE_wasm --target TerminalUIScenes` succeeds

Checkpoint P0.2:

- `xcrun swift test --filter TerminalUITests.InputReaderControlMessageTests` still passes
- new `InjectedTerminalInputReaderTests` prove pushed resize control messages do not leak into key input

Checkpoint P0.3:

- new `SceneManifestTests` prove multi-scene apps emit stable manifest JSON
- new `HostedSceneSessionTests` prove:
  - output reaches the supplied closure
  - resize triggers rerender without exiting
  - appearance updates cause a fresh frame

## Project 1: `GUI/SwiftUITUIGUI`

### Package Shape

Keep it as a standalone SPM package at `GUI/SwiftUITUIGUI`.

Dependencies:

- local path dependency on the root package at `../..`
- local path dependency on `../../reference/libghostty-spm`

The package should stay library-only. It should not create an app target.

### Files To Change

- `GUI/SwiftUITUIGUI/Package.swift`
- `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUIGUI.swift`
- `GUI/SwiftUITUIGUI/Tests/SwiftUITUIGUITests/SwiftUITUIGUITests.swift`

### Files To Add

- `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUIAppState.swift`
- `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUIAppView.swift`
- `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUISceneHost.swift`
- `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/GhosttySceneBridge.swift`
- `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUITerminalStyle.swift`
- `GUI/SwiftUITUIGUI/Tests/SwiftUITUIGUITests/SceneRetentionTests.swift`
- `GUI/SwiftUITUIGUI/Tests/SwiftUITUIGUITests/StyleMappingTests.swift`
- `GUI/SwiftUITUIGUI/Tests/SwiftUITUIGUITests/ResizeBridgeTests.swift`

### Public API

Add these wrapper-facing types:

- `public struct SwiftUITUITerminalStyle: Equatable, Sendable`
  - `fontSize: Float?`
  - `fontFamily: String?`
  - `cursorStyle: block | bar | underline`
  - `cursorBlink: Bool`
  - `backgroundOpacity: Float`
  - `lightPalette`
  - `darkPalette`
- `public struct SwiftUITUISceneDescriptor: Identifiable, Hashable, Sendable`
  - mirrors `TerminalUISceneDescriptor`
- `@MainActor @Observable public final class SwiftUITUIAppState<A: TerminalUI.App>`
  - `scenes: [SwiftUITUISceneDescriptor]`
  - `selectedSceneID: WindowIdentifier`
  - `style: SwiftUITUITerminalStyle`
  - `isRunning: Bool`
- `@MainActor public struct SwiftUITUIAppView<A: TerminalUI.App>: SwiftUI.View`
  - `init(state: SwiftUITUIAppState<A>)`

### Hosting Design

- `SwiftUITUIAppState` builds the root `TerminalUISceneManifest` once from the supplied `App`.
- It lazily creates one `SwiftUITUISceneHost` per scene id.
- Each `SwiftUITUISceneHost` owns:
  - one `HostedSceneSession` from the root package
  - one `InMemoryTerminalSession` from `GhosttyTerminal`
  - one `GhosttyTerminal.TerminalViewState`
- Output flow:
  - `HostedSceneSession` output closure emits ANSI text
  - bridge converts `String` to UTF-8 `Data`
  - `InMemoryTerminalSession.receive(...)` feeds Ghostty
- Input flow:
  - Ghostty `write:` callback provides bytes from keyboard/paste/input
  - bridge forwards those bytes to `HostedSceneSession.sendInput(...)`
- Resize flow:
  - Ghostty `resize:` callback yields grid metrics
  - bridge forwards `columns` and `rows` to `HostedSceneSession.resize(...)`

### Scene Switching Contract

- The wrapper does not impose its own scene switcher UI.
- Host apps read `state.scenes` and bind their own tabs/sidebar/segmented control to `state.selectedSceneID`.
- Switching the selected scene only changes which retained `TerminalSurfaceView` is visible.
- Hidden scenes remain alive and keep their TerminalUI state.
- The first selected scene is `manifest.defaultSceneID`.

### Style Contract

`SwiftUITUITerminalStyle` is the only public style surface for this package.

It maps to Ghostty as follows:

- `fontSize` and `fontFamily` map to Ghostty surface options/configuration
- `cursorStyle` and `cursorBlink` map to Ghostty terminal configuration
- `lightPalette` and `darkPalette` map to Ghostty light/dark theme configuration
- `backgroundOpacity` maps to Ghostty background opacity

Style updates must not recreate scene runtimes. They may recreate Ghostty controller/config state only when required by the underlying API.

### Verification Checkpoints

Checkpoint P1.1:

- `xcrun swift build --package-path GUI/SwiftUITUIGUI`
- `xcrun swift test --package-path GUI/SwiftUITUIGUI`

Checkpoint P1.2:

- `SceneRetentionTests` prove scene-local `@State` survives `selectedSceneID` changes
- `ResizeBridgeTests` prove Ghostty resize triggers a second frame in the hosted session

Checkpoint P1.3:

- `StyleMappingTests` prove changing `SwiftUITUITerminalStyle` updates Ghostty config without destroying scene state

## Project 2: `GUI/WebTUIGUI`

### Package Shape

Keep it as a Bun package at `GUI/WebTUIGUI`.

Use Bun-native tooling only:

- `bun install`
- `bun run`
- `bun build`
- `bun test`
- `bunx` only where browser automation is necessary

Do not use Vite in this package.

### Files To Change

- `GUI/WebTUIGUI/package.json`
- `GUI/WebTUIGUI/index.ts`
- `GUI/WebTUIGUI/README.md`
- `GUI/WebTUIGUI/tsconfig.json`

### Files To Add

- `GUI/WebTUIGUI/index.html`
- `GUI/WebTUIGUI/src/WebTUIApp.ts`
- `GUI/WebTUIGUI/src/WebTUISceneRuntime.ts`
- `GUI/WebTUIGUI/src/WebTUITerminalStyle.ts`
- `GUI/WebTUIGUI/src/WebTUISceneManifest.ts`
- `GUI/WebTUIGUI/src/wasi/BrowserWASIBridge.ts`
- `GUI/WebTUIGUI/src/wasi/StdIOPipe.ts`
- `GUI/WebTUIGUI/src/build/buildAppWasm.ts`
- `GUI/WebTUIGUI/src/build/generateSceneManifest.ts`
- `GUI/WebTUIGUI/src/build/resolveSwiftArtifacts.ts`
- `GUI/WebTUIGUI/src/WebTUIApp.test.ts`
- `GUI/WebTUIGUI/src/WebTUITerminalStyle.test.ts`
- `GUI/WebTUIGUI/src/WebTUISceneManifest.test.ts`

### Public API

Expose one minimal controller surface:

- `createWebTUIApp(options): Promise<WebTUIAppController>`
- `WebTUIAppController`
  - `scenes: WebTUISceneDescriptor[]`
  - `selectedSceneId: string`
  - `switchScene(id: string): Promise<void>`
  - `setStyle(style: WebTUITerminalStyle): void`
  - `dispose(): Promise<void>`

`WebTUITerminalStyle` mirrors the Swift package concept:

- `fontSize?: number`
- `fontFamily?: string`
- `cursorStyle?: 'block' | 'bar' | 'underline'`
- `cursorBlink?: boolean`
- `lightPalette`
- `darkPalette`

### Build Pipeline

`package.json` scripts must include:

- `build:manifest`
- `build:wasm`
- `build:web`
- `build`
- `dev`
- `test`

Required build flow:

1. `build:manifest`
   - run the app product natively with `TUIGUI_MODE=manifest`
   - capture stdout JSON
   - write `dist/scene-manifest.json`
2. `build:wasm`
   - run `xcrun swift build --swift-sdk swift-6.3-RELEASE_wasm --product <AppProduct> -c release`
   - locate the produced wasm artifact using `xcrun swift build --show-bin-path --swift-sdk swift-6.3-RELEASE_wasm`
   - copy the app wasm to `dist/assets/app.wasm`
3. `build:web`
   - bundle the HTML/TS entrypoint with `bun build`
   - emit the terminal frame assets to `dist/`

Expected outputs:

- `dist/index.html`
- `dist/scene-manifest.json`
- `dist/assets/app.wasm`
- bundled JS/CSS assets

### Runtime Design

- Parse `scene-manifest.json` on startup.
- Create scene runtimes lazily. Each runtime owns:
  - one `ghostty-web` `Terminal`
  - one `FitAddon`
  - one browser WASI instance of the Swift app module
  - one stdin pipe
  - one stdout/stderr consumer
- Keep scene runtimes in `Map<string, WebTUISceneRuntime>`.
- `switchScene(id)` hides the current scene container and shows the selected scene container.
- Already-created scenes stay alive and preserve state.

### Browser I/O Contract

- User input:
  - `terminal.onData(...)` writes bytes to the scene stdin pipe
- Resize:
  - `FitAddon.fit()` computes cols/rows
  - `terminal.onResize(...)` writes `0x1Eresize:<cols>:<rows>\n` to stdin
- Output:
  - stdout bytes are decoded as UTF-8 and sent to `terminal.write(...)`
- Initial size:
  - pass `TUIGUI_SCENE`, `TUIGUI_COLUMNS`, and `TUIGUI_ROWS` into the WASI environment for the initial boot

### HTML And Visual Scope

- The default rendered artifact is only a terminal frame mount.
- No built-in app sidebar or navigation shell belongs in this package.
- Consumers can build their own scene chooser around the returned controller.

### Verification Checkpoints

Checkpoint P2.1:

- `cd GUI/WebTUIGUI && bun test`

Checkpoint P2.2:

- `cd GUI/WebTUIGUI && bun run build --app <AppProduct>`
- `dist/index.html`
- `dist/scene-manifest.json`
- `dist/assets/app.wasm`
  all exist after the build

Checkpoint P2.3:

- manual browser smoke:
  - initial scene renders
  - switching scenes preserves prior scene output/state
  - resizing the browser container changes TerminalUI layout
  - calling `setStyle(...)` updates the active terminal surface

## Implementation Order

1. Land Project 0 first. Do not start either wrapper package before the root package exposes hosted-session and manifest APIs.
2. Land `SwiftUITUIGUI` second. It has the cleaner runtime contract and validates the hosted-session API without browser/WASI noise.
3. Land `WebTUIGUI` third using the now-stable scene manifest and resize control-message contract.
4. Update docs after both peer packages work:
  - `README.md`
  - `docs/ARCHITECTURE.md`
  - `docs/STATUS.md`
  - `docs/SOURCE_LAYOUT.md`

## Done Means

This work is done only when all of the following are true:

- the root package exposes a public, documented scene-manifest and hosted-session story
- the root package resolves under `swift-6.3-RELEASE_wasm`
- `GUI/SwiftUITUIGUI` can host a TerminalUI app in a SwiftUI view and preserve per-scene state across scene switches
- `GUI/WebTUIGUI` can build a browser bundle, host one retained wasm runtime per scene, and resize via the existing synthetic-`SIGWINCH` path
- both peer packages expose explicit APIs for scene switching and terminal styles
- all checkpoints above are passing or manually verified where marked as browser smoke
