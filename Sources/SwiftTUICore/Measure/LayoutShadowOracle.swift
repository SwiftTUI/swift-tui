/// The result of one sampled measure/place shadow comparison
/// (`layout-shadow-divergence`).
///
/// Produced on the frame tail (possibly off-main) and carried back to the
/// main-actor frame coordinator, which records it on
/// `SoundnessProbeConfiguration` — the same hop the raster shadow comparison
/// (`raster-damage`) makes. The production trees are never repaired before
/// recording: this oracle exists to observe false-equal reuse, not to heal it.
package struct LayoutShadowComparisonSummary: Sendable, Equatable {
  /// Pairs in the measured-tree walk whose identity, size, or child count
  /// diverged from the fresh shadow measure. A diverged pair's subtree is not
  /// descended into, so one wrong subtree counts once.
  package var measureDivergenceCount = 0
  /// Pairs in the placed-tree walk whose identity, bounds, or child count
  /// diverged from the fresh shadow placement.
  package var placeDivergenceCount = 0
  /// Windowed lazy or hosted subtrees skipped by the D12 carve-out, plus
  /// place-walk bounds tolerated because the production subtree carries
  /// `lazyChildScrollEstimates` (an estimated lazy extent propagating into an
  /// ancestor's bounds — the same running-refinement class, reached through a
  /// custom scroll layout's subview measure where no `measuredWindow` node is
  /// visible to the measured walk). T-info currency: it keeps the size of the
  /// oracle's blind spot measured.
  package var windowedExclusionCount = 0
  /// Whole sampled frames skipped because the SHADOW pass hit the engine
  /// re-entry depth budget (`layout.customLayoutDepthLimitExceeded`). The
  /// all-fresh shadow legitimately consumes more re-entry depth than a
  /// production pass whose serve tiers skip interior descents, so at the
  /// budget boundary the shadow truncates geometry production computed and
  /// every downstream pair diverges spuriously — the 2026-08-11 mrkdwn
  /// examples-gate false alarm. T-info currency, same terms as the
  /// windowed carve-out.
  package var depthExclusionCount = 0
  /// The first diverging pair, for trace attribution. Later divergences on the
  /// same frame update counters only.
  package var firstDivergenceDetail: String?

  package init() {}

  package var hasDivergence: Bool {
    measureDivergenceCount > 0 || placeDivergenceCount > 0
  }

  /// Folds another pass's summary into this one (late-preference
  /// reconciliation runs the layout stage more than once per frame; every
  /// pass's shadow verdict must survive to the recording point).
  package mutating func merge(_ other: Self) {
    measureDivergenceCount += other.measureDivergenceCount
    placeDivergenceCount += other.placeDivergenceCount
    windowedExclusionCount += other.windowedExclusionCount
    depthExclusionCount += other.depthExclusionCount
    if firstDivergenceDetail == nil {
      firstDivergenceDetail = other.firstDivergenceDetail
    }
  }
}

