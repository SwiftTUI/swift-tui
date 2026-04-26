# Status

## Product Status

The core terminal UI stack is implemented and regression-tested across the full frame pipeline:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

The package is already usable for real terminal interfaces. The main gaps are
not around the fundamental pipeline anymore; they are around breadth of surface
area, app-shell ergonomics, and a few still-conservative runtime paths.

The 2026 terminal-native reset is substantially landed: automatic chrome has
been reset, shell navigation primitives are canonical, multiline editing and
indeterminate loading are public, and `alert`/`confirmationDialog`/`sheet`/
`toast` presentation surfaces live in the main `View` module. The
ActionScope/commands rollout (see
[proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md))
is fully landed: the scope scaffolding, `.keyCommand`, `.paletteCommand`, and
`.toolbar` + `.toolbarItem` are all part of the public `View` surface.

## Shipped Surface

### Authoring surface

- SwiftUI-shaped `@MainActor`-isolated `View` authoring with body-only `View`, `@ViewBuilder`, `TupleView`, `ConditionalContent`, `AnyView`, and `Resolver`
- Layout and containers including `VStack`, `HStack`, `LazyVStack`, `LazyHStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `ViewThatFits`, `GeometryReader`, and custom `Layout`, with `LazyVStack` and `LazyHStack` supporting viewport-lazy placement and single-`ForEach` full-lazy rows
- Controls and primitives including `Text`, proposal-aware `TextFigure` backed by embedded FIGlet fonts, rich `Text` interpolation, `Link`, `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `TextEditor`, `SecureField`, `DisclosureGroup`, `Picker`, `Menu`, determinate and indeterminate `ProgressView`, `Label`, `LabeledContent`, `GroupBox`, `ControlGroup`, `Spacer`, `Divider`, and shapes
- PNG-backed `Image` with named-resource, local-file-URL, and embedded-byte sources plus `.resizable()`, `.scaledToFit()`, and `.scaledToFill()`
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

- The core `TerminalUI` runtime still renders one active scene into one active host per session, but it no longer decides that an authored app must declare exactly one scene.
- `TerminalUI` is now library-only. Platform integration splits between executable runner packages in `Runners/` and embedded host packages in `GUI/`.
- Embedded GUI host packages now use `TerminalUI` scene manifests plus `HostedSceneSession`, and the repository includes peer host packages at `GUI/SwiftUITUIGUI`, `GUI/SwiftTermTUIGUI`, `GUI/WebTUIGUI`, and `GUI/XtermWebTUIGUI`. Those packages still own their own platform shell integration, scene switching chrome, and style surfaces.
- Embedded GUI host packages own one active host style object at a time and
  can swap it at runtime; the root TUI app continues to render semantic tokens
  without knowing which host theme is active.
- The runtime is keyboard-first, but mouse input is supported where the terminal advertises reporting. Pointer interaction should be treated as additive rather than as the primary design center.
- Image decoding and terminal presentation are PNG-only in the current runtime. Broader media formats and animation remain deferred.
- WASI support now works with the `swiftly`-managed Swift 6.3.1 toolchain and `swiftly run swift build --swift-sdk swift-6.3.1-RELEASE_wasm ...` through the `Runners/TerminalUIWASI` / example-app build path. The shorter `swift ...` form is fine from a shell where `swift` already resolves through `swiftly`. `xcrun swift` may still resolve to an incompatible Xcode toolchain.
- Some focus surfaces are still missing:
  - namespace-scoped default-focus APIs such as `.prefersDefaultFocus(_:in:)`, `.focusScope(_:)`, and `resetFocus`
  - object-focused wrappers such as `@FocusedObject`
- Some geometry-bound preference surfaces are still deferred:
  - anchor-based preference APIs such as `anchorPreference(...)` and `transformAnchorPreference(...)` until local coordinate spaces and anchor resolution ship
- Some higher-level workflow surfaces are still unsettled:
  - richer multiline editing behaviors beyond the current `TextEditor`
- Some internal lowering seams remain package-only for runtime plumbing and tests:
  - `ViewNode`
  - `ResolvableView`

## Deferred By Design

See [VISION.md](VISION.md) for the rationale and the intended ordering.

