@_spi(Testing) import SwiftTUIPrimitives

extension LayoutEngine {
  /// Admits a node to hosted-collection windowing. A non-empty `List` or
  /// `Table` container measures its realized rows out of line; every other
  /// node is answered `nil` from this small frame.
  ///
  /// Every scheduled measurement asks this question, so the common answer —
  /// not a collection — must cost no stack. The body's -Onone frame is
  /// large (about 56 KiB, 66 KiB under AddressSanitizer: the realized rows,
  /// both collection layouts and the allocation snapshot are static
  /// temporaries), and it sits at the tip of every nested custom-layout
  /// re-entry chain, where a plain leaf under two re-entries overflowed the
  /// frame-tail worker's stack under AddressSanitizer (STUI-1133). Keeping
  /// the admission here reserves that frame only for a collection that is
  /// actually windowed.
  func windowedHostedCollectionMeasurement(
    for node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> MeasuredNode? {
    guard
      case .intrinsic = node.layoutBehavior,
      let collection = node.semanticMetadata.hostedCollectionContainer,
      let source = node.indexedChildSource,
      source.count > 0
    else {
      return nil
    }
    return measureWindowedHostedCollection(
      for: node,
      collection: collection,
      source: source,
      originalProposal: originalProposal,
      effectiveProposal: effectiveProposal,
      passContext: passContext
    )
  }

  /// The windowing measurement proper; see the admission above for why it is
  /// a separate frame. `@inline(never)` keeps optimized builds from folding
  /// it back into the admission.
  @inline(never)
  private func measureWindowedHostedCollection(
    for node: ResolvedNode,
    collection: HostedCollectionContainerMetadata,
    source: any IndexedChildSource,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> MeasuredNode? {
    guard
      let plan = hostedCollectionWindowPlan(
        for: node,
        collection: collection,
        source: source,
        effectiveProposal: effectiveProposal,
        passContext: passContext
      )
    else {
      return nil
    }
    // Measuring each realized row below re-enters the layout engine on the
    // native call stack — the hosted-collection sibling of the custom-layout
    // compatibility recursion. Nested collections therefore consume real
    // stack per level, so the re-entry shares the same depth boundary: the
    // resolve-time `maxEngineReentryNestingDepth` aggregate keeps deep trees
    // off the small-stack worker, and this runtime gate bounds the recursion
    // (with a `layout.customLayoutDepthLimitExceeded` runtime issue) instead
    // of letting a pathological nest overflow the stack.
    guard
      passContext?.enterCustomLayoutCompatibilityBoundary(
        identity: node.identity,
        debugName: collection.kind == .table ? "Table" : "List",
        phase: .measurement
      ) ?? true
    else {
      return MeasuredNode(
        viewNodeID: node.viewNodeID,
        identity: node.identity,
        proposal: originalProposal,
        measuredSize: .zero,
        childMeasurements: [],
        containerAllocationSnapshot: nil
      )
    }
    defer {
      passContext?.exitCustomLayoutCompatibilityBoundary()
    }

    // This frame is live across every row's re-entry, so it holds only the
    // realized band. The window was planned out of line above, and each
    // kind's layout products are derived out of line below; one straight-line
    // body reserved all of their temporaries here at once (STUI-1133).
    var sourceIndices = plan.sourceIndices
    var measuredWindow = plan.measuredWindow
    var hiddenEdges = plan.retainedHiddenEdges
    var children: [ResolvedNode] = []
    var measurements: [MeasuredNode] = []
    children.reserveCapacity(sourceIndices.count)
    measurements.reserveCapacity(sourceIndices.count)
    if collection.kind == .table {
      // Discovery must see every row at its own width. An earlier
      // measurement of this source in the same frame (a scroll view measures
      // the viewport, then re-measures against its content height) applied
      // its widths, and a row framed at them reports nothing wider
      // (STUI-1230). The second pass re-applies the retained widths.
      source.beginHostedTableColumnDiscovery()
    }
    for index in sourceIndices {
      let child = source.child(at: index)
      children.append(child)
      measurements.append(
        measure(child, proposal: plan.childProposal, passContext: passContext)
      )
    }
    if collection.kind == .table {
      // Out of line: this function sits on every re-entrant measurement
      // level, so its own stack frame must not grow (custom-layout depth).
      widenWindowForHiddenTableSeparators(
        node: node, source: source, bounds: plan.bounds, hint: plan.hint,
        rowStride: plan.rowStride, tallRowHeights: plan.retainedTallRowHeights,
        childProposal: plan.childProposal, passContext: passContext,
        sourceIndices: &sourceIndices, measuredWindow: &measuredWindow,
        children: &children, measurements: &measurements, hiddenEdges: &hiddenEdges)
      return hostedTableMeasurement(
        for: node, source: source, plan: plan, sourceIndices: sourceIndices,
        measuredWindow: measuredWindow, children: &children, measurements: &measurements,
        hiddenEdges: hiddenEdges, originalProposal: originalProposal,
        effectiveProposal: effectiveProposal, passContext: passContext)
    }
    return hostedListMeasurement(
      for: node, plan: plan, sourceIndices: sourceIndices, measuredWindow: measuredWindow,
      children: children, measurements: measurements, hiddenEdges: hiddenEdges,
      originalProposal: originalProposal, effectiveProposal: effectiveProposal)
  }

  /// Which rows a hosted collection realizes this pass, and at what proposal.
  /// Derived out of line from the measurement so its temporaries (payload
  /// copies, the line model's display lines, the retained estimates) are not
  /// live across the rows' re-entry.
  @inline(never)
  private func hostedCollectionWindowPlan(
    for node: ResolvedNode,
    collection: HostedCollectionContainerMetadata,
    source: any IndexedChildSource,
    effectiveProposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> HostedCollectionWindowPlan? {
    let fallbackSize: CellSize
    switch node.drawPayload {
    case .list(let payload):
      fallbackSize = measuredListIdealSize(for: payload)
    case .table(let payload):
      fallbackSize = measuredTableIdealSize(for: payload)
    default:
      return nil
    }
    let concreteSize = CellSize(
      width: proposedCollectionDimension(effectiveProposal.width, fallback: fallbackSize.width),
      height: proposedCollectionDimension(effectiveProposal.height, fallback: fallbackSize.height)
    )
    let bounds = CellRect(origin: .zero, size: concreteSize)
    let retainedTallRows = retainedTallRowHeights(
      for: node,
      source: source,
      passContext: passContext
    )
    let retainedHiddenEdges =
      collection.kind == .table
      ? retainedHiddenRowSeparatorEdges(for: node, source: source, passContext: passContext)
      : [:]
    let rowStride: Int
    switch (collection.kind, node.drawPayload) {
    case (.list, .list(let payload)):
      rowStride = payload.style.listRowDisplaySpan
    case (.table, .table):
      // A table body always alternates row and separator lines.
      rowStride = 2
    default:
      return nil
    }

    // The line model answers "which rows are visible" exactly, but only when
    // the height it is asked about really is the viewport. Two callers break
    // that: an unbounded proposal (nothing to slice against), and the
    // placement pass inside a scroll view, which re-measures the collection
    // against its own CONTENT height — as tall as the dataset. In both cases
    // the enclosing scroll layout's declared measure viewport is the better
    // information, so it wins.
    let hint = passContext?.currentMeasureViewportHint
    let viewportHeight = hint?.viewportSize.height ?? 0
    let usesLineModel: Bool
    switch effectiveProposal.height {
    case .finite(let height):
      usesLineModel = viewportHeight <= 0 || height <= viewportHeight
    case .unspecified, .infinity:
      usesLineModel = false
    }

    var sourceIndices: [Int]
    var measuredWindow: Range<Int>?
    if usesLineModel {
      // The proposal fits inside the viewport, so the line model's answer is
      // both exact and cheap.
      let visibleIndices: [Int]
      switch (collection.kind, node.drawPayload) {
      case (.list, .list(let payload)) where isCellPosition(payload.scrollAnchor):
        visibleIndices = positionedHostedCollectionWindow(
          anchor: payload.scrollAnchor, count: source.count, capacity: concreteSize.height)
      case (.table, .table(let payload)) where isCellPosition(payload.scrollAnchor):
        visibleIndices = positionedHostedCollectionWindow(
          anchor: payload.scrollAnchor, count: source.count, capacity: concreteSize.height)
      case (.list, .list(let payload)):
        visibleIndices = payload.style.visibleListLayout(for: payload, in: bounds).lines.compactMap(
          \.itemIndex
        )
      case (.table, .table(let payload)):
        visibleIndices = DrawExtractor().visibleTableLayout(for: payload, in: bounds).lines
          .compactMap(
            \.rowIndex
          )
      default:
        return nil
      }
      sourceIndices = finiteHostedCollectionWindow(
        visibleIndices: visibleIndices,
        count: source.count
      )
    } else if let window = hostedCollectionHintWindow(
      hint: hint,
      count: source.count,
      rowStride: rowStride,
      tallRowHeights: retainedTallRows,
      hiddenSeparators: hiddenTableSeparators(from: retainedHiddenEdges, rowCount: source.count)
    ),
      passContext?.claimCurrentMeasureViewportHint(for: node.identity) != nil
    {
      // Deriving the window from the hint — rather than from the line model
      // over the full content height — is the whole point: asking the line
      // model here would generate a display line per row before windowing
      // anything, which is the O(dataset) collapse this path exists to avoid.
      // The claim keeps a collection NESTED inside an outer windowed stack
      // from anchoring the outer scroll's offset at its own origin: the
      // outermost indexed container per hint wins, everything deeper falls
      // back (scroll-latency Stage 2, plan 2026-07-31-002).
      sourceIndices = Array(window)
      measuredWindow = window
    } else {
      // Nothing bounds the realization. Report the cliff rather than guessing
      // a size for content whose true ideal was explicitly asked for.
      passContext?.recordUnboundedCollectionRealization(
        identity: node.identity,
        count: source.count,
        source: collection.kind == .table ? "Table" : "List"
      )
      sourceIndices = Array(0..<source.count)
    }

    let childWidth: Int
    if case .table(let payload) = node.drawPayload {
      childWidth = max(0, concreteSize.width - payload.style.contentInsets.horizontal)
    } else if case .list(let payload) = node.drawPayload {
      let markerWidth = payload.showsSelectionMarker ? 2 : 0
      childWidth = max(0, concreteSize.width - payload.style.contentInsets.horizontal - markerWidth)
    } else {
      childWidth = max(0, concreteSize.width)
    }
    // An intrinsic-width request must discover the realized rows' widths.
    // Constraining them to the empty payload's fallback width erases their
    // text before it can contribute to the collection's ideal size.
    let proposedChildWidth: ProposedDimension
    switch effectiveProposal.width {
    case .finite: proposedChildWidth = .finite(childWidth)
    case .unspecified, .infinity: proposedChildWidth = effectiveProposal.width
    }
    return HostedCollectionWindowPlan(
      bounds: bounds,
      retainedTallRowHeights: retainedTallRows,
      retainedHiddenEdges: retainedHiddenEdges,
      rowStride: rowStride,
      hint: hint,
      sourceIndices: sourceIndices,
      measuredWindow: measuredWindow,
      childProposal: ProposedSize(width: proposedChildWidth, height: .unspecified)
    )
  }

  /// A hosted list's product from its realized rows. Out of line from the
  /// row loop (see `measureWindowedHostedCollection`).
  @inline(never)
  private func hostedListMeasurement(
    for node: ResolvedNode,
    plan: HostedCollectionWindowPlan,
    sourceIndices: [Int],
    measuredWindow: Range<Int>?,
    children: [ResolvedNode],
    measurements: [MeasuredNode],
    hiddenEdges: [Int: HiddenRowSeparatorEdges],
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize
  ) -> MeasuredNode? {
    guard case .list(let payload) = node.drawPayload else {
      return nil
    }
    // Derive the height-aware layout ONCE, from the real measured heights,
    // and carry it forward. `bounds` here is origin-zero; placement
    // translates.
    var tallRowHeights = plan.retainedTallRowHeights
    mergeTallRowHeights(
      from: measurements,
      at: sourceIndices,
      into: &tallRowHeights
    )
    let measuredSize = measuredHostedListSize(
      for: payload,
      childMeasurements: measurements,
      sourceIndices: sourceIndices,
      retainedTallRowHeights: plan.retainedTallRowHeights,
      proposal: effectiveProposal
    )
    let listLayout = payload.style.visibleListLayout(
      for: payload,
      in: .init(origin: .zero, size: measuredSize),
      rowHeights: tallRowHeights,
      // Only set on the hint path, where `bounds` is the collection's own
      // content height rather than a viewport. Without it the line model
      // would build a display line per row of the whole dataset before
      // anything windowed it — the interim O(dataset) cost S2 left behind.
      rowWindow: measuredWindow
    )
    return hostedCollectionMeasuredNode(
      for: node,
      originalProposal: originalProposal,
      measuredSize: measuredSize,
      children: children,
      measurements: measurements,
      sourceIndices: sourceIndices,
      measuredWindow: measuredWindow,
      rowStride: plan.rowStride,
      tableColumnWidths: nil,
      listLayout: listLayout,
      tableLayout: nil,
      tallRowHeights: tallRowHeights,
      hiddenEdges: hiddenEdges
    )
  }

  /// A hosted table's product from its realized rows: column discovery, the
  /// framed second pass (which re-enters the engine, so this frame is live
  /// for it, holding only the table's temporaries) and the layout.
  @inline(never)
  private func hostedTableMeasurement(
    for node: ResolvedNode,
    source: any IndexedChildSource,
    plan: HostedCollectionWindowPlan,
    sourceIndices: [Int],
    measuredWindow: Range<Int>?,
    children: inout [ResolvedNode],
    measurements: inout [MeasuredNode],
    hiddenEdges: [Int: HiddenRowSeparatorEdges],
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> MeasuredNode? {
    guard case .table(let payload) = node.drawPayload else {
      return nil
    }
    var discovered = measureTableColumnWidths(
      columns: payload.columns,
      rows: payload.isViewportBacked ? [] : payload.rows
    )
    for rowMeasurement in measurements {
      for (columnIndex, cellMeasurement) in rowMeasurement.childMeasurements.enumerated()
      where discovered.indices.contains(columnIndex) {
        discovered[columnIndex] = max(
          discovered[columnIndex],
          cellMeasurement.measuredSize.width
        )
      }
    }
    let tableColumnWidths: [Int]? = source.retainedTableColumnWidths(
      columns: payload.columns,
      discovered: discovered
    )
    // The second pass is load-bearing, not redundant (register item D21).
    // Discovery above reads each cell's MEASURED width, and a cell that has
    // had `.frame(width:)` applied reports exactly that width — a frame
    // reports `width ?? contentSize.width`, so it fully masks the child's
    // ideal. Discovery therefore needs an UNFRAMED measurement while the
    // layout product needs a FRAMED one, and one pass cannot be both.
    //
    // Applying the retained widths before the loop instead — the obvious
    // single-pass rewrite — caps every column at whatever it first
    // discovered and never lets it grow again; with no retained widths on
    // the first frame that cap is the column TITLE width, so a 16-character
    // cell renders as narrow as a 2-character one, permanently.
    // `TableColumnWidthPassTests` pins both halves of that.
    //
    // The cost is one extra measure of the WINDOW — not a re-realization:
    // `applyHostedTableColumnWidths` re-frames the realization cache's rows
    // on demand, so `child(at:)` below hits it (D21-a).
    if let tableColumnWidths {
      source.applyHostedTableColumnWidths(tableColumnWidths)
      children.removeAll(keepingCapacity: true)
      measurements.removeAll(keepingCapacity: true)
      for index in sourceIndices {
        let child = source.child(at: index)
        children.append(child)
        measurements.append(
          measure(child, proposal: plan.childProposal, passContext: passContext)
        )
      }
    }
    // Derive the height-aware layout ONCE, from the real measured heights,
    // and carry it forward. `bounds` here is origin-zero; placement
    // translates.
    var tallRowHeights = plan.retainedTallRowHeights
    mergeTallRowHeights(
      from: measurements,
      at: sourceIndices,
      into: &tallRowHeights
    )
    let hiddenSeparators = hiddenTableSeparators(from: hiddenEdges, rowCount: source.count)
    let measuredSize = measuredHostedTableSize(
      for: payload,
      childMeasurements: measurements,
      sourceIndices: sourceIndices,
      retainedTallRowHeights: plan.retainedTallRowHeights,
      hiddenSeparatorCount: hiddenSeparators.count,
      proposal: effectiveProposal
    )
    let tableLayout = DrawExtractor().visibleTableLayout(
      for: payload,
      in: .init(origin: .zero, size: measuredSize),
      columnWidths: tableColumnWidths,
      rowHeights: tallRowHeights,
      hiddenSeparators: hiddenSeparators,
      rowWindow: measuredWindow
    )
    return hostedCollectionMeasuredNode(
      for: node,
      originalProposal: originalProposal,
      measuredSize: measuredSize,
      children: children,
      measurements: measurements,
      sourceIndices: sourceIndices,
      measuredWindow: measuredWindow,
      rowStride: plan.rowStride,
      tableColumnWidths: tableColumnWidths,
      listLayout: nil,
      tableLayout: tableLayout,
      tallRowHeights: tallRowHeights,
      hiddenEdges: hiddenEdges
    )
  }

  private func hostedCollectionMeasuredNode(
    for node: ResolvedNode,
    originalProposal: ProposedSize,
    measuredSize: CellSize,
    children: [ResolvedNode],
    measurements: [MeasuredNode],
    sourceIndices: [Int],
    measuredWindow: Range<Int>?,
    rowStride: Int,
    tableColumnWidths: [Int]?,
    listLayout: ListVisibleLayout?,
    tableLayout: TableVisibleLayout?,
    tallRowHeights: [Int: Int],
    hiddenEdges: [Int: HiddenRowSeparatorEdges]
  ) -> MeasuredNode {
    MeasuredNode(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      proposal: originalProposal,
      measuredSize: measuredSize,
      childMeasurements: measurements,
      containerAllocationSnapshot: .init(
        childSizes: zip(children, measurements).map {
          ChildAllocation(identity: $0.identity, size: $1.measuredSize)
        },
        hostedCollection: .init(
          sourceIndices: sourceIndices,
          tableColumnWidths: tableColumnWidths,
          measuredWindow: measuredWindow,
          estimatedRowStride: measuredWindow == nil ? nil : rowStride,
          listLayout: listLayout,
          tableLayout: tableLayout,
          tallRowHeights: tallRowHeights,
          hiddenRowSeparatorEdges: hiddenEdges
        )
      )
    )
  }

  /// The tall-row heights the previous frame measured for this collection,
  /// when they still describe these rows (the same element ids). They are
  /// what keeps a tall row's cells in the content extent and in every later
  /// row's position after the window stops realizing it — without them the
  /// extent shrinks as the row scrolls out, and a scroll view sitting at its
  /// bottom edge snaps back. Like the lazy stacks' retained element lengths
  /// they are estimates: a row is re-measured whenever it is realized.
  private func retainedTallRowHeights(
    for node: ResolvedNode,
    source: any IndexedChildSource,
    passContext: LayoutPassContext?
  ) -> [Int: Int] {
    // Scratch passes (the shadow oracle, the size-stability certificate) read
    // the production session through the seed seam, so they reproduce the
    // production pass's sizes.
    guard
      let retainedLayout = passContext?.retainedLayout ?? passContext?.measurementSeedSession
    else {
      return [:]
    }
    let previousMeasured =
      node.viewNodeID.flatMap { retainedLayout.previousFrameIndex?.measuredByNodeID[$0] }
      ?? retainedLayout.measuredNode(for: node.identity)
    let previousResolved =
      node.viewNodeID.flatMap { retainedLayout.previousFrameIndex?.resolvedByNodeID[$0] }
      ?? retainedLayout.resolvedNode(for: node.identity)
    guard
      let snapshot = previousMeasured?.containerAllocationSnapshot?.hostedCollection,
      !snapshot.tallRowHeights.isEmpty,
      let previousSource = previousResolved?.indexedChildSource,
      // The signature is immutable metadata, including on a live source.
      // Comparing it does not realize rows or touch main-actor state.
      previousSource.measurementSignature == source.measurementSignature
    else {
      return [:]
    }
    return snapshot.tallRowHeights
  }

  /// Records the realized rows' measured heights over the retained ones: a row
  /// that now measures one cell is no longer tall.
  private func mergeTallRowHeights(
    from measurements: [MeasuredNode],
    at sourceIndices: [Int],
    into tallRowHeights: inout [Int: Int]
  ) {
    for (index, measurement) in zip(sourceIndices, measurements) {
      let height = measurement.measuredSize.height
      tallRowHeights[index] = height > 1 ? height : nil
    }
  }

  /// Hidden table separators let more rows into the window than the
  /// one-separator-per-row estimate chose. Realized rows report their edges,
  /// so widen the realized band until it covers every row the
  /// separator-aware line model places. Tables whose realized and retained
  /// rows hide no separator never widen.
  @inline(never)
  private func widenWindowForHiddenTableSeparators(
    node: ResolvedNode,
    source: any IndexedChildSource,
    bounds: CellRect,
    hint: MeasureViewportHint?,
    rowStride: Int,
    tallRowHeights: [Int: Int],
    childProposal: ProposedSize,
    passContext: LayoutPassContext?,
    sourceIndices: inout [Int],
    measuredWindow: inout Range<Int>?,
    children: inout [ResolvedNode],
    measurements: inout [MeasuredNode],
    hiddenEdges: inout [Int: HiddenRowSeparatorEdges]
  ) {
    guard case .table(let payload) = node.drawPayload else { return }
    for (index, child) in zip(sourceIndices, children) {
      recordHiddenRowSeparatorEdges(of: child, at: index, into: &hiddenEdges)
    }
    while let lower = sourceIndices.first, let upper = sourceIndices.last,
      let covered = hiddenSeparatorTableWindow(
        payload: payload, bounds: bounds, count: source.count, hint: hint,
        measuredWindow: measuredWindow, rowStride: rowStride,
        tallRowHeights: tallRowHeights, hiddenEdges: hiddenEdges),
      covered.lowerBound < lower || covered.upperBound > upper + 1
    {
      let widened = min(lower, covered.lowerBound)..<max(upper + 1, covered.upperBound)
      var realized = Dictionary(
        uniqueKeysWithValues: zip(sourceIndices, zip(children, measurements)).map { ($0, $1) })
      for index in widened where realized[index] == nil {
        let child = source.child(at: index)
        recordHiddenRowSeparatorEdges(of: child, at: index, into: &hiddenEdges)
        realized[index] = (child, measure(child, proposal: childProposal, passContext: passContext))
      }
      sourceIndices = Array(widened)
      children = sourceIndices.compactMap { realized[$0]?.0 }
      measurements = sourceIndices.compactMap { realized[$0]?.1 }
      if measuredWindow != nil { measuredWindow = widened }
    }
  }

  /// The hidden separator edges the previous frame recorded for this table,
  /// on the same currency terms as ``retainedTallRowHeights(for:source:passContext:)``.
  private func retainedHiddenRowSeparatorEdges(
    for node: ResolvedNode,
    source: any IndexedChildSource,
    passContext: LayoutPassContext?
  ) -> [Int: HiddenRowSeparatorEdges] {
    guard
      let retainedLayout = passContext?.retainedLayout ?? passContext?.measurementSeedSession
    else {
      return [:]
    }
    let previousMeasured =
      node.viewNodeID.flatMap { retainedLayout.previousFrameIndex?.measuredByNodeID[$0] }
      ?? retainedLayout.measuredNode(for: node.identity)
    let previousResolved =
      node.viewNodeID.flatMap { retainedLayout.previousFrameIndex?.resolvedByNodeID[$0] }
      ?? retainedLayout.resolvedNode(for: node.identity)
    guard
      let snapshot = previousMeasured?.containerAllocationSnapshot?.hostedCollection,
      !snapshot.hiddenRowSeparatorEdges.isEmpty,
      let previousSource = previousResolved?.indexedChildSource,
      previousSource.measurementSignature == source.measurementSignature
    else {
      return [:]
    }
    return snapshot.hiddenRowSeparatorEdges
  }

  /// Records a realized row's hidden separator edges over the retained ones.
  private func recordHiddenRowSeparatorEdges(
    of row: ResolvedNode,
    at index: Int,
    into edges: inout [Int: HiddenRowSeparatorEdges]
  ) {
    let style = row.drawMetadata.listStyle
    let edge = HiddenRowSeparatorEdges(
      top: style?.rowSeparatorTopVisibility == .hidden,
      bottom: style?.rowSeparatorBottomVisibility == .hidden)
    edges[index] = edge.top || edge.bottom ? edge : nil
  }

  /// The rows a table's separator-aware line model places for this pass: the
  /// visible rows of the finite line model, or the hint window.
  private func hiddenSeparatorTableWindow(
    payload: TablePayload,
    bounds: CellRect,
    count: Int,
    hint: MeasureViewportHint?,
    measuredWindow: Range<Int>?,
    rowStride: Int,
    tallRowHeights: [Int: Int],
    hiddenEdges: [Int: HiddenRowSeparatorEdges]
  ) -> Range<Int>? {
    let hidden = hiddenTableSeparators(from: hiddenEdges, rowCount: count)
    guard !hidden.isEmpty else { return nil }
    if measuredWindow != nil {
      return hostedCollectionHintWindow(
        hint: hint, count: count, rowStride: rowStride, tallRowHeights: tallRowHeights,
        hiddenSeparators: hidden)
    }
    let visible = DrawExtractor().visibleTableLayout(
      for: payload, in: bounds, rowHeights: tallRowHeights, hiddenSeparators: hidden
    ).lines.compactMap(\.rowIndex)
    let window = finiteHostedCollectionWindow(visibleIndices: visible, count: count)
    guard let first = window.first, let last = window.last else { return nil }
    return first..<(last + 1)
  }

  private func proposedCollectionDimension(
    _ proposal: ProposedDimension,
    fallback: Int
  ) -> Int {
    switch proposal {
    case .finite(let value):
      max(0, value)
    case .unspecified, .infinity:
      max(0, fallback)
    }
  }

  private func finiteHostedCollectionWindow(
    visibleIndices: [Int],
    count: Int
  ) -> [Int] {
    guard count > 0 else {
      return []
    }
    let valid = visibleIndices.filter { (0..<count).contains($0) }
    guard let first = valid.min(), let last = valid.max() else {
      return [0]
    }
    let lower = max(0, first - 1)
    let upper = min(count, last + 2)
    return Array(lower..<upper)
  }

  /// A cell position starts inside its anchor row. Realize a bounded band
  /// around that row before measuring it; estimating every row as one cell
  /// would skip a tall anchor, while using retained heights would change the
  /// realization window after an otherwise reusable frame. One row per cell
  /// bounds both the visible suffix and any backfill at the content's end.
  private func positionedHostedCollectionWindow(
    anchor: CollectionScrollAnchor?, count: Int, capacity: Int
  ) -> [Int] {
    let row = anchor?.rowIndex(rowCount: count) ?? 0
    let span = max(1, capacity)
    return Array(max(0, row - span)..<min(count, row + span + 1))
  }

  private func isCellPosition(_ anchor: CollectionScrollAnchor?) -> Bool {
    if case .position = anchor { return true }
    return false
  }

  /// The estimated-visible row band for a hosted collection under a scroll
  /// layout's measure-viewport hint: anchor from the (unclamped) offset over
  /// the display-line stride, extended by the rows one viewport spans, with a
  /// row of overscan each side.
  ///
  /// Unlike a lazy stack, a collection needs no probe measurement for the
  /// stride — its line model is arithmetic (one line per row, two when the
  /// style draws separators), plus the extra cells of the rows
  /// `tallRowHeights` knows are taller.
  func hostedCollectionHintWindow(
    hint: MeasureViewportHint?,
    count: Int,
    rowStride: Int,
    tallRowHeights: [Int: Int] = [:],
    hiddenSeparators: Set<Int> = []
  ) -> Range<Int>? {
    guard let hint,
      hint.axes.contains(.vertical),
      hint.viewportSize.height > 0,
      count > 0
    else {
      return nil
    }
    let stride = max(1, rowStride)
    let offset = max(0, hint.contentOffset.y)
    let overscan = 1
    let geometry = CollectionScrollGeometry(
      rowCount: count, rowSpan: stride, rowHeights: tallRowHeights,
      hiddenSeparators: hiddenSeparators)
    let anchor = geometry.row(atOrBeforeLine: offset)
    // Rows whose separators are hidden pack one line closer each.
    // Ceiling division without the overflowing `height + stride - 1`.
    let rowsPerViewport =
      hiddenSeparators.isEmpty
      ? hint.viewportSize.height / stride + (hint.viewportSize.height % stride == 0 ? 0 : 1)
      : max(
        1,
        geometry.row(
          atOrBeforeLine: SaturatingConversion.adding(offset, hint.viewportSize.height))
          - anchor + 1)
    let lower = max(0, anchor - overscan)
    let upper = min(count, SaturatingConversion.sum([anchor, rowsPerViewport, overscan, 1]))
    guard lower < upper else {
      return nil
    }
    return lower..<upper
  }

}

/// The cells the rows `tallRowHeights` knows are taller than one cell add to a
/// collection's one-cell-per-row line model, counting only the rows whose index
/// satisfies `isIncluded`.
package func tallRowExtraCells(
  in tallRowHeights: [Int: Int],
  where isIncluded: (Int) -> Bool
) -> Int {
  tallRowHeights.reduce(0) { partial, entry in
    isIncluded(entry.key)
      ? SaturatingConversion.adding(
        partial, max(0, SaturatingConversion.subtracting(entry.value, 1)))
      : partial
  }
}

/// The window `measureWindowedHostedCollection` realizes, planned out of
/// line (see `hostedCollectionWindowPlan`).
private struct HostedCollectionWindowPlan {
  var bounds: CellRect
  var retainedTallRowHeights: [Int: Int]
  var retainedHiddenEdges: [Int: HiddenRowSeparatorEdges]
  var rowStride: Int
  var hint: MeasureViewportHint?
  var sourceIndices: [Int]
  var measuredWindow: Range<Int>?
  var childProposal: ProposedSize
}

extension ProposedDimension {
  fileprivate var isFinite: Bool {
    if case .finite = self {
      return true
    }
    return false
  }
}
