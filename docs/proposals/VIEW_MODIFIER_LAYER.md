# View Modifier Layer

**Date:** 2026-04-21  
**Status:** Shipped. Retained as the April 21, 2026 implementation note for the
modifier-layer migration.  
**Scope:** `View` public surface, modifier lowering, transition probing, tab metadata peeking

## Summary

Introduce a public SwiftUI-shaped modifier layer built around:

- `ViewModifier`
- `View.modifier(_:)`
- `ModifiedContent<Content, Modifier>`
- `ViewModifier.concat(_:)`

Make `ModifiedContent` the canonical modifier application node in the resolver.
Delete the current fleet of package-only wrapper views as the primary modifier
representation. Replace the remaining wrapper-inspection debt with:

- generic `ModifiedContent` lowering
- package-only modifier capability protocols for the few modifier semantics that
  genuinely need special treatment

This is a clean break. The framework is pre-release, so the goal is not
compatibility shims. The goal is a better architecture.

## Goals

1. Expose an authentic SwiftUI-like modifier model on the public `View` surface.
2. Keep lowering and runtime hooks package-only.
3. Prefer generics over `AnyView`-like erasure everywhere except the one public
   content-carrier seam that SwiftUI itself also has.
4. Make modifier application a first-class typed node in the resolver instead of
   a large collection of wrapper views.
5. Delete the current known-wrapper inspection debt in transition probing and
   `TabView` metadata peeking.
6. Preserve the current authoring-context, identity, lifecycle, and state
   semantics.

## Non-Goals

1. Do not move authoring context out of the current task-local model in this
   proposal. That is a separate refactor.
2. Do not add every public SwiftUI modifier-refinement protocol on day one
   (`EnvironmentalModifier`, `GeometryEffect`, legacy
   `AnyTransition.modifier(active:identity:)`, etc.).
3. Do not preserve the old package-only wrapper-view layer behind shims or
   deprecations.
4. Do not reintroduce broad `AnyView` storage as the normal representation of
   modifier application.

## Design Principles

### 1. `ModifiedContent` Is The Canonical Modifier Node

The framework should have one modifier application shape, not many ad hoc
wrapper views. Every public modifier application becomes either:

- `ModifiedContent<Content, Modifier>` for ordinary modifier composition
- a package-only optimized lowering of the same `ModifiedContent` node when the
  modifier is framework-owned and needs direct resolve-time behavior

This matches the public SwiftUI model while preserving package-only control over
lowering.

### 2. Generic First, Erase Once

The implementation should stay fully generic across:

- modifier chains
- built-in modifier values
- base content
- built-in modifier payloads like background/overlay/inset content

The only opaque seam should be the public `ViewModifier.Content` carrier, since
that surface must hide the base view type in the same way SwiftUI hides
`_ViewModifier_Content<Self>`.

Even there, prefer a private boxed resolver or closure-backed carrier over
`AnyView`. The modifier system should not normalize to `AnyView` internally.

### 3. Separate Composition From Semantics

Most modifiers are just modifier application plus lowering.

Some modifiers also carry framework semantics that matter before or outside full
resolution:

- transition effect extraction
- pre-resolve tab metadata peeking
- identity rewriting

Those semantics should be expressed through explicit package-only capability
protocols on modifier values, not through concrete wrapper-type inspection.

### 4. Built-In Modifiers Should Be Modifier Values, Not Wrapper Views

Current package-only wrapper views like `PaddingView`, `FrameView`, `OffsetView`,
`OverlayView`, `BackgroundView`, and `EnvironmentWritingModifier` should become
package modifier values such as:

- `PaddingModifier`
- `FrameModifier`
- `OffsetModifier`
- `OverlayModifier<Overlay>`
- `BackgroundModifier<Background>`
- `EnvironmentWritingModifier<Value>`

Public `View` extension methods continue to return `some View`, but now they do
so by applying modifier values through `.modifier(...)`.

## Public API Shape

