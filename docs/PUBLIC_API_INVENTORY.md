# Public API Inventory

This page is the post-migration reference for the public surface of the package. It separates the canonical SwiftUI-shaped API and actor-isolation model from package-only seams that still exist in the codebase.

> **Companion artefacts.** A machine-generated, complete enumeration of every public Swift symbol — derived from `swift package dump-symbol-graph` and classified through [`docs/public_api_overrides.yml`](public_api_overrides.yml) — lives in [`PUBLIC_API_BASELINE.md`](PUBLIC_API_BASELINE.md) (curated grouping) and [`.public-api-baseline.txt`](.public-api-baseline.txt) (flat sorted list, the machine-grep target). Both are committed and regenerated via `Scripts/generate_public_api_inventory.sh`. PRs that add or remove a public symbol see the change in those files.
>
> This inventory remains the prose reference: it explains *why* the API is shaped the way it is and groups symbols by purpose. The baseline answers "is symbol X public?" — this doc answers "should I be using X?".

## How To Read This

- **Canonical public surface** means the API new app code should use first.
- **Migration note** means the symbol or behavior changed in the cleanup that internalized view lowering.
- **Test-support or internal seam** means the symbol should not shape ordinary app authoring, even if some tests still need it.

## Canonical Public Surface

### `View`

The canonical authoring surface is the SwiftUI-shaped one:

- `View`, `ViewBuilder`, `AnyView`, `TupleView`, `ConditionalContent`, `VariadicView`, `EmptyView`, `Text`, `TextFigure`, `Link`, `Image`, `Spacer`, `Divider`, `Group`
- modifier algebra through `ViewModifier`, `View.modifier(_:)`, and `ModifiedContent`
- text layout enums and interpolation support exposed through `Text`, including `Text.TruncationMode`, `Text.WrappingStrategy`, and rich interpolation of embedded `Text` and `Link` segments
- banner-style text rendering through `TextFigure`, including enum-backed embedded-font selection through `TextFigure.Font` and discovery through `TextFigure.availableFonts`
- `VStack`, `HStack`, `LazyVStack`, `LazyHStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `GeometryReader` (`LazyVStack` and `LazyHStack` support viewport-lazy placement and single-`ForEach` full-lazy rows)
- `Tab`, `TabView`, `NavigationStack`
- `Label`, `LabeledContent`, `GroupBox`, `ControlGroup`, `ViewThatFits`, `AnyLayout`
- `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `TextEditor`, `SecureField`, `Picker`, `Menu`, `DisclosureGroup`, `ProgressView`, `Spinner`
- `ToastStyle`
- `Layout`, `SendableLayout`, `LayoutValueKey`, `Binding`, `EnvironmentValues`, `EnvironmentKey`, `EnvironmentReader`, `FocusedValues`, `FocusedValueKey`, `PreferenceKey`, `Anchor`, `AnchorSource`, `FocusInteractions`, `LinkDestination`, `OpenLinkAction`, and `ResetFocusAction`
- image-source and runtime-policy environment configuration such as
  `EnvironmentValues.imageResourceRoots` and
  `EnvironmentValues.accessibilityReduceMotion`
- `@State`, `@Binding`, `@FocusState`, `@FocusedValue`, `@FocusedBinding`, and repo-owned `@Bindable`
- canonical layout and styling modifiers such as `.frame(...)`, `.padding(...)`, `.offset(...)`, `.layoutPriority(...)`, `.fixedSize(...)`, `.lineLimit(...)`, `.truncationMode(...)`, `.textWrappingStrategy(...)`, `.clipped()`, `.background(...)`, `.overlay(...)`, `.preference(key:value:)`, `.transformPreference(...)`, `.anchorPreference(key:value:transform:)`, `.transformAnchorPreference(_:value:transform:)`, `.onPreferenceChange(...)`, `.backgroundPreferenceValue(...)`, `.overlayPreferenceValue(...)`, `.semanticMetadata(...)`, `.drawMetadata(...)`, `.focusable(...)`, `.focusable(interactions:)`, `.focused(...)`, `.defaultFocus(...)`, `.prefersDefaultFocus(_:in:)`, `.focusedValue(...)`, `.focusedSceneValue(...)`, `.focusEffectDisabled()`, `.focusScope()`, `.focusScope(_:)`, `.focusSection()`, `.onChange(of:initial:_:)`, `.alert(...)`, `.confirmationDialog(...)`, `.sheet(...)`, `.toast(...)`, `.navigationDestination(isPresented:)`, `.navigationDestination(item:)`
- `Resolver` and the public `ResolveContext` configuration surface for low-level rendering entry points
- low-level `Standard` output/file helpers and `FileOpenError` for runtime
  integration paths that need direct stream writes

