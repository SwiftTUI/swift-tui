# Status

Last updated: April 1, 2026

## Product Status

The core terminal UI stack is implemented and regression-tested across the full frame pipeline:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

The package is already usable for real terminal interfaces. The main gaps are
not around the fundamental pipeline anymore; they are around breadth of surface
area, app-shell ergonomics, and a few still-conservative runtime paths.

The terminal-native roadmap work described in
[TERMINAL_NATIVE_ROADMAP.md](TERMINAL_NATIVE_ROADMAP.md) is now substantially
landed: automatic chrome has been reset, shell navigation primitives are
canonical, multiline editing and indeterminate loading are public, and the
example apps now teach pane-oriented workspaces instead of scrolled component
pages.

## Shipped Surface

### Authoring surface

- SwiftUI-shaped `@MainActor`-isolated `View` authoring with body-only `View`, `@ViewBuilder`, `TupleView`, `ConditionalContent`, `AnyView`, and `Resolver`
- Layout and containers including `VStack`, `HStack`, `LazyVStack`, `LazyHStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `ViewThatFits`, `GeometryReader`, and custom `Layout`, with `LazyVStack` and `LazyHStack` supporting viewport-lazy placement and single-`ForEach` full-lazy rows
- Controls and primitives including `Text`, rich `Text` interpolation, `Link`, `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `TextEditor`, `SecureField`, `DisclosureGroup`, `Picker`, `Menu`, determinate and indeterminate `ProgressView`, `Label`, `LabeledContent`, `GroupBox`, `ControlGroup`, `Spacer`, `Divider`, and shapes
- PNG-backed `Image` with named-resource, local-file-URL, and embedded-byte sources plus `.resizable()`, `.scaledToFit()`, and `.scaledToFill()`
- Environment, observation, and focus including `@State`, `@Binding`, repo-owned `@Bindable`, `@FocusState`, `FocusedValues`, `@FocusedValue`, `@FocusedBinding`, `PreferenceKey`, subtree preference readers, `OpenLinkAction`, actor-context-aware `.task(...)`, and default-focus modifiers
- Toolbar chrome including `toolbar(...)`, `toolbarItem(...)`, and `toolbarStyle(.default)` for terminal-native top and bottom bars

### Runtime surface

- `DefaultRenderer` for one-shot rendering and pipeline inspection from the main actor
- `RunLoop` for interactive terminal sessions
- `TerminalHost`, terminal appearance detection, graphics-capability probing, capability-aware presentation, and OSC 8 hyperlink emission when supported
- host-owned `ThemeColors` and paired `TerminalRenderStyle` updates so hosted
  sessions and browser/WASI runtimes can switch semantic themes at runtime
- Keyboard parsing, mouse input parsing, Unix signal handling, and runtime scheduling
- Identity-driven lifecycle diffs with post-present appear, disappear, task start, and task cancel staging
- Kitty and Sixel image presentation with ANSI or ASCII fallback compositing when graphics protocols are unavailable

### Scene and multi-scene surface

- `@MainActor` `App`, `Scene`, `SceneBuilder`, `WindowIdentifier`, and `WindowGroup` declarations in `TerminalUI`
- `MultiSceneLauncher` in `TerminalUIScenes` for public scene launch, including the single-window case today
- `TerminalUISceneDescriptor`, `TerminalUISceneManifest`, and `MultiSceneLauncher.sceneManifest(...)` for wrapper tooling and non-terminal packaging
- `HostedSceneSession` for embedding a retained `WindowGroup` runtime inside non-terminal hosts
- Pty-backed secondary scenes, Unix-domain-socket discovery, scene attachment, and lazy rendering of unattached secondary scenes
- `TabView` and `NavigationSplitView` for terminal-native shell composition
- terminal-native `alert` and `confirmationDialog` presentation in the canonical `View` surface

### Charts

- `BarChart`, `ColumnChart`, `ComparisonChart`, `Sparkline`, `Timeline`, `ThresholdGauge`, `BulletChart`, `Meter`, `Legend`, `HeatStrip`, and `StackedBarChart`

## Current Constraints

- The core `TerminalUI` runtime remains single-host and single-scene. The multi-scene story lives in the separate `TerminalUIScenes` product.
- The public scene launch path currently goes through `TerminalUIScenes.MultiSceneLauncher`, even when an app only has one `WindowGroup`.
- Embedded GUI wrappers can now host retained scene runtimes through `HostedSceneSession`, and the repository now includes peer wrapper packages at `GUI/SwiftUITUIGUI` and `GUI/WebTUIGUI`. Those packages still own their own platform shell integration, scene switching chrome, and style surfaces.
- Embedded GUI wrappers intentionally own the mapping from host light/dark mode
  to explicit theme variants; the root TUI app continues to render semantic
  tokens without knowing which wrapper theme is active.
- The runtime is keyboard-first, but mouse input is supported where the terminal advertises reporting. Pointer interaction should be treated as additive rather than as the primary design center.
- Image decoding and terminal presentation are PNG-only in the current runtime. Broader media formats and animation remain deferred.
- WASI support now works with the `swiftly`-managed Swift 6.3.0 toolchain and `swiftly run swift build --swift-sdk swift-6.3-RELEASE_wasm ...` for the wrapper-facing `Core` and `TerminalUIScenes` targets. The shorter `swift ...` form is fine from a shell where `swift` already resolves through `swiftly`. `xcrun swift` may still resolve to an incompatible Xcode toolchain.
- Some focus surfaces are still missing:
  - namespace-scoped default-focus APIs such as `.prefersDefaultFocus(_:in:)`, `.focusScope(_:)`, and `resetFocus`
  - object-focused wrappers such as `@FocusedObject`
- Some geometry-bound preference surfaces are still deferred:
  - anchor-based preference APIs such as `anchorPreference(...)` and `transformAnchorPreference(...)` until local coordinate spaces and anchor resolution ship
- Some higher-level workflow surfaces are still unsettled:
  - richer multiline editing behaviors beyond the current `TextEditor`

Prototype command-palette surfaces still exist in the repo-local
`PrototypeUIComponents` target, but the old help-strip API has been retired in
favor of the supported toolbar surface.
- Some internal lowering seams remain package-only for runtime plumbing and tests:
  - `ViewNode`
  - `ResolvableView`

## Deferred By Design

See [VISION.md](VISION.md) for the rationale and the intended ordering.

- `NavigationStack`
- sheets and popover-style presentation
- richer accessibility and assistive-technology modeling beyond the current semantic tree

The project now treats terminal-native reinterpretation as a first-class design
rule. The remaining gaps are therefore prioritized around terminal workspaces,
deeper scroll control, and navigation surfaces that still need a stronger
hypothesis before they graduate.

## Documentation Status

- Public module DocC catalogs now exist per target and should be treated as the public API guide
- The repository `README.md` is the public landing page
- The Markdown files in `docs/` remain the source of truth for architecture, runtime behavior, and API governance

## Reference Docs

- [ARCHITECTURE.md](ARCHITECTURE.md): target boundaries and frame pipeline
- [RUNTIME.md](RUNTIME.md): runtime behavior, lifecycle semantics, and incremental rendering
- [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md): current source ownership map
- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md): classified public surface inventory
- [PUBLIC_SURFACE_POLICY.md](PUBLIC_SURFACE_POLICY.md): future API governance rules
- [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md): fixture and regression policy
