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
| Terminal-native | `SwiftTUICLI` (`TerminalRunner`) | A real terminal via `TerminalHost` | Explicit terminal-only runner. The default `SwiftTUI` import reaches terminal launch through `SwiftTUIWebHostCLI`. |
| WASI / browser | `SwiftTUIWASI` (`WASIRunner`) | A browser canvas | Swift compiled to WASI. Raster output drawn onto a canvas via the `web-surface` transport. Uses the stack-lean resolve profile by default. |
| Host-managed Android | `SwiftTUIAndroidHost` | An Android Compose view inside an app | Retains ``HostedSceneSession`` values behind a JNI/C ABI and serializes committed frames as web-surface records (the converged wire). Draws styled cells/images plus a semantics overlay in Compose. The Swift host cross-compiles for arm64 and x86_64. |
| Localhost WebHost | `SwiftTUIWebHost` (`WebHostRunner`) | A browser, served by the native process | The process runs an embedded in-tree HTTP/WebSocket server and drives a bundled browser runtime over the `web-surface` protocol (v1/v2 full frames, v3 delta frames). |
| Native SwiftUI host (external package) | `SwiftUIHost` from [`swift-tui-swiftui`](https://github.com/SwiftTUI/swift-tui-swiftui) | A SwiftUI view on macOS or iOS | Retains the same runtime sessions. Presents raster, damage, focus, and accessibility through AppKit/UIKit-backed SwiftUI views. Bridges input plus clipboard writes back to the runtime. It is not a product of this package. |

A binary can support more than one mode. `SwiftTUIWebHostCLI`
(`WebHostCLIRunner`) combines terminal-native and localhost-browser launch in
one executable. `--web` selects the WebHost path. The `SwiftTUI` convenience
product includes that combined runner by default.

Hosts in other package ecosystems keep their non-Swift half in dedicated
sibling repositories: [`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web)
(Bun/npm browser packages) and
[`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android)
(Gradle/Maven AAR + plugin). Tagged releases or released artifacts couple them
back to this package.

## Per-Host Engine Profiles

The host boundary stays shared, but resolve has two profiles. “Full” means
that the retained-reuse door is eligible. Memoized-body reuse is eligible for
its `Equatable` opt-ins. Selective dirty-frontier evaluation can run after the
boot frame. It does not promise a reuse hit: invalidation, suppression, churn,
and each reuse door's normal guards still decide that.

| Host presentation | Default resolve profile |
| --- | --- |
| Terminal-native | Full/native |
| Localhost WebHost | Full/native — the Swift runtime is a native server process even though presentation is in a browser. |
| Host-managed Android | Full/native |
| Native SwiftUI host | Full/native |
| WASI / browser | Stack-lean |

The full/native profile uses the normal `TaskLocal` context bindings. It keeps
retained and memoized resolve reuse available. It enables selective evaluation
after the first full render and leaves the chunked-descent depth limit unset by
default.

The stack-lean profile preserves the same phase products and committed-frame
contract while changing resolve mechanics to fit constrained WebAssembly
stacks:

- Retained and memoized resolve reuse are disabled by default. Selective
  evaluation is also disabled, so frames enter resolve from the root.
- The three synchronous per-level bindings — ambient environment, authoring
  context, and view-node context — use MainActor-scoped save/restore slots
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

- ``SemanticHostFrame`` — the value `RunLoop.presentCommittedFrame` builds
  when a surface adopts `SemanticHostFramePresentationSurface`. It carries the
  raster, semantic snapshot, focused identity, host-facing damage, preferred
  layout size, and a producer sequence.
- ``PresentationSurface`` roles — a host adopts only the roles it needs:
  - `PresentationSurfaceMetricsProvider` — reports surface size and metrics.
  - `TerminalCommandPresentationSurface` — accepts terminal command output.
  - `RasterPresentationSurface` — accepts a raster surface.
  - `DamageAwarePresentationSurface` — accepts incremental damage regions.
  - `SemanticHostFramePresentationSurface` — accepts the full semantic frame.

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
desktop one — a press-drag is a click-drag, and scrolling belongs to the wheel,
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

`TerminalHost` is the POSIX terminal host.

- **Output** is written by a `PresentationWriter` on a private serial
  `DispatchQueue`, so a blocking `write(2)` never stalls the run loop. Stale
  frames are dropped with a `forceFullRepaint` recovery path.
- **Graphics capabilities** are re-probed each frame:
  `baselineGraphicsCapabilities` re-reads the cell pixel size via
  `ioctl(TIOCGWINSZ)`, so a resize is picked up without a separate query.
- **Crash safety** is the runner's job, not the framework's.
  `CrashSignalHandler` is installed by the CLI runner so a crash restores the
  terminal. `SwiftTUICore` and `SwiftTUIRuntime` install no signal handlers.

## Platform Support Matrix

| Surface | Status |
| --- | --- |
| macOS package development | Primary supported Apple-host path (macOS 15+). |
| Linux terminal builds and tests | Supported through `swiftly`. |
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

SwiftTUI can embed a real child terminal program as authored content — a
deliberate terminal-native capability. `TerminalView` hosts a
`TerminalSession`; the `terminal-workspace` example in `swift-tui-examples`
layers tabbed and split-pane composition above it. See
<doc:TerminalEmbedding>.

## See Also

- <doc:Host-Integration>
- <doc:Running-Apps>
- <doc:Environment-Variables>
- <doc:Runtime-Render-Pipeline>