- `NavigationStack`
- popover-style presentation beyond the current sheet support
- richer accessibility and assistive-technology modeling beyond the current semantic tree

The project now treats terminal-native reinterpretation as a first-class design
rule. The remaining gaps are therefore prioritized around terminal workspaces,
deeper scroll control, and navigation surfaces that still need a stronger
hypothesis before they graduate.

### Commands, Keybindings, and Scopes

An earlier toolbar/command-palette/help-sheet implementation was reverted
because it preceded a clear design model. The replacement is the ActionScope
model described in
[proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md)
and tracked by
[proposals/ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md](proposals/ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md).
The core model operates at a deeper level than toolbars or commands specifically.

**Commands belong to scopes. A scope is a tree-authored command set with an
activation predicate. The activation predicate is focus-chain membership.**

See
[proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md)
for the full model: the scope-kind taxonomy (`Scene`, `Presentation`, `Panel`),
shallowest-wins dispatch precedence, the scope-root-only command surface, the
hoisted toolbar-item preference contract, and the discoverability invariant.

#### Landed vs pending

The rollout follows the phased plan in
[proposals/ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md](proposals/ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md).

Landed:

- `.onKeyPress(...)` and the global `HotkeyRegistry` have been removed. The
  consumer-facing keybinding surface is now the ActionScope-based commands
  plan rather than a view modifier that writes into a global registry.
- `ActionScope` protocol, `AnyID`, and a scope-identity-keyed `CommandRegistry`
  are in place and wired into the runtime.
- `Panel` primitive plus `.panel(id:)` / `.panel()` / `.focusContainment(_:)`
  are part of the public `View` surface.
- `Scene`-conforming types and the `.alert` / `.confirmationDialog` / `.sheet`
  presentation modifiers conform to `ActionScope`, and presentation overlays
  scope-inherit scene identity.
- `.keyCommand(...)` with shallowest-wins focus-chain dispatch. Consumer-
  registered `(key, modifiers)` bindings on any `ActionScope & View` fire
  when the scope is on the current focus chain; modifier-less registrations
  are silently dropped (single-key dispatch is framework-reserved for typing,
  arrow navigation, Tab, Enter, and Escape); a disabled match consumes the
  event without firing and blocks deeper matches.
- `.paletteCommand(...)` plus `EnvironmentValues.activePaletteCommands`.
  Palette commands register at their scope's identity; after each frame the
  runtime captures the commands visible along the current focus chain and
  exposes them (ordered shallowest-first) through the environment so
  consumer-authored palette surfaces can query them.
- `.toolbar(style:)` on any `ActionScope & View`, plus the `.toolbarItem(...)`
  hoisting preference that lets any descendant view contribute an item to the
  nearest enclosing toolbar. `ToolbarStyle` plus `DefaultTopToolbarStyle` and
  `DefaultBottomToolbarStyle` control the strip's layout and placement;
  contributions bubble past intermediate scopes until absorbed, and render as
  a horizontal strip above or below the scope's content.

Framework-owned single-key dispatch continues through `LocalKeyHandlerRegistry`
for built-in controls.

#### Open design questions

The following are tracked alongside the remaining implementation phases:

- **Precedence on collisions.** If two scopes on the same chain both bind the same `(key, modifiers)` pair, shallowest wins per the landed plan. Cross-scope-kind priority beyond pure chain depth is still open.
- **State-predicated scopes still tree-author.** Selection-like state lives on some node; the anchor is that node. What differs is the activation predicate, not the authoring site.
- **Escape-hatch risk.** A generic condition-scope would become a dumping ground. Resist a new scope kind until a real case proves the curated set insufficient.
- **Modes aren't always navigation.** Vim-style modes (insert/normal/visual) are state-predicated scopes that don't correspond to tree transitions. The model handles this, but the DSL needs state-predicate scopes as first-class, not just structural ones.

## See Also

The repository [README.md](../README.md) is the public landing page; this
document and the rest of `docs/` are the source of truth for architecture,
runtime behavior, and API governance. Per-target DocC catalogs under
`Sources/*/*.docc` are the public API guide. [docs/README.md](README.md) is
the full doc index.
