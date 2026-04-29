# Runtime

This document is the stable reference for runtime behavior. It captures the shipped lifecycle rules, state and observation model, input handling, and the current incremental delivery cost model.

## Runtime Shape

The runtime presents one committed frame at a time through the same strict pipeline used everywhere else:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

`RunLoop` integrates terminal I/O, invalidation scheduling, input, signals,
lifecycle staging, and task reconciliation around that pure frame pipeline. See
[ASYNC_RENDERING.md](ASYNC_RENDERING.md) for the current main-actor, worker, and
writer-queue ownership split.

For interactive sessions, the runtime owns the terminal alternate-screen buffer while running. That gives each `WindowGroup` a clean full-canvas presentation surface and restores the previous shell buffer on exit.

## Root-Hoisted Presentations

Built-in presentations — `alert`, `confirmationDialog`, `sheet`, and `toast` —
are authored inside the base view tree but displayed at the root.

- Base resolution collects presentation declarations during the ordinary resolve pass
- Visible presentation payloads resolve as overlay roots after the base tree has already been resolved
- Presentation hosts derive visible overlay state from the current resolved
  base declarations before overlay composition; wrapper-hosted and selectively
  re-evaluated subtrees must not wait for an outer host rerender before an
  already-declared presentation appears
- The renderer composes the base root and any overlay roots for downstream measure, place, semantics, draw, raster, and commit work
- Opening or dismissing a presentation does not re-resolve the displayed base
  subtree under a synthetic identity path. Presentation churn should be
  transparent to the currently selected tab or child owner unless the
  presentation action itself mutates the state that selects different content
- Dismissing a presentation prunes only the overlay-owned subtree identities
  for that presentation; dismissal must not run broad stale-subtree cleanup
  that reaches unrelated retained content
- Modal overlays can still suppress base interaction through the composed frame's semantic state

## Input, Focus, And Interaction

The runtime is keyboard-first, but it is not keyboard-only.

- Keyboard input is parsed into `KeyEvent` and `InputEvent` values
- Terminals that advertise mouse reporting feed pointer-style events into the same semantic routing layer
- Focus routing remains the authoritative target-selection system for keyboard-driven interaction
- Pointer interaction augments authored controls and collections rather than replacing the focus model

That means control activation, selection changes, scrolling, and editing can all flow through the same semantic and lifecycle system regardless of whether the initiating event came from the keyboard or the mouse-reporting stream.

### Pointer Coordinates And Capabilities

The runtime normalizes every pointer event into `PointerLocation`.

- `PointerLocation.cell` is the containing integer terminal cell used for
  routing through the semantic snapshot.
- `PointerLocation.location` is the continuous cell-space point delivered to
  gestures, hover handlers, spatial taps, drags, and drop contexts.
- Cell-only terminals synthesize `location` at the center of the reported cell.
  Native hosts, web hosts, and terminal SGR-Pixels mode can provide sub-cell
  locations derived from pixel coordinates.
- `PointerInputCapabilities` and `CellPixelMetrics` are copied into
  `EnvironmentValues` before each render so authored views and `GeometryReader`
  can display precision state or adapt direct-manipulation affordances without
  changing layout.

The policy is conservative in terminal-native sessions. SGR 1006 cell mouse
reporting remains the default. SGR-Pixels 1016 is enabled only when the host
policy requests terminal-pixel coordinates and the runtime has trustworthy cell
pixel metrics. Known terminal multiplexers fall back to cell coordinates unless
terminal pixels are explicitly forced.

### Pointer Modes And Hover Volume

Raw-mode setup enables terminal mouse reporting only for the precision mode the
runtime has selected:

- cell fallback: `CSI ? 1002 h` plus `CSI ? 1006 h`
- terminal pixels: `CSI ? 1002 h`, `CSI ? 1006 h`, and `CSI ? 1016 h`
- hover subscribers: `CSI ? 1003 h` is added while at least one rendered view
  has `onPointerHover`

Teardown disables the active modes in reverse so the shell is restored on normal
exit and in the CLI crash guard. Hover is intentionally subscriber-gated because
all-motion mouse reporting can produce high event volume. The run loop tracks
the current hovered route, delivers `.entered`, `.moved`, and `.exited` phases
with local continuous coordinates, and removes hover mode again when a render no
longer contains hover subscribers.

## Commit, Lifecycle, And Tasks

Lifecycle is identity-driven.

- An identity appears when it is present in the next committed tree but absent from the previous one
- An identity disappears when it is present in the previous committed tree but absent from the next one
- Reordering, layout movement, focus changes, clipping changes, or scroll-position changes do not count as lifecycle transitions if identity is preserved
- Off-screen or clipped nodes that remain in the tree do not disappear

`ViewGraph` finalizes each frame into explicit lifecycle events. `CommitPlanner`
only packages those events into `CommitPlan.lifecycle` alongside semantic
handler-installation work.

### Ordering Rules