Important public-surface rules after the lowering migration:

- `View` is body-only. It has no `Body = Never` default and no broad
  `extension View` body witness.
- Primitive lowering remains package-only. Framework primitives opt into
  `PrimitiveView` or a view-like protocol such as `Shape`; values that lower
  directly opt into `ResolvableView`; primitive modifiers opt into
  `PrimitiveViewModifier` or explicitly set `Body == Never`.
- `View`, `Scene`, and `App` are `@MainActor` authoring protocols.
- APIs that evaluate authored `body` trees, including `Resolver.resolve(...)` and `DefaultRenderer.render(...)`, are `@MainActor`.
- Callback-bearing authoring APIs follow the same model: `Binding.init(get:set:)` and `.task(...)` use actor-inheriting closure signatures, while button actions, `OpenLinkAction` over typed `LinkDestination`s, `.onAppear`, `.onDisappear`, and `.onChange(of:initial:_:)` stay explicitly `@MainActor`. In ordinary authored view code those all still resolve to main-actor authoring because `View.body` is `@MainActor`.
- Dynamic-property callbacks preserve the graph-scoped state identity captured
  at registration time. `DefaultRenderer` still preserves same-instance
  snapshot behavior when no invalidating runtime graph exists.
- `ViewBuilder` no longer exposes `[AnyView]` in public closure signatures.
- `AnyView` remains public as `View` erasure, but `AnyView.init(erasing:)` is no longer public.
- Anchor preferences are ordinary reduced preferences that carry opaque
  `Anchor<Rect>` or `Anchor<Point>` tokens. Resolve them inside
  `GeometryReader` using `GeometryProxy[anchor]`; use `GeometryProxy.frame(in:)`
  for `.local`, `.global`, and `.named(_)` coordinate-space frames.
- Public custom layouts run through the main-actor custom-layout bridge unless
  they explicitly conform to `SendableLayout`, which requires the layout value
  and its cache to be `Sendable` and requires stable measurement and placement
  reuse signatures before the renderer may evaluate that layout on the
  frame-tail worker.

### Accessibility

The shipped accessibility surface is semantic-first; see
[`ACCESSIBILITY.md`](ACCESSIBILITY.md) for target behavior.

- `AccessibilityRole`, `AccessibilityPoliteness`, `AccessibilityNode`, and
  `AccessibilityAnnouncement` define the public semantic records consumed by
  terminal accessible output, Web/WASI ARIA, embedded WebHost ARIA, and the
  SwiftUI host overlay.
- Authoring modifiers include `.accessibilityRole(_)`,
  `.accessibilityLabel(_)`, `.accessibilityHint(_)`,
  `.accessibilityHidden(_)`, `.accessibilityLiveRegion(_)`, and
  `.accessibilityCursorAnchor(_)`.
- `AccessibilityAnnouncer.announce(_:politeness:)` sends app-triggered
  announcements to the active runtime accessibility target.
- `EnvironmentValues.accessibilityReduceMotion` mirrors the resolved runtime
  motion policy and can be overridden by authored views.

### Shapes, borders, and styling

The canonical shape / border / gradient surface as of the Milestone 7 shape-and-border revamp:

- **Shape primitives** (`Core` + `View`): `Rectangle`, `RoundedRectangle`, `Capsule`, `Circle`, `Ellipse`, and the `Shape` / `InsettableShape` protocols. Custom shapes contribute by returning one of the `ShapeGeometry` cases (`.rectangle`, `.roundedRectangle(cornerRadius:)`, `.circle`, `.ellipse`, `.capsule`) or by dropping to `Canvas`.
- **Stroke and fill**: `Shape.fill(_:)`, `Shape.stroke(_:style:)`, `Shape.stroke(_:style:background:)`, `Shape.strokeBorder(_:style:)`, `Shape.strokeBorder(_:style:background:)` — all accept `some ShapeStyle` for the paint. `StrokeStyle` stores `lineWidth: Int`, `borderSet: BorderSet`, and `placement: StrokeStyle.Placement`; the legacy `LineVariant` enum is gone.
- **Static `StrokeStyle` presets**: `.rounded`, `.heavy`, `.single`, `.double`, `.ascii`, `.block`, `.innerHalfBlock`, `.hidden`, `.markdown` — each backed by the matching `BorderSet`.
- **`BorderSet`** (`Core`): public struct with per-edge, per-corner, and per-join `String` fields. Placement is intentionally separate and lives on `StrokeStyle.Placement` (`.outset` or `.inset`). Multi-rune edges give free dashed/patterned borders via per-cell cycling. Built-ins: `.single`, `.rounded`, `.double`, `.heavy`, `.block`, `.outerHalfBlock`, `.innerHalfBlock`, `.singleDouble`, `.doubleSingle`, `.ascii`, `.hidden`, `.none`, `.dashed`, `.dashedHeavy`, `.markdown`.
- **`BorderEdgeStyle`** (`Core`): per-side foreground shape styles for borders (`top`, `right`, `bottom`, `left`) with CSS-shorthand initializers (1 / 2 / 3 / 4 values).
- **`BorderBackgroundStyle`** (`Core`): per-side background shape styles for borders, with the same CSS-shorthand initializers.
- **`BorderBlend`** (`Core`): perimeter 1D gradient sampled clockwise around a rectangle, with an animatable `phase` for chasing-light borders.
- **`.border(...)` view modifiers**: three overloads — uniform style + `BorderSet` + placement, per-side `BorderEdgeStyle` + `BorderSet` + placement, and perimeter `BorderBlend` + `BorderSet` + placement + animatable `phase`. All three route through the layout-aware border path so `.outset` borders reserve frame insets while `.inset` borders intentionally draw into the content frame's outer cells.
- **Gradient / tile paints**: `LinearGradient`, `RadialGradient`, `TileStyle` (`░▒` checker shading, single-glyph shading, and optional background). All conform to `ShapeStyle` and are sampled per-cell at rasterization time. As of the April 13, 2026 Animatable-protocol migration `LinearGradient.startPoint` / `endPoint` and `RadialGradient.center` are typed as `UnitPoint` instead of `Alignment` (see below).
- **`Canvas<Drawing>`**, `CanvasDrawing`, `CanvasClosureDrawing`, and `CanvasContext` (`Core` + `View`): arbitrary drawing escape hatch for content the `Shape` algebra can't express (sparklines, plots, hand-drawn glyphs, and dense pixel grids). The context supports the original 2×4 Braille-subpixel drawing APIs, styled Braille `setPixel` for one foreground/background per terminal cell, and direct terminal-cell writes via `setCell`, `fillCell`, and `clearCell`. `Canvas { ... }` uses identity-based equality for ad-hoc closure drawing; use a value `CanvasDrawing` type when structural equality and renderer deduplication matter.
- **Canvas pixel grids** (`Core` + `View`): `CanvasPixelGridDrawing` renders row-major `[Color?]` buffers through `Canvas`, with `CanvasPixelGridMode.fullCell` for one logical pixel per terminal cell and `.verticalHalfBlock` for two vertical logical pixels per terminal cell. `Canvas(pixelGridWidth:height:pixels:mode:)` is the public authoring initializer. Pixel-exact Canvas grids are intentionally not public until a buffer-backed graphics renderer exists.

### Authoring style families

The repo is mid-migration from enum-owned control and container styling to
public, extensible style protocols.

- **Protocol-backed style families today**: `ShapeStyle`, `ToolbarStyle`,
  `ButtonStyle`, `TextFieldStyle`, `PickerStyle`, `ListStyle`,
  `OutlineStyle`, `ToastStyle`, and `TabViewStyle`.
- **Type-erased style storage**: `AnyShapeStyle`, `AnyButtonStyle`,
  `AnyTextFieldStyle`, `AnyPickerStyle`, `AnyListStyle`, `AnyOutlineStyle`,
  `AnyToastStyle`, and `AnyTabViewStyle` are the concrete values used where
  environment or modifier plumbing needs a non-generic stored style.

Migration note:

- New authoring-facing `*Style` APIs should prefer public style protocols plus
  type-erased environment storage. Enum-backed authoring style families are not
  part of the intended public design.

### Animation primitives and `Animatable` conformance

The animation pipeline now follows the SwiftUI-shaped `Animatable`-protocol model (see `docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md`). The new public surface is:

- **`Animatable`** (`Core`): the SwiftUI-shaped protocol that exposes an `animatableData: AnimatableData` round-trip for any type that wants to participate in interpolation. Built-in conformances cover all paint and geometry types the controller needs to interpolate.
- **`AnimatablePair<First, Second>`** (`Core`): the standard pair combinator for composing two `Animatable` values into a single `animatableData` round-trip.
- **`AnimatableArray<Element>`** (`Core`): an ordered, fixed-length array of `Animatable` elements that itself conforms to `Animatable`, used by gradients to interpolate their stops list and by any other variable-arity collection of animatable values. Length mismatches between the source and target snap to the target rather than interpolating, matching SwiftUI's behavior.
- **`UnitPoint`** (`Core`): continuous unit-square coordinate (`x ∈ [0, 1]`, `y ∈ [0, 1]`) with named-corner static initializers (`.topLeading`, `.center`, `.bottomTrailing`, etc.). Used by `LinearGradient.startPoint`, `LinearGradient.endPoint`, and `RadialGradient.center`. Conforms to `Animatable` so gradient orientations interpolate continuously under `withAnimation`. Coexists with `Alignment`, which remains the named-slot type for stack/overlay/background alignment parameters.
- **`EdgeInsets`** (`Core`): now conforms to `Animatable`, so `.padding(...)` and frame-inset values interpolate componentwise.
- **`Color`** (`Core`): conforms to `Animatable` via OKLab interpolation, so `.foregroundStyle(color)` and any other `Color`-typed value interpolates perceptually.
- **`Gradient.Stop`, `Gradient`, `LinearGradient`, `RadialGradient`** (`Core`): all conform to `Animatable`. Compound conformance flows through `AnimatablePair` and `AnimatableArray` so gradient stops, locations, colors, and endpoints all interpolate together.
- **`TileStyle`** (`Core`): variant-aware `Animatable` participation through helper functions on `TileStyle.Paint` so a tile style whose foreground or background is a gradient animates the interior of that gradient continuously, while tile paints that change variant (e.g. flat color → gradient) snap.

The animation authoring surface (`Animation`, `withAnimation`, `PhaseAnimator`, `.transition`, `matchedGeometryEffect`, completion closures) is unchanged and continues to live in `View`.

Removed from the public surface in this revamp:

- `LineVariant` — deleted wholesale, no deprecation shim. The rasterizer now reads glyphs from `BorderSet`. `StrokeStyle(lineVariant:)` is replaced by `StrokeStyle(borderSet:)`.
- `BorderSet.Placement` / `BorderSet.placement` — placement is now owned by `StrokeStyle.Placement`.
- `BorderSet.presentationChrome`, `StrokeStyle.normal`, `StrokeStyle.outerHalfBlock`, and `StrokeStyle.presentationChrome` — removed as sugar duplicates. Use explicit `BorderSet` values and `StrokeStyle(borderSet:placement:)`.

### Action scopes and commands

The full ActionScope/commands rollout is public; see
[proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md)
and
[proposals/ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md](proposals/ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md)
for the model and the implementation record.

- `ActionScope` protocol (`Core`) with `AnyID` type-erased identity
- `CommandRegistry` runtime hook (`Core`), wired into `RunLoop`
- `Panel<ID, Content>` primitive plus `.panel(id:)` and `.panel()` modifiers (`View`)
- `NavigationStack<ID, Root>` primitive plus
  `.navigationDestination(isPresented:)` and `.navigationDestination(item:)`
  modifiers (`View`)
