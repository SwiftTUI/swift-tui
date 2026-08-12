/// The size-stability measure cutoff's certificate pre-pass (plan
/// 2026-08-11-002, Stage 1 — dark).
///
/// Between resolve and the main measure pass, derive the outermost dirty
/// roots and test whether each re-measures to exactly its stored size at
/// every stored baseline proposal (D1: multi-sample — a single-sample match
/// is unsound against a fresh stack pass, which consumes the child's
/// ideal-round response before its final offer). In this stage the result is
/// counters only: nothing is lifted, and the main pass runs unchanged. The
/// pre-pass measures on the production `MeasurementCache`, so a failed
/// certificate's work is reclaimed by the main pass as cache hits.
package struct MeasureCutoffPolicy: Sendable {
  /// Skip the whole pre-pass when the outermost dirty-root count exceeds this.
  package var maxOutermostDirtyRoots = 8
  /// Deny a root whose retained subtree exceeds 1/`subtreeShareDenominator`
  /// of the previous frame's node count — the spine saving cannot cover the
  /// double-measure risk.
  package var subtreeShareDenominator = 4

  package init() {}

  package static let standard = Self()
}

package struct MeasureCutoffCertificate: Sendable {
  package var rootIdentity: Identity
  /// The certified root's subtree in the current resolved tree — the resolved
  /// half of the derived-session patch.
  package var currentResolvedSubtree: ResolvedNode
  /// The pre-pass product at the retained proposal — the measured half of the
  /// derived-session patch.
  package var freshMeasuredAtRetainedProposal: MeasuredNode
  package var retainedProposal: ProposedSize

  /// Stage 2's provably constant family: an explicit fixed-extent frame's
  /// parent-visible response is proposal-independent, so one confirmed sample
  /// proves all samples and the serve's soundness question is closed by
  /// construction.
  package var qualifiesForConstantFamilyServe: Bool {
    if case .frame(.some, .some, _) = currentResolvedSubtree.layoutBehavior {
      return true
    }
    return false
  }
}

package struct MeasureCutoffPrePassResult: Sendable {
  package var metrics = PreMeasureCutoffMetrics()
  package var certificates: [MeasureCutoffCertificate] = []

  package init() {}
}

/// `SWIFTTUI_TRACE=cutoff`-armed reporting for the dark run's hit-rate
/// evidence. One line per frame with attempts; silent otherwise.
package enum MeasureCutoffTrace {
  /// Read once — trace arming latches like the feature gates.
  package static let isArmed = DebugTraceSelection.current.isArmed("cutoff")

  package static func emit(_ metrics: PreMeasureCutoffMetrics) {
    guard isArmed, metrics.certificatesAttempted > 0 else {
      return
    }
    DebugLogRouter.emit(
      "[MEASURE-CUTOFF] attempted=\(metrics.certificatesAttempted) "
        + "certified=\(metrics.certificatesCertified) "
        + "served=\(metrics.certificatesServed) "
        + "denied(indexed=\(metrics.deniedIneligibleIndexed) "
        + "windowed=\(metrics.deniedIneligibleWindowed) "
        + "spine=\(metrics.deniedIneligibleSpine) "
        + "animated=\(metrics.deniedIneligibleAnimated) "
        + "no-baseline=\(metrics.deniedNoBaseline) "
        + "size-mismatch=\(metrics.deniedSizeMismatch) "
        + "capped=\(metrics.deniedAbortedByCap) "
        + "coverage-uncovered=\(metrics.deniedProposalCoverage) "
        + "record-overflow=\(metrics.deniedRecordOverflow))\n",
      toFileAt: DebugLogRouter.resolvedFilePath(
        override: FeatureFlags.environmentValue(named: "SWIFTTUI_MEASURE_CUTOFF_TRACE_FILE"),
        bundleFileName: "measure-cutoff.log"
      )
    )
  }
}

