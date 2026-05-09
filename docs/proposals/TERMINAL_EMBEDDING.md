# Terminal Embedding

**Status:** Implemented for v1 by
[plans/2026-05-04-001-terminal-embedding-plan.md](../plans/2026-05-04-001-terminal-embedding-plan.md).
This document remains the design record for the capability and the deferred
v2 edges.

**Reproposes:** the latent "embed external terminal applications inside a
SwiftTUI scene" capability that
[TERMINAL_NATIVE_UX_RESEARCH.md](../TERMINAL_NATIVE_UX_RESEARCH.md) implies
when it cites Zellij, tmux, and WezTerm as workspace baselines but stops short
of saying how an authored SwiftTUI app would *host* a child program. This
proposal makes that capability explicit, picks a layering, and is honest about
what would and would not be required to express something the size of Zellij
in SwiftTUI.

---

## Problem

A SwiftTUI app today can render a SwiftUI-shaped tree into a single host
surface. It cannot, as authored content, run `zsh`, `htop`, `vim`, or another
SwiftTUI app inside one of its own panes. Three observable consequences:

1. **The workspace doctrine has no first-class verb.**
   [TERMINAL_NATIVE_DOCTRINE.md](../TERMINAL_NATIVE_DOCTRINE.md) and
   [TERMINAL_NATIVE_UX_RESEARCH.md](../TERMINAL_NATIVE_UX_RESEARCH.md) describe
   the workspace pattern (tabs, panes, status bars, mode visibility) and cite
   tmux/Zellij/WezTerm as the reference. SwiftTUI ships `TabView`, `HStack`/
   `VStack` splits, custom `Layout`, and `ActionScope` commands — every part
   of that workspace **except** "what runs inside a pane is something other
   than authored SwiftUI content."

2. **Existing PTY work is half-used.** `Platforms/CLI/Sources/SwiftTUICLI/PtyPair.swift`
   already opens a pty pair, and the multi-scene runner in
   `Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift` already attaches
   secondary scenes to that slave. That investment is **PTY-as-output** —
   the slave receives another SwiftTUI scene's render. The complementary
   role, **PTY-as-input** (the slave is the controlling terminal for an
   *external* child program whose byte stream we read back), has no Swift
   surface today.

3. **`HostedSceneSession` is the obvious composition point but is one-way.**
   `Platforms/SwiftUI` and `Platforms/Web` already retain a SwiftTUI
   runtime inside a non-terminal host and consume `RasterSurface` values.
   A symmetric inward pattern — a SwiftTUI scene hosting a non-SwiftTUI
   terminal-program runtime as a `View` — does not exist.

The reproposal: introduce a **single embeddable view** whose contents are a
running pseudo-terminal session, plus the runtime support to drive it through
the existing seven-phase pipeline without breaking
[Foundation-free Core](../PUBLIC_SURFACE_POLICY.md) or the
[`AnyView` policy](../PUBLIC_SURFACE_POLICY.md).

## Goal

A SwiftTUI app author writes:

```swift
import SwiftTUI
import SwiftTUITerminal  // new peer package

struct ShellPane: View {
  @State private var session = TerminalProcessSession(command: "/bin/zsh")

  var body: some View {
    TerminalView(session: $session)
      .focusable()
  }
}
```

…and gets a focusable rectangle whose contents are the live output of `zsh`,
sized by SwiftTUI's normal layout proposal, with keyboard input forwarded to
the child when the view is on the focus chain, with `SIGWINCH` propagated to
the child on parent resize, and with the child's exit surfaced as an
observable event that the surrounding view tree can react to.

The same `TerminalView` can host any byte source that looks like a terminal:
a spawned process, an SSH stream, the output of one SwiftTUI app inside another
(closing the loop with the existing `PtyPair` story), or a recorded asciinema
file. The view does not care; the session does.

## Non-Goals

- **Not a full terminal emulator product.** This is an embedding API for
  SwiftTUI authors, not a replacement for iTerm2 or Alacritty. Capabilities
  that only matter when SwiftTUI is the *outer* terminal (pixel-precise
  font rendering, ligatures, custom shaders) are explicitly out.
- **Not a Zellij ABI clone.** A later section discusses what a Zellij-shaped
  app would need; the proposal is **not** "implement Zellij's protobuf
  plugin protocol in Swift."
