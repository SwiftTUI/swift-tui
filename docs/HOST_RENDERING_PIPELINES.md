# Host Rendering Pipelines

This document is the current-state map for how authored SwiftTUI apps render
through the first-party execution and host surfaces:

- terminal-native CLI execution through `SwiftTUI` / `SwiftTUICLI`
- one-shot CLI rendering through `RenderOnce`
- native Apple embedding through `SwiftUIHost`
- localhost browser execution through `SwiftTUIWebHost` / `SwiftTUIWebHostCLI`
- deploy-to-browser WASI execution through `Platforms/Web` and `SwiftTUIWASI`

It is a companion to [ARCHITECTURE.md](ARCHITECTURE.md),
[RUNTIME.md](RUNTIME.md), [ASYNC_RENDERING.md](ASYNC_RENDERING.md),
[ACCESSIBILITY.md](ACCESSIBILITY.md), and [HOST_PACKAGES.md](HOST_PACKAGES.md).
Those documents define the core pipeline, runtime contract, accessibility model,
and product boundaries. This page focuses on host-specific frame flow, input
flow, resize/style flow, and the places where the implementations intentionally
diverge.

## Vocabulary

- A **runner** owns process startup or launch routing.
- A **host** retains SwiftTUI scenes inside another lifecycle, such as a native
  SwiftUI app or browser shell.
- A **presentation surface** is the low-level sink consumed by `RunLoop`.
- A **hosted scene session** is a retained runtime session built from a
  `SceneManifest`/scene selection and driven by a host.

The important distinction is that `SwiftTUICLI`, `SwiftTUIWASI`,
`SwiftTUIWebHost`, and `SwiftTUIWebHostCLI` can own executable launch, while
`SwiftUIHost` and the browser package retain or display sessions inside an
outer shell. `SwiftTUIWebHost` is compound: it owns a Swift-side runner plus a
browser host bridge.

## Shared Pipeline

Every frame uses the same ordered renderer pipeline:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

The phases remain host-neutral:

| Phase | Main product | Role |
| --- | --- | --- |
| `resolve` | `ResolvedNode` | Lowers authored views into a graph-shaped tree with environment and metadata. |
| `measure` | `MeasuredNode` | Computes subtree sizes under a cell-based proposal. |
| `place` | `PlacedNode` | Produces final cell geometry for drawing, interaction, scrolling, and semantics. |
| `semantics` | `SemanticSnapshot` | Extracts focus, interaction, pointer, action, scroll, selection, and accessibility records. |
| `draw` | `DrawNode` | Lowers placed geometry and metadata into draw commands. |
| `raster` | `RasterSurface` | Produces the cell grid, style runs, continuation cells, and image attachments. |
| `commit` | `CommitPlan` | Packages lifecycle, task, and handler-installation work for the runtime. |

The core rule is: layout, semantics, draw, and raster do not know whether the
result will be ANSI bytes, a SwiftUI/CoreGraphics view, or a browser canvas.
Host-specific behavior starts at the `PresentationSurface` boundary and in the
host-specific input/resize bridge.

`DefaultRenderer` owns the concrete renderer components:

```text
Resolver
LayoutEngine
SemanticExtractor
DrawExtractor
Rasterizer
CommitPlanner
ViewGraph
PresentationPortalState
AnimationController
FrameTailRenderer
```

`RunLoop` wraps that renderer in an interactive session:

```text
FrameScheduler wake
-> build ResolveContext from the current host surface
-> DefaultRenderer.renderAsync(...)
-> focus/default-focus/focused-value/scroll convergence
-> present committed frame
-> apply lifecycle/task commit
-> schedule animation/deadline follow-up work
```

The async rendering contract is also shared. The current ownership split is:

```text
main actor: resolve -> animation interpolation
worker when eligible: measure -> place
worker: placed-overlay application -> semantics -> draw -> raster
main actor: commit -> present -> lifecycle
writer queue when terminal-backed: write(2)
```

The host decides what "present" means.

## Common Runtime Data Flow

All interactive hosts eventually construct `SceneSessionResources`:

```text
SceneSessionResources(
  presentationSurface: ...,
  terminalInputReader: ...,
  signalReader: ...,
  scheduler: ...,
  surfaceName: ...,
  runtimeConfiguration: ...,
  focusPresentationHandler: ...
)
```

`SceneSession.run(...)` turns those resources into a `RunLoop`. The same
`RunLoop` then asks the surface for:

- `surfaceSize` for the layout proposal
- terminal appearance and semantic theme for environment values
- graphics capabilities and cell-pixel metrics for image/pointer-aware views
- pointer input capabilities for gesture and `GeometryReader` behavior

The same `RunLoop` also consumes:

- `InputEvent` streams from `TerminalInputReading`
- optional signal events from `SignalReading`
- invalidation and deadline requests from `FrameScheduler`

The host-specific parts are therefore:

