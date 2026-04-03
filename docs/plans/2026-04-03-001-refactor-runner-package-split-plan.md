# refactor: Split Platform Runners Out Of TerminalUI

Date: 2026-04-03
Plan depth: Deep
Status: Proposed

## Problem Frame

The current package boundary no longer matches the product story:

- `TerminalUI` already owns scene authoring primitives such as `App`, `Scene`,
  `SceneBuilder`, `WindowGroup`, and scene collection helpers in
  `Sources/TerminalUI/App.swift`.
- The executable launch path, manifest generation, hosted-session creation, and
  CLI attach or discovery behavior live in `Sources/TerminalUIScenes/`.
- `TerminalUIScenes` is documented as an optional multi-scene layer, but it
  currently carries the default `App.main()` and the single-window launch path.

That makes the current split misleading in two ways:

1. The root package still knows enough to author apps, but the actual running
   story lives in a second package product.
2. CLI multi-scene management is currently bundled together with the concept of
   authored multiple scenes, even though they are separate concerns.

The desired direction is:

- `TerminalUI` becomes a pure library surface and cannot directly produce a
  runnable executable app.
- Platform-specific runner packages own launching and process-host behavior.
- SwiftUI, CLI, and WASI all wrap the same `TerminalUI` app or scene model.
- Web remains a Bun-only wrapper that consumes a `TerminalUI` app built for
  WASI.
- The `TerminalUI` layer should not special-case single-scene apps.

## Requirements Trace

This plan is driven directly by the April 3, 2026 discussion:

- CLI multi-scene management must be independent from authored multiple scenes.
- Target one runner package per platform:
  - CLI
  - SwiftUI
  - WASI
- Each runner package should wrap the same `TerminalUI` build.
- Web should remain a Bun-only wrapper that consumes a `TerminalUI` plus WASI
  build.
- `TerminalUI` should not special-case any single-scene type.
- `TerminalUI` on its own should no longer be able to make a running
  executable product.

## Current Repo Grounding

Relevant current files and packages:

- Root authoring and scene collection:
  - `Sources/TerminalUI/App.swift`
- Root runtime seams already suitable for reuse:
  - `Sources/TerminalUI/StreamingTerminalHost.swift`
  - `Sources/TerminalUI/InjectedTerminalInputReader.swift`
  - `Sources/TerminalUI/TerminalControlMessages.swift`
  - `Sources/TerminalUI/TerminalHost.swift`
- Scene-launch and wrapper-facing APIs currently in the wrong layer:
  - `Sources/TerminalUIScenes/MultiSceneLauncher.swift`
  - `Sources/TerminalUIScenes/SceneManifest.swift`
  - `Sources/TerminalUIScenes/HostedSceneSession.swift`
  - `Sources/TerminalUIScenes/SceneSession.swift`
- CLI-native terminal attach and discovery concerns:
  - `Sources/TerminalUIScenes/CLIMode.swift`
  - `Sources/TerminalUIScenes/SceneRuntime.swift`
  - `Sources/TerminalUIScenes/SceneInfoRegistry.swift`
  - `Sources/TerminalUIScenes/SocketServer.swift`
  - `Sources/TerminalUIScenes/SocketClient.swift`
  - `Sources/TerminalUIScenes/AttachProxy.swift`
  - `Sources/TerminalUIScenes/PtyPair.swift`
- Existing SwiftUI wrapper package:
  - `GUI/SwiftUITUIGUI/Package.swift`
  - `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUIAppState.swift`
  - `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUISceneHost.swift`
- Existing Bun web wrapper:
  - `GUI/WebTUIGUI/package.json`
  - `GUI/WebTUIGUI/src/WebTUIApp.ts`
  - `GUI/WebTUIGUI/src/build/buildAppWasm.ts`
  - `GUI/WebTUIGUI/src/build/generateSceneManifest.ts`
- Existing example launchers that currently depend on `TerminalUIScenes`:
  - `Examples/gallery/Package.swift`
  - `Examples/gallery/Sources/GalleryDemo/GalleryDemoApp.swift`
  - `Examples/todoist/Package.swift`
  - `Examples/todoist/Sources/TodoistDemo/TodoistDemoApp.swift`
  - `Examples/WebExample/TerminalApp/Package.swift`
  - `Examples/WebExample/TerminalApp/Sources/TerminalApp/main.swift`

## Decisions

### 1. `TerminalUI` Becomes Library-Only

`TerminalUI` should own:

- scene authoring protocols and builders
- scene manifest data models and manifest generation
- retained embedded scene sessions used by wrapper packages
- runner-neutral scene-session bootstrap APIs
- terminal host abstractions and control-message contracts

`TerminalUI` should not own:

- terminal-process launch entry points
- `App.main()`
- CLI argument parsing
- socket discovery
- pty attach behavior
- WASI process-specific scene selection or environment bootstrapping

Rationale:

- This matches the user's requirement that the root package no longer be able to
  make a runnable executable product.
- It keeps the reusable app model in one place while moving process or platform
  policy to the runner packages that actually need it.

### 2. CLI Multi-Scene Management Is A Runner Concern

The CLI runner should treat these as separate axes:

- authored scene count
- instance management capabilities such as list, attach, discovery, and
  secondary scene ptys

Implication:

- A CLI runner can manage one scene or many scenes through the same runtime
  management model.
- `TerminalUI` should no longer expose `primaryWindowSceneConfiguration(...)`
  as the normal path for running apps.
- `AppLaunchError.multipleScenesUnsupported` should be removed from the root
  package once no root runtime path depends on it.

Rationale:

- The current single-scene special case in
  `Sources/TerminalUIScenes/MultiSceneLauncher.swift` leaks runner policy back
  into the authored scene model.

### 3. The SwiftUI Wrapper Is The SwiftUI Runner Package

Treat `GUI/SwiftUITUIGUI` as the SwiftUI platform runner package in phase 1.
Do not require an immediate package rename.

It should depend only on `TerminalUI`, not on `TerminalUIScenes`.

Rationale:

- The package already acts like a platform runner.
- Avoiding a simultaneous package rename keeps the refactor narrower and lowers
  migration noise for examples and external consumers.

### 4. WASI Runner Package Is Separate From The Bun Web Wrapper

Introduce a new Swift package dedicated to WASI runner concerns. The Bun web
wrapper should build and consume that package's output artifacts.

The WASI runner owns:

- process environment parsing for scene selection and initial surface sizing
- manifest-only mode for wasm-facing build scripts
- binding a selected scene to a `WebTerminalHost` and injected control-message
  stream

The Bun wrapper owns:

- browser runtime management
- Ghostty terminal embedding
- one wasm module instance per scene
- browser-side scene switching chrome
- build orchestration for manifest and wasm assets

Rationale:

- This matches the requirement that Web remain a Bun-only wrapper rather than a
  fourth root runner concept.

### 5. Root Wrapper APIs Move Into `TerminalUI`

Move the following public APIs out of `TerminalUIScenes` and into `TerminalUI`:

- `TerminalUISceneDescriptor`
- `TerminalUISceneManifest`
- manifest generation helper currently reached through
  `MultiSceneLauncher.sceneManifest(...)`
- `HostedSceneSession`

Likely new file locations:

- `Sources/TerminalUI/SceneManifest.swift`
- `Sources/TerminalUI/HostedSceneSession.swift`
- `Sources/TerminalUI/SceneSession.swift`

Rationale:

- These APIs are not CLI-specific.
- They are the shared wrapper-facing seams already used by SwiftUI and by the
  web build pipeline.

### 6. Temporary Compatibility Shims Are Acceptable, But The End State Removes `TerminalUIScenes`

Use a staged migration:

1. Introduce the new root and runner APIs.
2. Convert examples, wrappers, and docs.
3. Deprecate `TerminalUIScenes`.
4. Remove the `TerminalUIScenes` product and target.

Rationale:

- This reduces breakage while still preserving a clear final state.

## Target Architecture

### Root Package Products

Keep:

- `View`
- `TerminalUI`
- `TerminalUICharts`

Remove after migration:

- `TerminalUIScenes`

### Root Package Responsibilities

`TerminalUI` should expose:

- `App`, `Scene`, `SceneBuilder`, `WindowGroup`, `WindowIdentifier`
- scene collection and normalization
- scene manifest models and generation
- retained scene session APIs for non-terminal hosts
- terminal host abstractions and control-message handling
- the existing `RunLoop` and rendering pipeline

`TerminalUI` should not expose:

- any public `main()` implementation
- a runner that binds apps to terminal stdio by default
- CLI attach or discovery APIs
- WASI process-launch selection policy

### Platform Runner Packages

#### CLI Runner Package

Proposed package:

- `Runners/TerminalUICLI/Package.swift`

Proposed target layout:

- `Runners/TerminalUICLI/Sources/TerminalUICLI/TerminalCLIAppRunner.swift`
- `Runners/TerminalUICLI/Sources/TerminalUICLI/CLIInstanceManager.swift`
- `Runners/TerminalUICLI/Sources/TerminalUICLI/CLIMode.swift`
- `Runners/TerminalUICLI/Sources/TerminalUICLI/SceneRuntime.swift`
- `Runners/TerminalUICLI/Sources/TerminalUICLI/SceneInfoRegistry.swift`
- `Runners/TerminalUICLI/Sources/TerminalUICLI/SocketServer.swift`
- `Runners/TerminalUICLI/Sources/TerminalUICLI/SocketClient.swift`
- `Runners/TerminalUICLI/Sources/TerminalUICLI/AttachProxy.swift`
- `Runners/TerminalUICLI/Sources/TerminalUICLI/PtyPair.swift`

Responsibilities:

- terminal-owned app launch
- CLI argument parsing
- list and attach flows
- pty allocation for secondary terminal scenes
- socket discovery and instance management

Important behavioral rule:

- the CLI runner always operates on the app's full scene configuration set
- single-scene apps are simply a one-element configuration list
- no special fast path in `TerminalUI`

#### SwiftUI Runner Package

Phase-1 package:

- `GUI/SwiftUITUIGUI/Package.swift`

Dependencies after refactor:

- `TerminalUI`
- `GhosttyTerminal`

Responsibilities:

- wrapper-local scene switching chrome
- wrapper-local style mapping
- retained session ownership per scene
- embedding `TerminalUI` sessions in SwiftUI

Required code changes:

- replace `MultiSceneLauncher.sceneManifest(for:)` calls with a
  `TerminalUI`-native manifest API
- replace `MultiSceneLauncher.makeHostedSceneSession(...)` calls with a
  `TerminalUI`-native hosted-session API
- remove `TerminalUIScenes` imports from all SwiftUI wrapper sources

#### WASI Runner Package

Proposed package:

- `Runners/TerminalUIWASI/Package.swift`

Proposed target layout:

- `Runners/TerminalUIWASI/Sources/TerminalUIWASI/WASIAppRunner.swift`
- `Runners/TerminalUIWASI/Sources/TerminalUIWASI/WASIEnvironment.swift`

Responsibilities:

- bind one selected scene to `WebTerminalHost`
- parse WASI-facing environment variables such as scene ID, initial size, and
  render style
- emit manifest output for build tooling
- run the same `TerminalUI` scene model compiled for wasm

Important boundary:

- the WASI runner is still a Swift package
- the browser shell remains in `GUI/WebTUIGUI`

### Web Wrapper

Keep as Bun-only:

- `GUI/WebTUIGUI`

It should consume:

- a wasm build produced by a `TerminalUIWASI` executable or build target
- a manifest produced by the same `TerminalUIWASI` runner package

It should not depend conceptually on `TerminalUIScenes` or on ad hoc root
package launch helpers.

## Proposed API Shape

Exact symbol names can be adjusted during implementation, but the boundaries
should look like this:

### In `TerminalUI`

- `App`
- `Scene`
- `WindowGroup`
- `WindowIdentifier`
- `TerminalUISceneDescriptor` or a renamed runner-neutral descriptor type
- `TerminalUISceneManifest` or a renamed runner-neutral manifest type
- `SceneManifestBuilder.manifest(for:)` or an equivalent static manifest API
- `HostedSceneSession` or a renamed runner-neutral retained session type

### In `TerminalUICLI`

- `TerminalCLIAppRunner.run(MyApp.self)`
- `TerminalCLIAppRunner.run(MyApp())`
- CLI mode and attach or discovery support types as package-internal helpers

### In `TerminalUIWASI`

- `WASIAppRunner.run(MyApp.self)`
- `WASIAppRunner.run(MyApp())`
- `WASIAppRunner.manifest(for:)` only if the build scripts need a public helper

### Removed From Root Public Surface

- `App.main()` default implementation
- `MultiSceneLauncher`
- root-level single-scene runtime assumptions

## File-Level Refactor Plan

### Phase 1: Move Wrapper-Facing APIs Into `TerminalUI`

Update or create:

- `Sources/TerminalUI/SceneManifest.swift`
- `Sources/TerminalUI/HostedSceneSession.swift`
- `Sources/TerminalUI/SceneSession.swift`
- `Sources/TerminalUI/App.swift`
- `Sources/TerminalUI/TerminalUI.docc/Running-Apps.md`
- `Sources/TerminalUI/TerminalUI.docc/TerminalUI.md`

Actions:

- move manifest models and manifest generation into `TerminalUI`
- move hosted-session implementation into `TerminalUI`
- delete the root single-scene helper path from public guidance
- remove `App.main()` from the root public authoring story