- **Not a multiplexer daemon.** `Platforms/CLI` already owns Unix-socket
  attach/detach (`SocketServer.swift`, `SocketClient.swift`,
  `AttachProxy.swift`). This proposal layers on top of those; it does
  not introduce a second daemon.
- **Not a Foundation creep into `SwiftTUICore`/`SwiftTUIViews`/`SwiftTUI`.** The pure
  emulator state and the cell-grid types stay Foundation-free; the PTY
  driver, child-process management, and any third-party emulator
  dependency live in a peer package.
- **Not iOS or WASI in v1.** PTY semantics on iOS are restricted (no
  `forkpty`); WASI has no PTY at all. v1 targets macOS and Linux. iOS
  may later host a *connected* terminal (SSH-backed) without a local
  child process; that is a separate proposal.

## Principles

1. **The view is SwiftUI-shaped; the runtime is not novel.** `TerminalView`
   participates in the resolve→measure→place→semantics→draw→raster→commit
   pipeline like any other view. It is not a `BackgroundProcess` view, not
   a special scene, not a host package. Its only deviation from SwiftUI
   precedent is that SwiftUI itself has no analogous concept.
2. **The session is a `Sendable` actor; the view is a passive observer.**
   Authored apps create a session value, hand it to the view, and read
   observable state. The view does not own the child process lifetime
   except through the session's reference. This matches the
   `@Bindable` / `@Observable` story already in `View`.
3. **Cells in, cells out.** The embedded child's screen is reduced to the
   same `RasterCell`/`RasterSurface` vocabulary the rest of the runtime
   already speaks. The rasterizer has one extra job: blit a foreign cell
   rectangle. It does not gain a parallel rendering path.
4. **Foundation-free emulator core; Foundation-using PTY driver.** The
   pure VT/grid component must compile under the same prek hook that
   blocks `import Foundation` in `SwiftTUICore`/`SwiftTUIViews`/`SwiftTUI`. The PTY driver
   may use Foundation/Subprocess/POSIX freely because it lives in a peer
   target.
5. **Focus is the activation predicate, again.** Per
   [decisions/0003-action-scopes-not-global-hotkeys.md](../decisions/0003-action-scopes-not-global-hotkeys.md),
   keyboard forwarding to the child only happens when `TerminalView` is
   on the current focus chain. Off-focus, keys propagate to the
   surrounding scope as usual. This is identical to how `TextField`
   and `TextEditor` already behave.
6. **Resize is a layout consequence.** When SwiftTUI proposes a new size
   to `TerminalView`, the view forwards that size to the session, which
   issues `TIOCSWINSZ` on the master fd. There is no separate "terminal
   resize signal" — the existing layout pass *is* the resize signal.
7. **Multiplexer-tax is an opt-in modifier.** OSC interception, mode
   translation, and bracketed-paste namespacing are *not* default
   behavior of `TerminalView`. They are opt-in via modifiers
   (`.interceptClipboard()`, `.interceptHyperlinks(_:)`, etc.) so a
   simple "embed `htop`" use case does not pay the multiplexer cost.

## Layering

Five tiers, low to high:

```
Tier 5  Authored apps                  Examples/embedded-shell, future Zellij rewrite
Tier 4  TerminalView (View widget)     in SwiftTUITerminal
Tier 3  TerminalSession protocol +     in SwiftTUITerminal
        TerminalProcessSession actor
Tier 2  PTY driver                     in SwiftTUITerminal (POSIX/Foundation)
Tier 1  Emulator state machine         in SwiftTUITerminalCore (Foundation-free)
Tier 0  Existing SwiftTUI runtime      SwiftTUICore / SwiftTUIViews / SwiftTUI / Platforms/CLI
```

### Tier 1: `SwiftTUITerminalCore` (Foundation-free)

A pure-Swift, `Sendable`, no-Foundation library that takes a stream of bytes
and exposes a cell grid plus dispatched events.