/// The sampled measure/place shadow oracle.
///
/// On a sampled frame the frame tail re-runs measure and place over the same
/// resolved tree and proposal with every reuse tier disabled — a shadow
/// `LayoutEngine` with no measurement cache, and a scratch `LayoutPassContext`
/// with no retained session and an empty hint stack — then pair-walks the
/// production trees against the shadow trees on identity, `measuredSize`, and
/// placed `bounds`. This is the check `isEquivalentForMeasurement` cannot make
/// from inside: it proves a reuse decision against the fresh pass it stands in
/// for, rather than against the comparator that approved it.
package enum LayoutShadowOracle {
  /// Runs the shadow pass and compares it against the production products.
  ///
  /// `scrollViewportContext` and `customLayoutCompatibilityDepthLimit` seed
  /// the scratch context with the production pass's environment; everything
  /// stateful (hints, metrics, placed-frame table) starts empty by design.
  /// `measurementSeedSession` carries the production pass's retained session
  /// for the custom-layout hysteresis-seeding seam ONLY: seeds select among
  /// in-pass-verified fixed points (the scroll indicator gutter is bistable
  /// by design), so the fresh pass must evaluate the same seeds production
  /// did, while every product-reuse tier stays disabled.
  package static func comparisonSummary(
    resolved: ResolvedNode,
    proposal: ProposedSize,
    productionMeasured: MeasuredNode,
    productionPlaced: PlacedNode,
    scrollViewportContext: ScrollViewportContext?,
    customLayoutCompatibilityDepthLimit: Int,
    measurementSeedSession: RetainedLayoutSession? = nil,
    productionLayoutRealizations: [LayoutDependentContentRealization] = []
  ) -> LayoutShadowComparisonSummary {
    let shadowEngine = LayoutEngine(cache: nil)
    // Realized content is a resolve-domain product, like `resolved` itself:
    // realization resolves authored closures against the live graph (reads
    // AND writes), and within a frame it is not idempotent (the first
    // realization's entity commits change what a second one resolves). The
    // shadow therefore consumes the production pass's realizations as input —
    // always passing an array (never nil) so live realization stays disabled
    // and the scratch pass is observe-only by construction.
    let scratchContext = LayoutPassContext(
      purpose: .shadowOracle,
      retainedLayout: nil,
      invalidatedIdentities: [],
      scrollViewportContext: scrollViewportContext,
      customLayoutCompatibilityDepthLimit: customLayoutCompatibilityDepthLimit,
      measurementSeedSession: measurementSeedSession,
      seededLayoutRealizations: productionLayoutRealizations
    )
    var shadowMeasured = shadowEngine.measure(
      resolved,
      proposal: proposal,
      passContext: scratchContext
    )
    var shadowPlaced = shadowEngine.place(
      resolved,
      measured: shadowMeasured,
      passContext: scratchContext
    )
    // Depth carve-out: when the SHADOW pass hit the engine re-entry depth
    // budget, its truncated (zero-size) subtrees are a legal fresh-pass
    // outcome the production pass never produced — production's serve tiers
    // skip interior descents, so it consumes strictly less depth. Comparing
    // would report every truncated subtree as a spurious divergence (the
    // 2026-08-11 mrkdwn examples-gate class), so the frame is excluded
    // whole and counted.
    let shadowHitDepthBudget = scratchContext.runtimeIssues.contains { issue in
      issue.code == "layout.customLayoutDepthLimitExceeded"
    }
    let summary: LayoutShadowComparisonSummary
    if shadowHitDepthBudget {
      var excluded = LayoutShadowComparisonSummary()
      excluded.depthExclusionCount = 1
      summary = excluded
    } else {
      summary = compare(
        productionMeasured: productionMeasured,
        productionPlaced: productionPlaced,
        shadowMeasured: shadowMeasured,
        shadowPlaced: shadowPlaced,
        excludedSubtreeIdentities: scratchContext.deniedLayoutRealizationBoundaries
      )
    }
    // The shadow trees die here. Drain them iteratively so a deep frame's
    // teardown cannot recurse off the frame-tail worker's small stack.
    shadowPlaced.flattenForRelease()
    shadowMeasured.flattenForRelease()
    return summary
  }

  /// Pure pair-walk comparison, split out so tests can inject a doctored
  /// production tree and prove the red path without a real layout engine.
  package static func compare(
    productionMeasured: MeasuredNode,
    productionPlaced: PlacedNode,
    shadowMeasured: MeasuredNode,
    shadowPlaced: PlacedNode,
    excludedSubtreeIdentities: Set<Identity> = []
  ) -> LayoutShadowComparisonSummary {
    var summary = LayoutShadowComparisonSummary()

    // D12 carve-out: a windowed product's stride is a running refinement
    // seeded by the previous frame, while the shadow pass is cold, so geometry
    // under a `measuredWindow` can diverge legitimately. Skip those subtrees
    // and count each skip so the blind spot stays measured. Pre-excluded
    // identities (realization boundaries the observe-only shadow could not
    // reproduce) skip on the same terms and share the T-info counter.
    var excludedWindowedIdentities = excludedSubtreeIdentities
    summary.windowedExclusionCount += excludedSubtreeIdentities.count

    // Heap-backed pair walks; the frame tail runs on 512 KiB worker stacks.
    var measuredPending: [(MeasuredNode, MeasuredNode)] = [
      (productionMeasured, shadowMeasured)
    ]
    while let (production, shadow) = measuredPending.popLast() {
      if excludedWindowedIdentities.contains(production.identity) {
        continue
      }
      if carriesMeasuredWindow(production) {
        excludedWindowedIdentities.insert(production.identity)
        summary.windowedExclusionCount += 1
        continue
      }
      guard
        production.identity == shadow.identity,
        production.measuredSize == shadow.measuredSize,
        production.childMeasurements.count == shadow.childMeasurements.count
      else {
        summary.measureDivergenceCount += 1
        if summary.firstDivergenceDetail == nil {
          summary.firstDivergenceDetail =
            "measure shadow divergence at \(production.identity): "
            + "production size=\(production.measuredSize) "
            + "children=\(production.childMeasurements.count), "
            + "shadow identity=\(shadow.identity) size=\(shadow.measuredSize) "
            + "children=\(shadow.childMeasurements.count), "
            + "proposal=\(production.proposal)"
        }
        // A diverged pair's children cannot be paired soundly; count the
        // subtree once and stop descending.
        continue
      }
      for index in production.childMeasurements.indices.reversed() {
        measuredPending.append(
          (production.childMeasurements[index], shadow.childMeasurements[index])
        )
      }
    }

    var placedPending: [(PlacedNode, PlacedNode)] = [
      (productionPlaced, shadowPlaced)
    ]
    while let (production, shadow) = placedPending.popLast() {
      if excludedWindowedIdentities.contains(production.identity) {
        // Already counted on the measured walk; the placed twin of a windowed
        // product realizes window-dependent children and is equally excluded.
        continue
      }
      guard
        production.identity == shadow.identity,
        production.children.count == shadow.children.count
      else {
        summary.placeDivergenceCount += 1
        recordPlaceDivergenceDetail(&summary, production: production, shadow: shadow)
        continue
      }
      // D12, place-side: a lazy container that kept never-placed children
      // publishes `lazyChildScrollEstimates`, and EVERY dimension derived
      // from those estimates is a cross-frame running refinement a cold
      // fresh pass legitimately re-estimates — the container's own extent,
      // the extent of every wrapper up to the enclosing scroll viewport
      // clamp, and the origins of its realized rows (their offsets embed the
      // estimated heights of unrealized siblings above them). When the
      // container measures inside a custom scroll layout's subview walk (the
      // 2026-08-11 mrkdwn `ScrollContent` false alarm), no `measuredWindow`
      // node is visible to the measured-tree carve-out, so the placed walk
      // applies the same skip-and-count at the estimate carrier — and at an
      // ancestor whose bounds absorbed the estimate.
      if carriesLazyEstimates(production) {
        summary.windowedExclusionCount += 1
        continue
      }
      if production.bounds != shadow.bounds {
        if subtreeCarriesLazyEstimates(production) {
          summary.windowedExclusionCount += 1
        } else {
          summary.placeDivergenceCount += 1
          recordPlaceDivergenceDetail(&summary, production: production, shadow: shadow)
        }
        continue
      }
      for index in production.children.indices.reversed() {
        placedPending.append((production.children[index], shadow.children[index]))
      }
    }

    return summary
  }

  private static func recordPlaceDivergenceDetail(
    _ summary: inout LayoutShadowComparisonSummary,
    production: PlacedNode,
    shadow: PlacedNode
  ) {
    guard summary.firstDivergenceDetail == nil else {
      return
    }
    summary.firstDivergenceDetail =
      "place shadow divergence at \(production.identity): "
      + "production bounds=\(production.bounds) "
      + "children=\(production.children.count), "
      + "shadow identity=\(shadow.identity) bounds=\(shadow.bounds) "
      + "children=\(shadow.children.count)"
  }

  /// `true` when this placed node is a lazy container that kept never-placed
  /// children (published as `lazyChildScrollEstimates` for scroll targeting):
  /// its total extent and its realized children's offsets are estimates
  /// refined across frames, not fresh-pass invariants.
  private static func carriesLazyEstimates(_ node: PlacedNode) -> Bool {
    guard let estimates = node.lazyChildScrollEstimates else {
      return false
    }
    return !estimates.isEmpty
  }

  /// `true` when the production subtree contains an estimate-carrying lazy
  /// container (see `carriesLazyEstimates`), so bounds derived from it —
  /// every wrapper between the container and the enclosing scroll viewport
  /// clamp — may legitimately differ from the cold shadow's re-estimate.
  private static func subtreeCarriesLazyEstimates(_ node: PlacedNode) -> Bool {
    var pending: [PlacedNode] = [node]
    while let node = pending.popLast() {
      if carriesLazyEstimates(node) {
        return true
      }
      pending.append(contentsOf: node.children)
    }
    return false
  }

  private static func carriesMeasuredWindow(_ node: MeasuredNode) -> Bool {
    guard let snapshot = node.containerAllocationSnapshot else {
      return false
    }
    if snapshot.lazyStack?.measuredWindow != nil {
      return true
    }
    return snapshot.hostedCollection?.measuredWindow != nil
  }
}