- Removal cancels any owned task before running disappear handlers
- Insertion runs appear handlers before starting any owned task
- Task replacement on a stable identity cancels the old task before starting the new one

### Task Rules

- A task starts when an identity appears with a task descriptor
- A task also starts when a stable identity gains a task descriptor
- A task survives ordinary frame updates when the identity and task descriptor are unchanged
- A task restarts when the descriptor changes on the same identity
- A task cancels when its identity disappears, when its descriptor is replaced, or when the runtime shuts down

The practical rule is simple: if identity is preserved, it is not a lifecycle transition.

## State, Environment, Observation, And Isolation

The package still uses `.defaultIsolation(.none)` in `Package.swift`. That is deliberate. The shipped model now matches SwiftUI-style authoring isolation through explicit `@MainActor` annotations rather than through blanket target isolation.

The shipped ownership model is split into three categories:

- Main-actor authoring and body evaluation:
  - `View`, `Scene`, and `App`
  - `Resolver.resolve(...)`
  - `DefaultRenderer.render(...)`
  - scene collection helpers, typed `WindowIdentifier` values, and `WindowGroup` root-view construction
  - action-bearing authoring APIs such as `Binding.init(get:set:)`, button actions, `OpenLinkAction` over typed `LinkDestination`s, `.onAppear`, `.onDisappear`, `.onChange(of:initial:_:)`, and `.task(...)`
- Main-actor runtime coordination and ownership:
  - `RunLoop`
  - `StateContainer`
  - local action, focused-value, key, lifecycle, task, and pointer registries
  - retained frame and resolve-reuse stores
  - focus, pressed identity, lifecycle staging, and task reconciliation
  - terminal presentation commit boundaries
- Pure nonisolated frame products:
  - `ResolveContext`
  - `EnvironmentSnapshot`
  - resolved, measured, placed, semantic, draw, raster, and commit artifacts
- Genuinely concurrent I/O and host plumbing:
  - input readers
  - signal readers
  - terminal-host I/O
  - graphics or image transport support

### State Model

- `@State` persistence is keyed by view identity path plus source location
- Rebinding the same view instance into a different identity path creates a different state slot
- Keying only preserves state while the owning identity survives. State that
  must outlive active-tab bodies, deferred content, or presentation churn
  should be owned above those lazy seams and threaded down through bindings or
  explicit model state
- Active-tab local state may still be intentionally ephemeral across tab
  selection changes because `TabView` resolves only the selected body. Hoist
  only the state that must survive that tab churn; presentation open and close
  alone should not force the same reset
- `StateContainer` invalidates only when an `Equatable` state change actually changes value
- Projected bindings and local actions route through the same invalidation path
- Direct local actions restore the dynamic-property scope they were registered under so mutations remain bound to the right runtime scope
- Button actions, key-command handlers, dismiss closures, projected bindings,
  and other imperative paths must preserve that same authoring and
  dynamic-property scope so each path invalidates the same owner

### Environment Model

- `EnvironmentKey.Value` is `Sendable`
- `EnvironmentValues` stores typed sendable boxes rather than raw erased payloads
- `EnvironmentSnapshot` uses immutable value-style replacement semantics
- Style-affecting environment updates can change presentation without implying layout changes

Regression coverage exists for nested overrides, `transformEnvironment`, wrapper propagation, terminal-appearance updates, and style-only changes that preserve text layout.

### Observation Model

Observation is built on the same invalidation path as `@State`, not on a separate runtime.

- `resolveBody` and `EnvironmentReader` track observable reads through `ObservationBridge`
- observable callbacks invalidate the exact observed identity on the main actor
- generation tracking suppresses stale callbacks from older frames
- committed-frame pruning stops removed identities from continuing to invalidate hidden subtrees
- the package provides its own `@Bindable`

Supported scenarios include body-driven reads, environment-driven observable reads, bindable editing, and rerenders after observable edits.

## Current Incremental Cost Model

The runtime is materially incremental in common steady-state paths, but it is not uniformly incremental in every case.

### Resolve

- Invalidated identities are visible in `ResolveContext`, `FrameContext`, and `FrameDiagnostics`
- `FrameDiagnostics.presentationDamage` records the refined paint candidate that survived raster
  narrowing: dirty row count, range-aware row count, span count, candidate cell count, and whether
  the frame escalated to full-text or full-graphics fallback
- Localized dirty frames can reuse clean resolved subtrees when subtree identity, environment, and transaction still match
- Resolve reuse is conservative: root-invalidated frames and fully cold frames still resolve normally

### Measure And Place

- `MeasurementCache` survives across frames
- Cache reuse is guarded by a structural input snapshot, not just identity and proposal
- `RetainedLayoutSession` can reuse clean measured and placed subtrees when the invalidation set, subtree equality, proposals, bounds, and layout behavior all allow it

### Presentation

