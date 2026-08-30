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
    let resolvedNode = resolveView(
      view,
      in: childContext,
      authoringContextOverride: nil,
      structuralChildCutEligible: true
    )
    resolved.append(
      contentsOf: consumeDeclaredChild(
        resolvedNode,
        resolvedUnder: childContext.identity,
        in: context.viewGraph,
        policy: .declaredBuilder
      )
    )
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

    let occurrence = max(
      entityIdentity.occurrence,
      counts[entityIdentity.value, default: 0]
    )
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
    resolveView(
      view,
      in: childContext,
      authoringContextOverride: nil,
      structuralChildCutEligible: true
    )
  }
}

@MainActor
package func appendScopedDeclaredBuilderChildren<V: View>(
  from view: V,
  into children: inout [ScopedContentPayload]
) {
  var nextIndex = 0
  appendScopedDeclaredBuilderChildren(
    from: view,
    in: .root,
    kindName: "Group",
    nextIndex: &nextIndex,
    into: &children
  )
}

@MainActor
package func appendScopedDeclaredBuilderChildren<V: View>(
  from view: V,
  in context: DeclaredPayloadTraversalContext,
  kindName: String,
  nextIndex: inout Int,
  into children: inout [ScopedContentPayload]
) {
  let erased: Any = view
  if let structural = erased as? any DeclaredChildrenView {
    structural.appendScopedDeclaredChildren(
      in: context,
      kindName: kindName,
      nextIndex: &nextIndex,
      into: &children
    )
    return
  }
  nextIndex += 1
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
    // Capture-bind pass (plan 2026-08-20-001), resolvable tier: every
    // `ResolvableView` evaluation funnels through this branch —
    // `resolveView`'s fresh path, `ScopedBuilder`'s transparent
    // resolvable-output closure, body results that are themselves
    // resolvable containers, and conditional-branch content — so binding
    // here covers them all with one seam. The owner rule inside matches
    // `withDynamicPropertyUpdateScope` exactly.
    let bound: Any = bindingResolvableDynamicPropertyCaptures(view, in: context)
    return ((bound as? any ResolvableView) ?? resolvable).resolveElements(in: context)
  }
  // Capture-bind pass (plan 2026-08-20-001), body tier: this is the one
  // seam every plain body evaluation funnels through — the `{ view.body }`
  // closure formed here is what the body's closures ultimately capture, so
  // binding the copy here (under the ambient-wins owner rule the nested
  // `resolveBody` applies) covers direct `resolveView` children and
  // transparent forwarding containers (`ScopedBuilder` and peers) alike.
  let boundView = bindingBodyDynamicPropertyCaptures(view, in: context)
  return boundView.resolveBody(in: context) {
    boundView.body
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
  authoringContextOverride: AuthoringContext?,
  structuralChildCutEligible: Bool = false
) -> ResolvedNode {
  let forwardedPreparation = ForwardedDynamicPropertyPreparationScope.begin()
  defer {
    ForwardedDynamicPropertyPreparationScope.end(forwardedPreparation)
  }
  // Reused evaluator closures may have captured this context on a prior frame.
  // Refresh the pass-owned inputs before resolving so invalidation helpers and
  // transaction-aware reuse checks observe the current frame.
  let context = context.applyingCurrentFrameResolveInputs()
  let deferredDriver = context.viewGraph?.deferredResolveDriver
  deferredDriver?.enterLevel()
  defer {
    if let deferredDriver {
      deferredDriver.leaveLevel()
      // Trampoline: once the outermost call unwinds, resolve every deferred
      // subtree from this shallow stack, then RE-RUN this resolve so every
      // enclosing level and value consumer re-applies its post-processing
      // over the drained subtrees (fresh chunks then serve their committed
      // snapshots without re-enqueueing). A drained item's own epilogue
      // lands here too and is rejected by the driver's drain latch.
      deferredDriver.drainIfOutermost {
        _ = resolveView(
          view,
          in: context,
          authoringContextOverride: authoringContextOverride
        )
      }
    }
  }
  let routeIdentity = entityRouteIdentity(for: view, in: context)
  // The update pass runs `update(in:)` in place (plan 2026-08-30-001), so it
  // needs the copy the body will consume — not the authored `view`. Only the
  // two `resolveViewElements` calls below take `prepared`; the reuse door, the
  // memo witness, the stored evaluator, and deferred descent all keep `view`,
  // because those compare or replay the value the author wrote.
  var working = view
  let dynamicPropertyUpdateResult = prepareDynamicProperties(
    of: &working,
    in: context,
    routeIdentity: routeIdentity,
    authoringContextOverride: authoringContextOverride
  )
  // Immutable from here so `resolveFresh` captures it by value rather than
  // boxing a mutable capture.
  let prepared = working
  context.viewGraph?.setSuppressesStructuralLifecycle(
    context.suppressesStructuralLifecycle,
    for: context.identity
  )
  // Subtree reuse goes through the graph's one door: layer ordering,
  // profile/suppression policy, the memo exemption, and the graph-side accept
  // plumbing live in `ViewGraph.reuseResolvedSubtree` next to the
  // `CommittedFreshness` stamps. This entry point only assembles the seam
  // inputs from the context and tallies a serve.
  let suppressesRetainedReuse = context.effectiveSuppressesRetainedReuse(
    at: context.identity
  )
  // suppresses-value-verified ⊆ suppresses-retained, so the extra walk only
  // runs for identities the broad gate already denied.
  let suppressesValueVerifiedReuse =
    suppressesRetainedReuse
    && context.effectiveSuppressesValueVerifiedReuse(at: context.identity)
  if let decision = context.viewGraph?.reuseResolvedSubtree(
    inputs: ReuseDecisionInputs(
      identity: context.identity,
      invalidatedIdentities: context.effectiveInvalidatedIdentities,
      invalidationSummary: context.effectiveInvalidationSummary,
      environment: context.environment,
      transaction: context.transaction,
      allowsEmptyInvalidation:
        context.effectiveFiniteSuppressionScopeNamesForcedEvaluation,
      invalidator: context.invalidationProxy?.invalidator,
      // Focus/press env keys are excluded from `environmentSnapshot` equality
      // (they change every focus move) — see the door's field doc.
      uncoveredEnvironmentKeys: EnvironmentValues.runtimeFocusStateDependencyKeys,
      suppressesRetainedReuse: suppressesRetainedReuse,
      suppressesValueVerifiedReuse: suppressesValueVerifiedReuse,
      withinChurnedSubtree: context.withinChurnedSubtree,
      structuralPath: context.structuralPath,
      runtimeRegistrations: context.runtimeRegistrations,
      dynamicPropertyUpdateResult: dynamicPropertyUpdateResult
    ),
    viewValue: view
  ) {
    let served = decision.servedSubtree
    context.recordResolvedReuse(count: served.subtreeNodeCount)
    return served
  }

  let graphNode = context.viewGraph?.beginEvaluation(
    identity: context.identity,
    entityIdentity: routeIdentity,
    invalidator: context.invalidationProxy?.invalidator,
    suppressesStructuralLifecycle: context.suppressesStructuralLifecycle
  )
  if let graphNode, graphNode.isAtOutermostEvaluationDepth {
    // A dirty-frontier re-run invokes this evaluator OUTSIDE the enclosing
    // resolve pass, so the enclosing view's authoring context (a task-local)
    // is absent. Container registration code that snapshots
    // `currentAuthoringContext()` at resolve time (List/Menu/Stepper row
    // actions' mutation scopes and follow-up owners) would capture nil and
    // re-register DEGRADED handlers whose imperative `@State` writes land in
    // the detached seed box — silently, with no invalidation. Full-root
    // frames masked this by re-running the enclosing body; selective
    // frontiers must reinstall the captured enclosing scope instead (the
    // same capture the lazy-subview and portal-attachment seams use).
    let capturedEnclosingScope = makeCapturedAuthoringContext()
    // The re-run must carry the same authoring-scope override the original
    // resolve used: a node-backed style body re-resolved without it would
    // re-root a fresh scope onto the style-body island and re-register
    // degraded (seed-backed) owners — the wedge this override exists to
    // prevent. Strip the override's live `viewNode` before the long-lived
    // evaluator closure captures it: the node's stored evaluator retaining an
    // ancestor node forms an ARC cycle (ancestor's children already retain
    // this node), and every fire site rebases onto its own fresh graph node
    // anyway, so the captured `viewNode` would never be read.
    let capturedOverride = authoringContextOverride.map {
      rebasedAuthoringContext($0, viewNode: nil)
    }
    context.viewGraph?.setEvaluator(for: context.identity) {
      if let capturedEnclosingScope, currentAuthoringContext() == nil {
        withAuthoringContext(capturedEnclosingScope) {
          _ = resolveView(
            view,
            in: context,
            authoringContextOverride: capturedOverride
          )
        }
      } else {
        _ = resolveView(
          view,
          in: context,
          authoringContextOverride: capturedOverride
        )
      }
    }
  }
  // The cut is only sound on structural child edges, where the parent
  // consumes the returned node verbatim. A modifier-content or style-body
  // edge post-processes the returned value (preference merges, lifecycle
  // metadata, wrapping) — deferring there would attach that post-processing
  // to the placeholder and the drain's splice would discard it. Refusing
  // here just moves the cut to the next structural edge below, so inline
  // overshoot is bounded by the deepest non-structural chain.
  if structuralChildCutEligible,
    let deferredDriver, deferredDriver.shouldDeferDescent,
    let graphNode, let graph = context.viewGraph,
    let deferred = deferResolveDescent(
      view,
      in: context,
      graph: graph,
      graphNode: graphNode,
      routeIdentity: routeIdentity,
      authoringContextOverride: authoringContextOverride
    )
  {
    return deferred
  }

  let resolveFresh = { () -> ResolvedNode in
    context.recordResolvedComputation()
    // Memoization diagnostics: would this recomputed node have been memoizable?
    // Captured before the body runs, while `graphNode.committed` still holds the
    // prior frame's output. In release this is sampled and opt-in via
    // `SWIFTTUI_MEMO_TRACE`; when unsampled it is a single Bool guard.
    let memoObservation = beginMemoObservation(
      view,
      graphNode: graphNode,
      context: context,
      dynamicPropertyUpdateResult: dynamicPropertyUpdateResult
    )
    let erased: Any = view
    var accessedStateSlots = 0
    var resolved = ViewUpdateGuard.withViewUpdate {
      EnvironmentValuesStorage.binding(context.environmentValues) {
        ViewNodeContext.withValue(graphNode) {
          if erased is any ResolvableView {
            // Capture binding (plan 2026-08-20-001) happens inside
            // `resolveViewElements`' resolvable branch — the funnel this
            // call and every resolvable bypass route share — under the same
            // owner rule the container's own update scope applies. Fresh
            // evaluations only by construction: reuse serves never reach
            // `resolveViewElements`, and the stored evaluator and
            // deferred-descent closures capture the authored `view` and
            // re-prepare and re-bind on re-entry. `memoViewValue` below
            // stashes that authored `view` so memo comparison sees authored
            // values — never a capture, and never a dynamic property's
            // in-place update (plan 2026-08-30-001).
            let resolve = {
              normalizeResolvedElements(
                resolveViewElements(prepared, in: context),
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
              resolveViewElements(prepared, in: context),
              in: context
            )
            accessedStateSlots = authoringContext.ordinalTracker.nextOrdinal
            return resolved
          }
        }
      }
    }
    assignEntityIdentityOccurrences(to: &resolved._storedChildren)
    if case .uncertified = dynamicPropertyUpdateResult {
      // Direct certification is authoritative input to the subtree summary;
      // layout and child recomputes cannot launder it back to reusable.
      resolved.directDynamicPropertyReuseCertified = false
    }
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
    } else if graphNode?.memoViewValue != nil {
      // Not capturing must CLEAR, not leave the previous value standing. This
      // node's committed output now belongs to the view resolved this frame,
      // so a value stashed by an earlier frame is no longer a witness for it:
      // a later frame whose value compares equal to that stale witness would
      // pass the memo gate and be served this frame's foreign committed
      // snapshot. Under a stable `.id` alternating between an unplannable and
      // a plannable body that is exactly what happened — the unplannable frame
      // left the plannable frame's value in place, and the next plannable
      // frame matched it and was served the unplannable frame's output.
      // Guarded on non-nil so the common never-captured node pays no
      // checkpoint mutation.
      graphNode?.memoViewValue = nil
    }
    return resolved
  }

  let resolved: ResolvedNode
  if let graphNode, let graph = context.viewGraph {
    graph.reportResolvedLifetimeNode(graphNode)
    resolved = graph.withResolveLifetimeScope(hostedBy: graphNode, resolveFresh)
  } else {
    resolved = resolveFresh()
  }
  context.viewGraph?.reportResolvedLifetimeResult(resolved)
  return resolved
}

