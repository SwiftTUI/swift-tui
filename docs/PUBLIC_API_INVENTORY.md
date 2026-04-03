# Public API Inventory

Last updated: March 30, 2026

This page is the post-migration reference for the public surface of the package. It separates the canonical SwiftUI-shaped API and actor-isolation model from package-only seams that still exist in the codebase.

## How To Read This

- **Canonical public surface** means the API new app code should use first.
- **Migration note** means the symbol or behavior changed in the cleanup that internalized view lowering.
- **Test-support or internal seam** means the symbol should not shape ordinary app authoring, even if some tests still need it.

## Canonical Public Surface

### `View`

The canonical authoring surface is the SwiftUI-shaped one:

- `View`, `ViewBuilder`, `AnyView`, `TupleView`, `ConditionalContent`, `VariadicView`, `EmptyView`, `Text`, `Link`, `Image`, `Spacer`, `Divider`, `Group`
- text layout enums and interpolation support exposed through `Text`, including `Text.TruncationMode`, `Text.WrappingStrategy`, and rich interpolation of embedded `Text` and `Link` segments
- `VStack`, `HStack`, `LazyVStack`, `LazyHStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `GeometryReader` (`LazyVStack` and `LazyHStack` support viewport-lazy placement and single-`ForEach` full-lazy rows)
- `TabItemLabel`, `TabView`, `NavigationSplitView`
- `Label`, `LabeledContent`, `GroupBox`, `ControlGroup`, `ViewThatFits`, `AnyLayout`
- `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `TextEditor`, `SecureField`, `Picker`, `Menu`, `DisclosureGroup`, `ProgressView`
- `Layout`, `LayoutValueKey`, `Binding`, `EnvironmentValues`, `EnvironmentKey`, `EnvironmentReader`, `FocusedValues`, `FocusedValueKey`, `PreferenceKey`, `FocusInteractions`, `LinkDestination`, `OpenLinkAction`, `ToolbarPlacement`, `ToolbarAlignment`, and `ToolbarStyle`
- image-source environment configuration such as `EnvironmentValues.imageResourceRoots`
- `@State`, `@Binding`, `@FocusState`, `@FocusedValue`, `@FocusedBinding`, and repo-owned `@Bindable`
- canonical layout and styling modifiers such as `.frame(...)`, `.padding(...)`, `.layoutPriority(...)`, `.fixedSize(...)`, `.lineLimit(...)`, `.truncationMode(...)`, `.textWrappingStrategy(...)`, `.background(...)`, `.overlay(...)`, `.preference(key:value:)`, `.transformPreference(...)`, `.onPreferenceChange(...)`, `.backgroundPreferenceValue(...)`, `.overlayPreferenceValue(...)`, `.semanticMetadata(...)`, `.drawMetadata(...)`, `.focusable(...)`, `.focusable(interactions:)`, `.focused(...)`, `.defaultFocus(...)`, `.focusedValue(...)`, `.focusedSceneValue(...)`, `.focusEffectDisabled()`, `.focusScope()`, `.focusSection()`, `.toolbar(...)`, `.toolbarItem(...)`, `.toolbarStyle(...)`, `.alert(...)`, and `.confirmationDialog(...)`
- `Resolver` and the public `ResolveContext` configuration surface for low-level rendering entry points

Important public-surface rules after the lowering migration:

- `View` is body-only. It no longer inherits any low-level resolver protocol.
- `View`, `Scene`, and `App` are `@MainActor` authoring protocols.
- APIs that evaluate authored `body` trees, including `Resolver.resolve(...)` and `DefaultRenderer.render(...)`, are `@MainActor`.
- Callback-bearing authoring APIs follow the same model: `Binding.init(get:set:)` and `.task(...)` use actor-inheriting closure signatures, while button actions, `OpenLinkAction` over typed `LinkDestination`s, `.onAppear`, and `.onDisappear` stay explicitly `@MainActor`. In ordinary authored view code those all still resolve to main-actor authoring because `View.body` is `@MainActor`.
- `ViewBuilder` no longer exposes `[AnyView]` in public closure signatures.
- `AnyView` remains public as `View` erasure, but `AnyView.init(erasing:)` is no longer public.

### `TerminalUI`

The runtime-facing public surface is also canonical:

- `DefaultRenderer`
- `RunLoop`
- `ResolveContext` as external renderer or resolver configuration only
- terminal host, graphics-capability, and input or signal integration types that support the runtime
- app and scene entry points, including `App`, `Scene`, `SceneBuilder`, `WindowGroup`, and `WindowIdentifier`
- `TerminalUISceneDescriptor`
- `TerminalUISceneManifest`
- `HostedSceneSession`

### `TerminalUIScenes`

The optional multi-scene runtime surface is also supported:

- `MultiSceneLauncher`
- the separate `TerminalUIScenes` library product for multi-scene apps

### `Core`

The core data model and pipeline types are canonical:

- geometry, layout, semantic, draw, raster, scheduler, diagnostics, and commit data types
- image payload, resolved-asset, and raster-image-attachment data types used by the rendering pipeline
- the layout engine, rasterizer, scheduler, semantic extractor, draw extractor, snapshot renderer, and commit planner
- the incremental presentation and retained-frame machinery that the runtime depends on

`Core` is currently target-level infrastructure re-exported through
`TerminalUI`, not a separate library product.

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
- concrete wrapper-view implementation types such as `IDView`, `LayoutMetadataModifier`, `DrawMetadataModifier`, `SemanticMetadataModifier`, `EnvironmentWritingModifier`, `EnvironmentTransformModifier`, `PaddingView`, `FrameView`, `OverlayView`, and `BackgroundView`
- runtime registry and replay types such as `LocalActionRegistry`, `LocalKeyHandlerRegistry`, `LocalLifecycleRegistry`, `LocalTaskRegistry`, `TaskRegistration`, `LifecycleHandlerSnapshot`, and `LocalKeyEvent`
- keyboard-help compatibility APIs such as `KeyboardShortcut`, `KeyboardShortcutGroup`, `KeyboardShortcutHelpView`, `.keyboardShortcut(...)`, and `.keyboardShortcutHelp(...)`

### Removed Public Styling Compatibility

The old public styling shims from `View` are gone:

- `EnvironmentValues.theme`
- string-based style helpers such as `foregroundStyle(_ style: String)`, `backgroundStyle(_ style: String)`, and `borderStyle(_ style: String)`

Low-level styling support such as `Theme` remains public in `Core`, but it is no longer part of the main `View` authoring story.

### Package-Only Transitional Seams

These symbols still exist for internal reuse, diagnostics, or narrow package-local compatibility, but they are no longer part of the public API story:

- `ResolvableView`
- `ViewNode`
- the local runtime registries and lifecycle replay helpers used by `RunLoop`
- concrete modifier wrapper views that back `.id`, metadata modifiers, `.environment`, `.padding`, `.frame`, `.overlay`, and `.background`

## Test-Support And Internal Seams

The repo still contains tests that exercise low-level construction or reuse behavior directly. Those tests are valid, but they should be isolated as internal-seam coverage rather than presented as ordinary app code.

Current examples include:

- resolve-reuse probes that need direct access to package-only `ResolveContext` helpers
- lifecycle and handler replay tests that validate post-resolve internal registries
- commit-boundary coverage that exists only to prove staged commit-plan compatibility

## Experimental And Showcase Targets

Prototype and showcase code may still live in the repository as sibling example packages for demos, experiments, and regression coverage, but that does not make it part of the supported product surface.

Current rule:

- `PrototypeUIComponents` is a package target used by experiments and tests, not a library product that downstream packages should import as a supported API surface
- the current prototype target hosts command-palette exploration such as `PrototypeCommandPalette`
- prototype widgets are allowed to inform future canonical APIs, but they should not be documented as the framework's primary authoring model
- README and architecture-facing docs should describe prototype code as exploratory or showcase-only when it appears at all
- terminal-native interaction surfaces that are still being shaped, such as command palettes or launcher-like flows, should land here first rather than forcing premature API commitments onto `View`

## Policy Summary

- New app-facing docs should use the canonical surface first.
- Package-only seams should not be promoted as ordinary examples.
- If a new feature can be expressed on `View`, it should usually be documented there rather than through `*` construction.
- If a new public symbol is added, it should be classified here before it becomes the default example in the README or architecture docs.
- SwiftUI-shaped APIs may intentionally reinterpret behavior toward
  terminal-native defaults when a literal desktop translation would degrade the
  TUI experience.
