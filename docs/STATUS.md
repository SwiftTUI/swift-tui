# Status

## Product Status

The core terminal UI stack is implemented and regression-tested across the full frame pipeline:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

The package is usable for real terminal interfaces. The main gaps are not in
the fundamental pipeline; they are in breadth of surface area, app-shell
ergonomics, and a few still-conservative runtime paths.

This document is the high-level product and runtime overview. It may describe
goals, shipped surface, current constraints, and deferred-by-design areas, but
it is not the canonical work queue. Any gap described here that is planned,
actively investigated, or awaiting a decision must have a corresponding item in
[`TODO.md`](TODO.md). If no `TODO.md` item exists, the text here should
make clear that the topic is shipped, contextual, or explicitly deferred.

Current async presentation and frame-tail worker ownership is summarized in
[ASYNC_RENDERING.md](ASYNC_RENDERING.md).

`alert`, `confirmationDialog`, `sheet`, `popover`, `popoverTip`, and `toast`
are part of the public `View` surface. The full ActionScope/commands rollout — `Panel`,
`.keyCommand`, `.paletteCommand`, `.toolbar`, and `.toolbarItem` — has shipped
(see [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md)).

## Shipped Surface

### Authoring surface

- SwiftUI-shaped `@MainActor`-isolated `View` authoring with body-only `View`, `@ViewBuilder`, `TupleView`, `ConditionalContent`, `AnyView`, and `Resolver`
- Layout and containers including `VStack`, `HStack`, `LazyVStack`, `LazyHStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `ViewThatFits`, `GeometryReader`, and custom `Layout`, with `LazyVStack` and `LazyHStack` supporting viewport-lazy placement and single-`ForEach` full-lazy rows
- Controls and primitives including `Text`, proposal-aware `TextFigure` backed by embedded FIGlet fonts, rich `Text` interpolation, `Link`, `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `TextEditor`, `SecureField`, `DisclosureGroup`, `Picker`, `Menu`, determinate and indeterminate `ProgressView`, `Label`, `LabeledContent`, `GroupBox`, `ControlGroup`, `Spacer`, `Divider`, and shapes
- `Image` backed by PNG and baseline JPEG, with named-resource, local-file-URL, and embedded-byte sources plus `.resizable()`, `.scaledToFit()`, and `.scaledToFill()`. Format is detected from magic bytes.
- `AnimatedImage` as a peer product for finite pre-composed frame animation plus GIF import/export.
- Environment, observation, focus, and preferences including `@State`,
  `@Binding`, `@Environment`, repo-owned `@Bindable`, `@FocusState`, `FocusedValues`,
  `@FocusedValue`, `@FocusedBinding`, `PreferenceKey`, subtree preference
  readers, anchor preferences, `OpenLinkAction`, actor-context-aware
  `.task(...)`, default-focus modifiers, and graph-scoped imperative state
  writes for live runtime callbacks
- Presentation and workflow surfaces including terminal-native `alert`,
  `confirmationDialog`, `sheet`, `popover`, `popoverTip`, `toast`, and
  binding-driven `NavigationStack` destinations

### Accessibility

- Shared semantic accessibility substrate through `AccessibilityRole`,
  authoring modifiers, `AccessibilityNode`, and semantic extraction.
- Terminal accessible output, cursor-following policy, reduced-motion and
  no-progress runtime policy, and live-region announcements.
- Web/WASI and embedded WebHost ARIA delivery through the shared
  `web-surface` accessibility tree.
- SwiftUI host accessibility overlay and platform announcement bridge.
- Visual-only content policy, source-manifest guardrails, and manual listening
  evidence guidance.

### Runtime surface

- `DefaultRenderer` for one-shot rendering, async runtime rendering, and pipeline
  inspection from the main actor
- `RunLoop` for interactive terminal sessions
- `TerminalHost`, terminal appearance detection, graphics-capability probing,
  capability-aware presentation, sanitized text emission, and sanitized OSC 8
  hyperlinks when the terminal advertises support
- host-owned `Theme` and paired `TerminalRenderStyle` updates so hosted
  sessions and browser/WASI runtimes can switch semantic themes at runtime
- Keyboard parsing, mouse input parsing, Unix signal handling, and runtime scheduling
- Identity-driven lifecycle diffs with post-present appear, disappear, task start, and task cancel staging
- Kitty and Sixel image presentation with ANSI or ASCII fallback compositing when graphics protocols are unavailable