extension LayoutEngine {
  /// Runs the certificate pre-pass. Returns `nil` when the frame has no
  /// retained session, no previous frame index, or no invalidations — the
  /// populations the cutoff cannot address by construction (as opposed to
  /// denials, which are counted).
  package func preMeasureCutoffPrePass(
    resolved: ResolvedNode,
    passContext: LayoutPassContext,
    animationExcludedIdentities: Set<Identity>,
    policy: MeasureCutoffPolicy = .standard
  ) -> MeasureCutoffPrePassResult? {
    guard let session = passContext.retainedLayout,
      let index = session.previousFrameIndex,
      !passContext.invalidatedIdentities.isEmpty
    else {
      return nil
    }

    // Step 1 (plan mechanism): the outermost cover of invalidated identities
    // present in the previous structural frame. Roots inside another root's
    // subtree are re-measured fresh inside the outer certificate anyway (D7).
    let presentInPreviousFrame = passContext.invalidatedIdentities.filter {
      index.resolvedNode(for: $0) != nil
    }
    guard !presentInPreviousFrame.isEmpty else {
      return nil
    }
    var result = MeasureCutoffPrePassResult()
    let byDepth = presentInPreviousFrame.sorted { $0.components.count < $1.components.count }
    var roots: [Identity] = []
    for candidate in byDepth
    where !roots.contains(where: { $0 == candidate || $0.isAncestor(of: candidate) }) {
      roots.append(candidate)
    }

    // Whole-frame caps (D10): a dirty tree root has nothing above it to
    // save, and a large cover cannot amortize the pre-pass.
    if roots.contains(resolved.identity) || roots.count > policy.maxOutermostDirtyRoots {
      result.metrics.certificatesAttempted += roots.count
      result.metrics.deniedAbortedByCap += roots.count
      return result
    }

    let previousFrameNodeCount = index.placedRoot.subtreeNodeCount
    for root in roots {
      result.metrics.certificatesAttempted += 1
      certify(
        root: root,
        treeRoot: resolved,
        session: session,
        animationExcludedIdentities: animationExcludedIdentities,
        previousFrameNodeCount: previousFrameNodeCount,
        policy: policy,
        into: &result
      )
    }
    return result
  }

