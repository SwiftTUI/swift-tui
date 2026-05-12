# Public Surface Policy

This note defines how the package should think about its public API shape after the public-surface consolidation.

## Principle

The package should present one primary authoring story:

- write views with the SwiftUI-shaped surface in `View`
- use `SwiftTUI` for one-import terminal apps and `SwiftTUIRuntime` for
  platform-neutral runtime composition with explicit host products
- treat `Core` as pipeline and data-model infrastructure

Anything outside that shape must justify why it is public.

## Canonical Surface

The canonical public surface is the one used in README examples, architecture docs, and ordinary application code:

- `View` and the SwiftUI-shaped container and leaf APIs
- property wrappers and environment plumbing that feel like SwiftUI
- runtime integration points in `SwiftTUIRuntime` that render those views or
  retain shared scene sessions
- the `SwiftTUI` convenience product for ordinary terminal executable apps
- root package platform products when the app needs terminal-native execution,
  WASI execution, WebHost execution, host-managed embedding, or
  terminal-program embedding

The supported package model is one Swift package exposing `SwiftTUI` for the
default terminal app story, `SwiftTUIRuntime` for shared runtime integration,
and sibling platform integration products: runners for executable launch, host
products for host-managed embedding, and terminal embedding products for child
terminal programs.

In this repo, an executable runner product owns top-level execution and the
default `App.main()` story, while a host product retains `HostedSceneSession`
values inside another app or runtime shell.

Runner and host composition is explicit:

- terminal-only apps depend on `SwiftTUI`
- custom terminal launchers can compose `SwiftTUIRuntime` with `SwiftTUICLI`
- WASI apps depend on `SwiftTUIWASI`
- web-only localhost apps depend on `SwiftTUIWebHost` and call
  `WebHostRunner`
- apps that intentionally support both terminal-native and localhost-browser
  launch depend on `SwiftTUIWebHostCLI`; simple apps can use its default
  `App.main()`, while custom launchers can call `WebHostCLIRunner`

`SwiftTUIWebHost` and `SwiftTUIWebHostCLI` are the only first-party products
that may link the embedded HTTP/WebSocket server, FlyingFox, and bundled
browser resources. The `SwiftTUI` terminal convenience product and
`SwiftTUICLI` runner must keep rejecting web mode without probing or
weak-linking the WebHost package.

If a feature can be expressed naturally on that surface, it should be documented there first.

## Compatibility Tier

Some package-only symbols still exist because the repo is carrying internal compatibility and test seams.

Those seams are allowed to remain only if one of these is true:

- they are required by existing adopters
- they are needed to keep the runtime or tests stable during migration
- they are intentionally documented as package-only internals

Package-only seams should not be the first example a new reader sees.

Experimental or showcase targets follow the same rule. They may remain in the
repository for demos, tests, and design exploration, but they should not be
exported as package products unless they have graduated into the canonical
public story. Example apps should stay in their own mini packages and depend on
the root `swift-tui` package rather than becoming root products.

## Low-Level Construction Policy

The `*` authoring nodes are not part of the public authoring story.

They may remain package-only when:

- a test needs to validate internal reuse or identity behavior directly
- a compatibility path is still being migrated
- a symbol is a narrow adapter around the canonical surface

They should not be expanded casually. If a new feature can be authored on `View`, it should usually stay there.

## Styling Policy

Semantic styling is the preferred model.

The old public string-style helpers and public `Theme` shims have already been removed from `View`.

Any remaining styling compatibility should stay confined to lower-level core types and should not re-enter the main `View` authoring surface. New docs should show typed semantic style APIs instead.

Authoring-facing control and container style APIs should converge on public,
extensible style protocols rather than closed public enums.

- Prefer `public protocol ...Style` plus type-erased environment storage such
  as `Any...Style` for new authoring-facing style families.
- Built-in styles should be concrete style values that conform to those
  protocols; shorthand ergonomics belong on the eraser or dedicated default
  types, not on a closed enum that owns the whole authoring surface.
- Once a style family is migrated, the owning control or container should
  delegate through configuration and presentation seams instead of switching
  directly on every built-in style case.
- The current public authoring models are `ShapeStyle`, `ToolbarStyle`,
  `ButtonStyle`, `TextFieldStyle`, `PickerStyle`, `ListStyle`,
  `OutlineStyle`, `ToastStyle`, and `TabViewStyle`, with type-erased storage
  such as `Any...Style` where environment or modifier plumbing requires a
  concrete value.
- New public enum-backed authoring `*Style` surfaces should not be added, and
  previously removed enum-backed style families should not be reintroduced as
  compatibility shims.

## Geometry, Pointer, And Canvas Policy

Public naming should keep coordinate roles visible.

- Use `Cell*` names for integer terminal-cell geometry that participates in
  layout, semantic bounds, raster surfaces, and terminal output.
- Use `Point`, `Size`, `Rect`, and `Vector` for continuous cell-space geometry
  delivered to gestures, hover, Canvas drawing, interpolation, and hit-test
  paths.
- Use `Pixel*` only for host/device-pixel provenance or graphics interop.
  Public app code should not need device pixels to place normal views.

Pointer capability APIs should describe runtime input quality without changing
the layout contract. Prefer `PointerLocation`, `PointerInputCapabilities`, and
`CellPixelMetrics` over adding terminal-protocol-specific public modifiers.
Cell-only fallback behavior must remain supported for every pointer-facing
authoring API.