Tests to update or add:

- `Tests/TerminalUITests/AppRuntimeTests.swift`
- `Tests/TerminalUITests/Phase4ObservationAndEnvironmentTests.swift`
- `Tests/TerminalUITests/InteractiveRuntimeTests.swift`
- add a new `Tests/TerminalUITests/SceneManifestTests.swift` if manifest tests
  move out of the old target
- add a new `Tests/TerminalUITests/HostedSceneSessionTests.swift` if hosted
  session tests move out of the old target

### Phase 2: Add The CLI Runner Package

Create:

- `Runners/TerminalUICLI/Package.swift`
- `Runners/TerminalUICLI/Sources/TerminalUICLI/...`
- `Runners/TerminalUICLI/Tests/TerminalUICLITests/...`

Move logic from:

- `Sources/TerminalUIScenes/CLIMode.swift`
- `Sources/TerminalUIScenes/SceneRuntime.swift`
- `Sources/TerminalUIScenes/SceneLifecycle.swift`
- `Sources/TerminalUIScenes/SceneInfoRegistry.swift`
- `Sources/TerminalUIScenes/SocketServer.swift`
- `Sources/TerminalUIScenes/SocketClient.swift`
- `Sources/TerminalUIScenes/AttachProxy.swift`
- `Sources/TerminalUIScenes/PtyPair.swift`
- native-launch sections of `Sources/TerminalUIScenes/MultiSceneLauncher.swift`

Actions:

- remove the single-scene fast path and always build the CLI runner around a
  scene-configuration list
- keep list and attach behavior available even if the app only declares one
  scene
- treat instance discovery and attach routing as CLI runner features, not scene
  authoring features

Tests to create:

- `Runners/TerminalUICLI/Tests/TerminalUICLITests/CLIModeTests.swift`
- `Runners/TerminalUICLI/Tests/TerminalUICLITests/SceneRuntimeTests.swift`
- `Runners/TerminalUICLI/Tests/TerminalUICLITests/SceneInfoRegistryTests.swift`
- `Runners/TerminalUICLI/Tests/TerminalUICLITests/SocketDiscoveryTests.swift`
- `Runners/TerminalUICLI/Tests/TerminalUICLITests/SocketProtocolTests.swift`
- `Runners/TerminalUICLI/Tests/TerminalUICLITests/PtyPairTests.swift`

### Phase 3: Add The WASI Runner Package

Create:

- `Runners/TerminalUIWASI/Package.swift`
- `Runners/TerminalUIWASI/Sources/TerminalUIWASI/WASIAppRunner.swift`
- `Runners/TerminalUIWASI/Sources/TerminalUIWASI/WASIEnvironment.swift`
- `Runners/TerminalUIWASI/Tests/TerminalUIWASITests/...`

Move logic from:

- WASI sections of `Sources/TerminalUIScenes/MultiSceneLauncher.swift`
- any WASI-specific selection logic currently embedded in CLI-oriented types

Actions:

- make scene selection and initial terminal sizing a WASI runner concern
- keep the root package free of wasm process policy
- preserve the current one-scene-per-process wasm reality without teaching
  `TerminalUI` that one scene is special

Tests to create:

- `Runners/TerminalUIWASI/Tests/TerminalUIWASITests/WASIEnvironmentTests.swift`
- `Runners/TerminalUIWASI/Tests/TerminalUIWASITests/WASIManifestModeTests.swift`

### Phase 4: Convert Existing Runners And Examples

Update:

- `GUI/SwiftUITUIGUI/Package.swift`
- `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUIAppState.swift`
- `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUISceneHost.swift`
- `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/GhosttySceneBridge.swift`
- `Examples/gallery/Package.swift`
- `Examples/gallery/Sources/GalleryDemo/GalleryDemoApp.swift`
- `Examples/todoist/Package.swift`
- `Examples/todoist/Sources/TodoistDemo/TodoistDemoApp.swift`
- `Examples/WebExample/TerminalApp/Package.swift`
- `Examples/WebExample/TerminalApp/Sources/TerminalApp/main.swift`
- `GUI/WebTUIGUI/src/build/buildAppWasm.ts`
- `GUI/WebTUIGUI/src/build/generateSceneManifest.ts`
- `Examples/WebExample/README.md`

Actions:

- SwiftUI wrapper imports `TerminalUI` only
- native examples import `TerminalUICLI` for executable launch behavior
- Web example executable imports `TerminalUIWASI`
- Bun build scripts invoke the WASI runner package or executable instead of
  assuming a `TerminalUIScenes`-based launcher

