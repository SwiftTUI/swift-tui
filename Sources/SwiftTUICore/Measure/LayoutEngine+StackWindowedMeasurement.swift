// Windowed measurement for indexed-source lazy stacks (proposal
// 2026-07-13-002 Stage 2.2 / F144; eligibility, estimator, and iterative
// scheduling reworked by the scroll-latency program Stage 2, plan
// 2026-07-31-002).
//
// The exhaustive lazy measure arm realizes EVERY element (a full resolveView
// per row) and ideal-measures all of them before placement windows anything.
// Under a scroll-declared measure viewport, this path realizes and measures
// only the estimated-visible band plus overscan, and synthesizes every other
// allocation entry from the estimated row extent — the shape SwiftUI's lazy
// layout estimates use. A windowed product is valid only for the hint it was
// built under; the retained-measurement gate denies cross-frame reuse on any
// hint change, and windowed products are never stored in the cross-frame
// measurement cache (which has no such gate).
//
// The band is measured through the measurement WORK STACK, not by re-entrant
// `measure()` calls: windowed measurement now also runs on the frame-tail
// worker (snapshot sources are eligible), whose small stack the nested
// custom-layout + scroll shapes already push near the guard — an in-place
// per-row measure re-entry overflowed it (SIGBUS in the stack guard region,
// caught by the async frame-tail suite). The probe, the band, and the
// product assembly are three work-stack phases instead.

/// Everything the deferred windowed-lazy-stack phases need to run at the
/// work-stack top level. One context type serves both the probe finish (which
/// derives the window) and the band finish (which assembles the product).
/// A final class deliberately: the context rides inside work-stack items and
/// carries a whole `ResolvedNode`; as a struct every enum-case construction
/// copied it (retain traffic across the node's COW fields) on the windowed
/// hot path.
final class WindowedLazyStackMeasurementContext {
  let node: ResolvedNode
  let originalProposal: ProposedSize
  let effectiveProposal: ProposedSize
  let axis: Axis
  let spacing: Int
  let horizontalAlignment: HorizontalAlignment
  let verticalAlignment: VerticalAlignment
  let hint: MeasureViewportHint
  let idealProposal: ProposedSize

  init(
    node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    axis: Axis,
    spacing: Int,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment,
    hint: MeasureViewportHint,
    idealProposal: ProposedSize
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
  }
}

extension LayoutEngine {
  /// Phase 1 — eligibility, hint claim, and scheduling. Returns `true` when
  /// windowed measurement work was scheduled (the caller must not schedule
  /// the exhaustive arm); `false` falls through to exhaustive. Eligibility:
  /// - an indexed source. Both realization regimes benefit: a live
  ///   main-actor source windows realization *and* measurement; a frame-head
  ///   worker snapshot (`canRunOnWorker == true`) has realization sunk, but
  ///   windowing still bounds measurement — which Stage-0 measured as the
  ///   dominant per-notch phase (152 ms of a 292 ms document pipeline). The
  ///   old `!source.canRunOnWorker` gate assumed snapshots had nothing left
  ///   to save and put every under-budget document on the exhaustive path.
  /// - an unclaimed measure-viewport hint from an enclosing scroll layout
  ///   whose axes include the stack axis with a known viewport length. The
  ///   claim makes the *outermost* indexed stack the hint's only consumer:
  ///   the hint's offset is content-origin-relative, so a nested stack
  ///   anchoring `offset / ownStride` at its own origin would park its
  ///   window at its end (the claim is taken even when a later leg declines,
  ///   deliberately — descendants of an ineligible indexed stack must not
  ///   window against an offset that is not theirs either).
  /// - an explicit spacing override (`nil` spacing negotiates per adjacent
  ///   pair, which needs realized neighbors),
  /// - single-cell elements (a spliced/EmptyView element would break the
  ///   1:1 index alignment between allocation entries and source elements,
  ///   so the first splice observed falls back to exhaustive).
  func scheduleWindowedLazyStackMeasurement(
    for node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    passContext: LayoutPassContext?,
    work: inout [MeasurementWorkItem]
  ) -> Bool {
    guard
      case .lazyStack(
        let axis, let spacingOverride, let horizontalAlignment, let verticalAlignment
      ) = node.layoutBehavior,
      let source = node.indexedChildSource,
      let passContext,
      let candidateHint = passContext.currentMeasureViewportHint
    else {
      return false
    }
    let axisMatches =
      switch axis {
      case .horizontal:
        candidateHint.axes.contains(.horizontal)
      case .vertical:
        candidateHint.axes.contains(.vertical)
      }
    guard axisMatches else {
      return false
    }
    // Past this point the stack is an addressee of the hint on its axis, so
    // claim before the remaining legs: even if spacing/splice shape makes
    // THIS stack fall back to exhaustive, its descendants see the hint as
    // consumed and measure exhaustively too instead of mis-anchoring.
    guard let hint = passContext.claimCurrentMeasureViewportHint(for: node.identity) else {
      return false
    }
    let viewportLength = mainDimension(of: hint.viewportSize, for: axis)
    let count = source.count
    guard let spacing = spacingOverride, viewportLength > 0, count > 0 else {
      return false
    }

    let context = WindowedLazyStackMeasurementContext(
      node: node,
      originalProposal: originalProposal,
      effectiveProposal: effectiveProposal,
      axis: axis,
      spacing: spacing,
      horizontalAlignment: horizontalAlignment,
      verticalAlignment: verticalAlignment,
      hint: hint,
      idealProposal: stackProposal(
        axis: axis,
        main: .unspecified,
        cross: crossDimension(of: effectiveProposal, for: axis)
      )
    )

    // Anchor stride: the previous frame's product for this identity when one
    // exists (a windowed product carries its refined stride; an exhaustive
    // product yields its exact mean), else probe element 0 first. Markdown-
    // shaped content is wildly heterogeneous (heading 1–2 rows, code 12), so
    // a bare element-0 probe mis-anchors the window and under-estimates the
    // content length — which the enclosing scroll clamps its offset against.
    if let anchorStride = retainedEstimatedRowStride(
      for: node, axis: axis, passContext: passContext),
      let window = lazyStackEstimatedVisibleWindow(
        hint: hint,
        axis: axis,
        count: count,
        rowStride: anchorStride
      )
    {
      return scheduleWindowedLazyStackBand(
        context: context,
        source: source,
        window: window,
        probeElement: nil,
        probeMeasurement: nil,
        work: &work
      )
    }

    let probeElements = source.childElements(at: 0)
    guard probeElements.count == 1 else {
      return false
    }
    work.append(.finishWindowedLazyStackProbe(context, probeElement: probeElements[0]))
    work.append(.measure(probeElements[0], context.idealProposal))
    return true
  }

