---
title: "feat: embedded web host compile-time opt-in"
type: feature
status: shipped
date: 2026-05-06
proposal: "../proposals/EMBEDDED_WEB_HOST.md"
depends_on:
  - "../proposals/EMBEDDED_WEB_HOST.md"
  - "../proposals/ARGUMENT_PARSING.md"
  - "../proposals/ACCESSIBILITY.md"
  - "../decisions/0008-swifttui-library-only-runners-own-main.md"
  - "../decisions/0014-accessibility-web-aria-wire-policy.md"
---

# Embedded Web Host Compile-Time Opt-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for
> tracking. Keep commits scoped to stages that reach a green checkpoint. This
> plan creates a new runner package and must finish with
> `bun run test --skip-bun-install` before calling the work complete.

**Goal:** Add an opt-in embedded WebHost runner so SwiftTUI apps can serve a
local browser/ARIA view over HTTP/WebSocket, while terminal-only binaries
compile and link no web-server functionality.

**Architecture:** Implement `Platforms/WebHost` as a peer runner package with
two products: `SwiftTUIWebHost` for web-only launch and `SwiftTUIWebHostCLI`
for binaries that intentionally compose terminal and web behavior. The server,
WebSocket adapter, FlyingFox dependency, and bundled browser assets live only in
that package; root `SwiftTUI` and terminal-only `SwiftTUICLI` must never depend
on them. The transport reuses the shared `web-surface` v2 encoder/parser and
the existing `Platforms/Web` renderer/ARIA mounter.

**Tech Stack:** Swift 6.3 strict concurrency, SwiftPM peer packages,
`SwiftTUI` runner SPI, `WASISurfaceBridge` web-surface v2, FlyingFox behind an
internal server protocol, Bun-built `Platforms/Web` browser assets, Swift
Testing, Bun tests, package-graph guard scripts, and the repo-wide
`bun run test --skip-bun-install` gate.

---

## Non-Negotiable Constraints

1. **Compile-time opt-in only.** A consumer must depend on `SwiftTUIWebHost`
   or `SwiftTUIWebHostCLI` for the server to exist in the binary.
2. **No root or terminal leakage.** `SwiftTUI`, `SwiftTUIViews`,
   `SwiftTUICore`, and `SwiftTUICLI` must not depend on `SwiftTUIWebHost`,
   FlyingFox, or the browser bundle.
3. **Terminal-only `--web` is an error.** If a terminal-only binary receives
   `RuntimeConfiguration.web`, it exits before raw-mode setup with a clear
   "not compiled with WebHost" error.
4. **No weak linking.** `SwiftTUICLI` must not probe for `SwiftTUIWebHost`
   symbols, use `dlopen`, or contain a handoff hook to server code.
5. **Reuse web-surface v2.** The embedded host must carry the same
   `accessibilityTree` and announcement data as Web/WASI. Do not invent an
   alternate accessibility wire format.
6. **Manual browser open by default.** Resolve the current parser mismatch by
   making browser launch opt-in via `--open`; Remove `--no-open`, as there are
   no backwards compatibility concerns in this codebase.
7. **Localhost and token by default.** The server binds to `127.0.0.1` and
   emits a per-launch token unless explicitly configured otherwise.

## V1 Boundary

### In Scope

- New `Platforms/WebHost` package.
- `SwiftTUIWebHost` product with server, WebSocket transport, browser bundle,
  and web-only runner.
- `SwiftTUIWebHostCLI` product that composes `SwiftTUICLI` and
  `SwiftTUIWebHost` at compile time.
- Package-graph guardrail script added to `Scripts/test_all.sh`.
- Terminal-only `SwiftTUICLI` rejection for `RuntimeConfiguration.web`.
- `--open` parser policy and tests.
- Single-scene embedded-host execution.
- WebSocket output/input bridge using shared `web-surface` records.
- Static browser bundle served from SwiftPM resources.
- Basic token and origin enforcement.
- Example package proving terminal-only versus web-capable composition.

### Out of Scope

