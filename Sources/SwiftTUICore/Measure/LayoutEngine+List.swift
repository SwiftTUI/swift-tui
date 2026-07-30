extension LayoutEngine {
  /// The measured size of a hosted List.
  ///
  /// `sourceIndices` names the item each measurement belongs to. Without it,
  /// a windowed measurement is zipped POSITIONALLY against the global
  /// `payload.items` — so a window starting at row 500 has its measurements
  /// attributed to rows 0, 1, 2, … That silent misalignment is register item
  /// D19's fifth symptom; it is invisible while every row measures one cell
  /// and wrong the moment one does not.
  package func measuredHostedListSize(
    for payload: ListPayload,
    childMeasurements: [MeasuredNode],
    sourceIndices: [Int]? = nil,
    proposal: ProposedSize
  ) -> CellSize {
    guard !childMeasurements.isEmpty else {
      return measuredListSize(for: payload, proposal: proposal)
    }

    let pairs: [(item: ListItemPayload, measurement: MeasuredNode)]
    if let sourceIndices {
      pairs = zip(sourceIndices, childMeasurements).compactMap { index, measurement in
        guard payload.items.indices.contains(index) else {
          return nil
        }
        return (payload.items[index], measurement)
      }
    } else {
      pairs = Array(zip(payload.items, childMeasurements))
    }

    var idealSize = measuredListIdealSize(for: payload)
    let extraHeight = pairs.reduce(0) { partial, pair in
      guard pair.item.kind != .sectionBreak else {
        return partial
      }
      return partial + max(0, pair.measurement.measuredSize.height - 1)
    }
    idealSize.height += extraHeight

    let markerWidth = payload.showsSelectionMarker ? 2 : 0
    let widestChild = pairs.reduce(0) { partial, pair in
      let rowMarkerWidth = pair.item.kind == .row ? markerWidth : 0
      return max(partial, pair.measurement.measuredSize.width + rowMarkerWidth)
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