/// Whether to stash the resolved view value for next-frame memo comparison.
///
/// The production gate (`ViewGraph.memoizedReusableSnapshot`) compares through
/// a per-type ``MemoComparisonPlan`` (`Equatable` / POD byte compare / field
/// plan). Capture only types with a plan, so an unplannable node leaves
/// `memoViewValue` nil and the gate bails at its first guard — keeping the
/// gate near-free on trees the memo layer cannot serve. The plan is built and
/// cached here (the cold, once-per-type site); the gate path is lookup-only.
/// The caller CLEARS the slot when this returns false, so "no plan" always
/// means "no witness" — leaving an earlier frame's value standing would let a
/// later equal-comparing frame be served this node's intervening output.
///
/// The memo shadow oracle (``MemoSkipTrace``) measures the *full* reflective
/// addressable population on sampled frames, so it captures every value,
/// planned or not.
@MainActor
func shouldCaptureMemoViewValue<V: View>(_ view: V) -> Bool {
  if MemoSkipTrace.shouldObserve { return true }
  return MemoComparisonPlanCache.hasPlan(for: V.self)
}

/// Token carrying the prior committed output of a recomputed node that the memo
/// diagnostics classified as a memoization candidate, so the shadow oracle can
/// compare it against the freshly recomputed output.
struct MemoComputationObservation {
  let priorCommitted: ResolvedNode
  /// Whether the node had recorded dynamic reads last frame — distinguishes a
  /// dependency-closable unsound mismatch from a comparator false-equal.
  let hadReads: Bool
  /// The observed view's type, for the alarm detail.
  let viewTypeName: String
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
  context: ResolveContext,
  dynamicPropertyUpdateResult: DynamicPropertyUpdateResult
) -> MemoComputationObservation? {
  guard MemoSkipTrace.shouldObserve, let graphNode else { return nil }
  MemoSkipTrace.recordComputed()
  MemoSkipTrace.recordPlanTier(MemoComparisonPlanCache.diagnosticTier(for: V.self))
  // Mirror the production reuse door: changed/uncertified updates are not
  // would-skip candidates and must not feed a false soundness alarm.
  guard case .unchanged = dynamicPropertyUpdateResult else { return nil }
  // A self-invalidated node must re-run; only nodes reached under a re-run
  // ancestor are memoization candidates.
  guard !context.effectiveInvalidatedIdentities.contains(context.identity),
    let prior = graphNode.memoViewValue
  else { return nil }
  // Mirror the production gate's uncertified-empty-invalidation rule: a
  // reference-identity plan is refused service on a forced re-render (the
  // referenced contents are the out-of-band channel such frames refresh), so
  // the node is not a would-skip candidate — observing it would raise the
  // alarm on a serve the gate would never make.
  if context.effectiveInvalidatedIdentities.isEmpty,
    !context.effectiveFiniteSuppressionScopeNamesForcedEvaluation,
    !MemoComparisonPlanCache.mayServeUnderUncertifiedEmptyInvalidation(V.self)
  {
    return nil
  }
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
      hadReads: hadReads,
      viewTypeName: String(reflecting: V.self)
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
    // Content-vs-bookkeeping classification drives the memo-soundness alarm:
    // a no-reads *content* divergence is a comparator false-equal (F90);
    // entity-bookkeeping re-stamps only feed the histogram.
    MemoSkipTrace.recordUnsoundSkip(
      hadReads: observation.hadReads,
      contentDivergenceField: newResolved.memoUnsoundContentDivergence(
        from: observation.priorCommitted
      ),
      firstDifferingField: newResolved.memoFirstDifferingField(
        from: observation.priorCommitted
      ),
      identity: newResolved.identity,
      viewTypeName: observation.viewTypeName
    )
  }
}