1. How the app or scene is selected.
2. Which `PresentationSurface` is provided.
3. Which input reader is provided.
4. How resize/style changes update the surface and wake the run loop.
5. How `RasterSurface` and `SemanticSnapshot` leave the runtime.
6. How platform events enter as `InputEvent`.

## Pipeline Summary

| Surface | Launch owner | Runtime session | Frame sink | Input source | Resize/style wake |
| --- | --- | --- | --- | --- | --- |
| CLI interactive | `TerminalRunner` / default `App.main()` | `SceneSession` + `RunLoop` | `TerminalHost` writes ANSI/terminal graphics to fd | `InputReader` parses terminal bytes | OS `SIGWINCH`; terminal size re-read on next frame |
| CLI `RenderOnce` | Caller | No live `RunLoop` | `TerminalSurfaceRenderer` returns ANSI text | None | Width resolved once |
| SwiftUIHost | SwiftUI app lifecycle | `HostedSceneSession` per scene | `HostedRasterSurface` delivers `RasterSurface`/semantics to native view | AppKit/UIKit events become `InputEvent` | `HostedRasterSurface` is updated directly; `HostedSceneSession.requestSurfaceRefresh()` sends in-process `SIGWINCH` |
| Local WebHost | `WebHostRunner` / `WebHostCLIRunner` | `SceneSession` + `RunLoop` | `WebSocketSurfaceTransport` sends `web-surface` records | WebSocket input records parsed by `WebSocketInputReader` | Current local path updates transport from control records; it does not install a signal reader |
| Platforms/Web WASI | Browser/WASI shell + `WASIRunner` | `SceneSession` + `RunLoop` inside wasm | `WebSurfaceTransport` writes `web-surface` records to stdout | `WebSurfaceInputReader` reads stdin records | Control records update host and send in-process `SIGWINCH` |

## Terminal-Native CLI

### Outbound Frame Flow

The normal terminal-native path is:

```text
SwiftTUI.App.main()
-> TerminalRunner.run(...)
-> collect WindowGroup scene selections
-> SceneRuntime per selected scene
-> SceneSession.run(...)
-> RunLoop.run()
-> DefaultRenderer.renderAsync(...)
-> presentCommittedFrame(...)
-> TerminalHost.present(...)
-> TerminalPresentationPlanner
-> TerminalSurfaceRenderer
-> PresentationWriter
-> terminal output fd
```

Relevant source:

- [`TerminalRunner.swift`](../Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift)
- [`SceneRuntime.swift`](../Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift)
- [`SceneSession.swift`](../Sources/SwiftTUIRuntime/Scenes/SceneSession.swift)
- [`RunLoop.swift`](../Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift)
- [`RunLoop+Rendering.swift`](../Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift)
- [`TerminalHost.swift`](../Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift)
- [`TerminalPresentation.swift`](../Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift)

`SwiftTUI` is the one-import terminal convenience product. Its default
`App.main()` detects runtime configuration from the process environment and TTY
state, then calls `TerminalRunner.run(Self.self, configuration:)`.

`TerminalRunner` first rejects WebHost configuration. A terminal-only binary does
not link `SwiftTUIWebHost`, FlyingFox, or browser resources. Supporting `--web`
is a compile-time opt-in through `SwiftTUIWebHostCLI`, not runtime discovery.

After scene collection, `SceneRuntime` builds per-scene resources:

- primary scene: inherited stdio, `TerminalHost`, `InputReader`, default signal
  reader, diagnostics logger, stderr runtime issue sink
- secondary scenes: pty pair, pty-backed `TerminalHost`, pty-backed
  `InputReader`, lifecycle state that waits for an attach client

This is a CLI-only policy. The shared `SwiftTUIRuntime` still executes one root
scene per `RunLoop`; the CLI runner is the layer that creates multiple runtimes,
serves scene discovery, and proxies attached secondary scenes through ptys.

When `RunLoop` starts in normal TUI output mode, `TerminalHost.enableRawMode()`
does terminal setup:

- save termios and file status flags
- enter raw mode and nonblocking input
- enter alternate screen
- clear the screen
- move the cursor to the origin
- hide the cursor
- enable terminal mouse reporting when supported
- enable bracketed paste
- register cleanup for normal process exit

The first render is scheduled as a root invalidation. After the first frame,
`DefaultRenderer` enables selective evaluation so later invalidations can reuse
measured and placed work.

For each ready scheduled frame, `RunLoop`:

1. Builds a `ResolveContext` from live terminal state.
2. Uses terminal `surfaceSize` as the proposal unless a proposal override exists.
3. Renders through `DefaultRenderer`.
4. Updates `latestSemanticSnapshot`.
5. Synchronizes focus regions, default focus, focus bindings, focused values, and
   scroll positions.
6. Rerenders if that synchronization changed the graph-visible state.
7. Appends pending accessibility announcements to the semantic snapshot.
8. Presents the committed frame.
9. Applies lifecycle and task commits.
10. Updates focus presentation.
11. Schedules follow-up animation/deadline work.

The presentation branch is:

```text
if output == .json:
  JSONFrameRenderer writes machine-readable frame JSON
else if output == .accessible:
  LinearAccessibilityRenderer writes semantic text
else if surface is SemanticHostFramePresentationSurface:
  present(SemanticHostFrame(sequence, raster, semantics, focusedIdentity, rasterDamage))
else if surface is DamageAwarePresentationSurface:
  present(raster, damage)
else:
  present(raster)
```

`TerminalHost` is damage-aware, so the normal CLI path uses `RasterSurface` plus
`PresentationDamage`. `TerminalHost.present(...)` then:

- synchronizes retained writer state
- probes/updates graphics capabilities when image attachments require it
- prepares image attachments for the selected terminal graphics protocol
- computes a terminal presentation plan from previous surface, current surface,
  and damage
- chooses full repaint or incremental row batches
- renders changed spans into terminal-safe text
- emits cursor movement and optional erase-to-end-of-line operations
- replays graphics attachments when needed
- wraps full repaint in synchronized output if the terminal supports it
- submits bytes to the queue-backed `PresentationWriter`
- stores the prepared surface for the next diff

`TerminalSurfaceRenderer` is the ANSI/text boundary. It adapts colors, glyphs,
style escape sequences, hyperlinks, line decorations, and ASCII fallback. It
also sanitizes authored text and OSC 8 hyperlink destinations before terminal
bytes are written.

### Inbound Input Flow

The terminal input path is:

```text
terminal fd or pty fd
-> InputReader
-> ControlMessageParser strips runtime control messages
-> TerminalInputParser
-> InputEvent
-> RunLoop.handle(...)
-> FrameScheduler
-> next render
```

`InputReader` emits:

- `.key(KeyPress)`
- `.mouse(MouseEvent)`
- `.paste(PasteEvent)`
- `.drop(paths:context:)`

The parser handles:

- control-key byte sequences
- CSI arrows/navigation/modifier sequences
- SGR mouse sequences
- SGR-Pixels mouse coordinates when enabled
- bracketed paste
- terminal control messages prefixed by record separator (`0x1E`)

`RunLoop.handle(...)` then routes events through the semantic/runtime registries:

- scoped key commands
- exit bindings
- focused local key handlers
- Escape dismissal and navigation pop
- keyboard focus traversal
- focused action activation
- paste/drop dispatch
- pointer routing, gesture recognizers, hover, scroll, and drag state

Terminal pointer precision is host-probed or pre-resolved before the event pump
starts. The selected terminal mouse coordinate mode is copied into configurable
input readers so the enabled escape sequences and parser interpretation stay in
lockstep. Hover mode is subscriber-gated because all-motion mouse reporting can
produce high event volume.

### Resize, Style, Accessibility, And Exit

Terminal resize uses OS signal flow:

```text
SIGWINCH
-> SignalReader
-> RunLoop.handle(.signal("SIGWINCH"))
-> FrameScheduler.requestSignal
-> next frame reads presentationSurface.surfaceSize
```

`SIGWINCH` schedules a fresh frame and does not exit the run loop. The proposal
for that frame is the latest `TerminalHost.surfaceSize`.

Normal TUI mode consumes semantic accessibility records for focus, cursor
following, and routing. It does not write live-region text beside the visual
surface because that would corrupt the terminal display. Accessible linear output
is a separate output mode.

The CLI runner also owns terminal crash recovery for the primary scene. It
installs a crash guard before raw mode so fatal signals can disable mouse
reporting, show the cursor, reset style, exit the alternate screen, restore
termios, and then re-raise the signal.

### CLI-Specific Divergences

CLI diverges from SwiftUIHost and Web in these ways:

- It owns process startup and terminal process cleanup.
- It is the only path that puts a real terminal fd into raw mode.
- It writes terminal bytes, not host-native drawing instructions.
- It has retained terminal diff state and a writer queue.
- It has pty-backed secondary scene attach/list behavior.
- It has terminal-protocol limitations for input chords and pointer precision.
- It has crash recovery responsibilities that host-managed surfaces do not have.

## CLI `RenderOnce`

`RenderOnce` is not an interactive host. It exists for command output,
snapshot-friendly text generation, and pipelines that should not claim the
alternate screen.

The flow is:

```text
RenderOnce.render(view, width, options, environment, isStdoutTTY)
-> resolve output width
-> resolve RuntimeConfiguration and TerminalCapabilityProfile
-> DefaultRenderer.render(view, proposal: width x nil)
-> TerminalSurfaceRenderer.render(frame.rasterSurface)
-> normalize row separators
-> return String
```

`RenderOnce` does not:

- enter raw mode
- install signal handlers
- create an event pump
- own an alternate-screen buffer
- apply lifecycle/task commits over time
- retain presentation diff state between frames

It still uses the full renderer pipeline to produce `FrameArtifacts`, but it
uses only the resulting `RasterSurface` for emitted text. Capability policy still
matters: color, glyph fallback, Unicode, links, and sanitization are applied by
`TerminalSurfaceRenderer`.

Relevant source:

- [`RenderOnce.swift`](../Platforms/CLI/Sources/SwiftTUICLI/RenderOnce.swift)

## SwiftUIHost

### Outbound Frame Flow

The native Apple host path is:

```text
SwiftUIHostAppView
-> SwiftUIHostAppState
-> SwiftUIHostSceneHost
-> NativeSceneBridge
-> HostedSceneSession
-> SceneSession.run(...)
-> RunLoop
-> DefaultRenderer
-> HostedRasterSurface.present(...)
-> SwiftUIHostSceneHost.latestSurface/latestSemanticSnapshot
-> NativeTerminalSurfaceView.draw(...)
-> HostedAccessibilityOverlay
```

Relevant source:

- [`SwiftUIHostAppState.swift`](../Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostAppState.swift)
- [`SwiftUIHostSceneHost.swift`](../Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostSceneHost.swift)
- [`NativeSceneBridge.swift`](../Platforms/SwiftUI/Sources/SwiftUIHost/NativeSceneBridge.swift)
- [`SwiftUIHostAppView.swift`](../Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostAppView.swift)
- [`NativeTerminalSurfaceView.swift`](../Platforms/SwiftUI/Sources/SwiftUIHost/NativeTerminalSurfaceView.swift)
- [`HostedSceneSession.swift`](../Sources/SwiftTUIRuntime/Scenes/HostedSceneSession.swift)

`SwiftUIHostAppState` builds a `SceneManifest` from the authored app. It creates
one `SwiftUIHostSceneHost` per scene and retains those hosts in a dictionary.
Scene switching changes selected native host visibility; it does not rebuild the
authored app from scratch.

Each `SwiftUIHostSceneHost` creates a `NativeSceneBridge`, constructs a
`HostedRasterSurface` with:

- initial cell size
- initial terminal appearance and theme
- `onFrame`
- clipboard writer

It then constructs a `HostedSceneSession` with:

- the selected scene
- the `HostedRasterSurface`
- runtime issue sink
- focus presentation callback

`HostedRasterSurface` conforms to `SemanticHostFramePresentationSurface`. When
`RunLoop.presentCommittedFrame(...)` reaches the semantic host-frame branch,
the host receives a single `SemanticHostFrame` containing:

```text
RasterSurface
SemanticSnapshot
focused Identity
raster PresentationDamage?
producer sequence
```

No ANSI is generated. No terminal fd exists. The surface handler stores the
latest raster surface, semantic snapshot, focused accessibility identity, and
raster damage hint on `SwiftUIHostSceneHost`. The `SemanticHostFrame.sequence`
is monotonically increasing for the runtime producer so retained hosts and
bridges can recognize stale asynchronous work without relying on callback
ordering alone.

`SwiftUIHostAppView` bridges that host into native UI with an
`NSViewRepresentable` or `UIViewRepresentable`. The representable configures
`NativeTerminalSurfaceView` with:

- latest `RasterSurface`
- latest `PresentationDamage?`
- `SwiftUIHostTerminalStyle`
- `FocusPresentation`
- text-input keyboard presentation state
- resize callback
- input callback

`NativeTerminalSurfaceView.present(surface:damage:)` invalidates the full native
view when damage is unknown, the surface size changed, or the damage flags force
a full text/graphics repaint. Otherwise it converts dirty rows and column ranges
into cell-aligned native dirty rectangles. The draw pass receives the platform
dirty rect and procedurally draws only intersecting content:

- fill the background
- walk raster cells
- draw cell backgrounds
- draw box-drawing glyphs procedurally where supported
- draw text through native fonts
- draw underline/strikethrough decorations
- draw image attachments through native image APIs

The visual raster view is marked accessibility-hidden. A sibling
`HostedAccessibilityOverlay` maps `SemanticSnapshot.accessibilityNodes` into
native accessibility elements and binds runtime focus into native VoiceOver
focus.

### Inbound Input And Resize Flow

Native input flow is:

```text
AppKit/UIKit event
-> NativeInputMapper or touch/mouse mapper
-> InputEvent
-> SwiftUIHostSceneHost.send(...)
-> NativeSceneBridge.send(...)
-> HostedSceneSession.send(...)
-> InjectedTerminalInputReader
-> RunLoop
```

Native resize flow is:

```text
NativeTerminalSurfaceView.layout/layoutSubviews
-> NativeTerminalMetrics.gridSize(...)
-> onResize(CellSize, PixelSize)
-> SwiftUIHostSceneHost.resize(...)
-> NativeSceneBridge.resize(...)
-> HostedRasterSurface.updateSurfaceSize/updateSurfaceCapabilities
-> HostedSceneSession.requestSurfaceRefresh()
-> InProcessSignalReader.send("SIGWINCH")
-> RunLoop schedules a signal frame
```

Style updates flow similarly through `SwiftUIHostAppState.setStyle(...)`,
`SwiftUIHostSceneHost.apply(style:)`, `NativeSceneBridge.apply(style:)`, and
`HostedRasterSurface.updateStyle(...)`. The hosted session sends in-process
`SIGWINCH` so the next frame resolves with the new environment.

