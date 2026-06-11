public import SwiftTUICore

/// Resolves authored views into resolved render trees.
///
/// This is the lowest public entry point for inspecting the authored view tree
/// before layout, semantics, draw extraction, and rasterization occur.
public struct Resolver {
  public init() {}

  /// Resolves `root` in the supplied context.
  @MainActor
  public func resolve<V: View>(
    _ root: V,
    in context: ResolveContext = .init()
  ) -> ResolvedNode {
    resolveView(root, in: context)
  }
}

@MainActor
package func scopedAnyView<V: View>(
  authoringContext: AuthoringContext? = currentAuthoringContext(),
  _ build: () -> V
) -> AnyView {
  // AnyView policy: use this helper instead of plain AnyView(...) when stored
  // authored content must preserve its original authored context.
  withAuthoringContext(authoringContext) {
    AnyView(
      scoped: build(),
      authoringContext: authoringContext
    )
  }
}

@MainActor
package func appendDeclaredChildNodes<V: View>(
  _ view: V,
  in context: ResolveContext,
  kindName: String,
  nextIndex: inout Int,
  into resolved: inout [ResolvedNode]
) {
  let erased: Any = view
  if let structural = erased as? any DeclaredChildrenView {
    structural.appendDeclaredChildren(
      in: context,
      kindName: kindName,
      nextIndex: &nextIndex,
      into: &resolved
    )
    return
  }

  let childContext = context.indexedChild(
    kind: .init(rawValue: kindName),
    index: nextIndex
  )
  nextIndex += 1

  if context.viewGraph != nil {
    let resolvedNode = resolveView(view, in: childContext)
    if resolvedNode.identity == childContext.identity,
      resolvedNode.kind == .view("EmptyView")
    {
      return
    }
    if resolvedNode.identity == childContext.identity,
      resolvedNode.kind == .view("Group")
    {
      resolved.append(contentsOf: resolvedNode.children)
      return
    }
    resolved.append(resolvedNode)
    return
  }

  let elements = resolveViewElements(view, in: childContext)
  childContext.recordResolvedComputation(count: elements.count)
  resolved.append(contentsOf: elements)
}

@MainActor
package func resolveDeclaredChildren<V: View>(
  _ view: V,
  in context: ResolveContext,
  kindName: String
) -> [ResolvedNode] {
  var resolved: [ResolvedNode] = []
  var nextIndex = 0
  appendDeclaredChildNodes(
    view,
    in: context,
    kindName: kindName,
    nextIndex: &nextIndex,
    into: &resolved
  )
  assignEntityIdentityOccurrences(to: &resolved)
  return resolved
}

package func assignEntityIdentityOccurrences(to resolved: inout [ResolvedNode]) {
  var counts: [AnyID: Int] = [:]

  for index in resolved.indices {
    guard let entityIdentity = resolved[index].entityIdentity,
      resolved[index].entityStructuralPath == resolved[index].structuralPath
    else {
      continue
    }

    let occurrence = counts[entityIdentity.value, default: 0]
    counts[entityIdentity.value] = occurrence + 1
    resolved[index].entityIdentity = entityIdentity.withOccurrence(occurrence)
  }
}

/// Walks the declared children of `view` using the same indexing scheme as
/// `appendDeclaredChildNodes`, but invokes `visitor` with the raw typed
/// child and a lazy resolve closure instead of resolving everything
/// eagerly.
///
/// This is the "metadata-first, resolve-second" entry point used by
/// container views (like `TabView`) that need to inspect child metadata
/// cheaply before deciding which children actually need to be resolved.
/// Only evaluating selected children avoids firing lifecycle handlers
/// (`.onAppear`, `.task`) on subtrees that should not yet be live.
@MainActor
package func enumerateDeclaredChildViews<V: View>(
  _ view: V,
  in context: ResolveContext,
  kindName: String,
  nextIndex: inout Int,
  visitor: (
    _ child: Any,
    _ childContext: ResolveContext,
    _ resolveOne: @escaping @MainActor () -> ResolvedNode
  ) -> Void
) {
  let erased: Any = view
  if let structural = erased as? any DeclaredChildrenView {
    structural.enumerateDeclaredChildren(
      in: context,
      kindName: kindName,
      nextIndex: &nextIndex,
      visitor: visitor
    )
    return
  }

  let childContext = context.indexedChild(
    kind: .init(rawValue: kindName),
    index: nextIndex
  )
  nextIndex += 1

  visitor(view, childContext) {
    resolveView(view, in: childContext)
  }
}