  private func certify(
    root: Identity,
    treeRoot: ResolvedNode,
    session: RetainedLayoutSession,
    animationExcludedIdentities: Set<Identity>,
    previousFrameNodeCount: Int,
    policy: MeasureCutoffPolicy,
    into result: inout MeasureCutoffPrePassResult
  ) {
    // D9: animated roots churn size per tick; certification would be pure
    // overhead at tick cadence.
    if animationExcludedIdentities.contains(where: { $0 == root || $0.isDescendant(of: root) }) {
      result.metrics.deniedIneligibleAnimated += 1
      return
    }
    // D8: the indexed measurement signature is the ordered ID list; payload
    // changes under a stable list are invisible to every comparator.
    if session.affectsIndexedChildSource(within: root) {
      result.metrics.deniedIneligibleIndexed += 1
      return
    }

    // Locate the root in the current resolved tree by lexical descent.
    // Plan 2026-08-11-006 Stage 1: a non-forwarding, non-lazy ancestor no
    // longer denies — it escalates the certificate to recorded-proposal
    // coverage below. Lazy containers still deny outright: their exclusion
    // is windowing (D6/D8 territory), not proposal-family knowledge.
    var spineParent: ResolvedNode?
    var coverageRequired = false
    var node = treeRoot
    while node.identity != root {
      if case .lazyStack = node.layoutBehavior {
        result.metrics.deniedIneligibleSpine += 1
        return
      }
      if !isSpineForwardingBehavior(node.layoutBehavior) {
        coverageRequired = true
      }
      guard
        let next = node.children.first(where: {
          $0.identity == root || $0.identity.isAncestor(of: root)
        })
      else {
        // Not present in the current tree along its previous-frame path —
        // there is no retained basis to certify against.
        result.metrics.deniedNoBaseline += 1
        return
      }
      spineParent = node
      node = next
    }
    let currentSubtree = node

    guard
      let previousMeasured = session.measuredNode(for: root),
      session.resolvedNode(for: root) != nil
    else {
      result.metrics.deniedNoBaseline += 1
      return
    }
    if previousMeasured.subtreeNodeCount * policy.subtreeShareDenominator > previousFrameNodeCount {
      result.metrics.deniedAbortedByCap += 1
      return
    }
    // D6: a windowed product is valid only for its hint; the scratch pre-pass
    // starts with an empty hint stack and must never claim the main pass's.
    // D8's structural half: an indexed source anywhere below re-measures
    // through signature-blind comparators.
    if subtreeCarriesMeasuredWindow(previousMeasured) {
      result.metrics.deniedIneligibleWindowed += 1
      return
    }
    if subtreeContainsIndexedChildSource(currentSubtree) {
      result.metrics.deniedIneligibleIndexed += 1
      return
    }

    // D1 baselines: the retained final measurement plus every cache variant,
    // deduplicated by proposal with the retained size winning. When the
    // parent is a stack, its reconstructed ideal-round proposal MUST be in
    // the baseline set — a child whose ideal drifted but whose final-offer
    // size did not would reallocate the whole run under a fresh pass.
    var baselines: [(proposal: ProposedSize, measuredSize: CellSize)] = [
      (previousMeasured.proposal, previousMeasured.measuredSize)
    ]
    if let viewNodeID = currentSubtree.viewNodeID {
      for stored in cache?.storedBaselineSizes(for: viewNodeID) ?? []
      where !baselines.contains(where: { $0.proposal == stored.proposal }) {
        baselines.append(stored)
      }
    }
    // The coverage certificate (plan 2026-08-11-006 Stage 1): with a
    // non-forwarding ancestor on the spine, the retained parent's
    // issued-proposal record for this root must exist, not have
    // overflowed, and be fully covered by the baseline set the loop below
    // fresh-measures. Records are observed reality; the induction that
    // makes this sufficient is that every spine ancestor is
    // equivalence-served, so its probe family reproduces given this
    // root's certified responses.
    if coverageRequired {
      guard let spineParent,
        let parentMeasured = session.measuredNode(for: spineParent.identity),
        let record = parentMeasured.containerAllocationSnapshot?
          .childIssuedProposals?.first(where: { $0.identity == root })
      else {
        result.metrics.deniedNoBaseline += 1
        return
      }
      guard !record.overflowed else {
        result.metrics.deniedRecordOverflow += 1
        return
      }
      let uncovered = record.proposals.contains { proposal in
        !baselines.contains(where: { $0.proposal == proposal })
      }
      guard !uncovered else {
        result.metrics.deniedProposalCoverage += 1
        return
      }
    }
    if let parent = spineParent,
      case .stack(let axis, _, _, _) = parent.layoutBehavior
    {
      guard
        let parentMeasured = session.measuredNode(for: parent.identity)
      else {
        result.metrics.deniedNoBaseline += 1
        return
      }
      let parentEffective = proposalApplyingFixedSizeMetadata(
        parent.layoutMetadata,
        to: parentMeasured.proposal
      )
      let idealProposal = stackProposal(
        axis: axis,
        main: .unspecified,
        cross: crossDimension(of: parentEffective, for: axis)
      )
      guard baselines.contains(where: { $0.proposal == idealProposal }) else {
        result.metrics.deniedNoBaseline += 1
        return
      }
      // Test the retained proposal last (and the ideal round just before
      // it): every pre-pass measure stores into the production cache, and
      // the main pass's fall-through wants exactly those variants to survive
      // the per-node LRU.
      let priority: (ProposedSize) -> Int = { proposal in
        if proposal == previousMeasured.proposal { return 2 }
        if proposal == idealProposal { return 1 }
        return 0
      }
      baselines.sort { priority($0.proposal) < priority($1.proposal) }
    } else {
      let retainedProposal = previousMeasured.proposal
      baselines.sort {
        ($0.proposal == retainedProposal ? 1 : 0) < ($1.proposal == retainedProposal ? 1 : 0)
      }
    }

    // The certificate: fresh-measure the current subtree at every baseline
    // proposal on a scratch context; every size must reproduce exactly. The
    // scratch context carries the session for the hysteresis-seeding seam
    // only (the same terms as the layout shadow oracle's fresh pass).
    let scratchContext = LayoutPassContext(
      purpose: .sizeStabilityPrePass,
      measurementSeedSession: session
    )
    var certifiedProduct: MeasuredNode?
    for baseline in baselines {
      // Pre-pass measures are probe-grade (plan 2026-08-11-004): their
      // products either fail the certificate and are discarded, or are
      // re-validated size-for-size before the patch serves them. Exact-key
      // cache stores stay grade-blind, so the variants the main pass wants
      // still land in the production cache.
      var fresh = measure(
        currentSubtree,
        proposal: baseline.proposal,
        passContext: scratchContext,
        grade: .probe
      )
      guard fresh.measuredSize == baseline.measuredSize else {
        fresh.flattenForRelease()
        certifiedProduct?.flattenForRelease()
        result.metrics.deniedSizeMismatch += 1
        return
      }
      if baseline.proposal == previousMeasured.proposal {
        certifiedProduct = fresh
      } else {
        fresh.flattenForRelease()
      }
    }
    // Depth-parity guard (plan 2026-08-11-006): a pre-pass measure that hit
    // the engine re-entry depth budget produced truncated geometry — it may
    // still MATCH a baseline (a fixed-extent ancestor masks the
    // truncation), and certifying it would serve a product a fresh
    // production pass could not compute. Deny instead of certifying.
    if scratchContext.runtimeIssues.contains(where: { issue in
      issue.code == "layout.customLayoutDepthLimitExceeded"
    }) {
      certifiedProduct?.flattenForRelease()
      result.metrics.deniedAbortedByCap += 1
      return
    }
    guard let certifiedProduct else {
      // The retained proposal is always in the baseline set; reaching here
      // means it produced no product, which cannot happen — deny safely.
      result.metrics.deniedNoBaseline += 1
      return
    }
    result.metrics.certificatesCertified += 1
    result.certificates.append(
      .init(
        rootIdentity: root,
        currentResolvedSubtree: currentSubtree,
        freshMeasuredAtRetainedProposal: certifiedProduct,
        retainedProposal: previousMeasured.proposal
      )
    )
  }