```swift
public struct EmulatorGrid: Sendable {
  public var size: CellSize          // shares Core.CellSize
  public var cells: [[RasterCell]]   // shares Core.RasterCell
  public var cursor: CellPoint
  public var cursorVisible: Bool
  public var inAlternateScreen: Bool
  public var scrollback: ContiguousArray<EmulatorRow>  // pull on demand
}

public actor TerminalEmulator {
  public init(size: CellSize)
  public func feed(_ bytes: [UInt8]) -> [EmulatorEvent]
  public func snapshot() -> EmulatorGrid
  public func resize(_ size: CellSize)
  public func encode(key: EmulatorKey) -> [UInt8]   // forward translator
}

public enum EmulatorEvent: Sendable, Equatable {
  case titleChanged(String)
  case workingDirectoryChanged(String)        // OSC 7
  case clipboardWriteRequested(Data)          // OSC 52
  case hyperlink(URL?, range: GridRange)      // OSC 8
  case bell
  case mouseModeChanged(MouseMode)
  case keyboardModeChanged(KeyboardMode)
  case clientReply([UInt8])                   // bytes to write back to PTY master
  case bufferActivated(BufferKind)            // alt-screen toggle
}
```

Two implementation paths, picked deliberately:

- **(A)** Vendor SwiftTerm's `Terminal`, `EscapeSequenceParser`, `Buffer`,
  and `BufferLine` files with the AppKit/UIKit view layers excluded, and
  wrap them in the `TerminalEmulator` actor above. SwiftTerm is BSD-style
  licensed, has the production-tested OSC dispatch surface, and ships a
  `HeadlessTerminal` proving the split is real.
- **(B)** Clean-room port a focused subset of `alacritty/vte`'s state
  machine plus a minimal `TerminalState` (alt buffer, scroll region,
  attribute set). ~2 weeks of work and produces a smaller, strict-
  concurrency-clean dependency, but reproduces ground SwiftTerm already
  covers.

The recommendation is **(A) for v1, with the `TerminalEmulator` actor
designed as a stable wrapper** so a (B) replacement remains feasible.
SwiftTerm's strict-concurrency annotation is incomplete; a
`@preconcurrency import SwiftTerm` plus actor isolation is the documented
adopter pattern (see e.g. `dodo-reach/hermes-desktop`).

The wrapper, *not* SwiftTerm itself, is the public surface. That is the
escape hatch if licensing, concurrency strictness, or SwiftTerm's
maintenance trajectory ever forces the swap.

### Tier 2: PTY driver (Foundation-using, peer target)

```swift
public actor PTYChildProcess {
  public init(
    executable: String,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    workingDirectory: String? = nil,
    initialSize: CellSize
  )
  public func start() throws
  public func read() -> AsyncStream<[UInt8]>
  public func write(_ bytes: [UInt8]) async throws
  public func resize(_ size: CellSize) throws       // TIOCSWINSZ on master
  public func sendSignal(_ signal: Int32) throws    // forward to child pgid
  public func waitForExit() async -> ExitStatus
}
```

