# Public API

This document defines the shape of SwiftTUI's public surface: what is canonical
app-facing API, what is package-only, what was removed, and the policies that
keep new API consistent with the rest.

A machine-generated enumeration of every public symbol lives in
`PUBLIC_API_BASELINE.md` (grouped) and `.public-api-baseline.txt` (flat). Both
are generated and checked by `Scripts/generate_public_api_inventory.sh` — see
[DEVELOPMENT.md](DEVELOPMENT.md#public-api-baseline). Those files answer "is
symbol X public?"; this document answers "should I use X, and why is it shaped
this way?".

## The one authoring story

The package presents a single primary authoring story:

- Write views with the SwiftUI-shaped surface on `View`.
- Use `SwiftTUI` for one-import terminal apps, or `SwiftTUIRuntime` for
  platform-neutral runtime composition with explicit host products.
- Treat `SwiftTUICore` as pipeline and data-model infrastructure.

Anything outside that shape has to justify being public. The supported package
model is one Swift package exposing `SwiftTUI` for the default terminal app
story, `SwiftTUIRuntime` for shared runtime integration, and sibling platform
integration products for execution, hosting, and terminal-program embedding.

## The canonical surface

The canonical public surface is the API ordinary app code uses first:

- `View` and the SwiftUI-shaped containers, controls, and leaves — `VStack`,
  `HStack`, `ZStack`, `ScrollView`, `List`, `Table`, `OutlineGroup`,
  `NavigationStack`, `TabView`, `Button`, `Toggle`, `Slider`, `TextField`,
  `TextEditor`, `Picker`, `Text`, `Image`, and the rest.
- Property wrappers and environment plumbing: `@State`, `@Binding`,
  `@Environment`, `@FocusState`, `@FocusedValue`, `@FocusedBinding`, and the
  repo-owned `@Bindable`.
- The modifier algebra: `ViewModifier`, `View.modifier(_:)`, `ModifiedContent`,
  and the canonical identity/layout/styling/presentation modifiers.
- Runtime integration in `SwiftTUIRuntime`: `DefaultRenderer`, `RunLoop`,
  `RuntimeConfiguration`, `App`, `Scene`, `WindowGroup`, the scene builder
  artifacts, `HostedSceneSession`, `HostedRasterSurface`, `SemanticHostFrame`,
  and the `PresentationSurface` roles.
- The peer products `SwiftTUICharts` and `SwiftTUIAnimatedImage`.

If a feature can be expressed on this surface, it should be documented there
first.

## Actor isolation model

The authoring surface is honestly isolated; the package does not suppress the
concurrency checker.

- `View`, `Scene`, and `App` are `@MainActor` authoring protocols, and
  `View.body` is `@ViewBuilder` and `@MainActor`.
- APIs that evaluate authored `body` trees — `Resolver.resolve(...)` and
  `DefaultRenderer.render(...)` — are `@MainActor`.
- Callback-bearing APIs follow the model: `Binding.init(get:set:)` takes
  explicitly `@MainActor` closures; `.task(...)` uses actor-inheriting
  closures; button actions and `.onChange` callbacks stay `@MainActor`.
- The package forbids `@unchecked Sendable` and `nonisolated(unsafe)`. Shared
  mutable state uses explicit isolation, `Sendable` constraints, or
  `Synchronization` primitives.

## AnyView Policy

`AnyView` is part of the supported surface as a narrow type-erasure escape
hatch. It is not the default authoring model.

- Prefer typed `@ViewBuilder` closures and generic `Content: View` storage.
- `AnyView` is type-aware in the retained graph: the same erased static payload
  type preserves the payload subtree; a changed payload type replaces it
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
`Theme` shims have been removed from `View`.

Authoring-facing control and container style APIs converge on public,
extensible style protocols rather than closed public enums.

### Authoring style families

- **Protocol-backed style families today** are `ShapeStyle`, `ToolbarStyle`,
  `ButtonStyle`, `TextFieldStyle`, `PickerStyle`, `ListStyle`, `OutlineStyle`,
  `ToastStyle`, and `TabViewStyle`.
- **Type-erased style storage** — `AnyShapeStyle`, `AnyButtonStyle`,
  `AnyTextFieldStyle`, `AnyPickerStyle`, `AnyListStyle`, `AnyOutlineStyle`,
  `AnyToastStyle`, and `AnyTabViewStyle` — provides the concrete values used
  where environment or modifier plumbing needs a non-generic stored style.
- Built-in styles are concrete values conforming to those protocols.
- `TabViewStyle` is a full-body container style. Styles receive routeable tab
  item configurations, a routeable overflow trigger, routeable overflow item
  configurations, presentation metadata, and an active-content placeholder.
  Built-in tab styles are implemented through those same public hooks.
- New public enum-backed authoring `*Style` surfaces should not be added, and
  previously removed enum-backed style families should not return as shims.

## Geometry, pointer, and Canvas

Public naming keeps coordinate roles visible:

- `Cell*` names — `CellPoint`, `CellSize`, `CellRect` — for the integer
  terminal grid that layout, semantic bounds, and raster output use.
- `Point`, `Size`, `Rect`, and `Vector` for continuous cell-space geometry
  delivered to gestures, hover, `Canvas` drawing, and interpolation.
- `Pixel*` only for host/device-pixel provenance.

`PointerLocation`, `PointerInputCapabilities`, and `CellPixelMetrics` describe
input quality without changing the layout contract; cell-only fallback is
always supported. `Canvas` is the public arbitrary-drawing escape hatch:
prefer value drawings conforming to `CanvasDrawing` for stable structural
equality; the closure-backed `Canvas { ... }` compares by identity.

## Action scopes and commands

The full ActionScope/commands surface is public:

- `ActionScope` (with `AnyID`) and `CommandRegistry`.
- `Panel<ID, Content>` plus `.panel(id:)` and `.panel()`.
- `.keyCommand(...)` with shallowest-wins dispatch along the focus chain;
  modifier-less bindings are framework-reserved.
- `.paletteCommand(...)` plus `EnvironmentValues.activePaletteCommands`.
- `.toolbar(style:)` and `.toolbarItem(...)`.
- `Scene` and the presentation modifiers (`.alert`, `.confirmationDialog`,
  `.sheet`, `.popover`, `.popoverTip`, `.toast`) conform to `ActionScope`.

## Products

### `SwiftTUI`

`SwiftTUI` is the terminal app convenience product. It re-exports
`SwiftTUIRuntime`, `SwiftTUIArguments`, and `SwiftTUICLI`, so an ordinary
terminal app writes only `import SwiftTUI` and gets the standard flags and the
default terminal `App.main()`.

`SwiftTUIRuntime` is the platform-neutral runtime import for host products and
custom launchers that do not want the terminal convenience product.
`SwiftTUICore` is target-level pipeline infrastructure, re-exported through
`SwiftTUIRuntime` rather than published as its own product.

### Root-package platform integration products

Platform-specific execution and embedding are root-package products:

- **Runners** — `SwiftTUICLI` (`TerminalRunner`), `SwiftTUIWASI` (`WASIRunner`),
  `SwiftTUIWebHost` (`WebHostRunner`), `SwiftTUIWebHostCLI` (`WebHostCLIRunner`).
- **Hosts** — `SwiftUIHost` (macOS-only) retains `HostedSceneSession` values
  inside a SwiftUI shell.
- **Embedding** — `SwiftTUITerminal`, `SwiftTUITerminalWorkspace`, and
  `SwiftTUIPTYPrimitives`.

`SwiftTUIWebHost` and `SwiftTUIWebHostCLI` are the only first-party products
that may link the embedded HTTP/WebSocket server and the bundled browser
resources.

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
- The global hotkey seam — the `.onKeyPress(...)` modifier, `HotkeyRegistry`,
  `HotkeyBinding`, and keyboard-help compatibility APIs. Keys are now bound
  through the ActionScope commands surface.
- The old public styling shims — `EnvironmentValues.theme` and the string-based
  `foregroundStyle`/`backgroundStyle`/`borderStyle` helpers.

## Package-Only Transitional Seams

These symbols still exist for internal reuse and narrow compatibility, but they
are not part of the public API story and should not shape app authoring:

- `PrimitiveView` and `ResolvableView` — internal lowering protocols.
- `ViewNode` — internal runtime plumbing.
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
5. Is it a real product surface, or showcase code that should stay
   target-only — example apps and showcase targets should not be exported as
   package products. Experimental or showcase targets follow the same rule:
   they may live in the repo for demos and tests without becoming products.

If the answer points toward internal compatibility rather than product
direction, the symbol should stay non-public. When a new public symbol does
land, classify it here before it becomes a default example elsewhere.