  /// Phase 2 (no-seed shape only) — the probe's finish: derive the window
  /// from the probe extent and schedule the band, or fall back to the
  /// exhaustive arm when no window exists.
  func finishWindowedLazyStackProbe(
    context: WindowedLazyStackMeasurementContext,
    probeElement: ResolvedNode,
    probeMeasurement: MeasuredNode,
    work: inout [MeasurementWorkItem]
  ) {
    let anchorStride =
      max(1, mainDimension(of: probeMeasurement.measuredSize, for: context.axis))
      + context.spacing
    guard let source = context.node.indexedChildSource,
      let window = lazyStackEstimatedVisibleWindow(
        hint: context.hint,
        axis: context.axis,
        count: source.count,
        rowStride: anchorStride
      ),
      scheduleWindowedLazyStackBand(
        context: context,
        source: source,
        window: window,
        probeElement: probeElement,
        probeMeasurement: probeMeasurement,
        work: &work
      )
    else {
      scheduleExhaustiveStackMeasurement(
        for: context.node,
        originalProposal: context.originalProposal,
        effectiveProposal: context.effectiveProposal,
        axis: context.axis,
        spacing: context.spacing,
        work: &work
      )
      return
    }
  }

  /// Schedules the band's child measures plus the assembly finish. Returns
  /// `false` (scheduling nothing) when an element splices — the caller falls
  /// back to exhaustive.
  private func scheduleWindowedLazyStackBand(
    context: WindowedLazyStackMeasurementContext,
    source: any IndexedChildSource,
    window: Range<Int>,
    probeElement: ResolvedNode?,
    probeMeasurement: MeasuredNode?,
    work: inout [MeasurementWorkItem]
  ) -> Bool {
    var windowChildren: [ResolvedNode] = []
    windowChildren.reserveCapacity(window.count)
    for index in window {
      if index == 0, let probeElement {
        windowChildren.append(probeElement)
        continue
      }
      let elements = source.childElements(at: index)
      guard elements.count == 1 else {
        return false
      }
      windowChildren.append(elements[0])
    }

    // Index 0's probe measurement is reused when it landed inside the
    // window; every other in-window child measures through the work stack —
    // never by native re-entry, which overflows the frame-tail worker's
    // stack under nested custom-layout shapes.
    let probeReused = probeMeasurement != nil && window.lowerBound == 0
    let scheduledChildren = probeReused ? Array(windowChildren.dropFirst()) : windowChildren
    scheduleChildren(
      scheduledChildren,
      proposal: context.idealProposal,
      finish: .finishWindowedLazyStack(
        context,
        window: window,
        windowChildren: windowChildren,
        reusedProbeMeasurement: probeReused ? probeMeasurement : nil,
        scheduledChildCount: scheduledChildren.count
      ),
      work: &work
    )
    return true
  }