### SwiftUIHost Divergences

SwiftUIHost differs from CLI in these ways:

- It is a host-managed retained-session path, not a process runner.
- It retains one host/session per scene instead of pty-backed attach flows.
- It consumes `RasterSurface` directly instead of terminal bytes.
- It draws with native graphics, not terminal escape sequences.
- It does not use terminal raw mode, alternate screen, mouse reporting, or a
  terminal writer queue.
- It can provide native-pixel-derived sub-cell pointer locations directly.
- It mounts accessibility as native elements beside the visual raster view.
- Runtime focus moves native accessibility focus; native-to-runtime focus is not
  currently fed back into SwiftTUI focus.

SwiftUIHost differs from Web in these ways:

- It does not serialize frames over a wire format.
- It does not use canvas.
- It can use AppKit/UIKit keyboard and input-method behavior, subject to the
  current native input mapper.
- Scene switching is native SwiftUI state, not browser runtime/controller state.

## Local WebHost

### Outbound Frame Flow

The localhost browser path is:

```text
SwiftTUIWebHostCLI optional routing
-> WebHostCLIRunner
-> WebHostRunner
-> WebHostServer
-> WebSocketSurfaceTransport
-> SceneSession.run(...)
-> RunLoop
-> DefaultRenderer
-> WebSocketSurfaceTransport.present(SemanticHostFrame)
-> WebSurfaceFrameEncoder
-> WebSocket bytes
-> WebSocketSceneBridge
-> WebHostOutputDecoder
-> WebHostSceneRuntime.presentSurface(...)
-> browser canvas + ARIA tree
```

Relevant source:

- [`WebHostCLIRunner.swift`](../Platforms/WebHost/Sources/SwiftTUIWebHostCLI/WebHostCLIRunner.swift)
- [`WebHostRunner.swift`](../Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostRunner.swift)
- [`WebSocketSurfaceTransport.swift`](../Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift)
- [`WebSocketInputReader.swift`](../Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketInputReader.swift)
- [`WebSocketSceneBridge.ts`](../Platforms/Web/src/WebSocketSceneBridge.ts)
- [`WebHostSceneRuntime.ts`](../Platforms/Web/src/WebHostSceneRuntime.ts)
- [`WebHostSurfaceTransport.ts`](../Platforms/Web/src/WebHostSurfaceTransport.ts)

`SwiftTUIWebHostCLI` is the combined runner. If `RuntimeConfiguration.web` is
present, it delegates to `WebHostRunner`; otherwise it delegates to
`TerminalRunner`. This keeps terminal-only binaries free of WebHost dependencies
while giving opt-in binaries a single launch import.

`WebHostRunner` is a runner, not only a presentation surface. It:

1. Collects scene selections from the authored app.
2. Enforces the current V1 single-scene local WebHost constraint.
3. Starts the HTTP/WebSocket server.
4. Optionally opens the browser.
5. Creates `WebSocketSurfaceTransport`.
6. Creates `WebSocketInputReader`.
7. Runs the selected scene through `SceneSession.run(...)`.

`WebSocketSurfaceTransport` conforms to
`SemanticHostFramePresentationSurface`. It advertises a web-capable terminal
profile:

- Unicode glyphs
- true color
- no ANSI style escape emission
- hyperlink support
- mouse reporting support
- no synchronized-output terminal protocol

On presentation, it encodes:

- host-frame sequence
- raster width and height
- style table
- row cells as `[x, text, span, styleIndex]`
- image attachments
- raster damage when available
- accessibility tree and announcements when present
- optional presentation damage as dirty text rows and full-repaint flags
- accessibility tree
- accessibility announcements
- clipboard and runtime issue records when needed

The browser side uses `WebSocketSceneBridge` to decode byte chunks into
`WebHostOutputRecord` values. `WebHostSceneRuntime` then:

- stores the latest frame
- resizes the canvas
- clears and fills the full background, or only damage-derived dirty rectangles
  when the previous canvas/frame is compatible
- draws cells and line decorations intersecting the dirty region
- decodes and caches images
- draws image attachments intersecting the dirty region
- mounts accessibility nodes as ARIA beside the canvas
- posts accessibility announcements

### Inbound Input And Resize Flow

Browser input flow is:

```text
KeyboardEvent / PointerEvent / WheelEvent / ClipboardEvent
-> WebHostSceneRuntime input handlers
-> encodeKeyInputMessage / encodeMouseInputMessage / encodePasteInputMessage
-> WebSocketSceneBridge.sendInput(...)
-> WebSocketInputReader
-> WebSurfaceInputParser
-> InputEvent
-> RunLoop
```

Browser resize/style flow is:

```text
ResizeObserver or host style change
-> WebHostSceneRuntime.resizeToMount/setStyle
-> WebSocketSceneBridge.resize/updateRenderStyle
-> WebSocketInputReader control handler
-> WebSocketSurfaceTransport.updateSurfaceSize/updateStyle
```