- `FocusContainment` enum plus `.focusContainment(_:)` on `Panel`
- `Scene`-conforming types conform to `ActionScope`
- `.alert` / `.confirmationDialog` / `.sheet` presentation modifiers conform to `ActionScope`
- `.keyCommand(_:key:modifiers:isEnabled:action:)` on `ActionScope where Self: View & Sendable`, with shallowest-wins dispatch along the current focus chain (modifier-less bindings are framework-reserved and silently dropped)
- `.paletteCommand(name:description:isEnabled:action:)` on `ActionScope where Self: View & Sendable` plus `ActivePaletteCommand` and `EnvironmentValues.activePaletteCommands` for consumer-authored palette query surfaces. The captured list is refreshed after each frame from the current focus chain.
- `.toolbar(style:)` on `ActionScope where Self: View & Sendable`, plus
  `ToolbarStyle` protocol, `ToolbarPlacement` enum, and the
  `DefaultTopToolbarStyle` / `DefaultBottomToolbarStyle` default styles
- `.toolbarItem(_:)` on any `View`, plus the `@ViewBuilder`-based
  `.toolbarItem(position:isEnabled:action:label:icon:)` overload, backed by
  `ToolbarItemConfig` and the hoisting preference contract that bubbles item
  contributions up to the nearest enclosing `.toolbar(style:)` modifier

### `SwiftTUI`

The runtime-facing public surface is also canonical:

- `DefaultRenderer`
- `RunLoop`
- `RuntimeConfiguration`, including output, glyph/color/motion policy, web
  serving configuration, and opt-in `cursorFollowsFocus` behavior
- `ResolveContext` as external renderer or resolver configuration only
- terminal host, sanitized presentation, graphics-capability, and input or
  signal integration types that support the runtime
- app and scene entry points, including `App`, `Scene`, `SceneBuilder`, `WindowGroup`, `WindowIdentifier`, and the typed scene builder artifacts
- `AnyScene` as the explicit scene-erasure escape hatch
- `SceneDescriptor`
- `SceneManifest`
- `HostedSceneSession`

### `AnimatedImage`

The peer animated-image product is canonical for finite, pre-composed animated
image playback and GIF import/export:

- `AnimatedImage`
- `AnimatedImageSequence`
- `AnimatedImageFrame`
- `AnimatedImagePixel`
- `AnimatedGIF`

This module owns GIF encoding and decoding. It intentionally exposes frame-list
initializers keyed by `framesPerSecond` or explicit `frameDelays`, not
closure-based frame producers.

### Peer platform integration packages

Platform-specific execution and embedding are intentionally outside the root
package surface:

- executable runner packages:
  - `Platforms/CLI` exposes `TerminalRunner` plus the default terminal-native `App.main()` story
  - `Platforms/WASI` exposes `WASIRunner` plus the default WASI `App.main()` story
  - `Platforms/WebHost` exposes `WebHostRunner`, `WebHostConfig`, and
    `WebHostRunnerError` for web-only localhost-browser launch
  - `Platforms/WebHost` also exposes the `SwiftTUIWebHostCLI` product with
    `WebHostCLIRunner` for binaries that intentionally combine terminal and
    WebHost behavior
- embedded host packages:
  - `Platforms/SwiftUI` hosts retained `HostedSceneSession` values inside a SwiftUI app shell on a native raster surface
  - `Platforms/Web` hosts a `SwiftTUIWASI` build in the browser using the same manifest and hosted-session story, drawing raster output onto a canvas via the `web-surface` transport

`Platforms/WebHost` is compound: its runner starts a localhost browser host
that serves a bundled browser runtime from the native process and drives it over
the shared `web-surface` v2 WebSocket protocol.

These are supported peer packages, but they are not root library products in
`Package.swift`.

The WebHost surface is compile-time opt-in. A terminal-only app that imports
only `SwiftTUICLI` links no WebHost server, FlyingFox dependency, or browser
bundle, and web mode is rejected before raw-mode setup. A web-capable app must
depend on `SwiftTUIWebHost` or `SwiftTUIWebHostCLI` explicitly.

### `Core`

The core data model and pipeline types are canonical:

- geometry, layout, semantic, draw, raster, scheduler, diagnostics, and commit data types
  - **`CellPixelMetrics`**: read-only display metrics describing how cells map to device pixels. Exposes `width`, `height`, `source` (`.reported` / `.estimated`), derived `aspectRatio`, and the `.estimated` fallback constant. Consumed via `GeometryProxy.cellPixelMetrics` and `EnvironmentValues.cellPixelMetrics`.
- image payload, resolved-asset, and raster-image-attachment data types used by the rendering pipeline
- the layout engine, rasterizer, scheduler, semantic extractor, draw extractor, snapshot renderer, and commit planner
- the incremental presentation and retained-frame machinery that the runtime depends on