@MainActor
package func appendDeferredDeclaredBuilderChildren<V: View>(
  from view: V,
  into children: inout [DeferredViewPayload]
) {
  let erased: Any = view
  if let structural = erased as? any DeclaredChildrenView {
    structural.appendDeferredDeclaredChildren(
      into: &children
    )
    return
  }
  children.append(
    DeferredViewPayload {
      view
    }
  )
}

@MainActor
package func deferredDeclaredBuilderChildren<V: View>(
  from view: V
) -> [DeferredViewPayload] {
  var children: [DeferredViewPayload] = []
  appendDeferredDeclaredBuilderChildren(
    from: view,
    into: &children
  )
  return children
}

@MainActor
package func resolveViewElements<V: View>(
  _ view: V,
  in context: ResolveContext
) -> [ResolvedNode] {
  let erased: Any = view
  if let resolvable = erased as? any ResolvableView {
    return resolvable.resolveElements(in: context)
  }
  return view.resolveBody(in: context) {
    view.body
  }
}

@MainActor
package func resolveViewElements<V: View & ResolvableView>(
  _ view: V,
  in context: ResolveContext
) -> [ResolvedNode] {
  view.resolveElements(in: context)
}

@MainActor
package func normalizeResolvedElements(
  _ resolvedElements: [ResolvedNode],
  in context: ResolveContext
) -> ResolvedNode {
  switch resolvedElements.count {
  case 0:
    return ResolvedNode(
      identity: context.identity,
      kind: .view("EmptyView"),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      intrinsicSize: .zero
    )
  case 1:
    return resolvedElements[0]
  default:
    var groupedChildren = resolvedElements
    assignEntityIdentityOccurrences(to: &groupedChildren)
    return ResolvedNode(
      identity: context.identity,
      kind: .view("Group"),
      children: groupedChildren,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction
    )
  }
}

@MainActor
package func resolveView<V: View>(
  _ view: V,
  in context: ResolveContext
) -> ResolvedNode {
  resolveView(
    view,
    in: context,
    authoringContextOverride: nil
  )
}

