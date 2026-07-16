extension LayoutEngine {
  package func measuredHostedListSize(
    for payload: ListPayload,
    childMeasurements: [MeasuredNode],
    proposal: ProposedSize
  ) -> CellSize {
    guard !childMeasurements.isEmpty else {
      return measuredListSize(for: payload, proposal: proposal)
    }

    var idealSize = measuredListIdealSize(for: payload)
    let extraHeight = zip(payload.items, childMeasurements).reduce(0) { partial, pair in
      let (item, measurement) = pair
      guard item.kind != .sectionBreak else {
        return partial
      }
      return partial + max(0, measurement.measuredSize.height - 1)
    }
    idealSize.height += extraHeight

    let markerWidth = payload.showsSelectionMarker ? 2 : 0
    let widestChild = zip(payload.items, childMeasurements).reduce(0) { partial, pair in
      let (item, measurement) = pair
      let rowMarkerWidth = item.kind == .row ? markerWidth : 0
      return max(partial, measurement.measuredSize.width + rowMarkerWidth)
    }
    idealSize.width = max(
      idealSize.width,
      widestChild + payload.style.listContentInsets.leading
        + payload.style.listContentInsets.trailing
    )

    return CellSize(
      width: resolvedExpandingListDimension(idealSize.width, proposal: proposal.width),
      height: resolvedExpandingListDimension(idealSize.height, proposal: proposal.height)
    )
  }

  package func measuredListSize(
    for payload: ListPayload,
    proposal: ProposedSize
  ) -> CellSize {
    let idealSize = measuredListIdealSize(for: payload)

    return CellSize(
      width: resolvedExpandingListDimension(idealSize.width, proposal: proposal.width),
      height: resolvedExpandingListDimension(idealSize.height, proposal: proposal.height)
    )
  }

  package func measuredListIdealSize(
    for payload: ListPayload
  ) -> CellSize {
    payload.style.measuredListIdealSize(for: payload)
  }

  package func resolvedListDimension(
    _ ideal: Int,
    proposal: ProposedDimension
  ) -> Int {
    switch proposal {
    case .unspecified, .infinity:
      return ideal
    case .finite(let value):
      return min(max(ideal, 0), value)
    }
  }

  package func resolvedExpandingListDimension(
    _ ideal: Int,
    proposal: ProposedDimension
  ) -> Int {
    switch proposal {
    case .unspecified, .infinity:
      return ideal
    case .finite(let value):
      return max(0, value)
    }
  }

}