- Multi-scene browser UI.
- Multi-viewer driver/viewer control transfer.
- TLS flags.
- QR code output.
- Asciicast recording.
- ANSI/xterm.js fallback mode.
- External relay, daemon, or reverse-proxy mode.
- Windows support.
- Diff-based web-surface frames.

## File Map

### Create

- `Platforms/WebHost/Package.swift`
  - Defines `SwiftTUIWebHost` and `SwiftTUIWebHostCLI` products.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/SwiftTUIWebHost.swift`
  - `@_exported import SwiftTUI`.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostConfig.swift`
  - Web server bind, port, token, browser-open, and security settings.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostRunner.swift`
  - Web-only public runner entry point.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostServer.swift`
  - Internal server protocol and request/connection model.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostFlyingFoxServer.swift`
  - FlyingFox adapter hidden behind `WebHostServer`.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift`
  - `PresentationSurface` / `DamageAwareSemanticPresentationSurface` over a
    WebSocket send channel.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketInputReader.swift`
  - `TerminalInputReading` over a WebSocket receive channel.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostBrowserBundle.swift`
  - Static resource lookup and content type mapping.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostBanner.swift`
  - URL/banner rendering.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/BrowserOpener.swift`
  - Opt-in browser opening for macOS/Linux.
- `Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser/`
  - Built browser assets copied from `Platforms/Web/dist`.
- `Platforms/WebHost/Sources/SwiftTUIWebHostCLI/SwiftTUIWebHostCLI.swift`
  - `@_exported import SwiftTUI`.
- `Platforms/WebHost/Sources/SwiftTUIWebHostCLI/WebHostCLIRunner.swift`
  - Combined runner: `web != nil` uses WebHost, otherwise terminal.
- `Platforms/WebHost/Tests/SwiftTUIWebHostTests/*.swift`
  - Server, transport, package-graph, runner, and security tests.
- `Platforms/Web/src/WebSocketSceneBridge.ts`
  - Browser-side WebSocket bridge with the same API shape used by
    `WebHostSceneRuntime`.
- `Platforms/Web/src/WebSocketSceneBridge.test.ts`
  - Browser-side bridge tests.
- `Scripts/check_webhost_package_boundary.sh`
  - Guardrail for compile-time opt-in boundaries.
- `Examples/WebHostExample/`
  - Minimal web-capable example package.

### Modify

- `Sources/SwiftTUI/Configuration/RuntimeConfiguration.swift`
  - Make `WebConfig.openBrowser` default to `false`.
- `Sources/SwiftTUI/Configuration/EnvironmentResolver.swift`
  - Add `SWIFTTUI_OPEN=1`; keep `SWIFTTUI_NO_OPEN=1` as an explicit false.
- `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions.swift`
  - Add `--open`; Remove `--no-open`.
- `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions+Resolution.swift`
  - Resolve `openBrowser` with `--open`.
- `Platforms/Arguments/Tests/SwiftTUIArgumentsTests/`
  - Update parser/resolution tests for manual-open default.
- `Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift`
  - Reject `RuntimeConfiguration.web` without importing WebHost.
- `Platforms/CLI/Tests/SwiftTUICLITests/`
  - Cover terminal-only rejection.
- `Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`
  - Expose encoder/parser/control-message seams as SPI or public API suitable
    for the peer WebHost package.
- `Platforms/WASI/Tests/WASISurfaceBridgeTests/`
  - Lock the exposed encoder/parser behavior.
- `Platforms/Web/src/WebHostApp.ts`
  - Allow either WASI bridge or WebSocket bridge runtime construction.
- `Platforms/Web/src/browser.ts`
  - Support embedded-host configuration for manifest and WebSocket URLs.
- `Platforms/Web/index.ts`
  - Export WebSocket bridge entry points.
- `Scripts/test_all.sh`
  - Run `Scripts/check_webhost_package_boundary.sh`.
- `Scripts/check_demo_builds.sh`
  - Build `Examples/WebHostExample`.
