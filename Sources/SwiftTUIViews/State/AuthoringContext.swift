package import SwiftTUICore

// The authoring context — runtime identity carried across a resolve pass.
//
// `AuthoringContext` is the task-local that travels alongside view resolution:
// it names the view currently authoring (`viewIdentity`), its structural
// position (`structuralIdentity`), the focused values in scope, and the live
// `ViewNode` backing it. `@State` storage, bindings, and imperative callbacks
// all key off this identity, so the graph-scoped identity helpers that map a
// view identity into per-graph storage live here too.
//
// Split out of `State.swift` so that file stays focused on the `@State`
// property wrapper and its backing storage. `AuthoringOrdinalTracker` and
// `StateSlotOrdinals` stay with `State.swift` — they are storage-slot
// machinery, not authoring-context machinery.

struct ViewGraphScopeID: Hashable, Sendable {
  fileprivate let rawValue: UInt

  package init(_ viewGraph: SwiftTUICore.ViewGraph) {
    rawValue = UInt(bitPattern: ObjectIdentifier(viewGraph))
  }

  package init(rawValue: UInt) {
    self.rawValue = rawValue
  }
}

@MainActor
package struct AuthoringContext {
  /// Owner identity — used for invalidation routing, `@State` ownership,
  /// and follow-up identity captured by control action closures. Stable
  /// across per-iteration content expansion inside containers like
  /// `ForEach`; identifies the view struct currently authoring, not the
  /// structural position of a repeated child.
  var viewIdentity: Identity
  /// Structural identity — the authoring "position" in the view tree.
  /// Identity-deriving modifiers such as `.panel()` read this so they
  /// can distinguish per-iteration instances inside a `ForEach`. At the
  /// outermost authoring scope this equals `viewIdentity`; container
  /// iteration (e.g. `ForEach`) is the only context that diverges them.
  var structuralIdentity: Identity
  var focusedValues: FocusedValues
  var viewNode: SwiftTUICore.ViewNode?
  var ordinalTracker: AuthoringOrdinalTracker = .init()

  /// Primary initializer. `structuralIdentity` defaults to `viewIdentity`
  /// so non-iterating construction sites (the common case) need not
  /// distinguish the two — they're equal. `ForEach` is the only writer
  /// that currently diverges them by supplying a per-iteration
  /// `structuralIdentity`.
  init(
    viewIdentity: Identity,
    structuralIdentity: Identity? = nil,
    focusedValues: FocusedValues,
    viewNode: SwiftTUICore.ViewNode? = nil,
    ordinalTracker: AuthoringOrdinalTracker = .init()
  ) {
    self.viewIdentity = viewIdentity
    self.structuralIdentity = structuralIdentity ?? viewIdentity
    self.focusedValues = focusedValues
    self.viewNode = viewNode
    self.ordinalTracker = ordinalTracker
  }
}

package enum AuthoringContextStorage {
  @TaskLocal static var current: AuthoringContext?
}

@MainActor
package func currentAuthoringContext() -> AuthoringContext? {
  AuthoringContextStorage.current
}

@MainActor
func graphScopeID(for context: AuthoringContext?) -> ViewGraphScopeID? {
  context?.viewNode?.ownerGraph.map(ViewGraphScopeID.init)
}

// Graph-scoped identities are internal storage identities. Public invalidation
// and authored structural identities continue to use the base view identity.
let stateGraphIdentityPrefix = "__SwiftTUIStateGraph["
let stateGraphIdentitySuffix = "]"

func stateStorageIdentity(
  for viewIdentity: Identity,
  graphID: ViewGraphScopeID?
) -> Identity {
  guard let graphID else {
    return viewIdentity
  }
  return viewIdentity.child(
    "\(stateGraphIdentityPrefix)\(graphID.rawValue)\(stateGraphIdentitySuffix)")
}