```swift
@MainActor
public protocol ViewModifier {
  associatedtype Body: View = Never
  typealias Content = ViewModifierContent<Self>

  @ViewBuilder
  func body(content: Content) -> Body
}

public struct ViewModifierContent<Modifier: ViewModifier>: View {
  public typealias Body = Never
}

public struct ModifiedContent<Content, Modifier> {
  public var content: Content
  public var modifier: Modifier

  public init(content: Content, modifier: Modifier) {
    self.content = content
    self.modifier = modifier
  }
}

extension View {
  public func modifier<M: ViewModifier>(
    _ modifier: M
  ) -> ModifiedContent<Self, M>
}

extension ViewModifier {
  public func concat<M: ViewModifier>(
    _ modifier: M
  ) -> ModifiedContent<Self, M>
}

extension ModifiedContent: View
where Content: View, Modifier: ViewModifier {}

extension ModifiedContent: ViewModifier
where Content: ViewModifier, Modifier: ViewModifier {}
```

Conditional conformances that are worth adding immediately:

- `ModifiedContent: Sendable where Content: Sendable, Modifier: Sendable`
- `ModifiedContent: Equatable where Content: Equatable, Modifier: Equatable`
- `ModifiedContent: Animatable where Content: Animatable, Modifier: Animatable`

The last one matters because this repo already prefers the SwiftUI-shaped
`Animatable` model over `AnimatableModifier`.

## Internal Model

### Public Content Carrier

`ViewModifier.Content` must hide the concrete base type. That means one opaque
boundary is unavoidable. This is the one place where the design permits an
erased carrier.

The recommended shape is:

```swift
@MainActor
package protocol ViewModifierContentStorage {
  func resolveElements(in context: ResolveContext) -> [ResolvedNode]
  func resolve(in context: ResolveContext) -> ResolvedNode
}

@MainActor
package struct TypedViewModifierContentStorage<Base: View>: ViewModifierContentStorage {
  package let base: Base
  package let authoringContext: AuthoringContext?
}

public struct ViewModifierContent<Modifier: ViewModifier>: View, ResolvableView {
  package let storage: any ViewModifierContentStorage
}
```

This is intentionally narrower than `AnyView`:

- it is package-only
- it exists only to model SwiftUI’s opaque modifier-content carrier
- the rest of modifier application stays generic

If the implementation can make the storage generic without leaking the base type
through the public API, that is even better. The important rule is that there
should be no secondary `AnyView`-style normalization after this point.

### Generic Modifier Lowering

The core package hook should be a generic modifier-lowering protocol:

```swift
@MainActor
package protocol PrimitiveViewModifier: ViewModifier where Body == Never {
  func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode]
}

@MainActor
package struct ModifierContentInputs<Base: View> {
  package let base: Base
  package let authoringContext: AuthoringContext?

  package func resolve(in context: ResolveContext) -> ResolvedNode
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode]
}
```

Key property: `PrimitiveViewModifier.resolve` remains generic over the base
content type. That keeps direct-lowering modifiers fully typed.

### `ModifiedContent` Lowering Split

`ModifiedContent` should have two lowering modes:

1. Ordinary public modifier path  
   When `Modifier` does not conform to `PrimitiveViewModifier`,
   `ModifiedContent` resolves like an ordinary `View`:
   `body == modifier.body(content: ViewModifierContent(...))`.

2. Package fast path  
   When `Modifier` conforms to `PrimitiveViewModifier`,
   `ModifiedContent` conditionally conforms to `ResolvableView` and lowers
   directly through `modifier.resolve(...)`.

Sketch:

```swift
extension ModifiedContent: View
where Content: View, Modifier: ViewModifier {
  public var body: some View {
    modifier.body(
      content: ViewModifierContent(
        base: content,
        authoringContext: currentAuthoringContext()
      )
    )
  }
}

extension ModifiedContent: ResolvableView
where Content: View, Modifier: PrimitiveViewModifier {
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let authoringContext = dynamicPropertyAuthoringContext(for: context)
    let inputs = ModifierContentInputs(
      base: content,
      authoringContext: authoringContext
    )
    return withAuthoringContext(authoringContext) {
      modifier.resolve(content: inputs, in: context)
    }
  }
}
```