- `docs/SOURCE_LAYOUT.md`
  - Add `Platforms/WebHost`.
- `docs/HOST_PACKAGES.md`
  - Document compile-time composition.
- `docs/README.md`
  - Link this plan and the WebHost package once created.
- `docs/PUBLIC_API_INVENTORY.md`
  - Regenerate after new public runner products land.

## Stage 0: Boundary Guard And Parser Policy

**Purpose:** Land the safety rails before server code exists.

**Files:**
- Create: `Scripts/check_webhost_package_boundary.sh`
- Modify: `Scripts/test_all.sh`
- Modify: `Sources/SwiftTUI/Configuration/RuntimeConfiguration.swift`
- Modify: `Sources/SwiftTUI/Configuration/EnvironmentResolver.swift`
- Modify: `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions.swift`
- Modify: `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions+Resolution.swift`
- Modify: `Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIOptionsParseTests.swift`
- Modify: `Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIOptionsResolutionTests.swift`
- Modify: `Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift`
- Modify: `Platforms/CLI/Tests/SwiftTUICLITests/TerminalRunnerTests.swift`

- [x] Add `Scripts/check_webhost_package_boundary.sh`.

  The script must fail if any non-WebHost package or target references the
  server product/dependency names. It should allow docs/proposals/plans to
  mention them.

  ```sh
  #!/usr/bin/env sh
  set -eu

  fail() {
    printf '[check_webhost_package_boundary] %s\n' "$1" >&2
    exit 1
  }

  if rg -n --fixed-strings 'SwiftTUIWebHost' Package.swift Platforms/CLI Sources \
    --glob '*.swift' --glob 'Package.swift'
  then
    fail 'SwiftTUIWebHost must not be referenced by root SwiftTUI, Sources, or Platforms/CLI.'
  fi

  if rg -n --fixed-strings 'FlyingFox' Package.swift Platforms/CLI Sources \
    --glob '*.swift' --glob 'Package.swift'
  then
    fail 'FlyingFox must only be linked from Platforms/WebHost.'
  fi

  if find Sources Platforms/CLI -path '*Resources/browser*' -print | grep .
  then
    fail 'Browser resources must only live under Platforms/WebHost.'
  fi

  printf '[check_webhost_package_boundary] ok\n'
  ```

- [x] Add the guard to `Scripts/test_all.sh` after the existing policy checks.

  Expected command entry:

  ```sh
  run_step \
    "Check WebHost package boundary" \
    "./Scripts/check_webhost_package_boundary.sh" \
    ./Scripts/check_webhost_package_boundary.sh
  ```

- [x] Change `RuntimeConfiguration.WebConfig.openBrowser` default to `false`.

  Expected initializer shape:

  ```swift
  public init(port: Int = 0, bind: String = "127.0.0.1", openBrowser: Bool = false) {
    self.port = port
    self.bind = bind
    self.openBrowser = openBrowser
  }
  ```

- [x] Add `--open` to `SwiftTUIOptions` and remove `--no-open`.

  Resolution rule:

  ```swift
  let openBrowser = open
  ```

  Environment rule:

  ```swift
  let openBrowser = environment["SWIFTTUI_OPEN"].map { !$0.isEmpty && $0 != "0" } ?? false
  ```

- [x] Add parser/resolution tests:

  - `--web` produces `openBrowser == false`.
  - `--web --open` produces `openBrowser == true`.
  - `SWIFTTUI_WEB=1 SWIFTTUI_OPEN=1` produces `openBrowser == true`.
  - `SWIFTTUI_WEB=1`, and `SWIFTTUI_WEB=1 SWIFTTUI_OPEN=0` produce `openBrowser == false`.

- [x] Add a `TerminalRunner` error for web mode in terminal-only binaries.

  Expected behavior:

  ```swift
  if configuration.web != nil {
    throw TerminalRunnerError.webHostNotLinked
  }
  ```

  Error description:

```text
--web requires the opt-in WebHost runner, but this executable was built with
terminal-only SwiftTUICLI. Link the SwiftTUIWebHostCLI product and call
WebHostCLIRunner.run(...), or remove --web.
```

