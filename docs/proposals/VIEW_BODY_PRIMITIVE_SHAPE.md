# View Body Primitive Shape

**Date:** 2026-05-10  
**Status:** Proposed  
**Scope:** `View`, `ResolvableView`, `ViewModifier`, primitive lowering, public protocol conformance diagnostics

## Summary

SwiftTUI currently lets this compile:

```swift
import SwiftTUI

struct TestView: View {}
```

SwiftUI rejects the same shape because a user-defined `View` must either expose
a composed `body` or conform through a separate primitive protocol that supplies
the framework-owned implementation requirements. SwiftTUI accepts the empty
conformance because the public `View` protocol currently defaults `Body` to
`Never`, and an unconditional `extension View` supplies `body: Never`.

The fix is to move the primitive-body escape hatch off the public `View`
protocol and onto the package-only primitive lowering seam. In SwiftTUI, that
seam is currently `ResolvableView`. Public `View` should be body-only;
package-owned primitive views should be `ResolvableView` values whose
`Body == Never` witness is supplied through that package protocol.

`ViewModifier` has a related but slightly different mismatch. It should keep the
SwiftUI-compatible primitive modifier body default for explicitly primitive
modifiers, but it must not default `Body` to `Never`, and its default
`body(content:)` witness must return `Body`, not a concrete `Never`, so the
compiler does not infer a primitive modifier from an empty conformance.

## Problem

The current public `View` declaration in
`Sources/SwiftTUIViews/Foundation/ViewFoundation.swift` is:

```swift
@MainActor
public protocol View {
  associatedtype Body: View = Never

  @ViewBuilder @MainActor
  var body: Body { get }
}
```

The current public extension in
`Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift` is:

```swift
extension View {
  public var body: Never {
    fatalError("\(Self.self) is a primitive view and does not expose a composed body.")
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveViewElements(self, in: context)
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    resolveView(self, in: context)
  }
}
```

Together, those two facts let the compiler synthesize this conformance:

```text
TestView.Body == Never
TestView.body witness == SwiftTUIViews.View.body.getter : Never
```

That is wrong for consumer-authored views. A plain `View` conformance should
mean "this type describes its content through `body`." Primitive lowering is a
framework-owned capability, not the default meaning of `View`.

The bug is not in `resolveViewElements(...)` itself. The resolver correctly
checks whether a value is `ResolvableView` before calling primitive lowering.
The bug is that the public protocol surface makes every `View` eligible to be
treated as a primitive at compile time, even if the type does not conform to
`ResolvableView`.

## SwiftUI Shape

The current SwiftUI SDK shape is materially different:

```swift
@MainActor
public protocol View {
  associatedtype Body: View
  @ViewBuilder @MainActor var body: Self.Body { get }
}

extension Never: View {}
```

Important properties:

1. `View.Body` has no public default.
2. `View` has no public `body: Never` default.
3. `Never` conforms to `View`, allowing framework-owned primitive types to use
   `Body == Never`.
4. A user-defined `struct TestView: View {}` does not compile.
5. A user-defined `struct TestView: View { typealias Body = Never }` also does
   not compile unless it supplies a `body` witness or conforms through another
   framework protocol that owns the primitive implementation.

SwiftUI's `ViewModifier` also has no associated-type default:

```swift
@MainActor
public protocol ViewModifier {
  associatedtype Body: View
  @ViewBuilder @MainActor func body(content: Self.Content) -> Self.Body
}

extension ViewModifier where Self.Body == Never {
  public func body(content: Self.Content) -> Self.Body
}
```

That permits explicit primitive modifiers:

```swift
struct PrimitiveModifier: ViewModifier {
  typealias Body = Never
}
```

But it rejects an empty modifier:

```swift
struct EmptyModifier: ViewModifier {}
```

SwiftTUI should match those compile-time boundaries.

## Target SwiftTUI Shape

### Public `View`

`View` becomes body-only:

```swift
@MainActor
public protocol View {
  associatedtype Body: View

  @ViewBuilder @MainActor
  var body: Body { get }
}
```

`Never` remains the bottom-body witness:

```swift
extension Never: View {
  public typealias Body = Never

  public var body: Never {
    fatalError("Never.body is unreachable.")
  }
}
```

There must be no public or package extension directly on `View` that supplies a
`body` witness, including this seemingly narrower variant:

```swift
extension View where Body == Never {
  var body: Body { ... }
}
```

Swift can infer `Body == Never` from such an extension for an empty conformer,
so the extension still leaks primitive behavior to arbitrary views.

### Package Primitive View Seam

`ResolvableView` should become the package-only primitive view protocol:

```swift
@MainActor
package protocol ResolvableView: View where Body == Never {
  func resolveElements(in context: ResolveContext) -> [ResolvedNode]
}

extension ResolvableView {
  public var body: Body {
    fatalError("\(Self.self) is a primitive view and does not expose a composed body.")
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    resolveView(self, in: context)
  }
}
```

This makes the inheritance hierarchy match the behavior SwiftTUI already wants:

```text
View
+-- user-authored body views
+-- ResolvableView where Body == Never
    +-- Text, EmptyView, Group, ForEach, GeometryReader, Canvas, controls, shapes, ...
```

The public `View` protocol stays clean. The primitive-body default only exists
for types that opt into package-owned lowering.

The existing package helpers that are useful for any `View`, such as
`resolveElements(in:)` and `resolve(in:)`, may remain as package methods on
`extension View`. They must not include a public `body` witness.

### Public Built-In Views

Built-in primitive views should continue to compile because they conform to
`ResolvableView`, directly or indirectly:

```swift
public struct Text: View, ResolvableView { ... }
public struct EmptyView: View, ResolvableView { ... }
public struct Rectangle: InsettableShape, ResolvableView { ... }
```

They do not all need explicit `typealias Body = Never` declarations if the
`ResolvableView` protocol constraint and extension supply the witness. Existing
explicit `body: Never` declarations may remain temporarily if removing them
would make the first migration too noisy. The final shape should prefer one
primitive-body source of truth on `ResolvableView`.

### `DeclaredChildrenView`

`DeclaredChildrenView` should remain a separate package protocol. It describes
builder-child enumeration, not primitive lowering by itself. Most conformers are
also `ResolvableView`, but the relationship should not be encoded unless every
current and planned declared-child value is necessarily a primitive resolver.

### `ViewModifier`

`ViewModifier` should remove the associated-type default:

```swift
@MainActor
public protocol ViewModifier {
  associatedtype Body: View
  typealias Content = ViewModifierContent<Self>

  @ViewBuilder
  func body(content: Content) -> Body
}
```

The primitive modifier default should stay, but its signature must return
`Body`, not the concrete type `Never`:

```swift
extension ViewModifier where Body == Never {
  public func body(content _: Content) -> Body {
    fatalError("\(Self.self) is a primitive modifier and does not expose a composed body.")
  }
}
```

That distinction matters. With no `Body` default, a constrained extension whose
method returns `Never` can still let Swift infer `Body == Never` for an empty
conformer. Returning `Body` matches SwiftUI's interface shape and keeps empty
modifier conformances invalid while preserving explicit primitive modifiers.

`PrimitiveViewModifier` remains the package-only fast path:

```swift
@MainActor
package protocol PrimitiveViewModifier: ViewModifier where Body == Never {
  func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode]
}
```

Framework-owned primitive modifiers continue to conform through
`PrimitiveViewModifier`. Consumer-authored primitive modifiers may explicitly
write `typealias Body = Never`, but they do not gain package primitive lowering.

## Resolver Semantics

The resolver's runtime behavior should stay conceptually unchanged:

1. If a value conforms to `ResolvableView`, call `resolveElements(in:)`.
2. Otherwise, evaluate `body`.
3. Normalize zero, one, or many resolved elements as today.

The change is compile-time ownership, not runtime lowering:

- Today, an empty user `View` compiles and traps if resolved.
- After this migration, it fails before the resolver sees it.
- Built-in primitive views still resolve directly.
- Body-based user views still resolve through normal body evaluation.

## Public Surface Policy

The existing policy already says:

- Public `View` stays body-only.
- Internal lowering protocols such as `ResolvableView` stay package-only.
- Direct primitive lowering stays package-only through hooks such as
  `PrimitiveViewModifier`.

This proposal makes the implementation match that policy. The public API
baseline should change because the broad `View.body: Never` extension is no
longer public surface. That is an intended source break for invalid conformers.

## Non-Goals

1. Do not change renderer, layout, draw, raster, or commit semantics.
2. Do not make `ResolvableView` public.
3. Do not introduce a public `_PrimitiveView` API.
4. Do not preserve source compatibility for invalid empty `View` or
   `ViewModifier` conformances.
5. Do not migrate the gesture protocol hierarchy in this tranche, except for
   comment fixes made necessary by the `Never: View` witness remaining in
   `ViewFoundation.swift`.
6. Do not revisit the shipped `ModifiedContent` wrapper-to-modifier migration.

## Validation Requirements

Future implementation must add compile-time regression coverage for these
consumer-facing cases:

```swift
// Must fail.
struct EmptyUserView: View {}

// Must fail.
struct ExplicitNeverUserView: View {
  typealias Body = Never
}

// Must pass.
struct BodyUserView: View {
  var body: some View { Text("ok") }
}

// Must fail.
struct EmptyUserModifier: ViewModifier {}

// Must pass.
struct ExplicitPrimitiveModifier: ViewModifier {
  typealias Body = Never
}
```

It must also retain runtime coverage for representative primitives:

- `Text`
- `EmptyView`
- `Group`
- `ForEach`
- `GeometryReader`
- `Canvas`
- at least one `Shape`
- at least one primitive `ViewModifier`

## Open Decisions

None for the first migration. If the package protocol extension cannot provide
a public `body` witness for every public primitive under the active Swift 6.3
toolchain, the implementation should not broaden `View` again. It should add
explicit `public typealias Body = Never` and `public var body: Never` witnesses
to the affected primitive types, then continue toward the same public shape.
