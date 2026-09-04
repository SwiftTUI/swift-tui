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

    // A viewport-backed payload stores no items — its rows are committed child
    // nodes and its copies were identical empty stubs — so the stub is
    // synthesized here rather than looked up. Its only load-bearing field is
    // `kind`, and a hosted row is always `.row`.
    let stub = ListItemPayload(kind: .row, text: "")
    func item(at index: Int) -> ListItemPayload {
      payload.items.indices.contains(index) ? payload.items[index] : stub
    }

    let pairs: [(item: ListItemPayload, measurement: MeasuredNode)]
    if let sourceIndices {
      pairs = zip(sourceIndices, childMeasurements).map { index, measurement in
        (item(at: index), measurement)
      }
    } else if payload.items.isEmpty {
      pairs = childMeasurements.map { (stub, $0) }
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
      widestChild + payload.style.contentInsets.leading
        + payload.style.contentInsets.trailing
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
