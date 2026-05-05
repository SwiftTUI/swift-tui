# AnyView Internals And Review Guide

This guide is for maintainers changing SwiftTUI itself. Consumer-facing usage
guidance lives in the `SwiftTUIViews` DocC article for `AnyView`; this document
describes the internal invariants that new erasure sites must preserve.

## Core Contract

`AnyView` is a supported public escape hatch, but it is not the repo's default
storage or composition model.

Internally, the resolver lowers `AnyView` into a stable wrapper node and a
type-aware payload node:

```text
AnyView identity
+-- AnyViewPayload<ErasedStaticType> identity
    +-- Content
```

The wrapper identity belongs to the authored `AnyView` position. The payload
identity includes `ErasedViewTypeID.identityComponent`, and the payload node
carries `ErasedViewTypeID.typeDiscriminator`.

The behavior intentionally splits into two cases:

- Same erased static payload type: preserve payload-owned state, lifecycle,
  tasks, focus/action registrations, and measurement reuse.
- Changed erased static payload type: remove the old payload subtree through
  structural `ViewGraph` removal before resolving the new content.

Explicit `.id(...)` values inside the payload remain authored identities for
focus, actions, and user-directed lookup. They do not bypass the payload type
boundary. `AnyView` asks `ViewGraph.prepareStructuralChildren(...)` to prune the
old payload subtree before new content resolves, so a repeated explicit ID
cannot keep incompatible state alive after the erased static type changes.

## Differences From SwiftUI For Maintainers

SwiftTUI intentionally follows SwiftUI's source-level spelling, but maintainers
must not treat SwiftUI's private `AnyView` behavior as this package's contract.

Key differences:

- SwiftTUI has an inspectable retained graph. `AnyView` produces real
  `AnyView` and `AnyViewPayload<ErasedStaticType>` nodes, and tests,
  diagnostics, lifecycle cleanup, focus lookup, and measurement reuse observe
  those nodes.
- SwiftTUI's state-preservation rule is explicit: the erased static payload type
  is the payload boundary. If the type changes, the old payload subtree is
  removed even when inner explicit IDs repeat.
- SwiftTUI keeps authored explicit IDs stable for runtime lookup. Do not
  namespace explicit IDs to make graph cleanup easier; that breaks focus,
  actions, and user-directed identity comparisons.
- SwiftTUI has package-only authoring context capture through
  `scopedAnyView(...)`. SwiftUI examples that store `AnyView` directly are not
  a safe template for deferred SwiftTUI content.
- SwiftTUI's terminal renderer makes structural churn more expensive. Losing a
  reusable subtree can trigger extra measurement, lifecycle churn, task
  cancellation, and larger terminal presentation damage.
- SwiftUI compatibility is not enough to justify a public erasure surface here.
  New public `[AnyView]`, `() -> AnyView`, or builder-returning-`AnyView`
  shapes still need explicit policy justification.

When reviewing an `AnyView` patch, evaluate it against these SwiftTUI-specific
rules even if the same pattern appears in SwiftUI code.

## Public-Surface Rule

Do not add new public APIs shaped like this:

```swift
public init(children: [AnyView])
public func makeBody() -> AnyView
public var accessory: AnyView { get }
public init(@ViewBuilder content: () -> AnyView)
```

Prefer these shapes:

```swift
public init<Content: View>(@ViewBuilder content: () -> Content)
public func accessory() -> some View
public struct Container<Header: View, Content: View>: View
```

Adding a new public erasure seam requires ADR-level justification. Compatibility
alone is not enough if a typed builder can express the same surface.

## Acceptable Internal Uses

### Test Fixtures And Registries

Fixture catalogs may store erased views when the fixture is intentionally a
heterogeneous registry.

```swift
// AnyView policy: fixture roots are heterogeneous by design; each entry keeps a
// stable fixture ID, and production APIs do not expose this storage shape.
struct FixtureEntry {
  let id: String
  let view: AnyView
}
```

Keep the identity source next to the erased value. Tests should assert behavior,
not rely on `AnyView` being transparent in the resolved tree.

### Builder Backbone Compatibility

The current builder backbone still flattens some structural children into
`[AnyView]`. That is tolerated because it is package-owned implementation debt
tracked by the type-erasure deferral plan, not a public pattern to copy.

```swift
package func collectChildren(
  from view: some View,
  into children: inout [AnyView]
)
```

Do not expand this pattern to new subsystems unless the deferral plan explicitly
calls for it. New builder-like code should prefer typed structural storage.

### Deferred Authored Content

When package code stores authored content for later evaluation, use
`scopedAnyView(...)`.

```swift
struct DeferredSlot {
  // AnyView policy: content is evaluated later; scopedAnyView preserves the
  // authoring context needed by dynamic properties and action invalidation.
  let content: AnyView

  init<Content: View>(@ViewBuilder content: () -> Content) {
    self.content = scopedAnyView(content)
  }
}
```

