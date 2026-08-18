# Hosts And Platforms

Choose a host presentation and platform target. One authored app ships as a
terminal executable, a browser canvas, an Android view, a native SwiftUI
surface, or a localhost web session.

## Overview

The render pipeline produces a committed frame. A **host** presents that frame.
This article owns the canonical host matrix. This package contains four
execution modes. The native SwiftUI host ships separately, for five host
presentations in total. They share the phase ordering and committed-frame
contracts. Resolve reuse, evaluation, and stack behavior vary by the
per-host engine profile below.

## Canonical Host Matrix

| Mode | Product | Presents to | Notes |
| --- | --- | --- | --- |
| Terminal-native | `SwiftTUITerminalCLI` (`TerminalRunner`); `SwiftTUICLI` remains the POSIX facade that adds scene attach | A real terminal via `TerminalHost` — a POSIX terminal or the Win32 console | Explicit terminal-only runner. The default `SwiftTUI` import reaches terminal launch through `SwiftTUILauncher`. |
| WASI / browser | `SwiftTUIWASI` (`WASIRunner`) | A browser canvas | Swift compiled to WASI. Raster output drawn onto a canvas via the `web-surface` transport. Uses the stack-lean resolve profile by default. |
| Host-managed Android | `SwiftTUIAndroidHost` | An Android Compose view inside an app | Retains ``HostedSceneSession`` values behind a JNI/C ABI and serializes committed frames as web-surface records (the converged wire). Draws styled cells/images plus a semantics overlay in Compose. The Swift host cross-compiles for arm64 and x86_64. |
| Localhost WebHost | `SwiftTUIWebHost` (`WebHostRunner`) | A browser, served by the native process | The process runs an embedded in-tree HTTP/WebSocket server and drives a bundled browser runtime over the `web-surface` protocol (v1/v2 full frames, v3 delta frames). |
| Native SwiftUI host (external package) | `SwiftUIHost` from [`swift-tui-swiftui`](https://github.com/SwiftTUI/swift-tui-swiftui) | A SwiftUI view on macOS or iOS | Retains the same runtime sessions. Presents raster, damage, focus, and accessibility through AppKit/UIKit-backed SwiftUI views. Bridges input plus clipboard writes back to the runtime. It is not a product of this package. |

A binary can support more than one mode. `SwiftTUILauncher` (in
`SwiftTUITerminalCLI`) routes launch: the terminal by default, the localhost
WebHost when `--web` is present and `SwiftTUIWebHostCLI` installed its web arm
at launch. `WebHostCLIRunner` remains as a source-compatible facade over the
same launcher. The `SwiftTUI` convenience product re-exports exactly one
launch surface per platform: the combined terminal/WebHost launcher where the
WebHost products build (macOS, Mac Catalyst, iOS, Linux, Android), and the
portable terminal launcher on Windows, where `--web` fails with a clear
web-runner-not-linked diagnostic and the WebHost types are absent.

Hosts in other package ecosystems keep their non-Swift half in dedicated
sibling repositories: [`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web)
(Bun/npm browser packages) and
[`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android)
(Gradle/Maven AAR + plugin). Tagged releases or released artifacts couple them
back to this package.

## 0.9 Preview Support Contract

| Surface | 0.9 tier | Supported boundary |
| --- | --- | --- |
| Terminal runtime | Supported preview surface | Native macOS and Linux launch, input, raster presentation, and terminal graphics through the published SwiftPM products. |
| Windows terminal runtime | Preview — first carried by 0.9.2 | Native Windows launch, input, and raster presentation on Windows 10 1809+ (build 17763) / Windows Server 2019+ — the ConPTY line — for `aarch64-` and `x86_64-unknown-windows-msvc`. Terminal surface only: WebHost, PTY embedding, and `--attach` are not part of the Windows claim. Full input fidelity (bracketed paste, focus events, mouse from conhost's own window) varies with the console host — current Windows Terminal, or Windows 11 24H2 conhost; the console-record input pump keeps older in-box conhost degrading gracefully rather than misbehaving. |
| WASI / browser and localhost WebHost | Supported preview surface | Published npm/browser packages, keyboard and pointer input, resize and scroll, canvas/DOM raster presentation, and the converged host wire. |
| Native SwiftUI host | Supported preview surface | The lockstep external host on macOS 15+ and iOS 18+, including keyboard, pointer/touch, clipboard writes, native image placement, and semantic presentation. |
| Android Compose host | Preview, arm64 | `arm64-v8a`, API 28+, NDK `27.3.13750724`, Swift 6.3.x, the Swift Android SDK, and the published AAR/Gradle-plugin packaging path. The core host can cross-compile x86_64, but x86_64 packaging and Android IME marked/pre-edit composition are outside the 0.9 support claim. |
| Accessibility overlays | One-way presentation preview | Browser ARIA, AppKit/UIKit, and Compose overlays present reading order, names, roles, hidden state, live announcements, cursor anchoring, and runtime-origin focus. Assistive-origin focus, activation, adjustment, editing, and value/state actions do not route back into SwiftTUI in 0.9. |

Calling an overlay a real accessibility tree describes the host-native tree it
mounts; it does not imply bidirectional assistive control.

## Per-Host Engine Profiles

The host boundary stays shared, but resolve has two profiles. "Full" means
that the retained-reuse door is eligible. Memoized-body reuse is eligible for
its `Equatable` opt-ins. Selective dirty-frontier evaluation can run after the
boot frame. It does not promise a reuse hit: invalidation, suppression, churn,
and each reuse door's normal guards still decide that.

| Host presentation | Default resolve profile |
| --- | --- |
| Terminal-native | Full/native |
| Localhost WebHost | Full/native. The Swift runtime is a native server process even though presentation is in a browser. |
| Host-managed Android | Full/native |
| Native SwiftUI host | Full/native |
| WASI / browser | Stack-lean |

The full/native profile uses the normal `TaskLocal` context bindings. It keeps
retained and memoized resolve reuse available. It enables selective evaluation
after the first full render and leaves the chunked-descent depth limit unset by
default.

On Windows, the runtime measures the main thread's stack reserve at session
start and arms the stack-lean profile automatically when the reserve is below
the 8 MiB full-engine floor — a default-linked Windows executable reserves
only 1 MiB. Link apps with `-Xlinker /STACK:16777216` (release builds
included) to run the full/native profile. An explicit
`SWIFTTUI_STACK_LEAN_PROFILE` value overrides the automatic choice, and a
debug build that degrades emits a `windows.stack-floor-lean-profile` runtime
issue naming the remedy.

The stack-lean profile preserves the same phase products and committed-frame
contract while changing resolve mechanics to fit constrained WebAssembly
stacks:

- Retained and memoized resolve reuse are disabled by default. Selective
  evaluation is also disabled, so frames enter resolve from the root.
- The three synchronous per-level bindings (ambient environment, authoring
  context, and view-node context) use MainActor-scoped save/restore slots
  instead of `TaskLocal.withValue`. Async bindings remain task-local because
  they can suspend.
- The chunked resolve driver limits inline descent depth (default 6). Cuts
  occur only at structural child edges. The driver queues cut subtrees after
  the stack unwinds and reruns resolve to a bottom-up fixpoint.

`SWIFTTUI_STACK_LEAN_PROFILE`, `SWIFTTUI_LEAN_RETAINED_REUSE`, and
`SWIFTTUI_RESOLVE_DEPTH_LIMIT` select and tune the profiles in both
directions. Their grammar is documented in <doc:Environment-Variables>.

## The Host-Frame Contract

Hosts do not see the pipeline. They see a committed frame through a small set
of focused contracts.

- ``SemanticHostFrame`` is the value `RunLoop.presentCommittedFrame` builds
  when a surface adopts `SemanticHostFramePresentationSurface`. It carries the
  raster, semantic snapshot, focused identity, host-facing damage, preferred
  layout size, and a producer sequence.
- ``PresentationSurface`` roles. A host adopts only the roles it needs:
  - `PresentationSurfaceMetricsProvider` reports surface size and metrics.
  - `TerminalCommandPresentationSurface` accepts terminal command output.
  - `RasterPresentationSurface` accepts a raster surface.
  - `DamageAwarePresentationSurface` accepts incremental damage regions.
  - `SemanticHostFramePresentationSurface` accepts the full semantic frame.

| Host | Damage consumption |
| --- | --- |
| Terminal-native | `TerminalHost` uses damage to limit row/span diffing and terminal byte emission. |
| WASI / browser | `WebSurfaceTransport` serializes damage into the web-surface frame. The browser canvas clears and redraws dirty rects only. |
| Localhost WebHost | `WebSocketSurfaceTransport` serializes the same web-surface damage over WebSocket. |
| Host-managed Android | `SwiftTUIAndroidHost` serializes the same web-surface damage object (the converged wire). The Compose renderer keeps a retained bitmap and repaints only the damaged rows when consumption is contiguous, falling back to a full repaint otherwise. |
| Native SwiftUI host | `SwiftUIHost` converts damage into AppKit/UIKit dirty rectangles when text and graphics can be replayed incrementally, and requests a full redraw otherwise. |

`TerminalHost` takes the damage-aware raster path (and consumes terminal
command output for non-TUI modes). It does not receive a ``SemanticHostFrame``.
`HostedRasterSurface`, `WebSurfaceTransport`, and `WebSocketSurfaceTransport`
adopt the semantic host-frame role. The two web transports serialize the
`web-surface` wire frame. Full frames are wire v1 (base) or v2
(sequence/accessibility/scroll fields). When delta emission is enabled
(`SWIFTTUI_SURFACE_DELTA`, which the browser WASI bridge sets) and a raster
damage diff exists, steady-state frames ship as v3 `deltaRows` patches against
the previously presented surface instead.

Hosts declare wire capabilities through one Swift-side currency
(`HostWireCapabilities`) with one ingress per transport. Its only field at
`HEAD` is the named `acceptsDeltaFrames` bit. Absence keeps the default
full-frame bytes. The canonical field/ingress manifest is
`HostWireSchema.capabilityMappings`. The normative state and delivery rules
are maintained in the repository's internal `docs/HOST-WIRE-CONTRACT.md`, not
here.

### Pointer Paradigm

`PresentationSurfaceMetricsProvider` also carries `PointerInputCapabilities`,
which ``RunLoop`` copies verbatim into `EnvironmentValues` on every frame. Most
of it describes the input device (coordinate precision, hover, precise scroll).
`supportsScrollPanning` instead names the host's **interaction paradigm**:
whether a pointer drag on scrollable content pans it directly, so the content
follows the pointer.

It is off unless a host asks for it, because the default paradigm is the
desktop one: a press-drag is a click-drag, and scrolling belongs to the wheel,
the scroll indicators, and the keyboard. Declaring it turns on two behaviors
together: the scroll body claims the `.down`/`.dragged`/`.up` stream to pan,
and a drag that begins on an inner control is handed to the enclosing scroll
view once it crosses the takeover threshold, cancelling that control. Neither
is right where a mouse is the pointing device.

| Host | Pans by dragging | Why |
| --- | --- | --- |
| Terminal-native | No | A terminal mouse drag is a click-drag or a selection. |
| Native SwiftUI host (macOS) | No | Desktop pointer. |
| Native SwiftUI host (iOS) | Yes | Touch. |
| Host-managed Android | Yes | Touch. |
| WASI / browser, Localhost WebHost | Reported by the page | One bundle serves both paradigms, so the page declares what it sees through the `pointer:` control record (see the repository's internal `docs/HOST-WIRE-CONTRACT.md`). Absent record means desktop. |

Wheel scrolling, scroll indicator drags, and keyboard scrolling are unaffected
by the declaration and work on every host. Authored views can override the
declaration for a subtree with
`.environment(\.pointerInputCapabilities, …)`, but the host is the right place
to answer this question.

### Shared Raster Damage Contract

All raster frontends consume the same damage contract: `RasterSurface` plus
optional `PresentationDamage`.

- `nil` damage means full repaint.
- non-`nil` empty damage means no visible raster cells changed.
- non-`nil` row/range damage is relative to the previous `RasterSurface`
  actually presented by the same runtime/frontend pair.

``RunLoop`` derives this host-facing value from the frontend's presented
raster history instead of forwarding private retained-layout invalidation or
stale renderer artifact damage. Frontends must not reinterpret retained-layout
invalidation as frontend damage.

## The Terminal Host

`TerminalHost` is the terminal host. Terminal control sits behind a platform
seam: a POSIX controller (termios raw mode, `poll`-based reads, `SIGWINCH`
resize) and a Win32 console controller on Windows.

- **Output** is written by a `PresentationWriter` on a private serial
  `DispatchQueue`, so a blocking `write(2)` never stalls the run loop. Stale
  frames are dropped with a `forceFullRepaint` recovery path.
- **Graphics capabilities** are re-probed each frame:
  `baselineGraphicsCapabilities` re-reads the cell pixel size via
  `ioctl(TIOCGWINSZ)`, so a resize is picked up without a separate query.
- **Crash safety** is the runner's job, not the framework's.
  `CrashSignalHandler` is installed by the CLI runner so a crash restores the
  terminal. `SwiftTUICore` and `SwiftTUIRuntime` install no signal handlers.
- **Windows console control**: the controller enables VT processing and owns
  the UTF-8 code pages for the session, restoring both console modes and both
  code pages on exit — code pages are console-global and outlive the process.
  Input is read as console records (`ReadConsoleInputW`) and re-linearized
  into the same VT byte stream the input parser consumes on POSIX, which is
  what makes typed non-ASCII text reliable on every supported Windows version
  — the console's byte-oriented read path has shipped broken for UTF-8 input
  since Windows 10, so the record path is load-bearing, not an optimization.
  Resize arrives through the same record pump
  (there is no SIGWINCH), Ctrl+C arrives in-band as `0x03`, and legacy conhost
  mouse records are translated into SGR sequences so mouse input works in both
  Windows Terminal and `conhost`. The signal-based crash-restore path is
  POSIX-only: on Windows an abnormal termination can leave the console in
  raw/mouse-tracking modes.

## Platform Support Matrix

| Surface | Status |
| --- | --- |
| macOS package development | Primary supported Apple-host path (macOS 15+). |
| Linux terminal builds and tests | Supported through `swiftly`. |
| Windows terminal builds | Supported natively on Windows 10 1809+ (build 17763) / Windows Server 2019+ for `aarch64-` and `x86_64-unknown-windows-msvc`. The `SwiftTUI` umbrella serves the terminal launch surface only: the WebHost and PTY-embedding products do not build there, and `--web` fails with the web-runner-not-linked diagnostic. Link apps with `-Xlinker /STACK:16777216` — release builds included — or the runtime degrades to the stack-lean engine profile below the 8 MiB main-thread stack floor (see the per-host engine profiles). |
| iOS package builds | Supported for host-compatible products (iOS 18+). PTY/terminal-embedding products are excluded. |
| WASI / browser | Supported through `SwiftTUIWASI` and the [`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web) browser packages. |
| Android host / cross-compilation | `SwiftTUIAndroidHost` cross-compiles for `aarch64-unknown-linux-android28` and `x86_64-unknown-linux-android28`. The reusable Compose host + JNI shim ship as the published `sh.swifttui:android-host` AAR, with the `sh.swifttui.android` Gradle plugin, from [`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android). Consumer apps depend on the tagged `SwiftTUIAndroidHost` SwiftPM product over HTTPS and let the plugin cross-build their Swift host. |
| Native SwiftUI host | Supported on macOS 15+ and iOS 18+ by the external [`swift-tui-swiftui`](https://github.com/SwiftTUI/swift-tui-swiftui) package. |
| `SwiftTUITerminal` / `SwiftTUIPTYPrimitives` (PTY embedding) | macOS and Linux only. |

## The Web Packages

The Swift products that run browser surfaces live in this package:
`SwiftTUIWASI`, `SwiftTUIWebHost`, and `SwiftTUIWebHostCLI`.

The WASI browser worker owns stdin and timer readiness for Swift code compiled
to WASI. Its `poll_oneoff` adapter blocks on `SharedArrayBuffer`/`Atomics`
instead of polling from JavaScript. It wakes for clock deadlines, stdin
readability, resize/style control messages, and queue closure.

Browser TypeScript source lives in
[`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web) as
`@swifttui/web` and `@swifttui/build`. `SwiftTUIWebHost` consumes a committed
browser bundle under
`Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser` so Swift package
consumers do not need Bun or npm for localhost WebHost use.

## Terminal-Program Embedding

SwiftTUI can embed a real child terminal program as authored content, a
deliberate terminal-native capability. `TerminalView` hosts a
`TerminalSession`; the `terminal-workspace` example in `swift-tui-examples`
layers tabbed and split-pane composition above it. See
<doc:TerminalEmbedding>.

## See Also

- <doc:Host-Integration>
- <doc:Running-Apps>
- <doc:Environment-Variables>
- <doc:Runtime-Render-Pipeline>
