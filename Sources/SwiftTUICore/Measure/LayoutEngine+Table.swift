extension LayoutEngine {
  /// The measured size of a hosted Table, on the terms of
  /// ``measuredHostedListSize(for:childMeasurements:sourceIndices:retainedTallRowHeights:proposal:)``.
  package func measuredHostedTableSize(
    for payload: TablePayload,
    childMeasurements: [MeasuredNode],
    sourceIndices: [Int]? = nil,
    retainedTallRowHeights: [Int: Int] = [:],
    proposal: ProposedSize
  ) -> CellSize {
    guard !childMeasurements.isEmpty else {
      return measuredTableSize(for: payload, proposal: proposal)
    }

    var idealSize = measuredTableIdealSize(for: payload)
    idealSize.height += childMeasurements.reduce(0) {
      $0 + max(0, $1.measuredSize.height - 1)
    }
    let measuredIndices = Set(sourceIndices ?? [])
    idealSize.height += tallRowExtraCells(in: retainedTallRowHeights) {
      !measuredIndices.contains($0)
    }
    let leftWidth = layoutText(
      for: payload.style.borderGlyphs.left,
      width: nil
    ).size.width
    let rightWidth = layoutText(
      for: payload.style.borderGlyphs.right,
      width: nil
    ).size.width
    let widestChild = childMeasurements.map(\.measuredSize.width).max() ?? 0
    idealSize.width = max(
      idealSize.width,
      leftWidth + 1 + widestChild + 1 + rightWidth + payload.style.contentInsets.horizontal)

    return CellSize(
      width: resolvedExpandingListDimension(idealSize.width, proposal: proposal.width),
      height: resolvedExpandingListDimension(idealSize.height, proposal: proposal.height)
    )
  }

  package func measuredTableSize(
    for payload: TablePayload,
    proposal: ProposedSize
  ) -> CellSize {
    let idealSize = measuredTableIdealSize(for: payload)

    return CellSize(
      width: resolvedExpandingListDimension(idealSize.width, proposal: proposal.width),
      height: resolvedExpandingListDimension(idealSize.height, proposal: proposal.height)
    )
  }

  package func measuredTableIdealSize(
    for payload: TablePayload
  ) -> CellSize {
    let widths = measureTableColumnWidths(
      columns: payload.columns,
      rows: payload.isViewportBacked ? [] : payload.rows
    )
    var lineMetrics = (
      width: borderedTableLineWidth(
        widths: widths,
        glyphs: payload.style.borderGlyphs
      ),
      height: 2
    )

    if payload.showsHeaders {
      lineMetrics.height += 2
    }

    if payload.isViewportBacked {
      lineMetrics.height += payload.rows.count + max(0, payload.rows.count - 1)
    } else {
      for (index, row) in payload.rows.enumerated() {
        lineMetrics.height += 1
        if showsTableRowSeparator(
          current: row,
          next: payload.rows.dropFirst(index + 1).first
        ) {
          lineMetrics.height += 1
        }
      }
    }

    return CellSize(
      width: lineMetrics.width + payload.style.contentInsets.horizontal,
      height: lineMetrics.height + payload.style.contentInsets.vertical
    )
  }

  package func showsTableRowSeparator(
    current: TableRowPayload,
    next: TableRowPayload?
  ) -> Bool {
    guard let next else {
      return false
    }
    if current.rowSeparators.bottom == .hidden || next.rowSeparators.top == .hidden {
      return false
    }
    return true
  }
}