  /// D10's spine allowlist: plain stacks and single-proposal forwarding
  /// behaviors. `.custom` (arbitrary probing), `.viewThatFits` (probes by
  /// definition), `.flexibleFrame` (derived child proposals), `.decoration`,
  /// and lazy containers deny.
  private func isSpineForwardingBehavior(_ behavior: LayoutBehavior) -> Bool {
    switch behavior {
    case .stack, .overlay, .padding, .safeAreaIgnoring, .safeAreaInset,
      .border, .frame, .offset, .position, .intrinsic:
      true
    case .lazyStack, .flexibleFrame, .decoration, .viewThatFits, .custom:
      false
    }
  }

  private func subtreeCarriesMeasuredWindow(_ measured: MeasuredNode) -> Bool {
    var pending: [MeasuredNode] = [measured]
    while let node = pending.popLast() {
      if let snapshot = node.containerAllocationSnapshot,
        snapshot.lazyStack?.measuredWindow != nil
          || snapshot.hostedCollection?.measuredWindow != nil
      {
        return true
      }
      pending.append(contentsOf: node.childMeasurements)
    }
    return false
  }

  private func subtreeContainsIndexedChildSource(_ resolved: ResolvedNode) -> Bool {
    var pending: [ResolvedNode] = [resolved]
    while let node = pending.popLast() {
      if node.indexedChildSource != nil {
        return true
      }
      pending.append(contentsOf: node.children)
    }
    return false
  }
}
