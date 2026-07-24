// The reuse door: the single interface behind which the two-layer reuse
// decision lives. Resolve entry points assemble `ReuseDecisionInputs` and ask
// one question; the A-before-B ordering, the profile and suppression policy,
// the memo exemption, and the graph-side accept plumbing are owned here —
// next to the `CommittedFreshness` stamps the gates consume.

/// Everything a resolve entry point must hand the reuse door — the named
/// contents of the seam between the authoring surface and the graph's reuse
/// policy. `SwiftTUIGraph` cannot see `ResolveContext` (module DAG), so the
/// context's reuse-relevant facts cross the seam as this value.
package struct ReuseDecisionInputs {
  package var identity: Identity
  package var invalidatedIdentities: Set<Identity>
  package var invalidationSummary: InvalidationSummary?
  package var environment: EnvironmentSnapshot
  package var transaction: TransactionSnapshot
  /// Certifies that an empty invalidation set is fully named by a finite
  /// retained-reuse suppression scope (see `reusableSnapshot`'s guard).
  package var allowsEmptyInvalidation: Bool
  package var invalidator: (any Invalidating)?
  /// Environment keys deliberately excluded from `environmentSnapshot`
  /// equality (focus/press runtime side-fields); a recorded read of one keeps
  /// the node memo-ineligible on every render path.
  package var uncoveredEnvironmentKeys: Set<ObjectIdentifier>
  /// The run loop suppresses retained reuse for focus/press runtime readers
  /// and the old/new focus or press identities.
  package var suppressesRetainedReuse: Bool
  /// The memoized layer's narrower variant: below a focus-presentation
  /// value-verified slot the memo compare itself proves the handed-down value
  /// unchanged (suppresses-value-verified ⊆ suppresses-retained).
  package var suppressesValueVerifiedReuse: Bool
  /// A value change was detected under a reused ancestor this pass; both
  /// layers stand down inside the churned cone.
  package var withinChurnedSubtree: Bool
  package var structuralPath: StructuralPath
  /// The pass's registration intake; a served subtree's runtime registrations
  /// are restored into it before the door returns.
  package var runtimeRegistrations: RuntimeRegistrationSet

  package init(
    identity: Identity,
    invalidatedIdentities: Set<Identity>,
    invalidationSummary: InvalidationSummary?,
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot,
    allowsEmptyInvalidation: Bool,
    invalidator: (any Invalidating)?,
    uncoveredEnvironmentKeys: Set<ObjectIdentifier>,
    suppressesRetainedReuse: Bool,
    suppressesValueVerifiedReuse: Bool,
    withinChurnedSubtree: Bool,
    structuralPath: StructuralPath,
    runtimeRegistrations: RuntimeRegistrationSet
  ) {
    self.identity = identity
    self.invalidatedIdentities = invalidatedIdentities
    self.invalidationSummary = invalidationSummary
    self.environment = environment
    self.transaction = transaction
    self.allowsEmptyInvalidation = allowsEmptyInvalidation
    self.invalidator = invalidator
    self.uncoveredEnvironmentKeys = uncoveredEnvironmentKeys
    self.suppressesRetainedReuse = suppressesRetainedReuse
    self.suppressesValueVerifiedReuse = suppressesValueVerifiedReuse
    self.withinChurnedSubtree = withinChurnedSubtree
    self.structuralPath = structuralPath
    self.runtimeRegistrations = runtimeRegistrations
  }
}

/// Which layer served. Both layers' caller-side effects are identical today;
/// the tag exists so callers, tests, and traces can attribute the serve.
package enum ReuseDecision {
  case retained(ResolvedNode)
  case memoized(ResolvedNode)

  /// The served subtree, layer-blind.
  package var servedSubtree: ResolvedNode {
    switch self {
    case .retained(let node), .memoized(let node):
      return node
    }
  }
}

