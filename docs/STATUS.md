# Status

Last updated: March 28, 2026

## Product Status

The core terminal UI stack is implemented and regression-tested across the full frame pipeline:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

The package is already usable for real terminal interfaces. The main gaps are not around the fundamental pipeline anymore; they are around breadth of surface area, app-launch ergonomics, and a few still-conservative runtime paths.

## Shipped Surface

### Authoring surface

- SwiftUI-shaped `View` authoring with body-only `View`, `@ViewBuilder`, `TupleView`, `ConditionalContent`, `AnyView`, and `Resolver`
- Layout and containers including `VStack`, `HStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `ViewThatFits`, `GeometryReader`, and custom `Layout`
- Controls and primitives including `Text`, `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `SecureField`, `DisclosureGroup`, `Picker`, `Menu`, `ProgressView`, `Label`, `LabeledContent`, `GroupBox`, `ControlGroup`, `Spacer`, `Divider`, and shapes
- PNG-backed `Image` with named-resource, local-file-URL, and embedded-byte sources plus `.resizable()`, `.scaledToFit()`, and `.scaledToFill()`
- Environment, observation, and focus including `@State`, `@Binding`, repo-owned `@Bindable`, `@FocusState`, `FocusedValues`, `@FocusedValue`, `@FocusedBinding`, and default-focus modifiers

### Runtime surface

- `DefaultRenderer` for one-shot rendering and pipeline inspection
- `RunLoop` for interactive terminal sessions
- `TerminalHost`, terminal appearance detection, graphics-capability probing, and capability-aware presentation
- Keyboard parsing, mouse input parsing, Unix signal handling, and runtime scheduling
- Identity-driven lifecycle diffs with post-present appear, disappear, task start, and task cancel staging
- Kitty and Sixel image presentation with ANSI or ASCII fallback compositing when graphics protocols are unavailable

### Scene and multi-scene surface

- `App`, `Scene`, `SceneBuilder`, and `WindowGroup` declarations in `TerminalUI`
- `MultiSceneLauncher` in `TerminalUIScenes` for public scene launch, including the single-window case today
- Pty-backed secondary scenes, Unix-domain-socket discovery, scene attachment, and lazy rendering of unattached secondary scenes

### Charts

- `BarChart`, `ColumnChart`, `ComparisonChart`, `Sparkline`, `Timeline`, `ThresholdGauge`, `BulletChart`, `Meter`, `Legend`, `HeatStrip`, and `StackedBarChart`

## Current Constraints

- The core `TerminalUI` runtime remains single-host and single-scene. The multi-scene story lives in the separate `TerminalUIScenes` product.
- The public scene launch path currently goes through `TerminalUIScenes.MultiSceneLauncher`, even when an app only has one `WindowGroup`.
- The runtime is keyboard-first, but mouse input is supported where the terminal advertises reporting. Pointer interaction should be treated as additive rather than as the primary design center.
- Image decoding and terminal presentation are PNG-only in the current runtime. Broader media formats and animation remain deferred.
- Some focus surfaces are still missing:
  - namespace-scoped default-focus APIs such as `.prefersDefaultFocus(_:in:)`, `.focusScope(_:)`, and `resetFocus`
  - object-focused wrappers such as `@FocusedObject`
- Some internal lowering seams remain package-only for runtime plumbing and tests:
  - `ViewNode`
  - `ResolvableView`

## Deferred By Design

See [VISION.md](VISION.md) for the rationale and the intended ordering.

- `NavigationStack` and `NavigationSplitView`
- `Toolbar` and `ToolbarItem`
- alerts, confirmation dialogs, sheets, and popover-style presentation
- richer accessibility and assistive-technology modeling beyond the current semantic tree

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
