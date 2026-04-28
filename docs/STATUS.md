# Status

## Product Status

The core terminal UI stack is implemented and regression-tested across the full frame pipeline:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

The package is usable for real terminal interfaces. The main gaps are not in
the fundamental pipeline; they are in breadth of surface area, app-shell
ergonomics, and a few still-conservative runtime paths.

`alert`, `confirmationDialog`, `sheet`, and `toast` are part of the public
`View` surface. The full ActionScope/commands rollout — `Panel`,
`.keyCommand`, `.paletteCommand`, `.toolbar`, and `.toolbarItem` — has shipped
(see [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md)).

## Shipped Surface

### Authoring surface

- SwiftUI-shaped `@MainActor`-isolated `View` authoring with body-only `View`, `@ViewBuilder`, `TupleView`, `ConditionalContent`, `AnyView`, and `Resolver`
- Layout and containers including `VStack`, `HStack`, `LazyVStack`, `LazyHStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `ViewThatFits`, `GeometryReader`, and custom `Layout`, with `LazyVStack` and `LazyHStack` supporting viewport-lazy placement and single-`ForEach` full-lazy rows
- Controls and primitives including `Text`, proposal-aware `TextFigure` backed by embedded FIGlet fonts, rich `Text` interpolation, `Link`, `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `TextEditor`, `SecureField`, `DisclosureGroup`, `Picker`, `Menu`, determinate and indeterminate `ProgressView`, `Label`, `LabeledContent`, `GroupBox`, `ControlGroup`, `Spacer`, `Divider`, and shapes
- `Image` backed by PNG, baseline JPEG, and GIF (first frame for animated GIFs), with named-resource, local-file-URL, and embedded-byte sources plus `.resizable()`, `.scaledToFit()`, and `.scaledToFill()`. Format is detected from magic bytes, so the `pngData(_:)` / `jpegData(_:)` / `gifData(_:)` initializers all accept any supported format.
- Environment, observation, and focus including `@State`, `@Binding`, repo-owned `@Bindable`, `@FocusState`, `FocusedValues`, `@FocusedValue`, `@FocusedBinding`, `PreferenceKey`, subtree preference readers, `OpenLinkAction`, actor-context-aware `.task(...)`, and default-focus modifiers
- Presentation and workflow surfaces including terminal-native `alert`, `confirmationDialog`, `sheet`, `toast`

### Runtime surface

- `DefaultRenderer` for one-shot rendering and pipeline inspection from the main actor
- `RunLoop` for interactive terminal sessions
- `TerminalHost`, terminal appearance detection, graphics-capability probing, capability-aware presentation, and OSC 8 hyperlink emission when supported
- host-owned `Theme` and paired `TerminalRenderStyle` updates so hosted
  sessions and browser/WASI runtimes can switch semantic themes at runtime
- Keyboard parsing, mouse input parsing, Unix signal handling, and runtime scheduling
- Identity-driven lifecycle diffs with post-present appear, disappear, task start, and task cancel staging
- Kitty and Sixel image presentation with ANSI or ASCII fallback compositing when graphics protocols are unavailable

### Scene and multi-scene surface

- `@MainActor` `App`, `Scene`, `SceneBuilder`, `WindowIdentifier`, and `WindowGroup` declarations in `TerminalUI`
- `TerminalUISceneDescriptor`, `TerminalUISceneManifest`, and `HostedSceneSession` in `TerminalUI` for host-package tooling and retained non-terminal hosting
- `TerminalCLIAppRunner` in `Runners/TerminalUICLI` for terminal-native executable launch, scene discovery, attach, and pty-backed secondary scenes
- `TerminalWASIAppRunner` in `Runners/TerminalUIWASI` for manifest generation and WASI-hosted scene launch
- The same authored `App` can feed three execution modes: terminal-native execution, WASI execution, or host-managed embedding through peer GUI host packages
- Pty-backed secondary scenes, Unix-domain-socket discovery, scene attachment, and lazy rendering of unattached secondary scenes
- `TabView` for terminal-native shell composition
- terminal-native `alert` and `confirmationDialog` presentation in the canonical `View` surface

### Charts

- `BarChart`, `ColumnChart`, `ComparisonChart`, `Sparkline`, `Timeline`, `ThresholdGauge`, `BulletChart`, `Meter`, `Legend`, `HeatStrip`, and `StackedBarChart`

## Current Constraints

- The core `TerminalUI` runtime renders one active scene into one active host per session. Multi-scene apps are supported, but only one scene is on screen at a time per host.
- `TerminalUI` is library-only. Platform integration splits between executable runner packages in `Runners/` and embedded host packages in `GUI/`.
- Embedded GUI host packages use `TerminalUI` scene manifests plus `HostedSceneSession`. Peer host packages live at `GUI/SwiftUITUIGUI` and `GUI/WebTUIGUI`; they own their own platform shell integration, scene switching chrome, and style surfaces.
- Embedded GUI host packages own one active host style object at a time and
  can swap it at runtime; the root TUI app renders semantic tokens without
  knowing which host theme is active.
- The runtime is keyboard-first, but mouse input is supported where the terminal advertises reporting. Pointer interaction should be treated as additive rather than as the primary design center.
- Image decoding covers PNG, baseline-sequential JPEG (`SOF0`, 8-bit, all common chroma subsamplings), and static GIF (first frame composited onto the logical screen). Animated GIF playback, progressive JPEG, and broader media formats remain deferred.
- WASI builds use the `swiftly`-managed Swift 6.3.1 toolchain via `swiftly run swift build --swift-sdk swift-6.3.1-RELEASE_wasm ...` through `Runners/TerminalUIWASI` / example-app build paths. The shorter `swift ...` form works from a shell where `swift` already resolves through `swiftly`; `xcrun swift` may resolve to an incompatible Xcode toolchain.
- Some focus surfaces remain missing:
  - namespace-scoped default-focus APIs such as `.prefersDefaultFocus(_:in:)`, `.focusScope(_:)`, and `resetFocus`
  - object-focused wrappers such as `@FocusedObject`
- Some geometry-bound preference surfaces are deferred:
  - anchor-based preference APIs such as `anchorPreference(...)` and `transformAnchorPreference(...)` until local coordinate spaces and anchor resolution ship
- Some higher-level workflow surfaces are unsettled:
  - richer multiline editing behaviors beyond the current `TextEditor`
- Some internal lowering seams remain package-only for runtime plumbing and tests:
  - `ViewNode`
  - `ResolvableView`

## Deferred By Design

See [VISION.md](VISION.md) for the rationale and the intended ordering.

- `NavigationStack`
- popover-style presentation beyond the current sheet support
- richer accessibility and assistive-technology modeling beyond the current semantic tree

The project treats terminal-native reinterpretation as a first-class design
rule. The remaining gaps are prioritized around terminal workspaces, deeper
scroll control, and navigation surfaces that still need a stronger hypothesis
before they graduate.

### Commands, Keybindings, and Scopes

The ActionScope model described in
[proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md)
has fully landed:

- `ActionScope` protocol, `AnyID`, and a scope-identity-keyed `CommandRegistry`
  wired into the runtime.
- `Panel` primitive plus `.panel(id:)` / `.panel()` / `.focusContainment(_:)`.
- `Scene`-conforming types and the `.alert` / `.confirmationDialog` / `.sheet`
  presentation modifiers conform to `ActionScope`; presentation overlays
  scope-inherit scene identity.
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
