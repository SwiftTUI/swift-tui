/// A logical element owns a run of zero or more independently measured fragments.
struct LazyElementMeasurement {
  var children: [ResolvedNode]
  var measurements: [MeasuredNode]
}

final class WindowedLazyStackMeasurementContext {
  let node: ResolvedNode
  let originalProposal: ProposedSize
  let effectiveProposal: ProposedSize
  let axis: Axis
  let spacing: Int?
  let horizontalAlignment: HorizontalAlignment
  let verticalAlignment: VerticalAlignment
  let hint: MeasureViewportHint
  let idealProposal: ProposedSize
  let retainedSnapshot: LazyStackAllocationSnapshot?
  let grade: MeasurementGrade
  var known: [Int: LazyElementMeasurement] = [:]
  let identities: [Identity]
  let segments: [Identity]
  var anchor: (element: Int, fragment: Identity, viewportOffset: Int)?

  init(
    node: ResolvedNode, originalProposal: ProposedSize, effectiveProposal: ProposedSize,
    axis: Axis, spacing: Int?, horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment, hint: MeasureViewportHint,
    idealProposal: ProposedSize, retainedSnapshot: LazyStackAllocationSnapshot?,
    grade: MeasurementGrade
  ) {
    self.node = node
    self.originalProposal = originalProposal
    self.effectiveProposal = effectiveProposal
    self.axis = axis
    self.spacing = spacing
    self.horizontalAlignment = horizontalAlignment
    self.verticalAlignment = verticalAlignment
    self.hint = hint
    self.idealProposal = idealProposal
    self.retainedSnapshot = retainedSnapshot
    self.grade = grade
    let source = node.indexedChildSource!
    identities = (0..<source.count).map { source.elementIdentity(at: $0) }
    segments = (0..<source.count).map { source.estimationSegment(at: $0) }
    if let old = retainedSnapshot, let fragments = old.fragments,
      let oldHint = old.windowHint
    {
      let requested = axis == .vertical ? hint.contentOffset.y : hint.contentOffset.x
      let previous =
        old.correctedContentOffset
        ?? (axis == .vertical ? oldHint.contentOffset.y : oldHint.contentOffset.x)
      // An explicit offset change selects a new window and takes precedence
      // over automatic preservation, including short scrollTo commands.
      if requested == previous {
        let byIdentity = Dictionary(
          identities.enumerated().map { ($0.element, $0.offset) },
          uniquingKeysWith: { first, _ in first })
        let visible =
          fragments.firstIndex {
            $0.mainOffset
              + (axis == .vertical
                ? $0.measurement.measuredSize.height : $0.measurement.measuredSize.width) > previous
          } ?? 0
        let candidates =
          Array(fragments.dropFirst(visible)) + Array(fragments.prefix(visible).reversed())
        for fragment in candidates {
          guard old.childIdentities.indices.contains(fragment.elementIndex),
            let index = byIdentity[old.childIdentities[fragment.elementIndex]]
          else { continue }
          anchor = (index, fragment.identity, fragment.mainOffset - requested)
          break
        }
      }
    }
  }
}

enum LazyStackIdealEstimateGate {
  static let isEnabled = FeatureGate.lazyStackIdealEstimate.initialIsEnabled()
}