### Phase 5: Remove `TerminalUIScenes`

Delete after migration:

- `Sources/TerminalUIScenes/`
- `Tests/TerminalUIScenesTests/`
- `TerminalUIScenes` references in `Package.swift`

Update docs:

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/STATUS.md`
- `docs/SOURCE_LAYOUT.md`
- `docs/PUBLIC_API_INVENTORY.md`
- `docs/PUBLIC_SURFACE_POLICY.md`
- `docs/TESTING_AND_FIXTURE_POLICY.md`
- `docs/README.md`
- `TUIGUI.md`
- `docs/TOOLCHAINS.md`

## Sequencing And Dependencies

Recommended order:

1. Land root `TerminalUI` wrapper-facing APIs first.
2. Add the CLI runner package and move native terminal launch into it.
3. Add the WASI runner package and repoint the web build pipeline to it.
4. Update the SwiftUI wrapper to depend only on `TerminalUI`.
5. Convert examples.
6. Remove the compatibility layer and delete `TerminalUIScenes`.

Why this order:

- It creates the stable shared surface before moving platform behavior.
- It lets the platform runners adopt the same root manifest and session APIs.
- It avoids a period where wrappers depend on package-internal seams.

## Risks And Mitigations

### Risk: Public API Churn Breaks Existing Consumers

Mitigation:

- land temporary deprecated forwarding APIs where practical
- keep type names stable in phase 1 unless a rename provides major clarity
- remove `TerminalUIScenes` only after examples and wrappers compile cleanly

### Risk: Runner Extraction Reintroduces Hidden Single-Scene Assumptions

Mitigation:

- explicitly remove `primaryWindowSceneConfiguration(...)` from runtime-facing
  examples and runner flows
- test one-scene and many-scene apps through the same CLI and WASI runner
  surfaces

### Risk: Web Tooling Drifts From The Shared App Model

Mitigation:

- make manifest generation come from `TerminalUI` root APIs
- make wasm launch come from `TerminalUIWASI`
- keep `GUI/WebTUIGUI` focused on browser hosting only

### Risk: SwiftUI Wrapper Keeps Depending On Old Scene Product Semantics

Mitigation:

- migrate SwiftUI wrapper directly to root manifest and hosted-session APIs
- delete the extra dependency from `GUI/SwiftUITUIGUI/Package.swift`

## Verification Strategy

Root package:

- `swiftly run swift build`
- `swiftly run swift test`

SwiftUI runner package:

- `cd GUI/SwiftUITUIGUI && swiftly run swift build`
- `cd GUI/SwiftUITUIGUI && swiftly run swift test`

CLI runner package:

- `cd Runners/TerminalUICLI && swiftly run swift build`
- `cd Runners/TerminalUICLI && swiftly run swift test`

WASI runner package:

- `cd Runners/TerminalUIWASI && swiftly run swift build --swift-sdk swift-6.3-RELEASE_wasm`
- targeted tests for environment parsing and manifest mode where native test
  support is available

Web wrapper:

- `cd GUI/WebTUIGUI && bun test`
- `cd GUI/WebTUIGUI && bun run build -- --app <WASI runner product>`

Example apps:

- verify native examples compile against `TerminalUICLI`
- verify WebExample builds its manifest and wasm artifacts through
  `TerminalUIWASI`

## Open Implementation Questions

These are implementation-level questions, not blockers for the architecture:

- whether `HostedSceneSession` should keep its name after moving into
  `TerminalUI`, or whether a runner-neutral name such as `EmbeddedSceneSession`
  reads better
- whether `TerminalUISceneDescriptor` and `TerminalUISceneManifest` should keep
  their names for compatibility or be renamed to shorter root-owned types
- whether `GUI/SwiftUITUIGUI` should be renamed later to reflect its role as a
  runner package, or whether that rename is not worth the churn

None of those questions change the proposed boundary. They only affect naming.

## Success Criteria

This refactor is complete when all of the following are true:

- `TerminalUI` is a library-only product with no default executable entrypoint
- `TerminalUI` no longer documents or exposes a single-scene special case
- CLI launch, attach, discovery, and pty management live in a CLI runner
  package
- SwiftUI wrapper code depends only on `TerminalUI`
- WASI launch behavior lives in a WASI runner package
- `GUI/WebTUIGUI` consumes WASI build artifacts and remains Bun-only
- `TerminalUIScenes` is removed from products, sources, tests, docs, and
  examples