This is the notable local-WebHost divergence: the current `WebHostRunner` passes
no `SignalReading` instance in `SceneSessionResources`. Resize/style control
records update the transport, but unlike `HostedSceneSession` and
`SwiftTUIWASI`, the local WebHost runner does not synthesize an in-process
`SIGWINCH` in the checked-in path. Changes to this seam should explicitly decide
whether resize/style records must wake rendering immediately or only affect the
next scheduled frame.

### Local WebHost Divergences

Local WebHost differs from CLI in these ways:

- It is compile-time opt-in and links HTTP/WebSocket/browser resources.
- It does not put a terminal fd in raw mode.
- It does not emit ANSI or terminal graphics escape sequences.
- It serializes complete `web-surface` frame records over WebSocket.
- It draws with browser canvas and DOM/ARIA, not a terminal.
- Browser input starts as DOM events and can carry web-pixel-derived sub-cell
  pointer positions.
- V1 supports one selected scene in the Swift-side local runner.

Local WebHost differs from `Platforms/Web` WASI in these ways:

- It serves an embedded browser bundle from a native process.
- It transports records over WebSocket, not WASI stdin/stdout.
- It uses a tokenized server session rather than a WASI environment/stdio bridge.
- Its Swift-side runner starts and stops the web server.
- Its resize/style wake behavior currently differs from the WASI path, as noted
  above.

## Platforms/Web WASI

### Outbound Frame Flow

The deploy-to-browser WASI path uses the same browser runtime package but a
different Swift transport:

```text
Browser createWebHostApp(...)
-> BrowserWASIBridge
-> WASI stdio pipes and environment
-> SwiftTUIWASI.WASIRunner
-> WebSurfaceTransport
-> SceneSession.run(...)
-> RunLoop
-> DefaultRenderer
-> WebSurfaceTransport.present(SemanticHostFrame)
-> WebSurfaceFrameEncoder
-> stdout bytes
-> BrowserWASIBridge WebHostOutputDecoder
-> WebHostSceneRuntime.presentSurface(...)
-> browser canvas + ARIA tree
```

Relevant source:

- [`WASIRunner.swift`](../Platforms/WASI/Sources/SwiftTUIWASI/WASIRunner.swift)
- [`WebSurfaceTransport.swift`](../Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift)
- [`BrowserWASIBridge.ts`](../Platforms/Web/src/wasi/BrowserWASIBridge.ts)
- [`WebHostApp.ts`](../Platforms/Web/src/WebHostApp.ts)
- [`WebHostSceneRuntime.ts`](../Platforms/Web/src/WebHostSceneRuntime.ts)

`Platforms/Web` is the browser package. When it is not configured for an
embedded localhost host, `WebHostApp` creates a `BrowserWASIBridge` for each
runtime. That bridge owns stdin/stdout/stderr pipes and environment values such
as:

- `TUIGUI_MODE=browser`
- `TUIGUI_TRANSPORT=surface`
- `TUIGUI_SCENE`
- `TUIGUI_COLUMNS`
- `TUIGUI_ROWS`
- `TUIGUI_RENDER_STYLE`

Inside the wasm process, `WASIRunner` chooses web-surface resources when the
transport mode is surface. It creates:

- `WebSurfaceTransport` as the presentation surface
- `WebSurfaceInputReader` as the input source
- `InProcessSignalReader` for resize/style wakeups
- runtime issue sink that writes runtime issue records through the transport

`WebSurfaceTransport` conforms to the same semantic host-frame presentation
surface protocol as local WebHost. It writes the same record family consumed by
`WebHostOutputDecoder`: surface, clipboard, runtime issue, and text records.
Surface records include optional presentation damage, and the encoder is shared
at the Swift level with the WebHost transport through the `WASISurfaceBridge`
target.

### Inbound Input And Resize Flow

Browser input and resize flow is:

```text
WebHostSceneRuntime input/resize/style
-> BrowserWASIBridge.stdin
-> WebSurfaceInputReader
-> WebSurfaceInputParser
-> InputEvent and WebSurfaceInputControlMessage
-> WASIRunner control handler
-> WebSurfaceTransport.updateSurfaceSize/updateStyle
-> InProcessSignalReader.send("SIGWINCH")
-> RunLoop
```

The parser accepts record-separator-prefixed commands for:

- resize, optionally including cell pixel size
- style, encoded as terminal render style JSON/base64
- key input
- mouse input
- paste input

The resize path records web-pixel cell metrics and advertises sub-cell pointer
capabilities with `.webPixels` provenance. The next frame receives those metrics
through `EnvironmentValues.cellPixelMetrics`, `terminalSize`, and
`pointerInputCapabilities`.

### Platforms/Web WASI Divergences

The WASI path differs from CLI in the same broad ways as local WebHost: no raw
terminal, no terminal diff bytes, browser canvas output, and DOM-originated
input.

It differs from local WebHost because:

- transport is stdio, not WebSocket
- launch is owned by the browser/WASI shell and `SwiftTUIWASI`, not a native
  HTTP server