`Core` is currently target-level infrastructure re-exported through
`SwiftTUI`, not a separate library product.

## Removed From The Public Surface

These migration-era APIs are no longer public:

- `ViewNode`
- `AnyViewNode`
- `Leaf`
- `AnyView.init(erasing:)`
- `Package`
- `Package.makeResolver()`
- `Package.makeViewResolver()`
- `Package.makeNoOpRenderer()`
- `StateViewBuilder`
- the `AnyViewNode`-based `RunLoop` initializer
- `DefaultRenderer.render<V: ViewNode>`
- concrete wrapper-view implementation types such as `IDView`, `PaddingView`,
  `FrameView`, `OverlayView`, `BackgroundView`, and `TagValueView`
- runtime registry and replay types such as `LocalActionRegistry`, `LocalKeyHandlerRegistry`, `LocalLifecycleRegistry`, `LocalTaskRegistry`, `TaskRegistration`, `LifecycleHandlerSnapshot`, and `LocalKeyEvent`
- keyboard-help compatibility APIs such as `KeyboardShortcut`, `KeyboardShortcutGroup`, `KeyboardShortcutHelpView`, `.keyboardShortcut(...)`, and `.keyboardShortcutHelp(...)`
- the global hotkey registration seam: `.onKeyPress(...)` view modifier, `HotkeyRegistry`, `HotkeyBinding`, and `HotkeyRegistrationSnapshot`. Consumers now bind keys through the ActionScope-based commands surface (see [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md)); the replacements — `.keyCommand`, `.paletteCommand`, `.toolbar`, and `.toolbarItem` — ship on the public `View` surface.
- generic presentation coordination surface such as `PresentationFamilyID`, `PresentationLaneID`, `PresentationFamilySelectionPolicy`, `PresentationLaneOrdering`, `PresentationLaneVisibilityPolicy`, `PresentationBackgroundInteraction`, `PresentationFamilyPolicy`, `PresentationLanePolicy`, `PresentationCoordinatorConfiguration`, `PresentationPlacementContext`, `.presentationCoordinator(...)`, and `.presentation(...)`

### Removed Public Styling Compatibility

The old public styling shims from `View` are gone:

- `EnvironmentValues.theme`
- string-based style helpers such as `foregroundStyle(_ style: String)`, `backgroundStyle(_ style: String)`, and `borderStyle(_ style: String)`

Low-level styling support such as `Theme` remains public in `Core`, but it is no longer part of the main `View` authoring story.

### Package-Only Transitional Seams

These symbols still exist for internal reuse, diagnostics, or narrow package-local compatibility, but they are no longer part of the public API story:

- `PrimitiveView`
- `ResolvableView`
- `ViewNode`
- the local runtime registries and lifecycle replay helpers used by `RunLoop`
- primitive modifier-lowering hooks such as `PrimitiveViewModifier` and `ModifierContentInputs`

## Test-Support And Internal Seams

The repo still contains tests that exercise low-level construction or reuse behavior directly. Those tests are valid, but they should be isolated as internal-seam coverage rather than presented as ordinary app code.

Current examples include:

- resolve-reuse probes that need direct access to package-only `ResolveContext` helpers
- lifecycle and handler replay tests that validate post-resolve internal registries
- commit-boundary coverage that exists only to prove staged commit-plan compatibility

## Experimental And Showcase Targets

Prototype and showcase code may still live in the repository as sibling example packages for demos, experiments, and regression coverage, but that does not make it part of the supported product surface.

Current rule:

- sibling example packages and demos may exist for experiments or regression coverage, but they are not supported package products
- README and architecture-facing docs should describe showcase code as secondary when it appears at all
- terminal-native interaction surfaces that are still being shaped should not force premature API commitments onto `View`

## Policy Summary

- New app-facing docs should use the canonical surface first.
- Package-only seams should not be promoted as ordinary examples.
- If a new feature can be expressed on `View`, it should usually be documented there rather than through `*` construction.
- If a new public symbol is added, it should be classified here before it becomes the default example in the README or architecture docs.
- SwiftUI-shaped APIs may intentionally reinterpret behavior toward
  terminal-native defaults when a literal desktop translation would degrade the
  TUI experience.