extension LayoutEngine {
  func scheduleWindowedLazyStackMeasurement(
    for node: ResolvedNode, originalProposal: ProposedSize, effectiveProposal: ProposedSize,
    grade: MeasurementGrade, passContext: LayoutPassContext?,
    localMetrics: inout LayoutWorkMetrics, work: inout [MeasurementWorkItem]
  ) -> Bool {
    guard
      case .lazyStack(let axis, let spacing, let horizontal, let vertical) = node.layoutBehavior,
      let source = node.indexedChildSource, let passContext,
      let candidate = passContext.currentMeasureViewportHint,
      axis == .vertical ? candidate.axes.contains(.vertical) : candidate.axes.contains(.horizontal),
      let hint = passContext.claimCurrentMeasureViewportHint(for: node.identity),
      mainDimension(of: hint.viewportSize, for: axis) > 0, source.count > 0,
      (spacing ?? 0) >= 0
    else { return false }
    let context = WindowedLazyStackMeasurementContext(
      node: node, originalProposal: originalProposal, effectiveProposal: effectiveProposal,
      axis: axis, spacing: spacing, horizontalAlignment: horizontal, verticalAlignment: vertical,
      hint: hint,
      idealProposal: stackProposal(
        axis: axis, main: .unspecified,
        cross: crossDimension(of: effectiveProposal, for: axis)),
      retainedSnapshot: retainedLazyStackSnapshot(
        for: node, axis: axis, passContext: passContext,
        requireSameMembership: false), grade: grade
    )
    let old = context.retainedSnapshot
    let previousMean = old.map {
      ($0.contentMainLength + (spacing ?? 0)) / max(1, $0.childMainLengths.count)
    }
    let seed = max(1, old?.estimatedRowStride ?? previousMean ?? (axis == .vertical ? 1 : 2))
    let initial =
      lazyStackEstimatedVisibleWindow(
        hint: hint, axis: axis,
        count: source.count, rowStride: seed) ?? 0..<1
    let start = context.anchor?.element ?? initial.lowerBound + 1
    let length = mainDimension(of: hint.viewportSize, for: axis)
    let lower = context.anchor == nil ? initial.lowerBound : max(0, start - 1)
    let upper =
      context.anchor == nil
      ? initial.upperBound : min(source.count, start + max(2, length / seed + 2))
    scheduleLazyElements(
      context, indices: Array(lower..<upper), localMetrics: &localMetrics, work: &work)
    return true
  }

  private func scheduleLazyElements(
    _ context: WindowedLazyStackMeasurementContext, indices: [Int],
    localMetrics: inout LayoutWorkMetrics, work: inout [MeasurementWorkItem]
  ) {
    let source = context.node.indexedChildSource!
    let elements = indices.map { source.childElements(at: $0) }
    let children = elements.flatMap { $0 }
    localMetrics.branching.lazyFragmentMeasureRequests += children.count
    scheduleChildren(
      children, proposal: context.idealProposal, grade: context.grade,
      finish: .finishCompositionalLazyStack(
        context, indices: indices, elements: elements,
        childCount: children.count), localMetrics: &localMetrics, work: &work)
  }

  func finishCompositionalLazyStack(
    context: WindowedLazyStackMeasurementContext, indices: [Int], elements: [[ResolvedNode]],
    measurements: [MeasuredNode], passContext: LayoutPassContext?,
    localMetrics: inout LayoutWorkMetrics, work: inout [MeasurementWorkItem],
    results: inout [MeasuredNode]
  ) {
    var consumed = 0
    for (index, children) in zip(indices, elements) {
      let end = consumed + children.count
      context.known[index] = .init(
        children: children, measurements: Array(measurements[consumed..<end]))
      consumed = end
    }
    let snapshot = compositionalLazySnapshot(context, passContext: passContext)
    // Any observed negative gap invalidates monotone offset search. Exhaustive
    // measurement retains overlap semantics, including negative custom preferences.
    if snapshot == nil {
      scheduleExhaustiveStackMeasurement(
        for: context.node, originalProposal: context.originalProposal,
        effectiveProposal: context.effectiveProposal, axis: context.axis, spacing: context.spacing,
        grade: context.grade, localMetrics: &localMetrics, work: &work)
      return
    }
    let allocation = snapshot!
    let count = context.identities.count
    let viewport = mainDimension(of: context.hint.viewportSize, for: context.axis)
    let requested =
      allocation.correctedContentOffset
      ?? mainDimension(of: context.hint.contentOffset, for: context.axis)
    let offset = min(max(0, requested), max(0, allocation.contentMainLength - viewport))
    var needed: [Int] = []
    for index in 0..<count where context.known[index] == nil {
      let start = allocation.childMainOffsets[index]
      let end = start + allocation.childMainLengths[index]
      if end >= max(0, offset - 1) && start <= offset + viewport + 1 { needed.append(index) }
    }
    // Empty runs still advance logical indices; discovery continues until the
    // viewport is filled or the source ends. No phantom cell is assigned to empties.
    if !needed.isEmpty {
      scheduleLazyElements(context, indices: needed, localMetrics: &localMetrics, work: &work)
      return
    }
    let cross = max(0, allocation.crossLeading + allocation.crossTrailing)
    let size =
      context.axis == .vertical
      ? CellSize(width: cross, height: allocation.contentMainLength)
      : CellSize(width: allocation.contentMainLength, height: cross)
    let sizes = context.identities.indices.map { index in
      ChildAllocation(
        identity: context.identities[index],
        size: context.axis == .vertical
          ? CellSize(width: cross, height: allocation.childMainLengths[index])
          : CellSize(width: allocation.childMainLengths[index], height: cross))
    }
    results.append(
      MeasuredNode(
        viewNodeID: context.node.viewNodeID, identity: context.node.identity,
        proposal: context.originalProposal,
        measuredSize: clampedSize(
          size,
          proposal: clampingProposal(
            for: context.node, effectiveProposal: context.effectiveProposal)),
        childMeasurements: [],
        containerAllocationSnapshot: .init(childSizes: sizes, lazyStack: allocation)))
  }

