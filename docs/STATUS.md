# Status

Last updated: April 14, 2026

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
indeterminate loading are public, and toast/sheet presentation surfaces now
live in the main `View` module instead of only in earlier exploratory work.

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
- WASI support now works with the `swiftly`-managed Swift 6.3.0 toolchain and `swiftly run swift build --swift-sdk swift-6.3-RELEASE_wasm ...` through the `Runners/TerminalUIWASI` / example-app build path. The shorter `swift ...` form is fine from a shell where `swift` already resolves through `swiftly`. `xcrun swift` may still resolve to an incompatible Xcode toolchain.
- Some focus surfaces are still missing:
  - namespace-scoped default-focus APIs such as `.prefersDefaultFocus(_:in:)`, `.focusScope(_:)`, and `resetFocus`
  - object-focused wrappers such as `@FocusedObject`
- Some geometry-bound preference surfaces are still deferred:
  - anchor-based preference APIs such as `anchorPreference(...)` and `transformAnchorPreference(...)` until local coordinate spaces and anchor resolution ship
- Some higher-level workflow surfaces are still unsettled:
  - richer multiline editing behaviors beyond the current `TextEditor`
  - toolbar, command, and keybinding surfaces (see hypothesis below)
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

### Commands, Keybindings, and Toolbar Hypothesis

An earlier toolbar/command-palette/help-sheet implementation was reverted
because it preceded a clear design model. The current hypothesis:

**Navigation chrome (toolbar/nav bar) is the correct keybinding surface.**
The toolbar is always rendered while its context is on screen, scoped by the
navigation/presentation stack, and visible to the user as a discoverability
surface. This is the terminal analogue of the macOS menu bar.

The design rests on four requirements that must be satisfied simultaneously:

- **Lifetime** — the toolbar is always resolved while its context is on screen, so bindings don't silently vanish
- **Locality** — shortcuts are declared alongside toolbar content, the natural co-location point
- **Composability** — the navigation/presentation stack provides scoping and shadowing (push adds, pop restores, modal overrides)
- **Discoverability** — the toolbar IS the visible hint of what's available

SwiftUI solves this with `commands { }` at scene level, `@FocusedValue` for
bridging state from focused views, and the menu bar as persistent chrome. In
a terminal UI, the navigation bar serves the same structural role as the menu
bar — it is the chrome of the current context.

`.onKeyPress()` remains as a low-level escape hatch for "handle this key
while this specific view is rendered." It is not the primary keybinding API.

This hypothesis has not yet been implemented. The framework currently has
`.onKeyPress()` (global hotkey registry, tree-lifetime-dependent) and the
`LocalKeyHandlerRegistry` (focus-dependent, package-internal, used by built-in
controls). Neither satisfies all four requirements above.

## Documentation Status

- Public module DocC catalogs now exist per target and should be treated as the public API guide
- The repository `README.md` is the public landing page
- The Markdown files in `docs/` remain the source of truth for architecture, runtime behavior, and API governance

## Reference Docs

- [ARCHITECTURE.md](ARCHITECTURE.md): target boundaries and frame pipeline
- [RUNTIME.md](RUNTIME.md): runtime behavior, lifecycle semantics, and incremental rendering
- [HOST_PACKAGES.md](HOST_PACKAGES.md): runner-package and embedded-host packaging model
- [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md): current source ownership map
- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md): classified public surface inventory
- [PUBLIC_SURFACE_POLICY.md](PUBLIC_SURFACE_POLICY.md): future API governance rules
- [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md): fixture and regression policy
