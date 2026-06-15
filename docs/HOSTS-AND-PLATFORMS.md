# Hosts and Platforms

The render pipeline
([DocC source](../Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md))
produces a committed frame. A **host** presents that frame. The same authored app
can run under five different hosts; the pipeline above them is identical.

## The five execution modes

```mermaid
flowchart TD
    app["Authored App / Scene"]
    runtime["SwiftTUIRuntime<br/>RunLoop + DefaultRenderer"]
    app --> runtime

    runtime --> term["Terminal-native<br/>SwiftTUICLI · TerminalHost"]
    runtime --> wasi["WASI / browser<br/>SwiftTUIWASI · canvas"]
    runtime --> host["Host-managed Apple<br/>SwiftUIHost · raster surface"]
    runtime --> androidHost["Host-managed Android<br/>SwiftTUIAndroidHost · Compose canvas"]
    runtime --> web["Localhost WebHost<br/>SwiftTUIWebHost · FlyingFox"]

    term --> termOut["Terminal text + ANSI"]
    wasi --> wasiOut["Browser canvas"]
    host --> hostOut["SwiftUI raster view"]
    androidHost --> androidOut["Android Canvas + semantics overlay"]
    web --> webOut["Browser over WebSocket"]
```

| Mode | Product | Presents to | Notes |
| --- | --- | --- | --- |
| Terminal-native | `SwiftTUICLI` (`TerminalRunner`) | A real terminal via `TerminalHost` | Explicit terminal-only runner. The default `SwiftTUI` import reaches terminal launch through `SwiftTUIWebHostCLI`. |
| WASI / browser | `SwiftTUIWASI` (`WASIRunner`) | A browser canvas | Swift compiled to WASI; raster output drawn onto a canvas via the `web-surface` transport. |
| Host-managed Apple | `SwiftUIHost` | A `SwiftUI` view inside an app | Retains `HostedSceneSession` values and draws a `HostedRasterSurface`. macOS-only. |
| Host-managed Android | `SwiftTUIAndroidHost` | An Android Compose view inside an app | Retains `HostedSceneSession` values behind a JNI/C ABI, serializes `SemanticHostFrame` snapshots, and draws styled cells/images plus a semantics overlay in Compose. `arm64-v8a` only. |
| Localhost WebHost | `SwiftTUIWebHost` (`WebHostRunner`) | A browser, served by the native process | The process runs an embedded HTTP/WebSocket server (FlyingFox) and drives a bundled browser runtime over the `web-surface` v2 protocol. |

A binary can support more than one mode. `SwiftTUIWebHostCLI` (`WebHostCLIRunner`)
combines terminal-native and localhost-browser launch in one executable;
`--web` selects the WebHost path. The `SwiftTUI` convenience product includes
that combined runner by default.

## The host-frame contract

Hosts do not see the pipeline. They see a committed frame through a small set
of focused contracts.

- **`SemanticHostFrame`** — the value `RunLoop.presentCommittedFrame` builds for
  every host. It carries the raster surface, the commit plan, and the semantic
  snapshot.
- **`PresentationSurface` roles** — a host adopts only the roles it needs:
  - `PresentationSurfaceMetricsProvider` — reports surface size and metrics.
  - `TerminalCommandPresentationSurface` — accepts terminal command output.
  - `RasterPresentationSurface` — accepts a raster surface.
  - `DamageAwarePresentationSurface` — accepts incremental damage regions.
  - `SemanticHostFramePresentationSurface` — accepts the full semantic frame.

| Host | Damage consumption |
| --- | --- |
| Terminal-native | `TerminalHost` uses damage to limit row/span diffing and terminal byte emission. |
| WASI / browser | `WebSurfaceTransport` serializes damage into the web-surface frame; the browser canvas clears and redraws dirty rects only. |
| Localhost WebHost | `WebSocketSurfaceTransport` serializes the same web-surface damage over WebSocket. |
| Host-managed SwiftUI | `HostedRasterSurface` carries damage through `SemanticHostFrame`; `NativeTerminalSurfaceView` invalidates only dirty native rects. |
| Host-managed Android | `SwiftTUIAndroidHost` serializes damage rows/ranges into the Android frame snapshot; the Compose renderer keeps a retained bitmap and repaints only the damaged rows when a frame's damage is contiguous, falling back to a full repaint otherwise (size change, full-repaint flag, images present, or a skipped sequence). |

```mermaid
flowchart LR
    commit["Committed frame"]
    shf["SemanticHostFrame"]
    commit --> shf
    shf --> t["TerminalHost<br/>(terminal command surface)"]
    shf --> r["HostedRasterSurface<br/>(raster surface)"]
    shf --> w["WebSocketSurfaceTransport<br/>(web-surface v2)"]
```

`TerminalHost` (and `WebTerminalHost`) consume terminal command output;
`HostedRasterSurface` consumes a raster surface; `WebSocketSurfaceTransport`
serializes the `web-surface` v2 wire frame for the browser. Each conforms to
the host-frame surface protocols rather than reaching into the renderer.

### Shared Raster Damage Contract

All raster frontends consume the same damage contract: `RasterSurface` plus
optional `PresentationDamage`.