- `WindowGroup` roots render through a full-canvas window host that sizes itself to the current terminal proposal and clips drawing to terminal bounds
- `TerminalHost` keeps the previous `RasterSurface`
- `TerminalPresentationPlanner` emits row-batched incremental text updates when the previous and current surfaces are compatible
- Kitty-backed image presentation is planned separately from text diffing: dirty text rows trigger targeted re-placement, while attachment-layout changes fall back to a graphics-only full replay without forcing a text full repaint
- Row batches preserve logical span metadata, normalize around continuation cells, and share style/hyperlink state across disjoint edits on the same row
- Tail-only text shrink can lower to terminal-native erase-to-end-of-line when the host is running on
  a real terminal; the host keeps a local disable path and otherwise falls back to literal spaces
- Full repaints are wrapped in synchronized-output envelopes when the terminal capability profile marks that support as safe
- `TerminalPresentationMetrics` records the final write shape: strategy, bytes, touched lines/cells,
  synchronized-output usage, graphics replay scope, replayed attachment count, and any terminal edit
  op lowering that was actually applied
- `SIGWINCH` schedules a fresh frame and re-reads terminal size without exiting the run loop

### Cell pixel size refresh

`POSIXTerminalHost` (`TerminalHost` class in `Sources/TerminalUI/TerminalHost.swift`)
re-reads `cellPixelSize` on every access to `baselineGraphicsCapabilities()` via
`ioctl(TIOCGWINSZ)` — a single cheap syscall. Escape-sequence probes
(`CSI 16 t`, `CSI 14 t`, Kitty support, sixel capability) remain one-shot at
startup; only cell pixel dimensions are live.

Hosted sessions can simulate a cell-pixel-size change in tests via
`HostedSceneSession.resize(to:cellPixelSize:)`, which threads the new value
through `StreamingTerminalHost.updateCellPixelSize(_:)` and fires a SIGWINCH.

### Deterministic Scenario Checks

The standing runtime checks are deterministic scenario tests rather than wall-clock benchmarks.

- Idle rerender: the second frame reuses measured and placed work and writes no bytes
- Localized subtree update: work stays concentrated on the dirty path and reused siblings stay clean
- Focused button press: the second frame remains incremental and smaller than the initial full repaint
- Single-character text input: the second frame remains incremental, though a cursor-bearing insertion can still widen to a 2-cell span
- Trailing tail shrink: the second frame remains incremental, keeps narrow candidate damage, and
  prefers erase-to-end-of-line over literal trailing spaces when the host can prove it is safe
- Single-step scroll movement: still a documented conservative path and not yet a guaranteed incremental case

### Known Full-Repaint Fallbacks

- First frame, when there is no previous surface
- Surface size changes, including terminal resize
- Raster attachment changes
- Raster metadata changes
- Any host that relies on the default `TerminalHosting.present(_:)` implementation instead of `TerminalHost`
- The current `ScrollView` viewport-shift benchmark path

## Crash Recovery

When the process crashes (SIGABRT from `fatalError`/`preconditionFailure`, SIGSEGV from null dereference or stack overflow, SIGBUS, SIGILL, SIGFPE, SIGTRAP), a synchronous signal handler resets the terminal before the process dies.

The CLI runner (`TerminalUICLI`) installs the crash guard in `SceneRuntime` for the primary scene before the session enters raw mode. It uses `CrashSignalHandler` from the vendored `UnixSignals` package. The guard:

- Captures the pre-raw-mode termios from stdin
- Writes a pre-encoded reset escape sequence (disable mouse reporting, show cursor, reset style, exit alternate screen) to stdout using `write(2)` (async-signal-safe)
- Restores the saved termios via `tcsetattr` (practically safe on Darwin and Linux)
- Re-raises the signal with the default handler so the process terminates normally with a core dump

The crash guard is removed when the session ends normally.

This lives in the CLI runner rather than in `TerminalUI` because `TerminalUI` is also used in the WASM build where signals do not exist. Runner packages that own a real tty are responsible for installing the crash guard.

The crash guard is process-global. Signal handlers are inherently process-scoped, so only one scene can own the guard at a time. This matches the expected deployment: the primary scene owns the real tty.

An alternate signal stack (`sigaltstack`) is installed so that SIGSEGV from stack overflow can still run the handler.

Limitations:

- SIGKILL and OOM-kill cannot be caught — the kernel terminates the process immediately
- `tcsetattr` is not officially async-signal-safe per POSIX, though it is safe in practice on Darwin and Linux
- The crash guard does not cover WASI (no signals) or Windows
- Other runner packages (e.g. embedded hosts) would need their own crash guard installation if they own a real tty

## Coverage Anchors

Key suites that pin this document:

- `InteractiveRuntimeTests`
- `DiagnosticsAndCacheTests`
- `Phase1BenchmarkScenariosTests`
- `Phase2CommitPlannerTests`
- `Phase2LifecycleFixtureTests`
- `Phase4ObservationAndEnvironmentTests`
- `Phase4StateReliabilityTests`
