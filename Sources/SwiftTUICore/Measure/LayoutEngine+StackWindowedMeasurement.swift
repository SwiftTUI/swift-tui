// Windowed measurement for indexed-source lazy stacks (proposal
// 2026-07-13-002 Stage 2.2 / F144).
//
// The exhaustive lazy measure arm realizes EVERY element (a full resolveView
// per row) and ideal-measures all of them before placement windows anything.
// Under a scroll-declared measure viewport, this path realizes and measures
// only the estimated-visible band plus overscan, and synthesizes every other
// allocation entry from the probe row's extent — the shape SwiftUI's lazy
// layout estimates use. A windowed product is valid only for its window;
// the retained-measurement gate recomputes the current window and denies
// cross-frame reuse on mismatch, and windowed products are never stored in
// the cross-frame measurement cache (which has no such gate).

extension LayoutEngine {
  /// Windowed measurement for `node`, or `nil` when ineligible — the caller
  /// falls back to the exhaustive path. Eligibility is deliberately narrow:
  /// - an indexed source realized on the main actor (worker snapshots are
  ///   already-resolved children; windowing them saves nothing),
  /// - a measure-viewport hint from an enclosing scroll layout whose axes
  ///   include the stack axis with a known viewport length,
  /// - an explicit spacing override (`nil` spacing negotiates per adjacent
  ///   pair, which needs realized neighbors),
  /// - single-cell elements (a spliced/EmptyView element would break the
  ///   1:1 index alignment between allocation entries and source elements,
  ///   so the first splice observed falls back to exhaustive).
  func windowedLazyStackMeasurement(
    for node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> MeasuredNode? {
    guard
      case .lazyStack(
        let axis, let spacingOverride, let horizontalAlignment, let verticalAlignment
      ) = node.layoutBehavior,
      let source = node.indexedChildSource,
      !source.canRunOnWorker,
      let spacing = spacingOverride,
      let hint = passContext?.currentMeasureViewportHint
    else {
      return nil
    }
    let axisMatches =
      switch axis {
      case .horizontal:
        hint.axes.contains(.horizontal)
      case .vertical:
        hint.axes.contains(.vertical)
      }
    let viewportLength = mainDimension(of: hint.viewportSize, for: axis)
    let count = source.count
    guard axisMatches, viewportLength > 0, count > 0 else {
      return nil
    }

    let idealProposal = stackProposal(
      axis: axis,
      main: .unspecified,
      cross: crossDimension(of: effectiveProposal, for: axis)
    )

    // Probe the first element for the uniform-extent estimate (terminal rows
    // are near-uniform; a per-source estimate override can come later if a
    // real workload needs it). `measure` re-entry mid-pass is the sanctioned
    // pattern — custom layouts and the indexed placement arm already do it.
    let probeElements = source.childElements(at: 0)
    guard probeElements.count == 1 else {
      return nil
    }
    let probeMeasured = measure(
      probeElements[0],
      proposal: idealProposal,
      passContext: passContext
    )
    let rowExtent = max(1, mainDimension(of: probeMeasured.measuredSize, for: axis))
    let rowStride = rowExtent + spacing

    guard
      let window = lazyStackEstimatedVisibleWindow(
        hint: hint,
        axis: axis,
        count: count,
        rowStride: rowStride
      )
    else {
      return nil
    }

    var windowChildren: [ResolvedNode] = []
    var windowMeasurements: [MeasuredNode] = []
    windowChildren.reserveCapacity(window.count)
    windowMeasurements.reserveCapacity(window.count)
    for index in window {
      let elements = index == 0 ? probeElements : source.childElements(at: index)
      guard elements.count == 1 else {
        return nil
      }
      windowChildren.append(elements[0])
      windowMeasurements.append(
        index == 0
          ? probeMeasured
          : measure(elements[0], proposal: idealProposal, passContext: passContext)
      )
    }

    let crossMetrics = stackCrossMetrics(
      for: windowChildren,
      childMeasurements: windowMeasurements,
      axis: axis,
      horizontalAlignment: horizontalAlignment,
      verticalAlignment: verticalAlignment
    )
    let probeCross = crossDimension(of: probeMeasured.measuredSize, for: axis)
    let estimatedCellSize: CellSize =
      switch axis {
      case .vertical:
        CellSize(width: probeCross, height: rowExtent)
      case .horizontal:
        CellSize(width: rowExtent, height: probeCross)
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
        identity = source.elementIdentity(at: index)
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
      estimatedRowStride: rowStride
    )

    let crossLength = max(0, crossMetrics.leading + crossMetrics.trailing)
    let rawSize: CellSize =
      switch axis {
      case .vertical:
        CellSize(width: crossLength, height: contentMainLength)
      case .horizontal:
        CellSize(width: contentMainLength, height: crossLength)
      }

    // Mirrors makeMeasuredNode's assembly (clamping, no stored child
    // measurements for lazy stacks) WITHOUT the cross-frame cache store: a
    // windowed product must never be served for a different offset.
    return MeasuredNode(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      proposal: originalProposal,
      measuredSize: clampedSize(
        rawSize,
        proposal: clampingProposal(for: node, effectiveProposal: effectiveProposal)
      ),
      childMeasurements: [],
      containerAllocationSnapshot: ContainerAllocationSnapshot(
        childSizes: childSizes,
        selectedChildIndex: nil,
        lazyStack: snapshot
      )
    )
  }

  /// The estimated-visible index band for a lazy stack under a measure
  /// viewport: anchor from the (unclamped) offset over the uniform row
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