  private func compositionalLazySnapshot(
    _ context: WindowedLazyStackMeasurementContext, passContext: LayoutPassContext?
  ) -> LazyStackAllocationSnapshot? {
    let axis = context.axis
    let fallback = context.spacing ?? (axis == .vertical ? 0 : 1)
    var summaries: [Int: (extent: Int, first: Spacing?, last: Spacing?)] = [:]
    var samples: [Identity: (sum: Int, count: Int)] = [:]
    var localOffsets: [Int: [Int]] = [:]
    var crossLeading = 0
    var crossTrailing = 0
    for (index, run) in context.known {
      let spacings = run.children.map { effectiveSpacing(for: $0, passContext: passContext) }
      var cursor = 0
      var offsets: [Int] = []
      for ordinal in run.children.indices {
        if ordinal > 0 {
          let gap =
            context.spacing
            ?? preferredSpacingDistance(
              from: spacings[ordinal - 1],
              to: spacings[ordinal], axis: axis)
          if gap < 0 { return nil }
          cursor += gap
        }
        offsets.append(cursor)
        cursor += mainDimension(of: run.measurements[ordinal].measuredSize, for: axis)
      }
      localOffsets[index] = offsets
      summaries[index] = (cursor, spacings.first, spacings.last)
      if !run.children.isEmpty {
        let old = samples[context.segments[index]] ?? (0, 0)
        samples[context.segments[index]] = (old.sum + cursor, old.count + 1)
      }
      let cross = stackCrossMetrics(
        for: run.children, childMeasurements: run.measurements,
        axis: axis, horizontalAlignment: context.horizontalAlignment,
        verticalAlignment: context.verticalAlignment, passContext: passContext)
      crossLeading = max(crossLeading, cross.leading)
      crossTrailing = max(crossTrailing, cross.trailing)
    }
    var oldLengths: [Identity: Int] = [:]
    if let old = context.retainedSnapshot {
      for index in old.childIdentities.indices where old.childMainLengths.indices.contains(index) {
        oldLengths[old.childIdentities[index]] = old.childMainLengths[index]
      }
    }
    var offsets: [Int] = []
    var lengths: [Int] = []
    var fragments: [LazyStackFragmentAllocation] = []
    var cursor = 0
    var previous: Spacing?
    var hasPrevious = false
    let knownStart = context.known.keys.min() ?? 0
    for index in context.identities.indices {
      let summary = summaries[index]
      let isEmpty = context.known[index]?.children.isEmpty == true
      if !isEmpty && hasPrevious {
        let gap: Int
        if let previous, let first = summary?.first {
          gap = context.spacing ?? preferredSpacingDistance(from: previous, to: first, axis: axis)
        } else {
          gap = fallback
        }
        if gap < 0 { return nil }
        cursor += gap
      }
      offsets.append(cursor)
      let sample = samples[context.segments[index]]
      let estimate = sample.map { max(1, ($0.sum + $0.count / 2) / $0.count) } ?? 1
      // Old extents seed geometry only. Exact observations are always measured
      // from current producers and proposals; identity equality is not currency.
      let length =
        summary?.extent
        ?? ((index < knownStart || sample == nil)
          ? oldLengths[context.identities[index]].map { max(1, $0) } : nil)
        ?? estimate
      lengths.append(length)
      if let run = context.known[index] {
        for ordinal in run.children.indices {
          fragments.append(
            .init(
              elementIndex: index, fragmentIndex: ordinal,
              identity: run.children[ordinal].identity,
              mainOffset: cursor + localOffsets[index]![ordinal],
              measurement: run.measurements[ordinal]))
        }
      }
      cursor += length
      if !isEmpty {
        previous = summary?.last
        hasPrevious = true
      }
    }
    var snapshot = LazyStackAllocationSnapshot(
      axis: axis, childMainOffsets: offsets,
      childMainLengths: lengths, childIdentities: context.identities, contentMainLength: cursor,
      crossLeading: crossLeading, crossTrailing: crossTrailing,
      measuredWindow: (context.known.keys.min() ?? 0)..<((context.known.keys.max() ?? -1) + 1),
      estimatedRowStride: max(
        1, (cursor + context.identities.count / 2) / max(1, context.identities.count)),
      windowHint: context.hint)
    snapshot.fragments = fragments
    snapshot.exactElementIndices = Set(context.known.keys)
    if let anchor = context.anchor {
      var matching = fragments.first { $0.identity == anchor.fragment }
      var viewportOffset = anchor.viewportOffset
      if matching == nil, let oldFragments = context.retainedSnapshot?.fragments,
        let oldIndex = oldFragments.firstIndex(where: { $0.identity == anchor.fragment })
      {
        let byIdentity = Dictionary(
          fragments.map { ($0.identity, $0) },
          uniquingKeysWith: { first, _ in first })
        let candidates =
          Array(oldFragments.dropFirst(oldIndex + 1))
          + Array(oldFragments.prefix(oldIndex).reversed())
        for old in candidates {
          if let surviving = byIdentity[old.identity] {
            matching = surviving
            viewportOffset =
              old.mainOffset - mainDimension(of: context.hint.contentOffset, for: axis)
            break
          }
        }
      }
      if let matching {
        let viewport = mainDimension(of: context.hint.viewportSize, for: axis)
        snapshot.correctedContentOffset = min(
          max(0, matching.mainOffset - viewportOffset),
          max(0, cursor - viewport))
      } else {
        snapshot.correctedContentOffset = 0
      }
    }
    return snapshot
  }
  /// Hintless ideal-round estimate for indexed lazy stacks (scroll-latency
  /// R4-C, app-tier finding 1 of report 2026-08-01-001).
  ///
  /// An enclosing stack's ideal round proposes an UNSPECIFIED main dimension.
  /// A scroll layout maps an unspecified scrolling axis to "no measure
  /// viewport", so no hint exists and the exhaustive arm realized and
  /// ideal-measured every element — every frame, because per-notch
  /// invalidation of offset-reading descendants denies the retained product.
  /// The chrome `VStack { header; ScrollView { LazyVStack } }` shape held
  /// seconds of real-app notch latency behind exactly this round.
  ///
  /// The ideal result is an *offering* estimate for the enclosing allocator
  /// (the flexible scroll pane absorbs leftover in surplus and compresses
  /// proportionally in deficit); the product that PLACES comes from the
  /// subsequent finite-round measure, which windows under the scroll hint.
  /// So the ideal is served as an estimate:
  /// - **Retained arm** (steady state, zero realizations): the previous
  ///   frame's allocation snapshot — content length is the sum of
  ///   exact-as-of-last-frame element lengths — valid while the source
  ///   signature and count still match.
  /// - **Cold arm** (first frame, `count >= lazyStackIdealEstimateMinimumCount`
  ///   only): a single element-0 probe, content = count x extent +
  ///   (count-1) x spacing. Below the threshold the exhaustive round stays:
  ///   its cost is negligible there, and small heterogeneous collections
  ///   granted their unbounded ideal (`.fixedSize()`, nested unbounded
  ///   containers) keep exact cold sizing.
  ///
  /// Estimate products carry no child measurements and no allocation
  /// snapshot, and are never stored in the cross-frame measurement cache.
  /// Ineligible: any in-scope measure-viewport hint (a claimed hint means
  /// this measure is part of a windowed band — exhaustive semantics stay),
  /// overlapping negative spacing. Empty and multi-fragment probes keep their
  /// logical cardinality and use an explicitly estimated nonempty extent.
  ///
  /// Returns `true` when the estimate was served or scheduled; `false` falls
  /// through to the exhaustive arm.
  func scheduleLazyStackIdealEstimate(
    for node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    passContext: LayoutPassContext?,
    localMetrics: inout LayoutWorkMetrics,
    work: inout [MeasurementWorkItem],
    results: inout [MeasuredNode]
  ) -> Bool {
    guard LazyStackIdealEstimateGate.isEnabled,
      case .lazyStack(let axis, let spacingOverride, _, _) = node.layoutBehavior,
      let source = node.indexedChildSource,
      case .unspecified = mainDimension(of: effectiveProposal, for: axis)
    else {
      return false
    }
    let spacing = spacingOverride ?? (axis == .vertical ? 0 : 1)
    guard spacing >= 0 else { return false }
    // Hintless — or vacuous: a scroll layout measured at an unspecified
    // scrolling axis still pushes a hint whose viewport length on that axis
    // is 0 ("unknown — do not window"). Such a hint carries no window for
    // this axis, so the stack was headed for the exhaustive arm regardless
    // of who claimed it; the estimate serves instead. A hint with a real
    // length stays with the windowed path's claim semantics (a claimed
    // in-scope hint means this measure is part of a windowed band).
    if let hint = passContext?.currentMeasureViewportHint,
      mainDimension(of: hint.viewportSize, for: axis) > 0
    {
      return false
    }
    let count = source.count
    guard count > 0 else {
      return false
    }

    if let passContext,
      let snapshot = retainedLazyStackSnapshot(for: node, axis: axis, passContext: passContext)
    {
      results.append(
        lazyStackIdealEstimateProduct(
          for: node,
          originalProposal: originalProposal,
          effectiveProposal: effectiveProposal,
          axis: axis,
          contentMainLength: snapshot.contentMainLength,
          crossLength: max(0, snapshot.crossLeading + snapshot.crossTrailing)
        )
      )
      return true
    }

    guard count >= Self.lazyStackIdealEstimateMinimumCount else {
      return false
    }
    let probeElements = source.childElements(at: 0)
    scheduleChildren(
      probeElements,
      proposal: stackProposal(
        axis: axis, main: .unspecified,
        cross: crossDimension(of: effectiveProposal, for: axis)), grade: .probe,
      finish: .finishLazyStackIdealEstimate(
        node, originalProposal: originalProposal,
        effectiveProposal: effectiveProposal, axis: axis, spacing: spacing, count: count,
        childCount: probeElements.count), localMetrics: &localMetrics, work: &work)
    return true
  }

