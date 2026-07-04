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
  var structuralPath: StructuralPath
  var focusedValues: FocusedValues
  var viewNode: SwiftTUICore.ViewNode?
  var ownerNodeID: SwiftTUICore.ViewNodeID?
  var stateGraphScope: StateGraphScopeID?
  var ordinalTracker: AuthoringOrdinalTracker = .init()

  /// Primary initializer. `structuralIdentity` defaults to `viewIdentity`
  /// so non-iterating construction sites (the common case) need not
  /// distinguish the two — they're equal. `ForEach` is the only writer
  /// that currently diverges them by supplying a per-iteration
  /// `structuralIdentity`.
  init(
    viewIdentity: Identity,
    structuralIdentity: Identity? = nil,
    structuralPath: StructuralPath? = nil,
    focusedValues: FocusedValues,
    viewNode: SwiftTUICore.ViewNode? = nil,
    ownerNodeID: SwiftTUICore.ViewNodeID? = nil,
    stateGraphScope: StateGraphScopeID? = nil,
    ordinalTracker: AuthoringOrdinalTracker = .init()
  ) {
    self.viewIdentity = viewIdentity
    let resolvedStructuralPath =
      structuralPath ?? structuralIdentity.map(StructuralPath.init(identity:))
      ?? StructuralPath(identity: viewIdentity)
    self.structuralPath = resolvedStructuralPath
    self.structuralIdentity = structuralIdentity ?? resolvedStructuralPath.identityProjection
    self.focusedValues = focusedValues
    self.viewNode = viewNode
    self.ownerNodeID = ownerNodeID ?? viewNode?.viewNodeID
    self.stateGraphScope =
      stateGraphScope ?? viewNode?.ownerGraph.map(StateGraphScopeID.init)
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
func graphScopeID(for context: AuthoringContext?) -> StateGraphScopeID? {
  context?.stateGraphScope ?? context?.viewNode?.ownerGraph.map(StateGraphScopeID.init)
}

package struct StateStorageOwner: Hashable, Sendable {
  package var graphScope: StateGraphScopeID?
  package var ownerNodeID: ViewNodeID

  package init(
    graphScope: StateGraphScopeID?,
    ownerNodeID: ViewNodeID
  ) {
    self.graphScope = graphScope
    self.ownerNodeID = ownerNodeID
  }
}

@MainActor
package func stateStorageOwner(
  for context: AuthoringContext
) -> StateStorageOwner? {
  let ownerNodeID: ViewNodeID?
  if let contextOwnerNodeID = context.ownerNodeID {
    ownerNodeID = contextOwnerNodeID
  } else {
    ownerNodeID = context.viewNode?.viewNodeID
  }
  guard let ownerNodeID else {
    return nil
  }
  return StateStorageOwner(
    graphScope: graphScopeID(for: context),
    ownerNodeID: ownerNodeID
  )
}

/// Resolves the live owner node an authoring context names, for property
/// wrappers whose accesses run outside any resolve pass (a `.task` loop, a
/// gesture or action callback). During a resolve pass the enclosing graph is
/// the source of truth; the captured scope must match it so a scoped subtree
/// never reaches into a different graph than the one resolving it. Outside a
/// resolve pass the live graph is recovered from the captured scope via
/// `LiveViewGraphRegistry` — weak, so a retired graph yields nil and the
/// caller falls back to its seed storage.
@MainActor
package func liveAuthoringOwnerNode(
  ownerNodeID: ViewNodeID?,
  stateGraphScope: StateGraphScopeID?
) -> SwiftTUICore.ViewNode? {
  guard let ownerNodeID else {
    return nil
  }

  if ViewNodeContext.current != nil {
    guard let currentGraph = ViewNodeContext.current?.ownerGraph else {
      return nil
    }
    if let stateGraphScope,
      stateGraphScope != StateGraphScopeID(currentGraph)
    {
      return nil
    }
    return currentGraph.nodeForViewNodeID(ownerNodeID)
  }

  guard
    let stateGraphScope,
    let scopedGraph = LiveViewGraphRegistry.graph(for: stateGraphScope)
  else {
    return nil
  }
  return scopedGraph.nodeForViewNodeID(ownerNodeID)
}

package struct CapturedAuthoringContextSnapshot: Sendable {
  package let viewIdentity: Identity
  package let structuralIdentity: Identity
  package let structuralPath: StructuralPath
  package let focusedValues: FocusedValues
  package let ownerNodeID: SwiftTUICore.ViewNodeID?
  package let stateGraphScope: StateGraphScopeID?

  @MainActor
  package init?(_ context: AuthoringContext? = currentAuthoringContext()) {
    guard let context else {
      return nil
    }
    viewIdentity = context.viewIdentity
    structuralIdentity = context.structuralIdentity
    structuralPath = context.structuralPath
    focusedValues = context.focusedValues
    ownerNodeID = context.ownerNodeID
    stateGraphScope = graphScopeID(for: context)
  }

  @MainActor
  package var authoringContext: AuthoringContext {
    let ordinalTracker = AuthoringOrdinalTracker()
    ordinalTracker.freeze()
    return AuthoringContext(
      viewIdentity: viewIdentity,
      structuralIdentity: structuralIdentity,
      structuralPath: structuralPath,
      focusedValues: focusedValues,
      viewNode: nil,
      ownerNodeID: ownerNodeID,
      stateGraphScope: stateGraphScope,
      ordinalTracker: ordinalTracker
    )
  }
}

package struct CapturedSubviewScope: Sendable {
  private let snapshot: CapturedAuthoringContextSnapshot?

  @MainActor
  package init(
    from context: AuthoringContext? = currentAuthoringContext()
  ) {
    snapshot = CapturedAuthoringContextSnapshot(context)
  }

  @MainActor
  package var authoringContext: AuthoringContext? {
    snapshot?.authoringContext
  }
}

@MainActor
package func makeCapturedSubviewScope(
  from context: AuthoringContext? = currentAuthoringContext()
) -> CapturedSubviewScope {
  CapturedSubviewScope(from: context)
}

@MainActor
package func makeAuthoringContext(
  for context: ResolveContext,
  viewNode: SwiftTUICore.ViewNode? = ViewNodeContext.current
) -> AuthoringContext {
  AuthoringContext(
    viewIdentity: context.identity,
    structuralPath: context.structuralPath,
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
      structuralPath: context.structuralPath,
      focusedValues: context.focusedValues,
      viewNode: viewNode,
      ownerNodeID: current.ownerNodeID,
      stateGraphScope: current.stateGraphScope,
      ordinalTracker: current.ordinalTracker
    )
  }

  return makeAuthoringContext(
    for: context,
    viewNode: viewNode
  )
}

