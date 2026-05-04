extension LayoutEngine {
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
      rows: payload.rows
    )
    var lineMetrics = (
      width: borderedTableLineWidth(
        widths: widths,
        glyphs: payload.style.tableBorderGlyphs
      ),
      height: 2
    )

    if payload.showsHeaders {
      lineMetrics.height += 2
    }

    for (index, row) in payload.rows.enumerated() {
      lineMetrics.height += 1
      if showsTableRowSeparator(
        current: row,
        next: payload.rows.dropFirst(index + 1).first
      ) {
        lineMetrics.height += 1
      }
    }

    return CellSize(
      width: lineMetrics.width,
      height: lineMetrics.height
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