### Scene and multi-scene surface

- `@MainActor` `App`, `Scene`, `SceneBuilder`, `WindowIdentifier`, and `WindowGroup` declarations in `SwiftTUI`
- `SceneDescriptor`, `SceneManifest`, `HostedRasterSurface`, and
  `HostedSceneSession` in `SwiftTUI` for host product tooling and retained
  non-terminal hosting
- `TerminalRunner` in `SwiftTUICLI` for terminal-native executable launch, scene discovery, attach, and pty-backed secondary scenes
- `WASIRunner` in `SwiftTUIWASI` for manifest generation and WASI-hosted scene launch
- `WebHostRunner` and `WebHostCLIRunner` in `SwiftTUIWebHost` /
  `SwiftTUIWebHostCLI` for
  localhost-browser launch, selected-scene WebHost routing, and
  terminal/WebHost launch routing
- The same authored `App` can feed terminal-native execution, WASI execution,
  localhost-browser WebHost execution, or host-managed embedding through root
  package platform products
- Pty-backed secondary scenes, Unix-domain-socket discovery, scene attachment, and lazy rendering of unattached secondary scenes
- `TabView` for terminal-native shell composition
- Binding-driven `NavigationStack` destination presentation through
  `navigationDestination(isPresented:)` and `navigationDestination(item:)`;
  `NavigationLink`, public `NavigationPath`, and automatic Back chrome remain
  intentionally out of the shipped surface
- The `NavigationStack` and `.navigationDestination(...)` names are retained
  intentionally as SwiftUI-shaped names for a narrower terminal contract;
  `@Environment(\.dismiss)` remains excluded by policy in favor of explicit
  binding or callback ownership plus runtime Escape dismissal
- terminal-native `alert`, `confirmationDialog`, and popover presentation in the canonical `View` surface

### Charts

- `BarChart`, `ColumnChart`, `ComparisonChart`, `Sparkline`, `Timeline`, `ThresholdGauge`, `BulletChart`, `Meter`, `Legend`, `HeatStrip`, and `StackedBarChart`

### Animated Images

- `AnimatedImage`, `AnimatedImageSequence`, `AnimatedImageFrame`,
  `AnimatedImagePixel`, and `AnimatedGIF`

### Terminal embedding

- `TerminalView<Session>`, `TerminalSession` protocol, and
  `TerminalProcessSession` for spawned children
- Mouse mode translation (X10 / 1000 / 1002 / SGR), bracketed paste, OSC 0/2
  title changes, OSC 7 working-directory changes, and OSC 8 hyperlinks
- Lives in `Platforms/Embedding`; macOS and Linux only

### Terminal workspaces

- `SwiftTUITerminalWorkspace` provides `TerminalWorkspaceState`,
  `TerminalWorkspaceTab`, `TerminalWorkspaceNode`, `TerminalPaneSpec`,
  `TerminalWorkspaceSessionStore`, and `TerminalWorkspaceView`.
- V1 covers tabs, split-pane trees, stable pane identity, directional focus,
  split/close/zoom/new-tab commands, retained `TerminalProcessSession` values,
  and `Codable` layout/command metadata.
- `Examples/terminal-workspace` is the maintained Zellij-style evidence app.

## Current Constraints

- The core `SwiftTUIRuntime` runtime renders one active scene into one active
  presentation surface per session. Multi-scene apps are supported, but only
  one scene is on screen at a time per surface.
- `SwiftTUI` is the terminal app convenience product; platform integration
  lives in sibling root package products for explicit runners, hosts, WebHost,
  and terminal embedding. `Platforms/` is the source layout for those targets,
  while `Platforms/Web` is the `@swifttui/web` browser-runtime workspace and
  `Platforms/WebBuild` is the `@swifttui/build` browser build-tooling
  workspace.
- Host products and packages use `SwiftTUIRuntime` scene manifests plus
  `HostedRasterSurface` / `HostedSceneSession` and own their own platform shell
  integration, scene switching chrome, and style surfaces.
- Host products own one active host style object at a time and
  can swap it at runtime; the root TUI app renders semantic tokens without
  knowing which host theme is active.