/// Kind for a deferred subtree's first-sight placeholder. Deliberately NOT
/// `EmptyView`/`Group` (whose own-identity shapes the parent consumes by
/// value in `appendDeclaredChildNodes`) so the placeholder always survives
/// into the parent's children until the drain splices the real subtree.
private let deferredResolvePlaceholderKindName = "DeferredResolvePlaceholder"

/// The depth-cap cut of the chunked resolve driver (see
/// ``DeferredResolveDriver``). Runs *after* `beginEvaluation` claimed the
/// node's frame-order slot at its document position. Commits the node's stale
/// committed snapshot as a structural placeholder — a no-op child diff
/// against the live children — enqueues a captured re-resolve of the subtree
/// for the driver's shallow-stack drain, and returns the placeholder to the
/// parent. Returns `nil` (resolve inline; the node's children still cut at
/// the next level, so refusal costs exactly one extra stack level) for the
/// two stale shapes the parent consumes by value — an own-identity
/// `EmptyView` (dropped) or `Group` (spliced) — where serving a stale shape
/// would desynchronize the parent's structural handling from this frame's
/// real resolve.
@MainActor
private func deferResolveDescent<V: View>(
  _ view: V,
  in context: ResolveContext,
  graph: ViewGraph,
  graphNode: SwiftTUICore.ViewNode,
  routeIdentity: EntityIdentity?,
  authoringContextOverride: AuthoringContext?
) -> ResolvedNode? {
  // Entity-routed children resolve inline: the `.id` claim machinery
  // (route bindings, occurrence claims, cross-identity adoption, co-resident
  // escapes) is ordered against sibling resolution and the ambient claim
  // node, and a deferred re-claim replays it against a routing table the
  // cut-time bookkeeping already advanced. Refusing the cut here costs one
  // stack level — the chain's descendants still cut at the next structural
  // edge below.
  if routeIdentity != nil {
    return nil
  }
  let driver = graph.deferredResolveDriver
  let servesFreshChunk = driver.canServeFreshChunk(context.identity)
  // Serve the committed value AS-IS — never `snapshot()`: the rebuild
  // recursion (and the commit path's subtree-deep walks — structural diff,
  // committed-value anchors) is O(subtree depth) and would stack on top of
  // the K inline levels, re-creating the very overflow the cap exists to
  // prevent. The cut is O(1): the drain's shallow-stack commit does all
  // real bookkeeping, and the final fixpoint pass leaves every committed
  // value coherent for the next frame's serves.
  var placeholder = graphNode.committed
  if placeholder.viewNodeID == nil {
    // Never-applied node: the hollow init value is an own-identity
    // `EmptyView`, which the parent would consume by value. Mint a distinct
    // placeholder kind instead so the parent's `EmptyView`-drop and
    // `Group`-splice handling cannot consume it before the drain resolves
    // the real subtree and the rerun re-consumes it.
    placeholder = ResolvedNode(
      identity: context.identity,
      kind: .view(deferredResolvePlaceholderKindName),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      intrinsicSize: .zero
    )
    placeholder.viewNodeID = graphNode.viewNodeID
    placeholder.recomputeSubtreeRuntimeNodeIDsStamped()
  } else if placeholder.identity == context.identity,
    placeholder.kind == .view("EmptyView") || placeholder.kind == .view("Group")
  {
    return nil
  }

  // Close the begin without committing: `beginEvaluation` already claimed
  // the node's frame-order slot at its document position, and the drain's
  // real finish performs the structural diff, lifecycle diffs, and reindex
  // work from a shallow stack.
  graphNode.abandonEvaluation()
  var resolved = placeholder
  resolved.structuralPath = context.structuralPath

  if !servesFreshChunk {
    // Capture the per-level ambient state the drained re-resolve needs —
    // the same set the dirty-frontier evaluator install captures, plus the
    // entity route (a task-local the parent binds around this exact child
    // position) and the evaluating host node (rebound via the
    // captured-scope helper so fresh mints wire `evaluationHost` exactly
    // as the inline descent would).
    let capturedEnclosingScope = makeCapturedAuthoringContext()
    let capturedOverride = authoringContextOverride.map {
      rebasedAuthoringContext($0, viewNode: nil)
    }
    let capturedHost = ViewNodeContext.current
    let capturedEntityRoute = ResolveEntityRouteStorage.current
    driver.enqueueDeferredResolve(for: context.identity) {
      graph.withCapturedResolveLifetimeScope(hostedBy: capturedHost) {
        withResolveEntityRoute(capturedEntityRoute) {
          if let capturedEnclosingScope, currentAuthoringContext() == nil {
            withAuthoringContext(capturedEnclosingScope) {
              _ = resolveView(
                view,
                in: context,
                authoringContextOverride: capturedOverride
              )
            }
          } else {
            _ = resolveView(
              view,
              in: context,
              authoringContextOverride: capturedOverride
            )
          }
        }
      }
    }
  }

  graph.reportResolvedLifetimeNode(graphNode)
  graph.reportResolvedLifetimeResult(resolved)
  return resolved
}

@MainActor
package func rebasedAuthoringContext(
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
    stateOwnerHandle: authoringContext.stateOwnerHandle,
    stateGraphScope: authoringContext.stateGraphScope,
    ordinalTracker: authoringContext.ordinalTracker
  )
}