  /// Cold-arm threshold: below this element count the exhaustive ideal round
  /// stays (negligible cost, exact unbounded-ideal sizing for small
  /// collections); at or above it the element-0 stride estimate serves.
  static let lazyStackIdealEstimateMinimumCount = 64

  /// The cold arm's finish: assemble the stride x count estimate from the
  /// element-0 probe measurement.
  func finishLazyStackIdealEstimate(
    _ node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    axis: Axis,
    spacing: Int,
    count: Int,
    probeMeasurement: MeasuredNode
  ) -> MeasuredNode {
    let extent = max(1, mainDimension(of: probeMeasurement.measuredSize, for: axis))
    let contentMainLength = count * extent + max(0, count - 1) * spacing
    return lazyStackIdealEstimateProduct(
      for: node,
      originalProposal: originalProposal,
      effectiveProposal: effectiveProposal,
      axis: axis,
      contentMainLength: contentMainLength,
      crossLength: crossDimension(of: probeMeasurement.measuredSize, for: axis)
    )
  }

  /// The estimate product: size only — no child measurements (the indexed
  /// lazy-stack maximums walk answers from the measured ideal directly), no
  /// allocation snapshot (this product never places; the finite round's
  /// windowed product carries the placing snapshot), no cross-frame cache
  /// store (an estimate must never be served as an exact measurement).
  private func lazyStackIdealEstimateProduct(
    for node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    axis: Axis,
    contentMainLength: Int,
    crossLength: Int
  ) -> MeasuredNode {
    let rawSize: CellSize =
      switch axis {
      case .vertical:
        CellSize(width: crossLength, height: contentMainLength)
      case .horizontal:
        CellSize(width: contentMainLength, height: crossLength)
      }
    return MeasuredNode(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      proposal: originalProposal,
      measuredSize: clampedSize(
        rawSize,
        proposal: clampingProposal(for: node, effectiveProposal: effectiveProposal)
      ),
      childMeasurements: [],
      containerAllocationSnapshot: nil
    )
  }