This gives the public surface a real modifier model without exposing lowering.

### Authoring Context, State, And Lifecycle Semantics

The new design must preserve three existing behaviors:

1. Modifier state belongs to the modifier application site.
2. Lifecycle/task modifiers register against the modified identity, not against
   an incidental wrapper type.
3. Child content resolves under child contexts exactly as it does today.

Implications:

- `ModifiedContent` is the view-graph node for modifier application.
- Public modifiers that go through `body(content:)` use the normal body-based
  authoring path and therefore get `@State`, `@Environment`, and closure
  rebinding “for free.”
- Primitive modifiers must establish `dynamicPropertyAuthoringContext(for:)`
  explicitly because their fast path bypasses ordinary body evaluation.
- This proposal does not require moving authoring context into
  `ResolveContext`. The current task-local system stays in force.

### Identity Semantics

Modifier application is not uniformly identity-transparent.

The framework should keep two categories:

1. Structural or decorating modifiers  
   Examples: padding, frame, overlay, background, border, offset.  
   These produce wrapper-like resolved nodes or metadata changes but do not
   replace authored identity intentionally.

2. Identity-rewriting modifiers  
   Example: `.id(_:)`.  
   These intentionally remap identity and therefore remain special at the
   lowering layer. Public `.id(_:)` accepts any `Hashable` value, matching
   SwiftUI's source-level shape, and derives an explicit identity under the
   current tree position.

This does not require a public identity-rewriting API. It only means the
package primitive modifier implementation must keep dedicated identity
rewriting behavior. Exact replacement with a concrete `Identity` remains
package-only runtime plumbing for tests and framework-owned focus/action
anchors.

## Built-In Modifier Representation

The framework should convert existing wrapper-view types into modifier values.

### Convert To Modifier Values

- `IDView` -> `IDModifier`
- `LayoutMetadataModifier` wrapper view -> `LayoutMetadataModifier` value
- `DrawMetadataModifier` wrapper view -> `DrawMetadataModifier` value
- `SemanticMetadataModifier` wrapper view -> `SemanticMetadataModifier` value
- `EnvironmentWritingModifier` wrapper view -> `EnvironmentWritingModifier`
  value
- `EnvironmentTransformModifier` wrapper view -> `EnvironmentTransformModifier`
  value
- `PaddingView` -> `PaddingModifier`
- `SafeAreaPaddingView` -> `SafeAreaPaddingModifier`
- `IgnoreSafeAreaView` -> `IgnoreSafeAreaModifier`
- `SafeAreaInsetView` -> `SafeAreaInsetModifier<Inset>`
- `BorderView` -> `BorderModifier`
- `FrameView` -> `FrameModifier`
- `FlexibleFrameView` -> `FlexibleFrameModifier`
- `OffsetView` -> `OffsetModifier`
- `PositionView` -> `PositionModifier`
- `OverlayView` -> `OverlayModifier<Overlay>`
- `BackgroundView` -> `BackgroundModifier<Background>`
- `TransitionViewModifier` -> `TransitionRegistrationModifier`
- `_AttachGestureModifier` -> `GestureAttachmentModifier<G>`
- `_ContentShapeModifier` -> `ContentShapeModifier`

### Keep As Views

Do not force non-modifier concepts into `ViewModifier`:

- `Tab`
- `ScrollView`
- `Button`
- `List`
- `Table`
- `Panel`
- presentation host/declaration views that are structurally more than modifier
  application

The clean-break line is: if the API is logically “apply something to a base
view,” use a modifier value. If the API declares a new structural view family,
keep it as a view.

## Replacing Known-Wrapper Inspection

Only two modifier-specific inspection families currently exist:

- transition effect probing in `AnyTransition`
- metadata-first child peeking in `TabView`

Both should migrate off concrete wrapper types.

### Transition Probing

Current design debt:

- `TransitionEffectContributing`
- `transitionChildForProbe`
- `Mirror` descent through known wrapper field names

Replacement:

```swift
@MainActor
package protocol TransitionEffectProvidingModifier: ViewModifier {
  func contributeTransitionEffects(into modifiers: inout TransitionModifiers)
}
```

