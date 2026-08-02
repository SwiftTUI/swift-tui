# Public API

This document defines the shape of SwiftTUI's public surface. It identifies the
canonical app-facing API, package-only API, removed API, and policies for
consistent new API.

A machine-generated enumeration of every public symbol lives in
`PUBLIC_API_BASELINE.md` (grouped) and `.public-api-baseline.txt` (flat). The
The `.spi-api-baseline.txt` file separately tracks the `@_spi` surface. Its most
important part is `@_spi(Runners)`, the host contract for the swiftui/web/android
host repos. Thus, an SPI break creates a reviewable diff instead of a silent
downstream failure. The inventory script generates and compares all
three files:
`Scripts/generate_public_api_inventory.sh` — see
[DEVELOPMENT.md](DEVELOPMENT.md#public-api-baseline). Those files answer "is
symbol X public?". This document explains when to use a symbol and why it has
its current shape.

## The one authoring story

The package presents a single primary authoring story:

- Write views with the SwiftUI-shaped surface on `View`.
- Use `SwiftTUI` for one-import apps. It includes terminal launch, localhost
  WebHost launch, and animated GIF/image support. Use `SwiftTUIRuntime` for
  platform-neutral runtime composition with explicit host products.
- Treat `SwiftTUICore` as pipeline and data-model infrastructure.

Anything outside that shape has to justify being public. One Swift package
provides the supported model. It exposes `SwiftTUI` for the default
batteries-included app story and `SwiftTUIRuntime` for shared runtime
integration. Sibling products provide narrow execution, hosting, charting, and
terminal-program embedding.

## The canonical surface

The canonical public surface is the API ordinary app code uses first:

- `View` and the SwiftUI-shaped containers, controls, and leaves. These include
  `VStack`, `HStack`, `ZStack`, `ScrollView`, `List`, `Table`, `OutlineGroup`,
  `NavigationStack`, `TabView`, and `Button`. They also include `Toggle`,
  `Slider`, `TextField`, `TextEditor`, `Picker`, `Text`, `Image`, and the rest.
- Property wrappers and environment plumbing: `@State`, `@Binding`,
  `@Environment`, `@FocusState`, `@FocusedValue`, `@FocusedBinding`, and the
  repo-owned `@Bindable`.
- The modifier algebra: `ViewModifier`, `View.modifier(_:)`, `ModifiedContent`,
  and the canonical identity/layout/styling/presentation modifiers.
- Runtime integration in `SwiftTUIRuntime`: `DefaultRenderer`, `RunLoop`,
  `RuntimeConfiguration`, `App`, `Scene`, `WindowGroup`, the scene builder
  artifacts, `RenderSnapshot`, `HostedSceneSession`, `HostedRasterSurface`,
  `SemanticHostFrame`, and the `PresentationSurface` roles.
- The default animated-image surface from `SwiftTUIAnimatedImage`. Charting
  ships separately from
  [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts).

Document a feature on this surface first when the surface can express it.

`NavigationStack` supports both a root-only initializer and a homogeneous
`Binding<[Route]>` path. Register route rendering with
`.navigationDestination(for:destination:)`. Append or remove path values to
push, pop, deep-link, or return to the root. Boolean- and item-binding
destinations remain available for presentation-shaped routes. A visible
destination can contribute `.navigationTitle(_:)` to an enclosing toolbar
style. The framework intentionally exposes neither `NavigationLink` nor an
environment dismiss command.

## Actor isolation model

The authoring surface is honestly isolated. The package does not suppress the
concurrency checker.

- `View`, `Scene`, and `App` are `@MainActor` authoring protocols, and
  `View.body` is `@ViewBuilder` and `@MainActor`.
- Public APIs that evaluate authored `body` trees — `DefaultRenderer.render(...)`
  and `DefaultRenderer.renderAsync(...)` — are `@MainActor`. The lower
  `Resolver.resolve(...)` entry point is package-only.
- Callback-bearing APIs follow the model: `Binding.init(get:set:)` takes
  explicitly `@MainActor` closures. `.task(...)` uses actor-inheriting
  closures. Button actions and `.onChange` callbacks stay `@MainActor`.
- The package forbids `@unchecked Sendable` and `nonisolated(unsafe)`. Shared
  mutable state uses explicit isolation, `Sendable` constraints, or
  `Synchronization` primitives.

## AnyView Policy

`AnyView` is part of the supported surface as a narrow type-erasure escape
hatch. It is not the default authoring model.

- Prefer typed `@ViewBuilder` closures and generic `Content: View` storage.
- `AnyView` is type-aware in the retained graph: the same erased static payload
  type preserves the payload subtree. A changed payload type replaces it
  through normal structural removal.
- Public APIs must not expose `[AnyView]`, builder closures returning
  `AnyView`, or direct node-erasure construction seams.
- Internal `AnyView` storage is acceptable only for heterogeneous child
  storage, deferred authored-content capture, or local branch unification.
- Deferred authored content must be captured with `scopedAnyView(...)`, not
  plain `AnyView(...)`, so dynamic-property scope and identity-bound state stay
  correct.
- A file that stores `AnyView`, `[AnyView]`, or a closure returning `AnyView`
  must carry a nearby `AnyView policy:` comment explaining why typed storage is
  not practical there. This is enforced by
  `Scripts/check_public_surface_policies.sh`.

`AnyScene` is the scene-layer equivalent, with the same rule: prefer typed
`@SceneBuilder` composition and generic `WindowGroup<Content>` storage.

## Styling

Semantic styling is the preferred model: views write semantic style roles, and
a host-owned `Theme` resolves them to concrete colors. `Theme` is not part of
the `View` authoring surface. The old public string-style helpers and public
The `View` surface no longer includes the `Theme` shims.

Authoring-facing control and container style APIs converge on public,
extensible style protocols rather than closed public enums.

### Authoring style families

- **Protocol-backed style families today** are `ShapeStyle`, `ToolbarStyle`,
  `ButtonStyle`, `TextFieldStyle`, `PickerStyle`, `ListStyle`, `OutlineStyle`,
  `ToastStyle`, and `TabViewStyle`.
- **Type-erased style storage** provides concrete values where environment or
  modifier plumbing needs a non-generic stored style. The types are
  `AnyShapeStyle`, `AnyButtonStyle`, `AnyTextFieldStyle`, `AnyPickerStyle`,
  `AnyListStyle`, `AnyOutlineStyle`, `AnyToastStyle`, and `AnyTabViewStyle`.
- Built-in styles are concrete values conforming to those protocols.
- `TabViewStyle` is a full-body container style. Styles receive routeable tab
  item configurations, a routeable overflow trigger, routeable overflow item
  configurations, presentation metadata, and an active-content placeholder.
  Built-in tab styles are implemented through those same public hooks.
- New public enum-backed authoring `*Style` surfaces should not be added. Do not
  restore removed enum-backed style families as shims.

## Geometry, pointer, and Canvas

Public naming keeps coordinate roles visible:

- `Cell*` names — `CellPoint`, `CellSize`, `CellRect` — for the integer
  terminal grid that layout, semantic bounds, and raster output use.
- `Point`, `Size`, `Rect`, and `Vector` for continuous cell-space geometry
  delivered to gestures, hover, `Canvas` drawing, and interpolation.
- `Pixel*` only for host/device-pixel provenance.

`PointerLocation`, `PointerInputCapabilities`, and `CellPixelMetrics` describe
input quality without changing the layout contract. Cell-only fallback is
always supported. `Canvas` is the public arbitrary-drawing escape hatch:
prefer value drawings conforming to `CanvasDrawing` for stable structural
equality. The closure-backed `Canvas { ... }` compares by identity.

## Action scopes and commands

The full ActionScope/commands surface is public:

- `ActionScope` (with `AnyID`) and `CommandRegistry`.
- `Panel<ID, Content>` plus `.panel(id:)` and `.panel()`.
- `.keyCommand(...)` with shallowest-wins dispatch along the focus chain.
  Modifier-less bindings are framework-reserved.
- `.paletteCommand(...)` plus `EnvironmentValues.activePaletteCommands`.
- `.toolbar(style:)` and `.toolbarItem(...)`.
- `Scene` and the presentation modifiers (`.alert`, `.confirmationDialog`,
  `.sheet`, `.fullScreenCover`, `.popover`, `.popoverTip`, `.toast`) conform
  to `ActionScope`. Boolean and optional-item presentation state is owned by
  the presenter. `onDismiss` observes committed teardown after the entry has
  left the rendered tree.

## Products

### `SwiftTUI`

`SwiftTUI` is the batteries-included app convenience product. It re-exports the
combined terminal/WebHost CLI surface and `SwiftTUIAnimatedImage`. An ordinary
app writes only `import SwiftTUI`. It gets standard flags, the default terminal
`App.main()`, `--web` localhost launch, and animated GIF/image support.
Charting/graph views live in the external
[`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package.

`SwiftTUIRuntime` is the platform-neutral runtime import for host products and
custom launchers that do not want the convenience product.
`SwiftTUICore` is target-level pipeline infrastructure, re-exported through
`SwiftTUIRuntime` rather than published as its own product. Public host code
uses `RenderSnapshot`, `RasterSurface`, `SemanticSnapshot`, and
`SemanticHostFrame`. Resolved/measured/placed/draw/commit phase IR stays
package-only.

### `SwiftTUIProfiling`

`SwiftTUIProfiling` is the optional, opt-in profiling product. Nothing in the
default graph depends on it, and it is zero-cost until activated. Its canonical
public surface is the activation entry point and the reusable CPU sampler:

- `ProfilingScene` and the `Scene.profiling(_:)` modifier — env-gated activation
  via `SWIFTTUI_PROFILE`, or an explicit `ProfileConfig`.
- `ProfileConfig` (with `Signal` and `SinkDescriptor`) — the programmatic
  selection of signals and sinks.
- `ProfileActivation` — owns the live session. Call `finish()` at shutdown to
  flush buffered sinks.
- The CPU sampler family — `CPUSampler`, `CPUSample`, `CPUSampleCollector`,
  `ProcessCPUReading`, `CPUSamplerError`.

The record/derivation/TSV types it consumes stay in `SwiftTUIRuntime` (they are
also used by `SwiftTUIWASISurfaceBridge` and the runners), so the runtime never depends
on the product. The sink and record-envelope types are package-internal for now.
The environment grammar builds them.

### Platform integration products

The canonical packaging and engine-profile boundaries live in
[HOSTS-AND-PLATFORMS.md](HOSTS-AND-PLATFORMS.md). At this package boundary:

- **Runners** — `SwiftTUICLI` (`TerminalRunner`), `SwiftTUIWASI` (`WASIRunner`),
  `SwiftTUIWebHost` (`WebHostRunner`), and `SwiftTUIWebHostCLI`
  (`WebHostCLIRunner`).
- **In-package host** — `SwiftTUIAndroidHost` retains runtime sessions for the
  separately distributed Android Compose/AAR integration.
- **External host** — `SwiftUIHost` lives in the separate
  [`swift-tui-swiftui`](https://github.com/SwiftTUI/swift-tui-swiftui) package.
- **Embedding** — `SwiftTUITerminal`, `SwiftTUITerminalWorkspace`, and
  `SwiftTUIPTYPrimitives`.

`SwiftTUIWebHost` owns the embedded HTTP/WebSocket server and bundled browser
resources. `SwiftTUIWebHostCLI` composes that local server with terminal launch,
and `SwiftTUI` includes the combined runner by default. Use `SwiftTUICLI`
directly for a terminal-only graph.

## Removed From The Public Surface

These migration-era APIs are no longer public:

- `ViewNode`, `AnyViewNode`, `Leaf`, and `AnyView.init(erasing:)`.
- `Package` and its factory helpers, `NoOpRoot`, `Renderer<Root>`, and
  `StateViewBuilder`.
- Concrete wrapper-view types such as `IDView`, `PaddingView`, `FrameView`,
  `OverlayView`, `BackgroundView`, and `TagValueView`.
- Runtime registry and replay types — `LocalActionRegistry`,
  `LocalKeyHandlerRegistry`, `LocalLifecycleRegistry`, `LocalTaskRegistry`,
  `TaskRegistration`, `LifecycleHandlerSnapshot`, and `LocalKeyEvent`.
- The global hotkey seam — `HotkeyRegistry`, `HotkeyBinding`, and the
  keyboard-help compatibility APIs. Global, always-on key bindings are now bound
  through the ActionScope commands surface. This removal does **not** include the
  focused-key `View.onKeyPress(_:perform:)` modifier, which is a separate,
  canonical API and remains part of the public surface.
- The old public styling shims — `EnvironmentValues.theme` and the string-based
  `foregroundStyle`/`backgroundStyle`/`borderStyle` helpers.
- Render-pipeline implementation IR — `Resolver`, `ResolvedNode`,
  `MeasuredNode`, `PlacedNode`, `DrawNode`, `FrameArtifacts`, `CommitPlan`,
  `CommitPlanner`, `LayoutEngine`, `SemanticExtractor`, `DrawExtractor`,
  `Rasterizer`, `SnapshotRenderer`, and `FrameDropEligibility`. The public
  one-shot renderer result is `RenderSnapshot`. Public diagnostics use
  `FrameDropBlocker` for completed-frame drop blocker vocabulary.

## Package-Only Transitional Seams

These symbols still exist for internal reuse and narrow compatibility. They are
not part of the public API story and must not shape app authoring:

- `PrimitiveView` and `ResolvableView` — internal lowering protocols.
- `ViewNode` — internal runtime plumbing.
- Render phase products and engines — package-only implementation detail behind
  `DefaultRenderer` and `RunLoop`.
- The local runtime registries and lifecycle replay helpers used by `RunLoop`.
- `PrimitiveViewModifier` and `ModifierContentInputs` — primitive
  modifier-lowering hooks.

## Adding public API: checklist

Before making a symbol public, ask:

1. Can the feature be expressed on the canonical SwiftUI-shaped surface
   instead?
2. Does it help new app code, or only package-local migration and tests?
3. Will the README and architecture docs still read as one coherent story?
4. Can it live behind an internal or test-support seam?
5. Is it a real product surface or showcase code that must stay target-only?
   Do not export example apps or showcase targets as package products.
   Experimental or showcase targets follow the same rule: they can remain for
   demos and tests without becoming products.

If the answer points toward internal compatibility rather than product
direction, keep the symbol non-public. When a new public symbol does
land, classify it here before it becomes a default example elsewhere.