  /// The shared exhaustive stack scheduling, extracted so the windowed
  /// probe's fallback can invoke it from a finish handler.
  func scheduleExhaustiveStackMeasurement(
    for node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    axis: Axis,
    spacing: Int?,
    grade: MeasurementGrade,
    localMetrics: inout LayoutWorkMetrics,
    work: inout [MeasurementWorkItem]
  ) {
    let children = stackChildren(for: node)
    let idealProposal = stackProposal(
      axis: axis,
      main: .unspecified,
      cross: crossDimension(of: effectiveProposal, for: axis)
    )
    // The one probe rule decidable at scheduling time (plan 2026-08-11-004
    // Stage 1): under a finite effective main the allocation round
    // supersedes these ideal products, so the ideal round is probe-grade.
    // With the main unspecified the ideal measurements ARE the final child
    // measurements and stay at the container's grade.
    let idealGrade: MeasurementGrade =
      switch mainDimension(of: effectiveProposal, for: axis) {
      case .finite: .probe
      case .unspecified, .infinity: grade
      }
    scheduleChildren(
      children,
      proposal: idealProposal,
      grade: idealGrade,
      finish: .finishStackIdeal(
        node,
        originalProposal: originalProposal,
        effectiveProposal: effectiveProposal,
        children: children,
        axis: axis,
        spacing: spacing,
        childCount: children.count,
        grade: grade
      ),
      localMetrics: &localMetrics,
      work: &work
    )
  }

