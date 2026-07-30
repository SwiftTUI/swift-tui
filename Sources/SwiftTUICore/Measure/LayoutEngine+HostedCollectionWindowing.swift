@_spi(Testing) import SwiftTUIPrimitives

extension LayoutEngine {
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

    let sourceIndices: [Int]
    var measuredWindow: Range<Int>?
    if usesLineModel {
      // The proposal fits inside the viewport, so the line model's answer is
      // both exact and cheap.
      let visibleIndices: [Int]
      switch (collection.kind, node.drawPayload) {
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
      rowStride: rowStride
    ) {
      // Deriving the window from the hint — rather than from the line model
      // over the full content height — is the whole point: asking the line
      // model here would generate a display line per row before windowing
      // anything, which is the O(dataset) collapse this path exists to avoid.
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
    var children: [ResolvedNode] = []
    var measurements: [MeasuredNode] = []
    children.reserveCapacity(sourceIndices.count)
    measurements.reserveCapacity(sourceIndices.count)
    let childProposal = ProposedSize(
      width: .finite(max(0, concreteSize.width)),
      height: .unspecified
    )
    for index in sourceIndices {
      let child = source.child(at: index)
      children.append(child)
      measurements.append(
        measure(child, proposal: childProposal, passContext: passContext)
      )
    }

    let measuredSize: CellSize
    var tableColumnWidths: [Int]?
    switch node.drawPayload {
    case .list(let payload):
      measuredSize = measuredHostedListSize(
        for: payload,
        childMeasurements: measurements,
        proposal: effectiveProposal
      )
    case .table(let payload):
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
      tableColumnWidths = source.retainedTableColumnWidths(
        columns: payload.columns,
        discovered: discovered
      )
      if let tableColumnWidths {
        source.applyHostedTableColumnWidths(tableColumnWidths)
        children.removeAll(keepingCapacity: true)
        measurements.removeAll(keepingCapacity: true)
        for index in sourceIndices {
          let child = source.child(at: index)
          children.append(child)
          measurements.append(
            measure(child, proposal: childProposal, passContext: passContext)
          )
        }
      }
      measuredSize = measuredHostedTableSize(
        for: payload,
        childMeasurements: measurements,
        proposal: effectiveProposal
      )
    default:
      return nil
    }

    return MeasuredNode(
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
          estimatedRowStride: measuredWindow == nil ? nil : rowStride
        )
      )
    )
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

  /// The estimated-visible row band for a hosted collection under a scroll
  /// layout's measure-viewport hint: anchor from the (unclamped) offset over
  /// the display-line stride, extended by the rows one viewport spans, with a
  /// row of overscan each side.
  ///
  /// Unlike a lazy stack, a collection needs no probe measurement for the
  /// stride — its line model is arithmetic (one line per row, two when the
  /// style draws separators).
  func hostedCollectionHintWindow(
    hint: MeasureViewportHint?,
    count: Int,
    rowStride: Int
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
    let anchor = min(max(0, count - 1), offset / stride)
    let rowsPerViewport = (hint.viewportSize.height + stride - 1) / stride
    let lower = max(0, anchor - overscan)
    let upper = min(count, anchor + rowsPerViewport + overscan + 1)
    guard lower < upper else {
      return nil
    }
    return lower..<upper
  }
}

extension ProposedDimension {
  fileprivate var isFinite: Bool {
    if case .finite = self {
      return true
    }
    return false
  }
}