@MainActor
package func makeCapturedAuthoringContext(
  from context: AuthoringContext? = currentAuthoringContext()
) -> AuthoringContext? {
  CapturedAuthoringContextSnapshot(context)?.authoringContext
}

@MainActor
package func makePortalAttachmentAuthoringContext(
  from context: AuthoringContext? = currentAuthoringContext()
) -> AuthoringContext? {
  makeCapturedAuthoringContext(from: context)
}

@MainActor
package func makeLazySubviewAuthoringContext(
  from context: AuthoringContext? = currentAuthoringContext()
) -> AuthoringContext? {
  makeCapturedAuthoringContext(from: context)
}

@MainActor
package func makeLayoutRealizedAuthoringContext(
  from context: AuthoringContext? = currentAuthoringContext()
) -> AuthoringContext? {
  makeCapturedAuthoringContext(from: context)
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
  package let ownerNodeID: SwiftTUICore.ViewNodeID?
  package let stateGraphScope: StateGraphScopeID?

  @MainActor
  package init?(_ context: AuthoringContext? = currentAuthoringContext()) {
    guard let context else {
      return nil
    }
    viewIdentity = context.viewIdentity
    focusedValues = context.focusedValues
    ownerNodeID = context.ownerNodeID
    stateGraphScope = graphScopeID(for: context)
  }

  @MainActor
  fileprivate var authoringContext: AuthoringContext {
    // Focused values are runtime state, not registration state: prefer the
    // graph scope's live set at fire time so `@FocusedValue`/`@FocusedBinding`
    // reads inside imperative callbacks track focus moves that happened after
    // this snapshot was captured. The captured set remains the fallback for
    // scopes without a live provider (snapshot rendering, retired graphs).
    let liveFocusedValues = stateGraphScope.flatMap {
      LiveFocusedValuesRegistry.currentFocusedValues(for: $0)
    }
    return AuthoringContext(
      viewIdentity: viewIdentity,
      focusedValues: liveFocusedValues ?? focusedValues,
      ownerNodeID: ownerNodeID,
      stateGraphScope: stateGraphScope
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