- [x] Run focused checks.

  ```bash
  ./Scripts/check_webhost_package_boundary.sh
  swiftly run swift test --package-path Platforms/Arguments
  swiftly run swift test --package-path Platforms/CLI
  ```

- [x] Commit.

  ```bash
  git add Scripts/check_webhost_package_boundary.sh Scripts/test_all.sh \
    Sources/SwiftTUI/Configuration \
    Platforms/Arguments/Sources Platforms/Arguments/Tests \
    Platforms/CLI/Sources Platforms/CLI/Tests
  git commit -m "Protect WebHost compile-time boundary"
  ```

## Stage 1: Expose Shared Web-Surface Seams

**Purpose:** Let the future WebHost package reuse Web/WASI framing without
copying the protocol.

**Files:**
- Modify: `Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`
- Modify: `Platforms/WASI/Tests/WASISurfaceBridgeTests/WebSurfaceTransportTests.swift`
- Create: `Platforms/WASI/Tests/WASISurfaceBridgeTests/WebSurfaceSPITests.swift`

- [x] Promote the minimum encoder/parser surface needed by peer packages.

  Preferred access shape: keep the existing type names and promote only
  `WebSurfaceFrameEncoder`, `WebSurfaceInputParser`, and
  `WebSurfaceInputControlMessage` as `@_spi(WebHost) public` declarations
  with the same methods and cases used by the current WASI tests.

  Keep field names and record framing byte-for-byte identical to existing
  fixtures.

- [x] Add tests that call the promoted API directly.

  Cover:

  - raster-only frame remains `version: 1`;
  - semantic frame with accessibility nodes emits `version: 2`;
  - parser decodes resize, style, key, mouse, and paste records;
  - malformed records are ignored rather than throwing.

- [x] Run focused checks.

  ```bash
  swiftly run swift test --package-path Platforms/WASI
  ```

- [x] Commit.

  ```bash
  git add Platforms/WASI/Sources Platforms/WASI/Tests
  git commit -m "Expose web-surface seams for WebHost"
  ```

## Stage 2: Scaffold The Opt-In WebHost Package

**Purpose:** Create the package and prove the dependency graph before writing
the server implementation.

