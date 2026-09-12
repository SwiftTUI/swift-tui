import SwiftTUICore

@MainActor
func resolveViewWork<V: View>(
  _ view: V,
  in context: ResolveContext,
  authoringContextOverride: AuthoringContext? = nil,
  rebuilding: ViewEvaluationProducer<V>? = nil
) -> ResolveWork<ResolvedNode> {
  .deferred {
    let forwardedPreparation = ForwardedDynamicPropertyPreparationScope.begin()
    let context = context.applyingCurrentFrameResolveInputs()
    // The producer owns the iteration's outer resolve. A forwarded exact-ID
    // modifier below it must not redirect a replay onto its inner state owner.
    // The ambient route remains scope-only, so interior claims retain their
    // ordinary ownership rules.
    let routeIdentity = rebuilding?.entityIdentity ?? entityRouteIdentity(for: view, in: context)
    // The update pass runs `update(in:)` in place (plan 2026-08-30-001), so it
    // needs the copy the body will consume — not the authored `view`. Only the
    // two `resolveViewElements` calls below take `prepared`; the reuse door, the
    // memo witness, the stored evaluator, and deferred work all keep `view`,
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
      // Even equal output may have come from a new producer/model. Keep that
      // producer current on reuse, while collapsed inner resolves leave the
      // outer evaluation owner's closure intact.
      if let rebuilding,
        let graphNode = context.viewGraph?.nodeForEntityIdentity(rebuilding.entityIdentity),
        !graphNode.isEvaluating
      {
        installViewEvaluator(
          for: view,
          in: context,
          on: graphNode,
          authoringContextOverride: authoringContextOverride,
          rebuilding: rebuilding
        )
      }
      let served = decision.servedSubtree
      context.recordResolvedReuse(count: served.subtreeNodeCount)
      ForwardedDynamicPropertyPreparationScope.end(forwardedPreparation)
      return .value(served)
    }

    let graphNode = context.viewGraph?.beginEvaluation(
      identity: context.identity,
      entityIdentity: routeIdentity,
      invalidator: context.invalidationProxy?.invalidator,
      suppressesStructuralLifecycle: context.suppressesStructuralLifecycle
    )
    if let graphNode, graphNode.isAtOutermostEvaluationDepth {
      installViewEvaluator(
        for: view,
        in: context,
        on: graphNode,
        authoringContextOverride: authoringContextOverride,
        rebuilding: rebuilding
      )
    }
    let resolveFresh = { () -> ResolveWork<ResolvedNode> in
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
      var ordinalTracker: AuthoringOrdinalTracker?
      graphNode?.beginRegistrationCapture()
      let elementsWork = ViewUpdateGuard.withViewUpdate {
        EnvironmentValuesStorage.binding(context.environmentValues) {
          ViewNodeContext.withCurrentValue(graphNode) {
            if erased is any ResolvableView {
              // Capture binding (plan 2026-08-20-001) happens inside
              // `resolveViewElements`' resolvable branch — the funnel this
              // call and every resolvable bypass route share — under the same
              // owner rule the container's own update scope applies. Fresh
              // evaluations only by construction: reuse serves never reach
              // `resolveViewElements`, and the stored evaluator and
              // continuation closures capture the authored `view` and
              // re-prepare and re-bind on re-entry. `memoViewValue` below
              // stashes that authored `view` so memo comparison sees authored
              // values — never a capture, and never a dynamic property's
              // in-place update (plan 2026-08-30-001).
              let resolve = {
                resolveViewElementsWork(prepared, in: context).map {
                  normalizeResolvedElements($0, in: context, loneForEachElementKeepsGroup: true)
                }
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
              ordinalTracker = authoringContext.ordinalTracker
              return resolveViewElementsWork(prepared, in: context).map {
                normalizeResolvedElements($0, in: context, loneForEachElementKeepsGroup: true)
              }
            }
          }
        }
      }
      return elementsWork.map { completed in
        graphNode?.endRegistrationCapture()
        var resolved = completed
        let accessedStateSlots = ordinalTracker?.nextOrdinal ?? 0
        assignEntityIdentityOccurrences(to: &resolved._storedChildren)
        if let rebuilding {
          // Commit the same entity metadata used by initial ForEach consumption.
          // Applying it before finishEvaluation also updates child routes when
          // the produced value is a Group.
          resolved.attachResolvedForEachEntity(
            rebuilding.entityIdentity,
            at: rebuilding.structuralPath
          )
        }
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
    }

    let resolved: ResolveWork<ResolvedNode>
    if let graphNode, let graph = context.viewGraph {
      graph.reportResolvedLifetimeNode(graphNode)
      let frame = ResolveLifetimeScopeFrame(graph: graph, hostNodeID: graphNode.viewNodeID)
      resolved = ResolveLifetimeScopeContext.$current.withValue(frame) {
        resolveFresh().map { result in
          graph.closeResolveLifetimeScope(frame)
          return result
        }
      }
    } else {
      resolved = resolveFresh()
    }
    return resolved.map { result in
      context.viewGraph?.reportResolvedLifetimeResult(result)
      ForwardedDynamicPropertyPreparationScope.end(forwardedPreparation)
      return result
    }
  }
}

@MainActor
package func resolveViewElementsWork<V: View>(
  _ view: V, in context: ResolveContext
) -> ResolveWork<[ResolvedNode]> {
  .deferred {
    if let resolvable = view as? any ResolvableView {
      let bound: Any = bindingResolvableDynamicPropertyCaptures(view, in: context)
      return ((bound as? any ResolvableView) ?? resolvable).makeResolveWork(in: context)
    }
    let bound = bindingBodyDynamicPropertyCaptures(view, in: context)
    let authoring = currentAuthoringContext() ?? makeAuthoringContext(for: context)
    return withAuthoringContext(authoring) {
      let body = context.trackingObservableAccess { bound.body }
      return resolveViewElementsWork(body, in: context)
    }
  }
}

extension View {
  package func resolveWork(in context: ResolveContext) -> ResolveWork<ResolvedNode> {
    resolveViewWork(self, in: context)
  }

  package func resolveElementsWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    resolveViewElementsWork(self, in: context)
  }
}
