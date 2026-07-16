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

    let sourceIndices = hostedCollectionWindow(
      visibleIndices: visibleIndices,
      count: source.count,
      isFiniteHeight: effectiveProposal.height.isFinite
    )
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
          tableColumnWidths: tableColumnWidths
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

  private func hostedCollectionWindow(
    visibleIndices: [Int],
    count: Int,
    isFiniteHeight: Bool
  ) -> [Int] {
    guard count > 0 else {
      return []
    }
    guard isFiniteHeight else {
      return Array(0..<count)
    }
    let valid = visibleIndices.filter { (0..<count).contains($0) }
    guard let first = valid.min(), let last = valid.max() else {
      return [0]
    }
    let lower = max(0, first - 1)
    let upper = min(count, last + 2)
    return Array(lower..<upper)
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
