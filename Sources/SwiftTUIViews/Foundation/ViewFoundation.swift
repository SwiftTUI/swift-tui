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

  resolvingStyleRouteAlternative {
    if context.viewGraph != nil {
      let resolvedNode = resolveView(
        view,
        in: childContext,
        authoringContextOverride: nil
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
      authoringContextOverride: nil
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
package func resolveViewElements<V: View>(_ view: V, in context: ResolveContext) -> [ResolvedNode] {
  resolveViewElementsWork(view, in: context).run()
}

/// Folds a composite's resolved elements into one node: none is an
/// `EmptyView`, several share a `Group`, and one is normally that element
/// itself.
///
/// `loneForEachElementKeepsGroup` applies to a composite's own body (the
/// `resolveView` sites): a lone `ForEach` element then keeps the `Group` its
/// siblings would share. The element's node carries the element's entity,
/// `@State`, lifecycle handler IDs and task; handing it up as the composite's
/// own value made the composite a "flattening absorber" that the identity
/// index, the task runner and lifecycle publication all treated as the
/// element — and growing the data to two re-rooted the composite from the
/// element to a fresh `Group`, re-parenting the surviving element
/// mid-animation (the counter demo's ripple: task cancelled, first ring's
/// animation snapped to its end value; org tasks T171/T172). With the `Group`
/// minted from one element on, a sibling's arrival is an ordinary child
/// insertion under an unchanged parent. Non-`ForEach` lone children (a
/// modifier's content, a conditional branch) keep flattening: their node IS
/// the composite's value by construction, with no entity of its own to
/// hijack. Scoped and portal payload hosting (`ScopedContentPayload.resolve`,
/// `Portal`) leaves the flag off: one payload hosts exactly one element and
/// the host reads the element's identity and entity off the payload's top
/// node, which is what lets payload identities follow element IDs across a
/// reorder.
@MainActor
package func normalizeResolvedElements(
  _ resolvedElements: [ResolvedNode],
  in context: ResolveContext,
  loneForEachElementKeepsGroup: Bool = false
) -> ResolvedNode {
  switch resolvedElements.count {
  case 0:
    return ResolvedNode(
      identity: context.identity,
      kind: .view("EmptyView"),
      typeDiscriminator: ObjectIdentifier(SynthesizedEmptyViewMarker.self),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      intrinsicSize: .zero
    )
  case 1
  where !loneForEachElementKeepsGroup
    || resolvedElements[0].entityIdentity?.isForEachScoped != true:
    return resolvedElements[0]
  default:
    var groupedChildren = resolvedElements
    assignEntityIdentityOccurrences(to: &groupedChildren)
    return ResolvedNode(
      identity: context.identity,
      kind: .view("Group"),
      typeDiscriminator: ObjectIdentifier(SynthesizedGroupWrapperMarker.self),
      children: groupedChildren,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction
    )
  }
}

/// Construction ownership is distinct from the node serving a reused value:
/// flattening can index that value onto an inner authored node.
struct ViewEvaluationProducer<Content: View> {
  let entityIdentity: EntityIdentity
  let structuralPath: StructuralPath
  var declaredChildReplayBoundary: DeclaredChildReplayBoundary? = nil
  let makeView: @MainActor (ResolveContext) -> Content
}

@MainActor
func installViewEvaluator<V: View>(
  for view: V,
  in context: ResolveContext,
  on graphNode: SwiftTUICore.ViewNode,
  authoringContextOverride: AuthoringContext?,
  rebuilding: ViewEvaluationProducer<V>?
) {
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
  // The enclosing entity route is a task-local the parent chain binds
  // around this position (`withResolveEntityRoute`), and the re-run fires
  // outside that binding. An exact `.id` below this node scopes its entity
  // to the enclosing route's entity (`ExactIdentityModifier`), so without
  // the capture a frontier re-run beneath a `.id(owner)` computed a
  // DIFFERENT entity for the same control: the modifier then saw a foreign
  // occupant on its slot node and hosted the content under an
  // `ExplicitIdentityHost`, while the chain's forwarded claim had already
  // bound the new entity to this wrapper node — the nested resolves
  // re-entered this node cross-identity, folding the control onto its own
  // `.frame` wrapper (a parent/child cycle: the DEBUG stamp-coherence
  // oracle on a `Panel`-hosted `TextEditor`'s focus frame, a livelock on
  // the next paste without it; org task T173). Scope only: a route bound
  // at THIS position is the parent level's claim on this child (a
  // `ForEach` iteration's element entity), consumed by that level's own
  // resolve. Re-fired from the child's re-run, a `ForEach` row claimed its
  // element entity at its own position while the row node's occupant was
  // the exact-`.id` entity its body chain had collapsed onto it, so the
  // claim evicted the row and re-minted it: a pre-churn closure kept
  // reading the evicted node's state (`CaptureBindingChurnJourneyTests`).
  // The same-frame deferred-descent continuation keeps the full route
  // because it resumes the very resolve that bound it.
  let capturedEntityRoute = ResolveEntityRouteStorage.current?.scopeOnly
  let capturedOwnerLifetimeID = graphNode.ownerLifetimeID
  graphNode.setEvaluator {
    withResolveEntityRoute(capturedEntityRoute) {
      let replay = {
        let currentContext = context.applyingCurrentFrameResolveInputs()
        let currentView: V
        let previousResolved: ResolvedNode?
        if let rebuilding {
          // A ForEach builder can read Observation before producing a View.
          // Replay that producer under its live owner without starting a new
          // registration capture (which would clear existing handlers).
          // Flattening can index the authored identity onto its absorber.
          // Observation belongs to the exact owner whose evaluator is firing.
          guard
            let owner = currentContext.viewGraph?.nodeForOwnerLifetimeID(capturedOwnerLifetimeID)
          else {
            return
          }
          previousResolved = owner.committed
          currentView = ViewNodeContext.withCurrentValue(owner) {
            rebuilding.makeView(currentContext)
          }
        } else {
          previousResolved = nil
          currentView = view
        }
        let resolved = resolveView(
          currentView,
          in: currentContext,
          authoringContextOverride: capturedOverride,
          rebuilding: rebuilding
        )
        if let boundary = rebuilding?.declaredChildReplayBoundary,
          let previousResolved,
          declaredChildShape(previousResolved, under: boundary.resolvedUnder) != .single
            || declaredChildShape(resolved, under: boundary.resolvedUnder) != .single
        {
          // A snapshot replacement cannot re-run the declaring container's
          // empty/group consumption. Request that owner after this frontier
          // unwinds; the frame head expands registration publication with it.
          currentContext.viewGraph?.requestDeclaredChildRecomposition(
            owner: boundary.ownerLifetimeID
          )
        }
      }
      if let capturedEnclosingScope, currentAuthoringContext() == nil {
        withAuthoringContext(capturedEnclosingScope, replay)
      } else {
        replay()
      }
    }
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
  rebuilding: ViewEvaluationProducer<V>? = nil
) -> ResolvedNode {
  resolveViewWork(
    view, in: context,
    authoringContextOverride: authoringContextOverride, rebuilding: rebuilding
  ).run()
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
    // production gate will DENY it because a state/observation certificate
    // is uncovered or stale, or it reads focus/press. Flag the inert boundary.
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