@MainActor
func resolveView<V: View>(
  _ view: V,
  in context: ResolveContext,
  authoringContextOverride: AuthoringContext?
) -> ResolvedNode {
  // Reused evaluator closures may have captured this context on a prior frame.
  // Refresh the pass-owned inputs before resolving so invalidation helpers and
  // transaction-aware reuse checks observe the current frame.
  let context = context.applyingCurrentFrameResolveInputs()
  let routeIdentity = entityRouteIdentity(for: view, in: context)
  context.viewGraph?.setSuppressesStructuralLifecycle(
    context.suppressesStructuralLifecycle,
    for: context.identity
  )
  // The run loop suppresses retained reuse for reuse-unsafe identities (focus/
  // press runtime readers and active property-animation identities): forcing
  // root evaluation only makes the walk *reach* every node — each reached node
  // still independently chooses reuse here — so affected nodes additionally
  // skip this fast path.
  if !context.effectiveSuppressesRetainedReuse(at: context.identity),
    let reused = context.viewGraph?.reusableSnapshot(
      for: context.identity,
      invalidatedIdentities: context.effectiveInvalidatedIdentities,
      invalidationSummary: context.effectiveInvalidationSummary,
      environment: context.environment,
      transaction: context.transaction,
      invalidator: context.invalidationProxy?.invalidator
    )
  {
    // `reusableSnapshot` already recorded this subtree — every non-nil return
    // routes through `recordReusedSubtree` — so re-recording here only hit the
    // `wasVisitedThisFrame` guard and returned at the root (a no-op). Drop it
    // and just restore registrations + tally the reuse.
    context.viewGraph?.restoreRuntimeRegistrations(
      for: reused,
      into: context.runtimeRegistrations
    )
    context.recordResolvedReuse(
      count: reused.subtreeNodeCount
    )
    var structurallyStamped = reused
    structurallyStamped.structuralPath = context.structuralPath
    return structurallyStamped
  }

  // Diagnostic (inert unless SWIFTTUI_REUSE_TRACE): this node is being recomputed
  // rather than reused — record why, to find what re-resolves the background on
  // sheet/palette open.
  if ReuseDenialTrace.isEnabled {
    context.viewGraph?.recordReuseDenialIfTracing(
      for: context.identity,
      suppressed: context.effectiveSuppressesRetainedReuse(at: context.identity),
      environment: context.environment,
      transaction: context.transaction,
      invalidatedIdentities: context.effectiveInvalidatedIdentities
    )
  }

  let graphNode = context.viewGraph?.beginEvaluation(
    identity: context.identity,
    entityIdentity: routeIdentity,
    invalidator: context.invalidationProxy?.invalidator,
    suppressesStructuralLifecycle: context.suppressesStructuralLifecycle
  )
  if let graphNode, graphNode.isAtOutermostEvaluationDepth {
    context.viewGraph?.setEvaluator(for: context.identity) {
      _ = resolveView(view, in: context)
    }
  }
  context.recordResolvedComputation()
  let erased: Any = view
  var accessedStateSlots = 0
  var resolved = ViewUpdateGuard.withViewUpdate {
    EnvironmentValuesStorage.$current.withValue(context.environmentValues) {
      ViewNodeContext.withValue(graphNode) {
        if erased is any ResolvableView {
          let resolve = {
            normalizeResolvedElements(
              resolveViewElements(view, in: context),
              in: context
            )
          }

          guard let authoringContextOverride else {
            return resolve()
          }

          let authoringContext = rebasedAuthoringContext(
            authoringContextOverride,
            viewNode: graphNode
          )
          return withAuthoringContext(authoringContext) {
            resolve()
          }
        }

        let authoringContext =
          authoringContextOverride.map {
            rebasedAuthoringContext($0, viewNode: graphNode)
          }
          ?? makeAuthoringContext(
            for: context,
            viewNode: graphNode
          )
        return withAuthoringContext(authoringContext) {
          let resolved = normalizeResolvedElements(
            resolveViewElements(view, in: context),
            in: context
          )
          accessedStateSlots = authoringContext.ordinalTracker.nextOrdinal
          return resolved
        }
      }
    }
  }
  assignEntityIdentityOccurrences(to: &resolved._storedChildren)
  if let graphNode {
    if let committed = context.viewGraph?.finishEvaluation(
      graphNode,
      resolved: resolved,
      accessedStateSlots: accessedStateSlots
    ) {
      resolved = committed
    } else {
      resolved.viewNodeID = graphNode.viewNodeID
      resolved.recomputeSubtreeRuntimeNodeIDsStamped()
    }
  }
  resolved.structuralPath = context.structuralPath
  return resolved
}

@MainActor
private func rebasedAuthoringContext(
  _ authoringContext: AuthoringContext,
  viewNode: SwiftTUICore.ViewNode?
) -> AuthoringContext {
  AuthoringContext(
    viewIdentity: authoringContext.viewIdentity,
    structuralIdentity: authoringContext.structuralIdentity,
    structuralPath: authoringContext.structuralPath,
    focusedValues: authoringContext.focusedValues,
    viewNode: viewNode,
    ownerNodeID: authoringContext.ownerNodeID,
    stateGraphScope: authoringContext.stateGraphScope,
    ordinalTracker: authoringContext.ordinalTracker
  )
}