- The runtime is keyboard-first, but mouse input is supported where the terminal advertises reporting. Pointer interaction should be treated as additive rather than as the primary design center.
- Core image decoding covers PNG and baseline-sequential JPEG (`SOF0`, 8-bit,
  all common chroma subsamplings). GIF import/export and finite animated image
  playback live in `AnimatedImage`; progressive JPEG and broader media formats
  remain deferred.
- Sixel and Kitty graphics inside an embedded pane are not supported; only
  full-screen child graphics work today.
- Kitty keyboard protocol and OSC 99 notifications are not intercepted for
  embedded children in v1. OSC 52 clipboard requests are forwarded to the
  active host clipboard action.
- `SwiftTUITerminalWorkspace` persists layout and non-secret command metadata,
  but does not yet reattach to still-running child processes after app restart.
  That is outside the current work queue until a session-supervisor or runner
  contract is scoped.
- Built-in text inputs use a `String`-backed package-private editing model with
  grapheme offsets, reducer commands, caret anchors, and focused selection
  rendering. Focused terminal text inputs use the hardware cursor by default
  when the host can place it at the caret. Focused copy/cut writes through host
  clipboard adapters, `ctrl-v` reads host clipboard text where supported, and
  secure inputs suppress clipboard text on copy/cut. Host-native
  value/selection transport, IME/composition, and large-document rope/piece-tree
  storage remain deferred until SwiftTUI has concrete host event contracts or
  workload evidence.
- `SwiftTUITerminal` / `SwiftTUIPTYPrimitives` do not build for iOS or WASI.
- WASI builds use the `swiftly`-managed Swift 6.3.1 toolchain via `swiftly run swift build --swift-sdk swift-6.3.1-RELEASE_wasm ...` through the root `SwiftTUIWASI` product / example-app build paths. Repo-local package builds and tests should use the explicit `swiftly run swift ...` form; `xcrun swift` may resolve to an incompatible Xcode toolchain.
- Some internal lowering seams remain package-only for runtime plumbing and tests:
  - `ViewNode`
  - `ResolvableView`

## Deferred By Design

See [VISION.md](VISION.md) for the rationale and the intended ordering. Planned
or decision-bound follow-up work is tracked in [TODO.md](TODO.md), not in this
status overview.

### Commands, Keybindings, and Scopes

The ActionScope model described in
[proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md)
has fully landed:

- `ActionScope` protocol, `AnyID`, and a scope-identity-keyed `CommandRegistry`
  wired into the runtime.
- `Panel` primitive plus `.panel(id:)` / `.panel()` / `.focusContainment(_:)`.
- `Scene`-conforming types and the `.alert` / `.confirmationDialog` / `.sheet`
  / `.popover` presentation modifiers conform to `ActionScope`; presentation
  overlays scope-inherit scene identity.
- `.keyCommand(...)` with shallowest-wins focus-chain dispatch. Modifier-less
  registrations are silently dropped (single-key dispatch is framework-reserved
  for typing, arrow navigation, Tab, Enter, and Escape); a disabled match
  consumes the event without firing and blocks deeper matches.
- `.paletteCommand(...)` plus `EnvironmentValues.activePaletteCommands` for
  consumer-authored palette surfaces. The captured list is refreshed after each
  frame from the current focus chain.
- `.toolbar(style:)` plus the `.toolbarItem(...)` hoisting preference;
  contributions bubble past intermediate scopes until absorbed by the nearest
  enclosing toolbar. `ToolbarStyle`, `DefaultTopToolbarStyle`, and
  `DefaultBottomToolbarStyle` control layout and placement.

Framework-owned single-key dispatch continues through `LocalKeyHandlerRegistry`
for built-in controls. The earlier global `HotkeyRegistry` and `.onKeyPress(...)`
modifier have been removed.

Open design questions still tracked in the proposal:

- **Cross-scope-kind precedence on collisions.** Shallowest-wins is the landed
  rule; cross-kind priority beyond chain depth remains open.
- **State-predicate scopes as first-class DSL surface.** The model handles
  selection- and mode-predicated scopes; the authoring DSL still treats
  state-predicate scopes implicitly through their anchor node.

## See Also

The repository [README.md](../README.md) is the public landing page; this
document and the rest of `docs/` are the source of truth for architecture,
runtime behavior, and API governance. Per-target DocC catalogs under
`Sources/*/*.docc` are the public API guide. [docs/README.md](README.md) is
the full doc index.