- `nil` damage means full repaint.
- non-`nil` empty damage means no visible raster cells changed.
- non-`nil` row/range damage is relative to the previous `RasterSurface`
  actually presented by the same runtime/frontend pair.

`RunLoop` derives this host-facing value from the frontend's presented raster
history instead of forwarding private retained-layout invalidation or stale
renderer artifact damage. Terminal, WASI/browser, localhost WebHost, and
host-managed SwiftUI paths must not reinterpret retained-layout invalidation as
frontend damage. If stale cells appear after this contract is satisfied, the
bug belongs to that frontend's damage consumer.

## The terminal host

`TerminalHost` is the POSIX terminal host.

- **Output** is written by a `PresentationWriter` on a private serial
  `DispatchQueue`, so a blocking `write(2)` never stalls the run loop. Stale
  frames are dropped with a `forceFullRepaint` recovery path.
- **Graphics capabilities** are re-probed each frame:
  `baselineGraphicsCapabilities` re-reads the cell pixel size via
  `ioctl(TIOCGWINSZ)`, so a resize is picked up without a separate query.
- **Crash safety** is the runner's job, not the framework's. `CrashSignalHandler`
  (from the vendored `UnixSignals`) is installed by the CLI runner so a crash
  restores the terminal; `SwiftTUICore` and `SwiftTUIRuntime` install no signal
  handlers.

## Platform support matrix

```mermaid
flowchart LR
    subgraph apple["Apple hosts"]
        macos["macOS 15+"]
        ios["iOS 18+"]
    end
    subgraph other["Other targets"]
        linux["Linux"]
        wasi2["WASI / browser"]
        android["Android"]
    end
```

| Surface | Status |
| --- | --- |
| macOS package development and CI | Primary supported Apple-host path. GitHub `macos-26` is the macOS CI floor. |
| Linux terminal builds and tests | Supported through `swiftly`. |
| iOS package builds | Supported for host-compatible products; CI builds (does not run tests). PTY/terminal-embedding products are excluded. |
| WASI / browser | Supported through `SwiftTUIWASI` and the `SwiftTUI/swift-tui-web` browser packages. |
| Android host / cross-compilation | `SwiftTUIAndroidHost` cross-compiles for both `aarch64-unknown-linux-android28` and `x86_64-unknown-linux-android28` (the vendored `swift-png`/`JPEG` image path builds for x86_64; the earlier SIMD blocker no longer applies). The reusable Compose host + JNI shim ship as the published `sh.swifttui:android-host` AAR (with the `sh.swifttui.android` Gradle plugin) from `SwiftTUI/swift-tui-android`; consumer apps depend on the tagged `SwiftTUIAndroidHost` SwiftPM product over HTTPS and let the plugin cross-build their Swift host. The `swift-tui-examples/AndroidGallery` Compose app packages and exercises `arm64-v8a` — see [VISION-GAP.md](VISION-GAP.md). |
| `SwiftTUITerminal` / `SwiftTUIPTYPrimitives` (PTY embedding) | macOS and Linux only. |
| `SwiftUIHost` | macOS only; excluded from Linux at compile time. |

The package declares `macOS 15` and `iOS 18` platforms unless the build sets
`DISABLE_EXPLICIT_PLATFORMS=1` (Linux CI does, to skip the Apple platform
restriction).

## The web packages

The Swift products that run browser surfaces live in this repo:
`SwiftTUIWASI`, `SwiftTUIWebHost`, and `SwiftTUIWebHostCLI`.

The WASI browser worker owns stdin and timer readiness for Swift code compiled
to WASI. Its `poll_oneoff` adapter blocks on `SharedArrayBuffer`/`Atomics`
rather than polling from JavaScript, and it must wake for clock deadlines,
stdin readability, resize/style control messages, and queue closure.

Browser TypeScript source lives in `SwiftTUI/swift-tui-web` as
`@swifttui/web` and `@swifttui/build`. `SwiftTUIWebHost` consumes a checked-in
browser bundle under `Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser`
so Swift package consumers do not need Bun or npm for localhost WebHost use.

## Terminal-program embedding

SwiftTUI can embed a real child terminal program as authored content — a
deliberate terminal-native capability (see [VISION.md](VISION.md)).

- **`TerminalView<Session>`** is an ordinary `View`. It hosts a
  `TerminalSession`; `TerminalProcessSession` is the built-in implementation
  that runs a child process over a pty (`ChildProcessPty`).
- The embedded program's grid is blitted into the surrounding frame as a
  `DrawCommand.foreignSurface`, which the rasterizer paints like any other draw
  command.
- The emulator handles OSC 0/2 (title), OSC 7 (working directory), OSC 8
  (hyperlinks), OSC 52 (clipboard), bracketed paste, and mouse-mode
  translation.
- **`SwiftTUITerminalWorkspace`** layers tabbed and split-pane composition
  (`TerminalWorkspaceView`, `TerminalWorkspaceState`, layout, and a session
  store) above `TerminalView`.

Sixel/Kitty graphics inside embedded panes, the Kitty keyboard protocol, OSC 99
notification namespacing, and process reattachment after an app restart are not
implemented — see [VISION-GAP.md](VISION-GAP.md).