Canvas is the public arbitrary-drawing escape hatch. Prefer value drawings that
conform to `CanvasDrawing` and draw in continuous cell space through
`CanvasContext` when stable structural equality and renderer deduplication
matter. The closure-backed `Canvas` initializer is available for ad-hoc drawing
code and compares by drawing identity. Keep dense terminal-cell pixel helpers as
value APIs rather than style enums or public erasure seams. Do not expose
pixel-exact Canvas grids until a real graphics-protocol renderer can exercise
them.

## Transitional Runtime Policy

Runtime bridges and staging adapters are acceptable while the package is still reconciling old host shapes with the current commit model.

If retained, host-staging adapters belong in this category as package-internal compatibility seams, not as part of the public story.

Compatibility factories such as the old `Package` helpers do not qualify as canonical runtime API and should not be reintroduced.

## Structured Concurrency Policy

Checked-in Swift sources should stay inside the structured concurrency model.

- Do not introduce `@unchecked Sendable`.
- Do not introduce `nonisolated(unsafe)`.
- Prefer explicit actor isolation, `Sendable` generic constraints, or `Synchronization` primitives such as `Mutex` when shared mutable state is unavoidable.
- If a type participates in the public or package-visible authoring surface, prefer modeling the isolation honestly over suppressing the compiler.

## View Lowering Policy

- Public `View` stays body-only: do not add `Body = Never` defaults or
  `extension View` body witnesses. Framework primitives must opt into
  package-only primitive ownership through `PrimitiveView` or a view-like
  protocol such as `Shape`.
- Public modifiers are first-class through `ViewModifier`, `View.modifier(_:)`,
  and `ModifiedContent`.
- Concrete built-in modifier value types may be public when they participate in
  that algebra; direct primitive lowering still remains package-only.
- Public builder-taking APIs should accept typed `@ViewBuilder` closures, not `[AnyView]`.
- Internal lowering protocols such as `PrimitiveView` and `ResolvableView` must
  stay package-only.
- Direct primitive lowering stays package-only through internal hooks such as
  `PrimitiveViewModifier`.

## AnyView Policy

`AnyView` remains part of the supported surface as a narrow type-erasure escape hatch,
but it is not the default authoring model for this package.

Consumer examples live in
[`Sources/SwiftTUIViews/SwiftTUIViews.docc/AnyView.md`](../Sources/SwiftTUIViews/SwiftTUIViews.docc/AnyView.md).
Maintainer examples and review guidance live in
[`ANYVIEW_INTERNALS.md`](ANYVIEW_INTERNALS.md).

- Prefer typed `@ViewBuilder` closures and generic `Content: View` storage.
- Do not approve `AnyView` usage solely because the same shape is common in
  SwiftUI examples. SwiftTUI documents a real retained-graph payload boundary,
  and terminal rendering makes unnecessary structural churn more expensive.
- `AnyView` is type-aware in the retained graph: the same erased static payload
  type preserves the payload subtree, while a changed erased static payload type
  replaces that subtree through normal `ViewGraph` structural removal.
- Explicit `.id(...)` values inside an `AnyView` payload remain authored
  identities for focus, actions, and user-directed lookup. When the erased
  static payload type changes, `ViewGraph` prunes the old payload subtree before
  resolving new content so an explicit ID cannot keep incompatible state alive.
- Do not add public APIs that expose `[AnyView]`, builder closures returning `AnyView`, or direct node-erasure construction seams.
- Internal `AnyView` storage is acceptable only for heterogeneous child storage, deferred authored-content capture, or local branch unification when concrete view types genuinely diverge.
- If authored content is stored for later evaluation, capture it with `scopedAnyView(...)`, not plain `AnyView(...)`, so dynamic-property scope and identity-bound state continue to behave correctly.
- New stored `AnyView`, `[AnyView]`, or closure-returning-`AnyView` members should carry a nearby `AnyView policy:` comment explaining why typed storage is not practical in that file.
- Reviewers should treat new erasure sites as design decisions, not as convenience refactors.

## AnyScene Policy

`AnyScene` remains part of the supported runtime surface as the scene-layer
equivalent of `AnyView`, but it is not the default way to compose authored
scenes.

- Prefer typed `@SceneBuilder` composition and generic `WindowGroup<Content>` storage.
- Do not add public APIs that expose `[AnyScene]` or reintroduce flattened scene-array builder storage as the normal representation.
- Internal `AnyScene` storage is acceptable only for explicit scene erasure, such as availability unification or narrow compatibility seams where concrete scene types genuinely diverge.
- Reviewers should treat new `AnyScene` storage as an architectural choice, not as a convenience refactor.

## Review Checklist

Before adding a new public symbol, ask:

1. Can the feature be expressed on the canonical SwiftUI-shaped surface instead?
2. Does the symbol help new app code, or only package-local migration and test compatibility?
3. Will the README and architecture docs still read as a single coherent story if this lands?
4. Can the feature live behind an internal or test-support seam instead?
5. Is this really a supported product surface, or is it still prototype or showcase code that should remain target-only inside the package?

If the answer points toward internal compatibility rather than product direction, the symbol should stay non-public.