  /// Phase 3 — assembly: refined stride from the measured band, allocation
  /// arrays with estimates outside the window, and the final product.
  /// Mirrors makeMeasuredNode's assembly (clamping, no stored child
  /// measurements for lazy stacks) WITHOUT the cross-frame cache store: a
  /// windowed product must never be served for a different offset.
  func assembleWindowedLazyStackProduct(
    context: WindowedLazyStackMeasurementContext,
    window: Range<Int>,
    windowChildren: [ResolvedNode],
    windowMeasurements: [MeasuredNode]
  ) -> MeasuredNode {
    let node = context.node
    let axis = context.axis
    let spacing = context.spacing
    // Bound once: the synthesis loop below asks for an identity per
    // out-of-window index, and an optional-chained existential open per
    // index is measurable at document scale.
    let source = node.indexedChildSource
    let count = source?.count ?? windowChildren.count

    // Refined estimate: the mean measured extent of this frame's band. The
    // product stores it (rounded) as the stride the NEXT window anchors
    // from, and synthesizes this frame's out-of-window entries with it.
    let measuredExtentSum = windowMeasurements.reduce(0) {
      $0 + mainDimension(of: $1.measuredSize, for: axis)
    }
    let rowExtent = max(
      1, (measuredExtentSum + windowMeasurements.count / 2) / max(1, windowMeasurements.count)
    )
    let rowStride = rowExtent + spacing

    let crossMetrics = stackCrossMetrics(
      for: windowChildren,
      childMeasurements: windowMeasurements,
      axis: axis,
      horizontalAlignment: context.horizontalAlignment,
      verticalAlignment: context.verticalAlignment
    )
    let bandCross = windowMeasurements.reduce(0) {
      max($0, crossDimension(of: $1.measuredSize, for: axis))
    }
    let estimatedCellSize: CellSize =
      switch axis {
      case .vertical:
        CellSize(width: bandCross, height: rowExtent)
      case .horizontal:
        CellSize(width: rowExtent, height: bandCross)
      }

    var childMainOffsets: [Int] = []
    var childMainLengths: [Int] = []
    var childIdentities: [Identity] = []
    var childSizes: [ChildAllocation] = []
    childMainOffsets.reserveCapacity(count)
    childMainLengths.reserveCapacity(count)
    childIdentities.reserveCapacity(count)
    childSizes.reserveCapacity(count)

    var cursor = 0
    for index in 0..<count {
      childMainOffsets.append(cursor)
      let length: Int
      let identity: Identity
      let size: CellSize
      if window.contains(index) {
        let measurement = windowMeasurements[index - window.lowerBound]
        length = mainDimension(of: measurement.measuredSize, for: axis)
        identity = windowChildren[index - window.lowerBound].identity
        size = measurement.measuredSize
      } else {
        length = rowExtent
        identity = source?.elementIdentity(at: index) ?? node.identity
        size = estimatedCellSize
      }
      childMainLengths.append(length)
      childIdentities.append(identity)
      childSizes.append(ChildAllocation(identity: identity, size: size))
      cursor += length
      if index < count - 1 {
        cursor += spacing
      }
    }
    let contentMainLength = cursor

    let snapshot = LazyStackAllocationSnapshot(
      axis: axis,
      childMainOffsets: childMainOffsets,
      childMainLengths: childMainLengths,
      childIdentities: childIdentities,
      contentMainLength: contentMainLength,
      crossLeading: crossMetrics.leading,
      crossTrailing: crossMetrics.trailing,
      measuredWindow: window,
      estimatedRowStride: rowStride,
      windowHint: context.hint
    )

    let crossLength = max(0, crossMetrics.leading + crossMetrics.trailing)
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
      proposal: context.originalProposal,
      measuredSize: clampedSize(
        rawSize,
        proposal: clampingProposal(for: node, effectiveProposal: context.effectiveProposal)
      ),
      childMeasurements: [],
      containerAllocationSnapshot: ContainerAllocationSnapshot(
        childSizes: childSizes,
        selectedChildIndex: nil,
        lazyStack: snapshot
      )
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
    work: inout [MeasurementWorkItem]
  ) {
    let children = stackChildren(for: node)
    let idealProposal = stackProposal(
      axis: axis,
      main: .unspecified,
      cross: crossDimension(of: effectiveProposal, for: axis)
    )
    scheduleChildren(
      children,
      proposal: idealProposal,
      finish: .finishStackIdeal(
        node,
        originalProposal: originalProposal,
        effectiveProposal: effectiveProposal,
        children: children,
        axis: axis,
        spacing: spacing,
        childCount: children.count
      ),
      work: &work
    )
  }

  /// The stride to anchor this frame's window from, carried from the
  /// previous frame's product for the same identity: a windowed product's
  /// refined `estimatedRowStride`, or an exhaustive product's exact mean
  /// (`(contentMainLength + spacing) / count` — content is `Σ extents +
  /// (count−1)·spacing`, so this recovers mean extent + spacing). `nil`
  /// when no usable previous product exists; the caller probes element 0.
  private func retainedEstimatedRowStride(
    for node: ResolvedNode,
    axis: Axis,
    passContext: LayoutPassContext
  ) -> Int? {
    guard
      let previous = passContext.retainedLayout?.measuredNode(for: node.identity),
      let snapshot = previous.containerAllocationSnapshot?.lazyStack,
      snapshot.axis == axis
    else {
      return nil
    }
    if let stride = snapshot.estimatedRowStride, stride > 0 {
      return stride
    }
    let count = snapshot.childMainLengths.count
    guard snapshot.measuredWindow == nil, count > 0, snapshot.contentMainLength > 0,
      case .lazyStack(_, .some(let spacing), _, _) = node.layoutBehavior
    else {
      return nil
    }
    return max(1, (snapshot.contentMainLength + spacing) / count)
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