extension ViewGraph {
  /// The one door for subtree reuse on the resolve path. Sequences the
  /// value-blind retained layer (Layer A) before the memoized value-verified
  /// layer, applies the stack-lean profile and focus/press suppression
  /// policy, and — on a serve — performs the graph-side accept plumbing
  /// (registration restore into the pass intake, structural-path stamp,
  /// lifetime report) before returning. On a decline it records the denial
  /// trace (inert unless `SWIFTTUI_REUSE_TRACE`) and returns `nil`; the
  /// caller re-evaluates the body.
  ///
  /// `viewValue` feeds the memo layer's value compare; it is an autoclosure
  /// so the `Any` boxing happens only when the memo layer is consulted —
  /// the same timing as the pre-door inline policy.
  package func reuseResolvedSubtree(
    inputs: ReuseDecisionInputs,
    viewValue: @autoclosure () -> Any
  ) -> ReuseDecision? {
    // Layer A — value-blind retained reuse. Lean engines opt back in via
    // `leanRetainedReuse`; a churned cone or a suppression scope stands the
    // layer down for this identity.
    if !stackLeanResolveProfile || leanRetainedReuse,
      !inputs.withinChurnedSubtree,
      !inputs.suppressesRetainedReuse,
      let reused = reusableSnapshot(
        for: inputs.identity,
        invalidatedIdentities: inputs.invalidatedIdentities,
        invalidationSummary: inputs.invalidationSummary,
        environment: inputs.environment,
        transaction: inputs.transaction,
        allowsEmptyInvalidation: inputs.allowsEmptyInvalidation,
        invalidator: inputs.invalidator
      )
    {
      return .retained(acceptServedSubtree(reused, inputs: inputs))
    }

    // Memoized-body reuse: Layer A rejected this node, but if it is only a
    // structural descendant of an invalidated ancestor whose own view value
    // is structurally unchanged (and it has no memo-uncovered dependencies
    // and passes every non-dirty reuse guard), the body re-run is redundant.
    // Behind the suppression gate's *value-verified* variant; `Equatable`-only,
    // so it is inert on trees that do not opt in.
    if !stackLeanResolveProfile,
      !inputs.withinChurnedSubtree,
      !inputs.suppressesValueVerifiedReuse,
      let reused = memoizedReusableSnapshot(
        for: inputs.identity,
        viewValue: viewValue(),
        environment: inputs.environment,
        transaction: inputs.transaction,
        invalidatedIdentities: inputs.invalidatedIdentities,
        uncoveredEnvironmentKeys: inputs.uncoveredEnvironmentKeys,
        invalidator: inputs.invalidator
      )
    {
      #if DEBUG
        if inputs.suppressesRetainedReuse {
          // This serve went through a value-verified-slot exemption; pin the
          // invariant that makes it sound (see the oracle's doc).
          debugAssertMemoReuseSubtreeFreeOfRuntimeFocusDependencies(
            reused,
            uncoveredEnvironmentKeys: inputs.uncoveredEnvironmentKeys
          )
        }
      #endif
      return .memoized(acceptServedSubtree(reused, inputs: inputs))
    }

    // Diagnostic (inert unless SWIFTTUI_REUSE_TRACE): this node is being
    // recomputed rather than reused — record why.
    if ReuseDenialTrace.isEnabled {
      recordReuseDenialIfTracing(
        for: inputs.identity,
        suppressed: inputs.suppressesRetainedReuse,
        environment: inputs.environment,
        transaction: inputs.transaction,
        invalidatedIdentities: inputs.invalidatedIdentities
      )
    }
    return nil
  }

  /// The accept plumbing both layers share. `reusableSnapshot` /
  /// `memoizedReusableSnapshot` already recorded the subtree (every non-nil
  /// return routes through `recordReusedSubtree`), so acceptance restores the
  /// subtree's runtime registrations into the pass intake, stamps the
  /// caller's structural path, and reports the lifetime result.
  private func acceptServedSubtree(
    _ reused: ResolvedNode,
    inputs: ReuseDecisionInputs
  ) -> ResolvedNode {
    restoreRuntimeRegistrations(
      for: reused,
      into: inputs.runtimeRegistrations
    )
    var structurallyStamped = reused
    structurallyStamped.structuralPath = inputs.structuralPath
    reportResolvedLifetimeResult(structurallyStamped)
    return structurallyStamped
  }
}