Plain `AnyView(content())` is not equivalent here. It can resolve under the
storage owner's context instead of the authoring context that declared the
dynamic properties and callbacks.

### Local Branch Unification

Some style and host integration code must return a single type from branches
whose concrete view types genuinely diverge. A local `AnyView` return can be
acceptable when the erasure is private to that file and the result immediately
re-enters normal view composition.

```swift
// AnyView policy: the style protocol requires one private transport type for
// several concrete label arrangements. The erasure is file-local and does not
// define public API.
private func label(for state: SelectionState) -> AnyView {
  switch state {
  case .selected:
    return AnyView(SelectedLabel())
  case .normal:
    return AnyView(NormalLabel())
  }
}
```

Prefer an `@ViewBuilder` helper or a private wrapper type if the caller can
consume an opaque or generic result.

### Package-Only Resolver Bridges

Package-only initializers such as `AnyView(resolving:)` and
`AnyView(erasing:)` are resolver bridges. They are not consumer API. Use them
only when code is already operating at the package lowering layer and cannot
stay in typed authored views.

## Dangerous Internal Uses

### Erasure As A Generic Shortcut

Do not introduce `AnyView` just to make a generic compile error disappear.

```swift
// Bad: erases an otherwise typed modifier layer.
let modified: AnyView = condition
  ? AnyView(content.padding())
  : AnyView(content.border(.red))
```

First try a typed modifier, a private wrapper view, or an `@ViewBuilder`
function. Erasing modifier or layout internals tends to hide structural
identity that the retained graph depends on.

### Plain AnyView For Stored Builders

```swift
// Bad for deferred content.
self.content = AnyView(content())
```

Use `scopedAnyView(content)` for stored authored content. This is especially
important for controls, focus bindings, tasks, `@State`, and action callbacks.

### Public Or Cross-Module Erased Arrays

```swift
public struct RowGroup: View {
  public let rows: [AnyView]
}
```

This makes erasure contagious. It also makes row identity a convention outside
the type system. Prefer data plus `ForEach`, or a generic container that owns a
typed builder.

### Rebuilding Views From Resolved Nodes

Avoid `ResolvedNode -> AnyView -> ResolvedNode` loops. Once content has entered
the seven-phase pipeline, keep it in pipeline artifacts. Re-erasing resolved
output back into authored views risks losing phase-specific metadata and
confuses ownership.

### Depending On Explicit IDs To Cross Type Swaps

This is intentionally unsupported:

```swift
if mode == .compact {
  AnyView(CompactPane().id("pane"))
} else {
  AnyView(ExpandedPane().id("pane"))
}
```

The explicit ID remains the external identity for focus and action lookup, but
state under `CompactPane` is removed when the payload changes to `ExpandedPane`.
State that must survive belongs above the erased boundary.

### Reusing ViewGraph.prepareStructuralChildren

`ViewGraph.prepareStructuralChildren(...)` exists for the `AnyView` payload
pre-prune path. It should not become a general-purpose diff shortcut. Calling it
from other subsystems can remove graph nodes before normal resolution has enough
context to preserve moves, registrations, or layout-dependent children.

## Test Expectations

New or changed `AnyView` behavior should cover the real retained graph path.
Renderer-level tests are preferred over resolver-only snapshots when state,
lifecycle, tasks, focus, actions, or invalidation are involved.

At minimum, a behavior-changing patch should consider:

- same static payload type preserves `@State`
- changed static payload type removes old `@State`
- changed static payload type runs disappear handlers and cancels tasks
- `scopedAnyView(...)` actions invalidate the original authoring owner
- focus and action registrations remain reachable through authored explicit IDs
- nested `AnyView` payloads preserve and reset independently
- `ForEach` identity remains data-driven inside an erased payload
- registration-alias diagnostics do not gain non-trivial aliases

Shape-sensitive tests should acknowledge the wrapper:

```text
AnyView
+-- AnyViewPayload<StaticType>
    +-- Content
```

If a test wants to inspect the concrete content, unwrap the payload deliberately
instead of asserting that `AnyView` disappears.

## Review Checklist

Before approving a new internal `AnyView` site:

1. Is the erasure private to a boundary that truly needs heterogeneous values?
2. Would `@ViewBuilder`, `some View`, or generic `Content: View` remove it?
3. If content is deferred, does the site use `scopedAnyView(...)`?
4. Is there a nearby `AnyView policy:` comment for stored erasure?
5. Does state that must survive type changes live above the erased boundary?
6. Are tests exercising the retained runtime path when behavior depends on
   state, lifecycle, focus, actions, tasks, or invalidation?
7. Does the patch avoid new public `[AnyView]`, `() -> AnyView`, or
   builder-returning-`AnyView` surfaces?