- resize/style control messages synthesize `SIGWINCH`
- `WebHostApp` can manage browser-side scene runtimes from a manifest, while
  `SwiftTUIWASI` still executes one selected scene per wasm process
- there is no FlyingFox/server-token boundary

## Accessibility Across Hosts

Accessibility data is produced once, during `semantics`, as part of
`SemanticSnapshot`. Hosts consume that same semantic data differently:

| Surface | Accessibility delivery |
| --- | --- |
| CLI `.tui` | Semantics drive focus, cursor-following, and routing; live-region text is not written beside the visual terminal surface. |
| CLI `.accessible` / `--linear` | `LinearAccessibilityRenderer` emits the semantic tree and live-region announcements as text. |
| SwiftUIHost | `HostedAccessibilityOverlay` maps semantic nodes to native accessibility elements and binds runtime focus into native focus. |
| Local WebHost | `WebSocketSurfaceTransport` encodes `accessibilityTree` and announcements into `web-surface` records; the browser mounts ARIA beside canvas. |
| Platforms/Web WASI | `WebSurfaceTransport` encodes the same `accessibilityTree` and announcements into stdout records; browser runtime mounts ARIA beside canvas. |

Host-specific accessibility should stay a presentation concern. App code should
not maintain separate accessibility trees for terminal, web, and native hosts.

## Key Divergence Points

### Runner Versus Host

CLI and WebHost are runner-heavy. They decide how an executable starts, which
mode was requested, and when the process/server exits. SwiftUIHost and
`Platforms/Web` browser runtime are host-heavy. They retain or display scenes
inside a lifecycle owned by SwiftUI or the browser shell.

### Frame Sink

The shared renderer always produces `RasterSurface` and `SemanticSnapshot`.
When retained raster/presentation state is compatible, it may also produce
`PresentationDamage` as an advisory host-presentation hint. After that:

- CLI lowers raster cells into terminal bytes.
- SwiftUIHost hands raster, semantics, focus, and damage directly to native
  objects.
- WebHost and WASI encode raster, semantics, focus, and damage into
  `web-surface` records.

### Incremental Presentation

There are two kinds of incrementality:

1. Renderer/runtime incrementality: selective view-graph evaluation, retained
   layout, retained raster inputs, and frame-tail reuse.
2. Presentation incrementality: the host-specific decision about how much output
   to send or redraw after a committed `RasterSurface`.

All interactive hosts share the first kind. CLI has the richest terminal-byte
lowering because terminal output is expensive and stateful: it tracks previous
surfaces, dirty rows/spans, cursor moves, erase-to-end-of-line lowering,
synchronized output, and terminal graphics replay. SwiftUIHost now uses the same
damage hint to limit native invalidation and drawing to dirty cell rectangles.
Web transports still ship complete surface records for correctness and simple
wire compatibility, but they include damage metadata so the browser canvas can
avoid clearing and redrawing cells/images outside the dirty rectangles.

### Input Precision

CLI input is limited by terminal protocols. It may be cell-only or SGR-Pixels,
depending on terminal support and probing. Some byte-level chords collapse in
the terminal parser.

SwiftUIHost and Web receive richer platform events first. They normalize those
events into the same `InputEvent` model but can provide native/web pixel
provenance and sub-cell locations without terminal escape-sequence probing.

### Resize Wakeups

Resize must do two things:

1. Update the presentation surface's size/cell metrics.
2. Wake the run loop so a frame resolves with the new proposal.

The current paths are:

- CLI: OS `SIGWINCH` wakes the run loop; `TerminalHost.surfaceSize` is read on
  the next render.
- SwiftUIHost: `HostedRasterSurface` is updated directly, then
  `HostedSceneSession.requestSurfaceRefresh()` sends in-process `SIGWINCH`.
- Platforms/Web WASI: `WebSurfaceInputReader` control handler updates
  `WebSurfaceTransport` and sends in-process `SIGWINCH`.
- Local WebHost: `WebSocketInputReader` control handler updates
  `WebSocketSurfaceTransport`; the checked-in runner does not provide a signal
  reader for resize/style wakeups.

That last bullet is an implementation-specific seam. Tests or future changes
that touch local WebHost resize should pin whether immediate resize rerendering
is required.

### Style Ownership

Hosts own terminal appearance and semantic theme. The authored app does not
branch on the host family. Style changes flow into `EnvironmentValues` before
resolve:

- CLI detects terminal appearance/capabilities from environment and terminal
  probes.
- SwiftUIHost owns `SwiftUIHostTerminalStyle` and applies it to hosted sessions.
- Web hosts mirror terminal render style concepts in TypeScript and Swift
  transport records.

### Scene Management

Scene declarations are shared. Scene management is host policy:

- CLI can create multiple scene runtimes and attach to secondary scenes through
  ptys.
- SwiftUIHost retains a native host/session per scene and switches selected
  scene in SwiftUI state.