  private func retainedLazyStackSnapshot(
    for node: ResolvedNode,
    axis: Axis,
    passContext: LayoutPassContext,
    requireSameMembership: Bool = true
  ) -> LazyStackAllocationSnapshot? {
    let retainedLayout = passContext.retainedLayout
    let previousMeasured: MeasuredNode?
    let previousPlaced: PlacedNode?
    let previousResolved: ResolvedNode?
    if let viewNodeID = node.viewNodeID {
      // The document's ForEach element applies an interior `.id`, so several
      // structural products can collapse onto the same runtime identity. Use
      // the occurrence-exact node table when the graph supplied a node ID.
      // Indexed-source measurements are not always present in that parallel
      // table, so retain the structural-identity fallback for their product.
      previousMeasured =
        retainedLayout?.previousFrameIndex?.measuredByNodeID[viewNodeID]
        ?? retainedLayout?.measuredNode(for: node.identity)
      previousPlaced =
        retainedLayout?.previousFrameIndex?.placedByNodeID[viewNodeID]
        ?? retainedLayout?.placedNode(for: node.identity)
      previousResolved =
        retainedLayout?.previousFrameIndex?.resolvedByNodeID[viewNodeID]
        ?? retainedLayout?.resolvedNode(for: node.identity)
    } else {
      previousMeasured = retainedLayout?.measuredNode(for: node.identity)
      previousPlaced = retainedLayout?.placedNode(for: node.identity)
      previousResolved = retainedLayout?.resolvedNode(for: node.identity)
    }
    let snapshot =
      previousPlaced?.lazyStackAllocationSnapshot
      ?? previousMeasured?.containerAllocationSnapshot?.lazyStack
    guard
      let snapshot,
      snapshot.axis == axis,
      let previousResolved,
      let previousSource = previousResolved.indexedChildSource,
      let source = node.indexedChildSource,
      // The retained frame can hold a LIVE source (the one-shot/sync commit
      // path stores it without worker-snapshot conversion — the "benign
      // byproduct" of the 2026-05-30 flake-#12 trace), and this function
      // also runs on the frame-tail worker, where reading a live source's
      // MainActor-checked signature trips the release isolation guard. A
      // live CURRENT source proves the pass is on the main actor (live
      // sources are offload-ineligible), so the retained read is safe
      // exactly when the retained source is a snapshot or the current one
      // is live; otherwise skip reuse and measure fresh.
      previousSource.canRunOnWorker || !source.canRunOnWorker,
      !requireSameMembership || previousSource.measurementSignature == source.measurementSignature,
      !requireSameMembership || snapshot.childMainLengths.count == source.count
    else {
      return nil
    }
    return snapshot
  }

  /// The estimated-visible index band for a lazy stack under a measure
  /// viewport: anchor from the (unclamped) offset over the estimated row
  /// stride, extended by the rows one viewport spans, one row of overscan on
  /// each side, plus one for the partially-visible row at each edge.
  func lazyStackEstimatedVisibleWindow(
    hint: MeasureViewportHint,
    axis: Axis,
    count: Int,
    rowStride: Int
  ) -> Range<Int>? {
    let viewportLength = mainDimension(of: hint.viewportSize, for: axis)
    guard viewportLength > 0, count > 0 else {
      return nil
    }
    let stride = max(1, rowStride)
    let offset = max(0, mainDimension(of: hint.contentOffset, for: axis))
    let overscan = 1
    let anchor = min(max(0, count - 1), offset / stride)
    let rowsPerViewport = (viewportLength + stride - 1) / stride
    let lower = max(0, anchor - overscan)
    let upper = min(count, anchor + rowsPerViewport + overscan + 1)
    guard lower < upper else {
      return nil
    }
    return lower..<upper
  }
}
