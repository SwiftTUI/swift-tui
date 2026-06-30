package import SwiftTUICore

/// Resolves authored views into resolved render trees.
package struct Resolver {
  package init() {}

  /// Resolves `root` in the supplied context.
  @MainActor
  package func resolve<V: View>(
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
package func appendScopedDeclaredBuilderChildren<V: View>(
  from view: V,
  into children: inout [ScopedContentPayload]
) {
  let erased: Any = view
  if let structural = erased as? any DeclaredChildrenView {
    structural.appendScopedDeclaredChildren(
      into: &children
    )
    return
  }
  children.append(
    ScopedContentPayload {
      view
    }
  )
}

@MainActor
package func scopedDeclaredBuilderChildren<V: View>(
  from view: V
) -> [ScopedContentPayload] {
  var children: [ScopedContentPayload] = []
  appendScopedDeclaredBuilderChildren(
    from: view,
    into: &children
  )
  return children
}

@MainActor
package func appendLazyDeclaredBuilderChildren<V: View>(
  from view: V,
  debugName: String,
  origin: LazySubviewPayloadOrigin = .tabBody,
  lifecyclePolicy: LazySubviewLifecyclePolicy = .activeOnly,
  into children: inout [LazySubviewPayload]
) {
  var scopedChildren: [ScopedContentPayload] = []
  appendScopedDeclaredBuilderChildren(
    from: view,
    into: &scopedChildren
  )
  children.append(
    contentsOf: scopedChildren.map {
      LazySubviewPayload(
        debugName: debugName,
        origin: origin,
        lifecyclePolicy: lifecyclePolicy,
        storage: .scopedContent($0)
      )
    }
  )
}

@MainActor
package func lazyDeclaredBuilderChildren<V: View>(
  from view: V,
  debugName: String,
  origin: LazySubviewPayloadOrigin = .tabBody,
  lifecyclePolicy: LazySubviewLifecyclePolicy = .activeOnly
) -> [LazySubviewPayload] {
  var children: [LazySubviewPayload] = []
  appendLazyDeclaredBuilderChildren(
    from: view,
    debugName: debugName,
    origin: origin,
    lifecyclePolicy: lifecyclePolicy,
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

  // Memoized-body reuse: Layer A above rejected this node, but if it is only a
  // structural descendant of an invalidated ancestor whose own view value is
  // structurally unchanged (and it has no recorded dependencies and passes every
  // non-dirty reuse guard), the body re-run is redundant — reuse the committed
  // subtree via the same path as Layer A. Behind the same focus/press
  // suppression gate. `Equatable`-only, so it is inert on trees that do not opt
  // in (a non-`Equatable` view leaves `memoViewValue` nil and bails immediately).
  if !context.effectiveSuppressesRetainedReuse(at: context.identity),
    let reused = context.viewGraph?.memoizedReusableSnapshot(
      for: context.identity,
      viewValue: view,
      environment: context.environment,
      transaction: context.transaction,
      invalidatedIdentities: context.effectiveInvalidatedIdentities,
      // Focus/press env keys are excluded from `environmentSnapshot` equality
      // (they change every focus move), so a node reading them is not verified by
      // the gate's snapshot conjunct — keep such readers memo-ineligible on every
      // render path (the run loop's suppression scope is not computed one-shot).
      uncoveredEnvironmentKeys: EnvironmentValues.runtimeFocusStateDependencyKeys,
      invalidator: context.invalidationProxy?.invalidator
    )
  {
    context.viewGraph?.restoreRuntimeRegistrations(
      for: reused,
      into: context.runtimeRegistrations
    )
    context.recordResolvedReuse(count: reused.subtreeNodeCount)
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
  // Memoization diagnostics: would this recomputed node have been memoizable?
  // Captured before the body runs, while `graphNode.committed` still holds the
  // prior frame's output. In release this is sampled and opt-in via
  // `SWIFTTUI_MEMO_TRACE`; when unsampled it is a single Bool guard.
  let memoObservation = beginMemoObservation(view, graphNode: graphNode, context: context)
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
  // Shadow oracle: a would-skip node's freshly recomputed output must equal
  // the prior committed output; a mismatch is the soundness alarm. Then stash
  // this frame's view value for next frame's comparison.
  if let memoObservation {
    finishMemoObservation(memoObservation, newResolved: resolved)
  }
  if shouldCaptureMemoViewValue(view) {
    graphNode?.memoViewValue = view
  }
  return resolved
}

/// Whether to stash the resolved view value for next-frame memo comparison.
///
/// The production gate (``MemoReuseConfiguration``) is `Equatable`-only, so a
/// non-`Equatable` value would only make the gate run its guards before
/// skipping. Capture solely `Equatable` values, so a non-`Equatable` node leaves
/// `memoViewValue` nil and the gate bails at its first guard — keeping the gate
/// near-free on trees that do not opt into memoization.
///
/// The memo shadow oracle (``MemoSkipTrace``) measures the *full* reflective
/// addressable population on sampled frames, so it captures every value,
/// `Equatable` or not.
@MainActor
func shouldCaptureMemoViewValue<V: View>(_ view: V) -> Bool {
  if MemoSkipTrace.shouldObserve { return true }
  return view is any Equatable
}

/// Token carrying the prior committed output of a recomputed node that the memo
/// diagnostics classified as a memoization candidate, so the shadow oracle can
/// compare it against the freshly recomputed output.
struct MemoComputationObservation {
  let priorCommitted: ResolvedNode
  /// Whether the node had recorded dynamic reads last frame — distinguishes a
  /// dependency-closable unsound mismatch from a comparator false-equal.
  let hadReads: Bool
}

/// Classifies a recomputed node: records it as `computed`, and — if it was
/// reached under a re-run ancestor (not itself the invalidation target), its
/// view value is structurally equal to the committed value, and it passes the
/// non-dirty reuse guards — returns a token for the shadow oracle. Records
/// blocked-field reasons (closure / AnyView / existential) along the way.
@MainActor
func beginMemoObservation<V: View>(
  _ view: V,
  graphNode: SwiftTUICore.ViewNode?,
  context: ResolveContext
) -> MemoComputationObservation? {
  guard MemoSkipTrace.shouldObserve, let graphNode else { return nil }
  MemoSkipTrace.recordComputed()
  // A self-invalidated node must re-run; only nodes reached under a re-run
  // ancestor are memoization candidates.
  guard !context.effectiveInvalidatedIdentities.contains(context.identity),
    let prior = graphNode.memoViewValue
  else { return nil }
  switch MemoValueComparator.compare(prior, view) {
  case .blocked(let reason):
    MemoSkipTrace.recordBlocked(reason)
    return nil
  case .changed:
    return nil
  case .equal:
    guard
      graphNode.canMemoReuse(
        environment: context.environment,
        transaction: context.transaction
      )
    else { return nil }
    let deps = graphNode.dependencies
    let hadReads =
      !deps.stateSlotReads.isEmpty
      || !deps.observableReads.isEmpty
      || !deps.environmentReads.isEmpty
    // Adoption-trap diagnostic: the author conformed this view to `Equatable`
    // (opted into memoization) and it is value-equal + reuse-guarded, but the
    // production gate will DENY it because it reads `@State`/`@Observable` or
    // focus/press — so the `.equatable()` is silently a no-op. Flag it.
    if view is any Equatable,
      !graphNode.hasNoMemoUncoveredDependencies(
        uncoveredEnvironmentKeys: EnvironmentValues.runtimeFocusStateDependencyKeys
      )
    {
      MemoSkipTrace.recordInertEquatableBoundary()
    }
    return MemoComputationObservation(
      priorCommitted: graphNode.committed,
      hadReads: hadReads
    )
  }
}

@MainActor
func finishMemoObservation(
  _ observation: MemoComputationObservation,
  newResolved: ResolvedNode
) {
  // Sound oracle: would reusing the committed node be observably identical
  // under retained-reuse semantics (structuralPath re-stamped, transaction by
  // reuse-equivalence)? Strict `==` over-counts re-stampable identity fields.
  if newResolved.memoReuseEquivalent(to: observation.priorCommitted) {
    MemoSkipTrace.recordAddressableSkip()
  } else {
    MemoSkipTrace.recordUnsoundSkip(hadReads: observation.hadReads)
    if let field = newResolved.memoFirstDifferingField(from: observation.priorCommitted) {
      MemoSkipTrace.recordUnsoundField(field)
    }
  }
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