- Local `SwiftTUIWebHost` V1 serves one selected scene.
- `Platforms/Web` can present browser-side scene runtimes from a manifest, but a
  single WASI process executes one selected SwiftTUI scene.

### Failure And Cleanup

CLI owns terminal cleanup because it mutates the user's terminal process state.
SwiftUIHost and Web do not enter terminal raw mode, so their cleanup concerns are
session cancellation, view disposal, bridge shutdown, server shutdown, or WASI
stdio disposal.

## Maintainer Rules

1. Keep terminal escape-sequence adaptation out of layout, semantics, draw, and
   raster.
2. Add host behavior at the `PresentationSurface`, `TerminalInputReading`,
   `SignalReading`, or `HostedSceneSession` seams.
3. If a surface needs accessibility data, implement
   `SemanticHostFramePresentationSurface` so semantic presentation carries
   raster redraw hints beside the semantic snapshot. Declare
   `.accessibilityAnnouncements` only when the host bridge can publish queued
   announcements.
4. Resize/style updates should update surface state and have an explicit wake
   contract.
5. Keep `SwiftTUIRuntime` below runner and host products. Host products should
   compose on `SwiftTUIRuntime`, not the terminal convenience `SwiftTUI` product.
6. Preserve the compile-time WebHost boundary. Terminal-only `SwiftTUI` /
   `SwiftTUICLI` binaries must not link server or browser-bundle code.
7. Keep input capability negotiation synchronized with parsing. If a host
   enables pixel mouse reporting or supplies native/web pixels, the reader and
   environment values must describe the same coordinate model.
8. Do not treat a passing isolated renderer snapshot as proof of host behavior.
   Host regressions should be tested through the composed runtime path that owns
   the relevant bridge.

## Source Map

Common runtime:

- [`Sources/SwiftTUIRuntime/SwiftTUI.swift`](../Sources/SwiftTUIRuntime/SwiftTUI.swift)
- [`Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift`](../Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift)
- [`Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`](../Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift)
- [`Sources/SwiftTUIRuntime/RunLoop/RunLoop+EventDispatch.swift`](../Sources/SwiftTUIRuntime/RunLoop/RunLoop+EventDispatch.swift)
- [`Sources/SwiftTUIRuntime/Scenes/SceneSession.swift`](../Sources/SwiftTUIRuntime/Scenes/SceneSession.swift)
- [`Sources/SwiftTUIRuntime/Scenes/HostedSceneSession.swift`](../Sources/SwiftTUIRuntime/Scenes/HostedSceneSession.swift)

CLI:

- [`Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift`](../Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift)
- [`Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift`](../Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift)
- [`Platforms/CLI/Sources/SwiftTUICLI/RenderOnce.swift`](../Platforms/CLI/Sources/SwiftTUICLI/RenderOnce.swift)
- [`Sources/SwiftTUIRuntime/Input/InputReader.swift`](../Sources/SwiftTUIRuntime/Input/InputReader.swift)
- [`Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`](../Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift)
- [`Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift`](../Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift)

SwiftUIHost:

- [`Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostAppState.swift`](../Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostAppState.swift)
- [`Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostSceneHost.swift`](../Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostSceneHost.swift)
- [`Platforms/SwiftUI/Sources/SwiftUIHost/NativeSceneBridge.swift`](../Platforms/SwiftUI/Sources/SwiftUIHost/NativeSceneBridge.swift)
- [`Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostAppView.swift`](../Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostAppView.swift)
- [`Platforms/SwiftUI/Sources/SwiftUIHost/NativeTerminalSurfaceView.swift`](../Platforms/SwiftUI/Sources/SwiftUIHost/NativeTerminalSurfaceView.swift)
- [`Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityOverlay.swift`](../Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityOverlay.swift)

WebHost and Platforms/Web:

- [`Platforms/WebHost/Sources/SwiftTUIWebHostCLI/WebHostCLIRunner.swift`](../Platforms/WebHost/Sources/SwiftTUIWebHostCLI/WebHostCLIRunner.swift)
- [`Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostRunner.swift`](../Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostRunner.swift)
- [`Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift`](../Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift)
- [`Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketInputReader.swift`](../Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketInputReader.swift)
- [`Platforms/WASI/Sources/SwiftTUIWASI/WASIRunner.swift`](../Platforms/WASI/Sources/SwiftTUIWASI/WASIRunner.swift)
- [`Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`](../Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift)
- [`Platforms/Web/src/WebHostApp.ts`](../Platforms/Web/src/WebHostApp.ts)
- [`Platforms/Web/src/WebHostSceneRuntime.ts`](../Platforms/Web/src/WebHostSceneRuntime.ts)
- [`Platforms/Web/src/WebHostSurfaceTransport.ts`](../Platforms/Web/src/WebHostSurfaceTransport.ts)
- [`Platforms/Web/src/WebSocketSceneBridge.ts`](../Platforms/Web/src/WebSocketSceneBridge.ts)
- [`Platforms/Web/src/wasi/BrowserWASIBridge.ts`](../Platforms/Web/src/wasi/BrowserWASIBridge.ts)