POSIX path: `forkpty` (the same primitive SwiftTerm's `Pty.swift` uses).
Notes from the research:

- `forkpty` does the right thing on macOS and Linux: `fork`, `openpty`,
  `login_tty` in the child (which calls `setsid` and makes the slave the
  controlling terminal). `posix_spawn` cannot make a fd the controlling
  terminal, so the cleaner-looking spawn path does not actually work
  here.
- SIGCHLD: do not install a global handler. Use
  `DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit)`
  per child. Linux libdispatch supports this.
- `TIOCSWINSZ` must target the *master* fd. The kernel propagates
  SIGWINCH to the child's foreground process group automatically.
- Master fd: keep blocking, run reader on a dedicated dispatch queue, or
  set `O_NONBLOCK` and use `DispatchSource.makeReadSource`. The latter is
  cleaner under structured concurrency.
- `FD_CLOEXEC` on the master before spawning the reader.

The driver intentionally does **not** import SwiftTerm. It speaks pure
bytes. The session glues driver to emulator.

#### Reusing existing `PtyPair`

The today-shipping `PtyPair.swift` exposes `openpty()` plus a slave path
and a master fd. It is a `final class` whose initializer fails for the
WASI build. `PTYChildProcess` should **subsume** `PtyPair` rather than
introduce a parallel type:

- Extract the `openpty` primitive into a free function in
  `Platforms/CLI` (`unowned(SwiftTUICLIPlatformPOSIX)` style).
- Have `PtyPair` (PTY-as-output, used by `SceneRuntime`) and
  `PTYChildProcess` (PTY-as-input, new) both consume it.
- Resist the urge to merge them into a single class with a mode flag —
  the lifecycle ownership is genuinely different (a `PtyPair` waits for
  *attach*; a `PTYChildProcess` owns a *spawn*). One primitive, two
  thin wrappers.

### Tier 3: `TerminalSession` protocol + `TerminalProcessSession` actor

```swift
public protocol TerminalSession: Observable, Sendable {
  var grid: EmulatorGrid { get async }
  var title: String? { get async }
  var workingDirectory: String? { get async }
  var lifecycle: TerminalLifecycle { get async }
  func send(key: EmulatorKey) async
  func send(mouse: EmulatorMouse) async
  func send(paste: String) async
  func resize(_ size: CellSize) async
}

@Observable
public final class TerminalProcessSession: TerminalSession {
  public init(
    command: String,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    workingDirectory: String? = nil
  )
}
```

Other conformers (followup proposals, not in scope here):

- `TerminalSSHSession` — drives the emulator from a libssh2/NIO-SSH stream
- `TerminalAsciinemaSession` — replays a `.cast` file at recorded timing
- `TerminalRecordingSession` — wraps another session and writes its byte
  stream to disk in asciinema format

The conformance pattern matters: alternate sources of *bytes* should be
expressible without re-implementing the emulator. This is the same
factoring alacritty/wezterm/xterm.js converged on.

### Tier 4: `TerminalView`

```swift
public struct TerminalView<Session: TerminalSession>: View {
  public init(
    session: Bindable<Session>,
    onTitleChange: ((String) -> Void)? = nil,
    onExit: ((TerminalExitReason) -> Void)? = nil
  )
}

extension View {
  public func interceptClipboard(_ handler: (Data) -> Void) -> some View
  public func interceptHyperlinks(_ handler: (URL) -> Void) -> some View
  public func interceptWorkingDirectory(_ handler: (String) -> Void) -> some View
  public func terminalKeyboardMode(_ mode: TerminalKeyboardMode) -> some View
}
```

Pipeline integration, phase-by-phase:

| Phase     | What `TerminalView` does                                                  |
|-----------|---------------------------------------------------------------------------|
| resolve   | Records the session reference and stable identity                         |
| measure   | Returns the parent's proposal — no intrinsic minimum, no maximum          |
| place     | Stores its assigned `CellRect`                                            |
| semantics | Registers a focus participant; declares no `ActionScope` of its own       |
| draw      | Emits one `DrawCommand.foreignSurface(bounds:, payload:)` (new variant)   |
| raster    | Rasterizer reads the session's grid snapshot and blits cells into bounds  |
| commit    | The committed cells go through `TerminalPresentation` like everything else|

The new `DrawCommand.foreignSurface` is a small, well-defined extension to
`Sources/SwiftTUICore/Draw/DrawTreeTypes.swift`. It carries an opaque
`ForeignSurfacePayload` (a `Sendable` snapshot reference) and the bounds.
The rasterizer's existing per-cell loop gains one branch: "if I'm inside
a foreign-surface bounds, sample from the payload's grid instead of the
cell I would otherwise draw." Rich-text shading, image attachments, and
border decorations from outside the foreign surface continue to compose
on top via the normal post-command path.

Resize: when `place` assigns `TerminalView` a new `CellRect` whose size
differs from the last one, the view enqueues `await session.resize(size)`
on its `.task(id: bounds.size)` — the existing
identity-driven lifecycle staging is exactly the right hook. No new
runtime mechanism is required.

Input forwarding: when the view is on the focus chain, key events
arriving through `RunLoop+EventDispatch` are encoded into byte sequences
by the session (which knows the child's negotiated keyboard mode) and
written to the PTY master. The encoding is the *emulator's* job because
keyboard mode is a per-child negotiated state — see "Keyboard mode
translation" below.

### Tier 5: authored apps

Two example apps in `Examples/`:

- `Examples/embedded-shell` — a single `TerminalView` running the user's
  default shell, demonstrating focus, resize, exit handling, and OSC
  interception.
- `Examples/dual-pane` — `HStack { TerminalView; TerminalView }` running
  two shells side by side. This is the smallest non-trivial multiplexer
  and validates the layout integration.

A future "Zellij-shaped" example app would build on the same pieces with
a custom `Layout` for tiled splits and `TabView` for tabs. See "Rewriting
Zellij in SwiftTUI" below.

## Public Surface Additions

Per [PUBLIC_SURFACE_POLICY.md](../PUBLIC_SURFACE_POLICY.md), new public
surface needs justification.

In the new peer package `Platforms/Embedding` (working name; alternatives:
`Sources/SwiftTUITerminal` if it ships from the root package, but the
Foundation requirement argues for a peer):

- `TerminalView<Session: TerminalSession>` — the only authored verb the
  doctrine actually adds
- `TerminalSession` protocol — the abstraction over byte sources
- `TerminalProcessSession` — the spawned-child conformance
- `EmulatorEvent`, `EmulatorKey`, `EmulatorMouse`, `CellSize`,
  `TerminalExitReason`, `TerminalKeyboardMode`, `TerminalLifecycle` —
  surface types
- four interception modifiers

In `Sources/SwiftTUICore/Draw/`:

- `DrawCommand.foreignSurface(bounds: CellRect, payload: ForeignSurfacePayload)`
  added to the existing `DrawTreeTypes.swift`
- `public protocol ForeignSurfacePayload: Sendable { var grid: ForeignGrid { get } }`
  in a new `ForeignSurface.swift`
- `public struct ForeignGrid: Sendable { var size: CellSize; var cells: [[RasterCell]] }`
  in the same `ForeignSurface.swift`

That is the *only* change to `SwiftTUICore`. `RasterCell` is reused unchanged. The
rasterizer gains a branch but no new types.

What stays package-internal:

- `PTYChildProcess`, `TerminalEmulator`, the SwiftTerm wrapper, mode
  translators, OSC interceptors. Authors interact with `TerminalSession`
  conformances, never with the driver or emulator directly.

What is explicitly *not* added:

- No public `RasterCell` mutation API. Foreign payloads expose grids
  read-only; only the emulator can produce one.
- No public `Process` wrapper. Process spawning is an implementation
  detail of `TerminalProcessSession`. If authors need raw process
  control, they use Foundation `Process` directly.

## Multiplexer-Tax: What's In, What's Out

Embedding `htop` requires only Tier 1–4. The "multiplexer tax" — the work
that lets SwiftTUI sit *between* the user's outer terminal and a child —
is large and most of it is opt-in:

| Concern                              | v1 default       | Opt-in modifier                    | Cost            |
|--------------------------------------|------------------|------------------------------------|-----------------|
| Cell grid + colors + cursor          | Yes              | —                                  | Tier 1 baseline |
| Alternate screen buffer              | Yes              | —                                  | Tier 1 baseline |
| Bracketed paste                      | Yes              | —                                  | Tier 1 baseline |
| Mouse mode (X10 / 1000 / 1002 / SGR) | Yes (translated) | —                                  | non-trivial     |
| Keyboard mode (CSI u, Kitty kbd)     | Legacy only      | `.terminalKeyboardMode(.kitty)`    | non-trivial     |
| OSC 0/2 (title)                      | Reported         | `onTitleChange`                    | trivial         |
| OSC 7 (cwd)                          | Reported         | `interceptWorkingDirectory`        | trivial         |
| OSC 8 (hyperlinks)                   | Pass-through     | `interceptHyperlinks`              | trivial         |
| OSC 52 (clipboard)                   | Dropped          | `interceptClipboard`               | low             |
| OSC 99 (Kitty notifications)         | Dropped          | (deferred)                         | high            |
| Sixel passthrough (full-pane child)  | Yes              | —                                  | medium          |
| Sixel inside tiled pane              | No               | (deferred)                         | very high       |
| Kitty graphics protocol              | No               | (deferred)                         | very high       |
| Synchronized output (DECSET 2026)    | Yes              | —                                  | medium          |
| Focus reporting (DECSET 1004)        | Yes              | —                                  | low             |
| Process group / job control          | Yes              | —                                  | Tier 2 baseline |
| Session attach/detach                | Inherited        | (uses CLI `AttachProxy`)           | already shipped |

Items marked "very high" are *the* underestimated complexity in any
multiplexer rewrite (per Zellij's own grid.rs implementation). Deferring
them to v2 is a deliberate scope choice.

## Rewriting Zellij in SwiftTUI

The user's prompting question. An honest answer:

### What the existing SwiftTUI runtime already gives you

| Zellij concept              | SwiftTUI equivalent today                                              |
|-----------------------------|------------------------------------------------------------------------|
| Tabs                        | `TabView`                                                              |
| Tiled panes                 | `HStack` / `VStack` / custom `Layout` (replaces Cassowary)             |
| Stacked panes               | a custom `Layout` variant                                              |
| Floating panes              | `.sheet(...)` / `.popover` (when it lands)                             |
| Status bar                  | `Text` + `LabeledContent` in a `VStack`                                |
| Mode indicator              | `@State` / `@Observable` driving status text                           |
| Keybindings + modes         | `ActionScope` + `.keyCommand(...)` (already shipped)                   |
| Command palette             | `.paletteCommand(...)` (already shipped)                               |
| Session attach/detach       | `Platforms/CLI/AttachProxy` + Unix socket discovery (already shipped)  |
| Multi-scene apps            | `App` with multiple `WindowGroup` scenes (already shipped)             |
| KDL config                  | a Swift `App` declaration *is* the config                              |
| Configuration file          | one Swift file authored by the user                                    |

That is most of Zellij's chrome. None of it requires this proposal.

### What this proposal adds toward a Zellij-shape

| Zellij concept              | What's new                                                              |
|-----------------------------|-------------------------------------------------------------------------|
| Pane (terminal child)       | `TerminalView(session: TerminalProcessSession(...))`                    |
| Per-pane PTY                | `PTYChildProcess` per session                                           |
| VT/grid emulator            | Tier 1 (`SwiftTUITerminalCore`)                                         |
| Pane resize on layout       | falls out of SwiftTUI's measure→place→`session.resize` chain            |
| Per-pane scrollback         | `EmulatorGrid.scrollback`, surfaced through a `ScrollView` modifier     |
| Selection / copy            | a `TerminalView` selection overlay + `OSC 52` interception              |
| Mouse forwarding            | mouse mode in Tier 1                                                    |

### What is genuinely missing for a 1.0 Zellij-clone

The honest punch list, ordered by load-bearing-ness:

1. **Render diff, not full redraw.** Zellij runs a debounced
   `RenderToClients` background job (~10 ms granularity) that emits a
   minimal VT byte stream with cursor moves and SGR diffs. SwiftTUI's
   commit phase already diffs cell-by-cell, so this *might* fall out for
   free — but only if a foreign-surface blit producing a full new grid
   each tick still hits the existing diff path. Validating that on
   `cat large.log` and over SSH is a deliberate v1 task, not an
   afterthought. Naive full-redraws will work locally and fall over on
   slow links.
2. **Sixel/Kitty graphics inside a tiled pane.** When a pane scrolls or
   is partially covered, the embedded image must be re-rasterized to the
   visible region. Zellij does this via a `SixelImageStore` +
   `intersecting_rect`; SwiftTUI has none of that scaffolding. Defer to
   v2; v1 supports graphics only when a child has the whole screen.
3. **Keyboard / mouse mode translation between client and child.** The
   multiplexer sits in the middle and must translate from the outer
   terminal's negotiated mode to whatever each child currently expects,
   updating on the fly when the child enables/disables a mode. Zellij
   has dedicated `keyboard_parser` + bracketed-paste markers. v1 ships
   legacy keyboard + SGR mouse only; Kitty keyboard is a v2 modifier.
4. **OSC 99, OSC 52 namespacing, hyperlink ID re-keying.** When two
   children both emit OSC 99 with id=1, the multiplexer must rewrite
   ids so activation responses route back to the right pane. This
   only matters in a true multiplexer; not in v1.
5. **Wasm plugin host.** Zellij's plugin system is the most novel part
   of its architecture and is *not* required to ship a multiplexer.
   `Platforms/WASI` already runs SwiftTUI itself in WASI; a SwiftTUI-
   shaped plugin host would let plugins author *views* directly rather
   than emit ANSI to a pane. That is a much better story than Zellij's
   "plugins draw by writing ANSI" — but it is a separate proposal and
   one of the strongest reasons to *not* clone Zellij's plugin ABI.
6. **Web client.** `Platforms/Web` already exists. A "browser client
   for an authored Zellij-shape SwiftTUI app" falls out of the existing
   web host; no extra work.

### Effort estimate, eyes open

For a *Zellij-feature-parity* SwiftTUI app, ordered by who does the work:

| Work                                                                | Owner          | Effort   |
|---------------------------------------------------------------------|----------------|----------|
| `Platforms/Embedding` package skeleton + dependency wiring          | SwiftTUI repo  | 1 week   |
| Tier 1 emulator (SwiftTerm wrap + actor isolation)                  | SwiftTUI repo  | 2 weeks  |
| Tier 2 PTY driver + reuse `PtyPair` primitive                       | SwiftTUI repo  | 1 week   |
| Tier 3 `TerminalProcessSession` + observable surface                | SwiftTUI repo  | 1 week   |
| Tier 4 `TerminalView` + `DrawCommand.foreignSurface` + rasterizer   | SwiftTUI repo  | 2 weeks  |
| Mouse mode translation + bracketed paste + OSC 0/2/7/8              | SwiftTUI repo  | 2 weeks  |
| Render-diff validation against `cat large.log`, SSH, top, vim       | SwiftTUI repo  | 1 week   |
| Tests + fixtures for the pipeline integration                       | SwiftTUI repo  | 1 week   |
| **Subtotal — embedding capability lands**                           |                | **~11 weeks** |
| Custom `Layout` for tiled splits + selection overlay + scrollback   | App author     | 2 weeks  |
| Zellij-style status/mode/command palette wiring                     | App author     | 1 week   |
| Session manager (uses existing `AttachProxy`)                       | App author     | 1 week   |
| Sixel-inside-pane (deferred from v1)                                | SwiftTUI repo  | 4 weeks  |
| Kitty kbd, OSC 52/99, hyperlink namespacing (deferred from v1)      | SwiftTUI repo  | 3 weeks  |
| Plugin system (Wasm-or-SwiftTUI; design first)                      | SwiftTUI repo  | unbudgeted |
| **Total to ship a credible Zellij-shape**                           |                | **~22+ weeks** |

For comparison: the published Zellij codebase is ~115k lines of Rust
across ~5 years and many contributors. The SwiftTUI rewrite is feasible
on this timeline because **most of Zellij isn't the multiplexer**, it's
the workspace UX — and SwiftTUI already ships the workspace UX. The
multiplexer-specific work compresses to the four to six items above
because the seven-phase pipeline, focus model, action scopes, and
host-package story are reused.

### What would make this a *better* product than Zellij

Worth saying out loud since the question asks for a rewrite, not a port:

- **Plugins are SwiftTUI views, not ANSI-emitting Wasm modules.** The
  Zellij plugin model exists because Zellij has no portable view layer.
  SwiftTUI does. A plugin authored as a `View` composes naturally
  inside the host's layout, gets focus, fires `ActionScope` commands,
  and renders without re-traversing a VT parser.
- **`Platforms/SwiftUI` and `Platforms/Web` come for free.** A
  Zellij-shape SwiftTUI app runs in a terminal *and* in a macOS window
  *and* in a browser, with the same authored code. Zellij needed an
  `axum`+`tokio-tungstenite` web feature added to the server to get
  the browser path; SwiftTUI already has it.
- **One language, one type system.** No wire-format protobuf between
  client and server — both are Swift, both observe the same
  `@Observable` session. The Unix-socket attach/detach is still
  there for actual *remote* sessions; in-process panes don't need it.
- **Configuration is code, not KDL.** A Zellij user describes their
  workspace in KDL because Zellij's runtime can't parse Rust at runtime.
  A SwiftTUI user describes their workspace in Swift, with type-checked
  references to their own `View`s. For users who want declarative
  config, a small `Codable`-shaped layout DSL is trivially layered on
  top.

## Risks

1. **SwiftTerm strict-concurrency drift.** SwiftTerm's `Sendable`
   annotations are incomplete and the project is in mid-migration to
   swift-subprocess. The wrapper actor isolates this, but a major
   SwiftTerm change could force a clean-room (B) port mid-stream.
   Mitigation: the wrapper protocol is the public surface; SwiftTerm
   is a swappable internal.
2. **`DrawCommand.foreignSurface` interaction with image attachments.**
   `RasterSurface.imageAttachments` exists for Kitty/Sixel image
   replay. A foreign surface inside an image-attached frame needs
   well-defined Z-order. Solvable, but worth a fixture pass.
3. **Pty + Foundation on Linux.** `Glibc` exposes `forkpty`, but the
   strict-memory-safety setting and `unsafe` audits of the existing
   `PtyPair.swift` show this is uneven terrain. Budget includes
   audit time.
4. **iOS / WASI exclusion.** v1 explicitly drops iOS and WASI for the
   embedding package. The root packages remain cross-platform; the
   peer package gates on `canImport(Darwin) || canImport(Glibc)`.
   This is a known constraint but not a blocker for the doctrine.
5. **`AnyView` policy.** `TerminalView` is generic over `Session`, so
   no erasure is needed. The package must not introduce
   `[any TerminalSession]` or builder-returning-`AnyTerminalSession`
   sugar. Easy to follow; worth being explicit.

## Open Questions

Decisions made during implementation:

- `TerminalSession` is not `Observable` in v1. It is a class-bound
  `Sendable` protocol with synchronous `cachedSnapshot`, async control
  methods, and an `events()` stream. `TerminalProcessSession` owns its
  mutable state internally, while `TerminalView` invalidates from session
  events.
- `DrawCommand.foreignSurface` does not have per-cell blend in v1. The
  rasterizer blits the foreign grid into the normal cell surface; authored
  tinting, framing, and overlays remain ordinary SwiftTUI composition around
  the terminal view.
- The package name is `Platforms/Embedding`. Its public products are
  `SwiftTUIPTYPrimitives` and `SwiftTUITerminal`; root `SwiftTUI` remains
  independent of the peer package.
- Selection overlay remains deferred. Clipboard writes are forwarded from
  embedded children through OSC 52 interception to the surrounding host
  clipboard action.
- Render-diff validation is covered by the landed `TerminalView` large-output
  byte-budget test and latency-injected presentation test, plus the repo's
  TermUIPerf smoke and layout-scroll-burst comparisons. A dedicated live SSH
  transport scenario remains future validation work rather than v1 API
  surface.

## What This Reproposal Is Not Saying

To pre-empt readings of this document that pull more scope than
intended:

- It is **not** saying SwiftTUI should compete with Alacritty, iTerm2,
  or WezTerm as an outer terminal emulator. The outer terminal stays
  whatever the user runs.
- It is **not** saying Zellij should be replaced. It is saying a
  Zellij-shape app *can* be expressed in SwiftTUI once embedding
  exists, and that the gap is smaller than Zellij's line count
  suggests because the workspace is already authored.
- It is **not** saying the plugin system question is solved. The
  proposal calls out that SwiftTUI's plugin story should be views, not
  ANSI modules — but that is a separate, harder design.
- It is **not** committing to any of the deferred v2 items (Sixel-in-
  pane, Kitty graphics, Kitty keyboard, OSC 99 namespacing). They are
  acknowledged as work, not promised.

## References

Internal:

- [VISION.md](../VISION.md) — SwiftUI faithfulness and terminal-native
  reinterpretation
- [HOST_PACKAGES.md](../HOST_PACKAGES.md) — peer-package precedent
- [TERMINAL_NATIVE_DOCTRINE.md](../TERMINAL_NATIVE_DOCTRINE.md) and
  [TERMINAL_NATIVE_UX_RESEARCH.md](../TERMINAL_NATIVE_UX_RESEARCH.md) —
  workspace doctrine that this proposal makes literal
- [PUBLIC_SURFACE_POLICY.md](../PUBLIC_SURFACE_POLICY.md) — why the
  emulator wrapper is the public surface, not SwiftTerm
- [decisions/0007-host-packages-are-peers.md](../decisions/0007-host-packages-are-peers.md)
- [decisions/0008-swifttui-library-only-runners-own-main.md](../decisions/0008-swifttui-library-only-runners-own-main.md)
- existing PTY work: `Platforms/CLI/Sources/SwiftTUICLI/PtyPair.swift`,
  `Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift`,
  `Platforms/CLI/Sources/SwiftTUICLI/AttachProxy.swift`

External:

- SwiftTerm — https://github.com/migueldeicaza/SwiftTerm (BSD-style;
  `Terminal.swift`, `EscapeSequenceParser.swift`, `HeadlessTerminal.swift`,
  `Pty.swift`, `LocalProcess.swift` are the reusable pieces)
- alacritty/vte — https://github.com/alacritty/vte (Williams state
  machine reference; clean-room port path)
- alacritty_terminal — https://github.com/alacritty/alacritty/tree/master/alacritty_terminal
  (emulator-core / renderer / PTY split reference)
- wezterm-term — https://github.com/wez/wezterm/tree/main/term
  (dirty-line tracking pattern)
- xterm.js — https://github.com/xtermjs/xterm.js (parser registry pattern)
- Zellij — https://github.com/zellij-org/zellij; especially
  `zellij-server/src/panes/grid.rs` (the VT/grid that any rewrite must
  match), `zellij-server/src/panes/tiled_panes/pane_resizer.rs`
  (Cassowary replaced by SwiftTUI's `Layout`),
  `zellij-server/src/output/mod.rs` (render diff that SwiftTUI's commit
  phase should subsume)