The transition walker should understand `ModifiedContent` generically:

1. If the current value is `ModifiedContent<Content, Modifier>`, inspect the
   modifier for `TransitionEffectProvidingModifier`.
2. Recurse into `content`.
3. Only use fallback reflection for arbitrary user-authored wrapper views that
   are not modifier chains and cannot be structurally traversed another way.

This removes direct dependence on `DrawMetadataModifier`, `OffsetView`, and the
wrapper-field conventions.

### `TabView` Metadata Peeking

Current design debt:

- `TabChildMetadataContributing` implemented by wrapper views
- `withTabChildInnerContent`
- wrapper peeling in `peekTabChildMetadata(from:)`

Replacement:

```swift
@MainActor
package protocol TabItemMetadataProvidingModifier: ViewModifier {
  var tabItemMetadataContribution: PeekedTabChildMetadata { get }
}

@MainActor
package protocol TabDeclarationView {
  var tabDeclarationMetadata: PeekedTabChildMetadata { get }
  func resolveTabDeclarationContent(in context: ResolveContext) -> ResolvedNode
}
```

Rules:

- `ModifiedContent` chains are inspected generically.
- Modifier-side `label`/`tag` semantics live on modifier values, not wrapper
  views.
- `Tab` remains a declaration-specific view protocol because it is not a
  modifier and because direct selected-child resolution is part of its job.

This eliminates `withTabChildInnerContent` and all wrapper-specific conformances
for `.semanticMetadata(...)` and `.tag(...)`.

## Erasure Policy

Because the user-facing design explicitly prefers generics over `AnyView`, the
modifier system should adopt these hard rules:

1. `ModifiedContent` is always generic over `Content` and `Modifier`.
2. Built-in modifiers remain generic over their view payloads:
   `OverlayModifier<Overlay>`, `BackgroundModifier<Background>`,
   `SafeAreaInsetModifier<Inset>`, etc.
3. `PrimitiveViewModifier.resolve` is generic over the base content.
4. Transition probing and tab peeking operate on `ModifiedContent` chains, not
   on erased wrapper values.
5. The only opaque content seam is `ViewModifier.Content`, implemented with a
   package-only storage box or closure carrier.
6. No `AnyView` is permitted in the new modifier layer unless a concrete
   implementation issue proves the package-only content carrier cannot be built
   another way.

This is stricter than the current repo and intentionally so.

## Clean-Break Migration Plan

### Phase 0: Characterize Existing Behavior

Before rewriting internals, add characterization tests for:

- custom `ViewModifier` state, environment, and lifecycle behavior
- `ModifiedContent` nesting and `concat(_:)`
- `.id(_:)` identity rewriting through modifier application
- transition effect extraction through modifier chains
- `TabView` metadata peeking through `.semanticMetadata(...)` and `.tag(...)`
- representative built-in modifiers: padding, frame, offset, position,
  overlay, background, environment, border, gestures, transition registration

### Phase 1: Add Public Modifier Algebra

Create:

- `Sources/View/Foundation/ViewModifier.swift`

Add:

- `ViewModifier`
- `ViewModifierContent`
- `ModifiedContent`
- `View.modifier(_:)`
- `ViewModifier.concat(_:)`
- conditional conformances for `View`, `ViewModifier`, `Animatable`,
  `Equatable`, and `Sendable`

Do not convert built-in modifiers yet. Land the public algebra first.

### Phase 2: Add Package Lowering Hooks

Create:

- `PrimitiveViewModifier`
- `ModifierContentInputs<Base>`
- package storage for `ViewModifierContent`

Teach `ModifiedContent` to:

- use ordinary body-based lowering for public modifiers
- use direct `ResolvableView` lowering for primitive modifiers

This is the phase that preserves authoring-context and identity behavior.

### Phase 3: Convert Built-In Modifier Families

Rewrite built-in modifier extension methods to apply modifier values rather than
return wrapper views.

Target files:

- `Sources/View/Modifiers/ViewModifiers.swift`
- `Sources/View/Modifiers/StyleModifiers.swift`
- `Sources/View/Gestures/GestureViewModifier.swift`
- `Sources/View/Animation/TransitionModifier.swift`

Delete the wrapper-view fleet once the modifier-value equivalents compile.

### Phase 4: Replace Wrapper Inspection With Modifier Capabilities

Target files:

- `Sources/View/Animation/AnyTransition.swift`
- `Sources/View/NavigationViews/TabView.swift`
- `Sources/View/NavigationViews/Tab.swift`
- `Sources/View/Modifiers/StyleModifiers.swift`

Changes:

- replace `TransitionEffectContributing` with
  `TransitionEffectProvidingModifier`
- remove `transitionChildForProbe`
- remove known-wrapper `Mirror` dependence as the primary transition mechanism
- replace wrapper-side `TabChildMetadataContributing` usage with
  `TabItemMetadataProvidingModifier`
- retain only one declaration-specific protocol for `Tab`

### Phase 5: Delete Obsolete Types And Helpers

Delete:

- `IDView`
- `PaddingView`
- `SafeAreaPaddingView`
- `IgnoreSafeAreaView`
- `SafeAreaInsetView`
- `BorderView`
- `FrameView`
- `FlexibleFrameView`
- `OffsetView`
- `PositionView`
- `OverlayView`
- `BackgroundView`
- wrapper-view versions of metadata/environment modifiers
- `resolveWrapperContent`
- `TransitionEffectContributing`
- `withTabChildInnerContent`

Rename files if needed so the source layout reflects modifier values rather than
wrapper views.

### Phase 6: Documentation Cleanup

Update:

- `docs/PUBLIC_API_INVENTORY.md`
- `docs/PUBLIC_SURFACE_POLICY.md`
- `docs/SOURCE_LAYOUT.md`
- `docs/README.md`
- `Sources/View/View.docc/Authoring-Views.md`
- `Sources/View/View.docc/View.md`

Document the new rules clearly:

- public modifiers are first-class
- lowering remains package-only
- built-in modifier internals are modifier values, not wrapper views
- generic modifier chains are the default representation
- the only permitted opaque seam is `ViewModifier.Content`

## Debt Explicitly Paid Down

This proposal is only worthwhile if it deletes the existing debt instead of
layering over it.

Debt that must disappear by the end:

- wrapper views as the main modifier representation
- modifier-specific runtime inspection by concrete wrapper type
- wrapper-field peeling in `TabView`
- wrapper-child probing in `AnyTransition`
- ad hoc role strings standing in for modifier application structure
- any new `AnyView` introduced purely to make the modifier layer compile

## Risks

### 1. Overusing The Primitive Fast Path

If too many framework-owned modifiers take the package fast path without a real
need, the system becomes a new special-case maze.

Rule: use `PrimitiveViewModifier` only when the modifier must directly affect
resolve-time structure, identity, environment, or registration behavior.
Purely compositional built-ins may still use `body(content:)`.

### 2. Regressing Authoring Context

The modifier fast path bypasses normal body evaluation. If it forgets to
establish `dynamicPropertyAuthoringContext(for:)`, state/lifecycle behavior will
silently regress.

Rule: `ModifiedContent` owns this setup centrally so individual modifiers do not
reimplement it.

### 3. Reintroducing Erasure Through Convenience

The easiest implementation path will often be `AnyView`.

Rule: reject that by default. If a specific case cannot avoid an opaque carrier,
limit it to the public `ViewModifier.Content` seam and document why.

## End State Checklist

The migration is complete only when all of these are true:

- public `ViewModifier` / `ModifiedContent` exist
- built-in `View` modifiers apply modifier values through `.modifier(...)`
- `ModifiedContent` is the canonical modifier node
- the modifier system is generic except for `ViewModifier.Content`
- no package-only wrapper views remain as the main modifier model
- transition probing no longer depends on concrete wrapper types
- `TabView` peeking no longer peels wrapper views
- docs describe modifiers as first-class public surface, not wrapper-backed
  implementation detail

At that point the repo has a real SwiftUI-shaped modifier architecture instead
of a wrapper-view approximation.