**Files:**
- Create: `Platforms/WebHost/Package.swift`
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHost/SwiftTUIWebHost.swift`
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostConfig.swift`
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostRunner.swift`
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHostCLI/SwiftTUIWebHostCLI.swift`
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHostCLI/WebHostCLIRunner.swift`
- Create: `Platforms/WebHost/Tests/SwiftTUIWebHostTests/PackageGraphIsolationTests.swift`
- Modify: `Scripts/check_demo_builds.sh`

- [x] Add `Platforms/WebHost/Package.swift` with two products.

  Product boundary:

  ```swift
  products: [
    .library(name: "SwiftTUIWebHost", targets: ["SwiftTUIWebHost"]),
    .library(name: "SwiftTUIWebHostCLI", targets: ["SwiftTUIWebHostCLI"]),
  ]
  ```

  Dependency direction:

  - `SwiftTUIWebHost` depends on root `SwiftTUI`, `WASISurfaceBridge`, and
    the server dependency.
  - `SwiftTUIWebHostCLI` depends on `SwiftTUIWebHost`, `SwiftTUICLI`, and
    `SwiftTUIArguments`.
  - `SwiftTUICLI` does not change its package dependencies.

- [x] Add placeholder runners that compile but do not start a server yet.

  `WebHostRunner.run` should throw a clear `WebHostRunnerError.serverNotImplemented`
  until Stage 4. `WebHostCLIRunner.run` should route `configuration.web != nil`
  to `WebHostRunner` and otherwise call `TerminalRunner`.

- [x] Add package graph tests and run the shell guard.

  Test expectations:

  - `Platforms/CLI/Package.swift` does not contain `SwiftTUIWebHost`;
  - root `Package.swift` does not contain `SwiftTUIWebHost`;
  - `Platforms/WebHost/Package.swift` contains `SwiftTUIWebHostCLI`;
  - `Scripts/check_webhost_package_boundary.sh` passes.

- [x] Add `Platforms/WebHost` to `Scripts/check_demo_builds.sh` build coverage.

- [x] Run focused checks.

  ```bash
  ./Scripts/check_webhost_package_boundary.sh
  swiftly run swift build --package-path Platforms/WebHost
  swiftly run swift test --package-path Platforms/WebHost
  swiftly run swift test --package-path Platforms/CLI
  ```

- [x] Commit.

  ```bash
  git add Platforms/WebHost Scripts/check_demo_builds.sh
  git commit -m "Scaffold opt-in WebHost runner package"
  ```

## Stage 3: WebSocket Surface And Input Adapters

**Purpose:** Prove the Swift runtime can talk web-surface over an abstract
bidirectional byte stream without an HTTP server.

**Files:**
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift`
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketInputReader.swift`
- Create: `Platforms/WebHost/Tests/SwiftTUIWebHostTests/WebSocketSurfaceTransportTests.swift`
- Create: `Platforms/WebHost/Tests/SwiftTUIWebHostTests/WebSocketInputReaderTests.swift`

- [x] Define a tiny package-internal byte-channel abstraction.

  Shape:

  ```swift
  package protocol WebHostByteSink: Sendable {
    func send(_ bytes: [UInt8]) async throws
  }

  package protocol WebHostByteSource: Sendable {
    func chunks() -> AsyncStream<[UInt8]>
  }
  ```

- [x] Implement `WebSocketSurfaceTransport`.

  It conforms to `PresentationSurface` and `DamageAwareSemanticPresentationSurface`.
  It uses `WebSurfaceFrameEncoder` from the promoted WASI SPI and sends full
  record-separator-prefixed `surface:` JSON records to `WebHostByteSink`.

- [x] Implement `WebSocketInputReader`.

  It consumes `WebHostByteSource`, feeds `WebSurfaceInputParser`, applies
  resize/style control messages to the transport, and yields `InputEvent`.

- [x] Add tests with in-memory byte channels.

  Cover:

  - `present(_:semanticSnapshot:focusedIdentity:damage:)` emits a v2 frame with
    `accessibilityTree` and optional presentation damage;
  - resize input updates `surfaceSize`;
  - style input updates `appearance`/`theme`;
  - key and paste input yield expected `InputEvent` values;
  - sink backpressure preserves record order.

- [x] Run focused checks.

  ```bash
  swiftly run swift test --package-path Platforms/WebHost \
    --filter SwiftTUIWebHostTests.WebSocket
  swiftly run swift test --package-path Platforms/WASI
  ```

- [x] Commit.

  ```bash
  git add Platforms/WebHost Platforms/WASI
  git commit -m "Add WebHost web-surface adapters"
  ```

## Stage 4: Embedded HTTP/WebSocket Server

**Purpose:** Start a local server, serve static responses, and attach one
WebSocket client to the in-memory transport.

**Files:**
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostServer.swift`
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostFlyingFoxServer.swift`
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostToken.swift`
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostOriginPolicy.swift`
- Create: `Platforms/WebHost/Tests/SwiftTUIWebHostTests/WebHostServerTests.swift`
- Create: `Platforms/WebHost/Tests/SwiftTUIWebHostTests/WebHostSecurityTests.swift`

- [x] Define `WebHostServer`.

  Required behavior:

  - bind to `127.0.0.1` by default;
  - return the selected port after binding;
  - serve `/`, `/static/*`, `/scene-manifest.json`, and `/ws/scene/{id}`;
  - reject invalid tokens with HTTP 403;
  - reject invalid WebSocket origins;
  - expose connected scene channels as `WebHostByteSink` /
    `WebHostByteSource`.

- [x] Implement `WebHostFlyingFoxServer` behind the protocol.

  Keep all FlyingFox imports in this file or adjacent WebHost-only files.
  No other package imports FlyingFox.

- [x] Add server tests.

  Cover:

  - binding to port `0` produces a reachable loopback URL;
  - token-protected endpoints reject missing/wrong token;
  - static resource content types are stable;
  - WebSocket upgrade receives output and forwards input;
  - invalid origins are rejected.

- [x] Run focused checks.

  ```bash
  swiftly run swift test --package-path Platforms/WebHost \
    --filter SwiftTUIWebHostTests.WebHostServer
  ./Scripts/check_webhost_package_boundary.sh
  ```

- [x] Commit.

  ```bash
  git add Platforms/WebHost
  git commit -m "Add embedded WebHost server"
  ```

## Stage 5: Browser WebSocket Bridge And Bundle

**Purpose:** Reuse the existing browser renderer without WASI by adding a
WebSocket bridge and packaging a static bundle as SwiftPM resources.

**Files:**
- Create: `Platforms/Web/src/WebSocketSceneBridge.ts`
- Create: `Platforms/Web/src/WebSocketSceneBridge.test.ts`
- Modify: `Platforms/Web/src/WebHostApp.ts`
- Modify: `Platforms/Web/src/WebHostSceneRuntime.ts`
- Modify: `Platforms/Web/src/browser.ts`
- Modify: `Platforms/Web/index.ts`
- Modify: `Platforms/Web/package.json`
- Create: `Scripts/build-webhost-bundle.sh`
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser/`
- Create: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostBrowserBundle.swift`
- Create: `Platforms/WebHost/Tests/SwiftTUIWebHostTests/WebHostBrowserBundleTests.swift`

- [x] Add `WebSocketSceneBridge`.

  It should:

  - open `/ws/scene/{id}?token=TOKEN`;
  - decode incoming text/binary chunks with `WebHostSurfaceDecoder`;
  - forward surface frames to `WebHostSceneRuntime`;
  - send input chunks produced by `WebHostSceneRuntime.onInput`.

- [x] Update `WebHostApp` to support WASI and WebSocket bridge factories.

  Keep existing WASI behavior unchanged. Use the WebSocket bridge only when
  browser config identifies an embedded host manifest.

- [x] Add `Scripts/build-webhost-bundle.sh`.

  Command behavior:

  ```bash
  Scripts/build-webhost-bundle.sh
  ```

  Output:

  - rebuilds `Platforms/Web/dist`;
  - copies `index.html`, JS, and CSS assets into
    `Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser`;
  - fails if the bundle is empty.

- [x] Add `WebHostBrowserBundle` resource lookup tests.

  Cover:

  - `index.html` exists;
  - JS asset exists;
  - CSS asset exists if emitted;
  - content types are `text/html`, `application/javascript`, and `text/css`.

- [x] Run focused checks.

  ```bash
  (cd Platforms/Web && bun run test)
  Scripts/build-webhost-bundle.sh
  swiftly run swift test --package-path Platforms/WebHost \
    --filter SwiftTUIWebHostTests.WebHostBrowserBundle
  ```

- [x] Commit.

  ```bash
  git add Platforms/Web Scripts/build-webhost-bundle.sh Platforms/WebHost
  git commit -m "Bundle browser runtime for WebHost"
  ```

## Stage 6: Run A SwiftTUI Scene Through WebHost

**Purpose:** Replace the placeholder runner with real scene execution.

**Files:**
- Modify: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostRunner.swift`
- Modify: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostBanner.swift`
- Modify: `Platforms/WebHost/Sources/SwiftTUIWebHost/BrowserOpener.swift`
- Create: `Platforms/WebHost/Tests/SwiftTUIWebHostTests/WebHostRunnerTests.swift`

- [x] Implement `WebHostRunner.run`.

  It must:

  - collect scene selections from the app body;
  - reject zero scenes;
  - reject multiple scenes in V1 with a clear error;
  - create `SceneSessionResources` using `WebSocketSurfaceTransport` and
    `WebSocketInputReader`;
  - start the server before running the scene;
  - print the tokenized URL;
  - open the browser only when `openBrowser == true`;
  - keep running until cancellation or process termination.

- [x] Add runner tests using an in-process server fake.

  Cover:

  - no-scene error;
  - multiple-scene V1 error;
  - banner includes tokenized loopback URL;
  - `openBrowser == false` does not invoke `BrowserOpener`;
  - `openBrowser == true` invokes the opener once;
  - one committed frame reaches the connected WebSocket client.

- [x] Run focused checks.

  ```bash
  swiftly run swift test --package-path Platforms/WebHost \
    --filter SwiftTUIWebHostTests.WebHostRunner
  ```

- [x] Commit.

  ```bash
  git add Platforms/WebHost
  git commit -m "Run SwiftTUI scenes through WebHost"
  ```

## Stage 7: Combined CLI Product And Examples

**Purpose:** Give consumers a clean compile-time composition path.

**Files:**
- Modify: `Platforms/WebHost/Sources/SwiftTUIWebHostCLI/WebHostCLIRunner.swift`
- Create: `Platforms/WebHost/Tests/SwiftTUIWebHostTests/WebHostCLIRunnerTests.swift`
- Create: `Examples/WebHostExample/Package.swift`
- Create: `Examples/WebHostExample/Sources/WebHostExample/main.swift`
- Create: `Examples/WebHostExample/Tests/WebHostExampleTests/WebHostExampleTests.swift`
- Modify: `Scripts/check_demo_builds.sh`

- [x] Implement `WebHostCLIRunner`.

  Behavior:

  - parse standard SwiftTUI arguments into `RuntimeConfiguration`;
  - if `configuration.web != nil`, run `WebHostRunner`;
  - otherwise call `TerminalRunner.run(app, configuration:)`;
  - do not modify `SwiftTUICLI` to know about WebHost.

- [x] Add combined-runner tests.

  Cover:

  - `--web` routes to a fake `WebHostRunner`;
  - no `--web` routes to a fake terminal runner;
  - terminal-only `TerminalRunner` still rejects `configuration.web`;
  - `SwiftTUICLI` package graph remains server-free.

- [x] Add `Examples/WebHostExample`.

  It should import only:

  ```swift
  import SwiftTUI
  import SwiftTUIWebHostCLI
  ```

  The terminal-only examples must not import `SwiftTUIWebHostCLI`.

- [x] Add demo build coverage.

  ```bash
  swiftly run swift build --package-path Examples/WebHostExample
  swiftly run swift test --package-path Examples/WebHostExample
  ```

- [x] Commit.

  ```bash
  git add Platforms/WebHost Examples/WebHostExample Scripts/check_demo_builds.sh
  git commit -m "Add combined WebHost CLI runner"
  ```

## Stage 8: Security, Lifecycle, And Failure Polish

**Purpose:** Make the V1 server safe enough to ship as an opt-in runner.

**Files:**
- Modify: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostConfig.swift`
- Modify: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostFlyingFoxServer.swift`
- Modify: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostBanner.swift`
- Modify: `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostOriginPolicy.swift`
- Modify: `Platforms/WebHost/Tests/SwiftTUIWebHostTests/WebHostSecurityTests.swift`
- Modify: `Platforms/WebHost/Tests/SwiftTUIWebHostTests/WebHostServerTests.swift`

- [x] Add port collision behavior.

  Rule:

  - explicit non-zero port fails if unavailable;
  - default port tries `9123` through `9132`;
  - port `0` accepts the kernel-assigned port.

- [x] Add external bind warning.

  If `bind == "0.0.0.0"`, the banner must include a warning that the server is
  reachable from the local network.

- [x] Add token cookie handoff.

  First valid `?token=` request may set a cookie; subsequent browser resource
  requests may use the cookie. WebSocket upgrades must validate token or
  cookie.

- [x] Add max message size enforcement.

  Default: close WebSocket connections over 8 MB with a clear close reason.

- [x] Run focused checks.

  ```bash
  swiftly run swift test --package-path Platforms/WebHost
  ```

- [x] Commit.

  ```bash
  git add Platforms/WebHost
  git commit -m "Harden WebHost server lifecycle"
  ```

## Stage 9: Documentation And Public Surface

**Purpose:** Make the package discoverable without implying it is compiled by
default.

**Files:**
- Modify: `docs/HOST_PACKAGES.md`
- Modify: `docs/SOURCE_LAYOUT.md`
- Modify: `docs/PUBLIC_API_INVENTORY.md`
- Modify: `docs/PUBLIC_SURFACE_POLICY.md`
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/proposals/EMBEDDED_WEB_HOST.md`
- Modify: `docs/proposals/ACCESSIBILITY.md`

- [x] Document consumer choices.

  Required message:

  - terminal-only: import `SwiftTUICLI`;
  - web-only: import `SwiftTUIWebHost`;
  - terminal plus web: import `SwiftTUIWebHostCLI`;
  - no WebHost product means no embedded server in the binary.

- [x] Update source layout docs for `Platforms/WebHost`.

- [x] Regenerate public API inventory.

  ```bash
  ./Scripts/generate_public_api_inventory.sh
  ```

- [x] Run doc/frontmatter checks.

  ```bash
  bun run Scripts/check_doc_frontmatter.ts
  ./Scripts/check_public_surface_policies.sh
  ```

- [x] Commit.

  ```bash
  git add README.md docs Scripts Platforms/WebHost
  git commit -m "Document opt-in WebHost runner"
  ```

## Stage 10: Final Verification

- [x] Run focused package gates.

  ```bash
  ./Scripts/check_webhost_package_boundary.sh
  swiftly run swift test --package-path Platforms/WebHost
  swiftly run swift test --package-path Platforms/CLI
  swiftly run swift test --package-path Platforms/Arguments
  swiftly run swift test --package-path Platforms/WASI
  (cd Platforms/Web && bun run test)
  swiftly run swift test --package-path Examples/WebHostExample
  ```

- [x] Run repo-wide verification.

  ```bash
  bun run test --skip-bun-install
  ```

- [x] Inspect linked package boundaries.

  Confirm these facts before final handoff:

  - `rg -n "SwiftTUIWebHost|FlyingFox" Package.swift Sources Platforms/CLI`
    returns no code/package hits;
  - `swiftly run swift build --package-path Platforms/CLI` succeeds without
    resolving the WebHost package;
  - `swiftly run swift build --package-path Platforms/WebHost` resolves
    FlyingFox only for the WebHost package;
  - the example that imports `SwiftTUIWebHostCLI` can run `--web`;
  - a terminal-only example that receives `--web` prints the not-compiled
    message without raw-mode corruption.

- [x] Commit final verification docs or fixture updates if the verification
  commands changed the public API inventory.

  ```bash
  git status --short
  git add docs/PUBLIC_API_INVENTORY.md docs/PUBLIC_API_BASELINE.md
  git commit -m "Verify WebHost opt-in integration"
  ```

## Implementation Risks

- **FlyingFox API drift.** Keep all server-library-specific code behind
  `WebHostServer`. If FlyingFox's WebSocket API does not match the proposal,
  adapt only `WebHostFlyingFoxServer.swift`.
- **Swift package access.** `WASISurfaceBridge` currently uses `package`
  access for encoder/parser types. Stage 1 must promote only the required
  surface, preferably as SPI, so WebHost can reuse it without duplicating the
  wire format.
- **Browser runtime coupling to WASI.** `Platforms/Web` currently uses
  `BrowserWASIBridge`. Stage 5 must add a WebSocket bridge without regressing
  WASI.
- **`App.main()` ambiguity.** Consumers must import exactly one runner
  composition. `SwiftTUIWebHostCLI` exists to avoid importing both
  `SwiftTUICLI` and `SwiftTUIWebHost` directly.
- **Server leakage.** The package-graph guard is not optional. Add it before
  server code lands, keep it in the full test gate, and update it whenever
  new server dependencies are introduced.