func graphScopeID(from identity: Identity) -> ViewGraphScopeID? {
  guard
    let component = identity.lastComponent,
    component.hasPrefix(stateGraphIdentityPrefix),
    component.hasSuffix(stateGraphIdentitySuffix)
  else {
    return nil
  }

  let start = component.index(component.startIndex, offsetBy: stateGraphIdentityPrefix.count)
  let end = component.index(component.endIndex, offsetBy: -stateGraphIdentitySuffix.count)
  guard let rawValue = UInt(component[start..<end]) else {
    return nil
  }
  return ViewGraphScopeID(rawValue: rawValue)
}

func baseStateStorageIdentity(from identity: Identity) -> Identity {
  graphScopeID(from: identity) == nil ? identity : identity.parent ?? identity
}

@MainActor
package func makeAuthoringContext(
  for context: ResolveContext,
  viewNode: SwiftTUICore.ViewNode? = ViewNodeContext.current
) -> AuthoringContext {
  AuthoringContext(
    viewIdentity: context.identity,
    focusedValues: context.focusedValues,
    viewNode: viewNode,
    ordinalTracker: .init()
  )
}

@MainActor
package func dynamicPropertyAuthoringContext(
  for context: ResolveContext,
  current: AuthoringContext? = currentAuthoringContext(),
  viewNode: SwiftTUICore.ViewNode? = ViewNodeContext.current
) -> AuthoringContext {
  if let current, current.viewNode === viewNode {
    return AuthoringContext(
      viewIdentity: context.identity,
      focusedValues: context.focusedValues,
      viewNode: viewNode,
      ordinalTracker: current.ordinalTracker
    )
  }

  return makeAuthoringContext(
    for: context,
    viewNode: viewNode
  )
}

@MainActor
package func makeDeferredAuthoringContext(
  from context: AuthoringContext? = currentAuthoringContext()
) -> AuthoringContext? {
  guard let context else {
    return nil
  }

  let ordinalTracker = AuthoringOrdinalTracker()
  ordinalTracker.freeze()
  return AuthoringContext(
    viewIdentity: context.viewIdentity,
    structuralIdentity: context.structuralIdentity,
    focusedValues: context.focusedValues,
    viewNode: context.viewNode,
    ordinalTracker: ordinalTracker
  )
}

@MainActor
package func withAuthoringContext<Result>(
  _ context: AuthoringContext?,
  _ apply: () -> Result
) -> Result {
  AuthoringContextStorage.$current.withValue(context) {
    apply()
  }
}

@MainActor
package func withAuthoringContext<Result>(
  _ context: AuthoringContext?,
  _ apply: () async -> Result
) async -> Result {
  await AuthoringContextStorage.$current.withValue(context) {
    await apply()
  }
}

/// A sendable snapshot of the graph-scoped authoring identity an imperative
/// callback should mutate through when it fires outside a resolve pass.
///
/// The snapshot intentionally stores identity and focused values only. It must
/// not retain the `ViewNode`; callbacks recover the current graph-bound state
/// location through the identity captured at registration time.
package struct ImperativeAuthoringContextSnapshot: Sendable {
  package let viewIdentity: Identity
  package let focusedValues: FocusedValues

  @MainActor
  package init?(_ context: AuthoringContext? = currentAuthoringContext()) {
    guard let context else {
      return nil
    }
    viewIdentity = stateStorageIdentity(
      for: context.viewIdentity,
      graphID: graphScopeID(for: context)
    )
    focusedValues = context.focusedValues
  }

  @MainActor
  fileprivate var authoringContext: AuthoringContext {
    AuthoringContext(
      viewIdentity: viewIdentity,
      focusedValues: focusedValues
    )
  }
}

@MainActor
package func currentImperativeAuthoringContextSnapshot() -> ImperativeAuthoringContextSnapshot? {
  ImperativeAuthoringContextSnapshot()
}

@MainActor
package func withImperativeAuthoringContext<Result>(
  _ snapshot: ImperativeAuthoringContextSnapshot?,
  _ apply: () -> Result
) -> Result {
  withAuthoringContext(snapshot?.authoringContext) {
    apply()
  }
}

@MainActor
package func withImperativeAuthoringContext<Result>(
  _ snapshot: ImperativeAuthoringContextSnapshot?,
  _ apply: () async -> Result
) async -> Result {
  await withAuthoringContext(snapshot?.authoringContext) {
    await apply()
  }
}
