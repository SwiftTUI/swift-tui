package enum RasterSurfaceDamageDiff {
  package static func diff(
    previous: RasterSurface?,
    current: RasterSurface
  ) -> PresentationDamage? {
    guard let previous else {
      return nil
    }
    guard previous.size == current.size,
      previous.attachments == current.attachments,
      previous.metadata == current.metadata
    else {
      return nil
    }

    var rowRanges: [Int: [Range<Int>]] = [:]
    appendCellDiffs(previous: previous, current: current, to: &rowRanges)
    appendImageDiffs(previous: previous, current: current, to: &rowRanges)

    return PresentationDamage(
      textRows: rowRanges.keys.sorted().map { row in
        PresentationDamage.TextRow(
          row: row,
          columnRanges: rowRanges[row] ?? []
        )
      }
    )
  }

  private static func appendCellDiffs(
    previous: RasterSurface,
    current: RasterSurface,
    to rowRanges: inout [Int: [Range<Int>]]
  ) {
    let height = max(
      current.size.height,
      previous.cells.count,
      current.cells.count
    )
    for row in 0..<height {
      let previousRow = row < previous.cells.count ? previous.cells[row] : []
      let currentRow = row < current.cells.count ? current.cells[row] : []
      let width = max(
        current.size.width,
        previousRow.count,
        currentRow.count
      )
      var ranges: [Range<Int>] = []

      for column in 0..<width {
        let previousCell = cell(in: previousRow, at: column)
        let currentCell = cell(in: currentRow, at: column)
        guard previousCell != currentCell else {
          continue
        }
        ranges.append(occupiedRange(in: previousRow, at: column, surfaceWidth: width))
        ranges.append(occupiedRange(in: currentRow, at: column, surfaceWidth: width))
      }

      if !ranges.isEmpty {
        rowRanges[row, default: []].append(contentsOf: ranges)
      }
    }
  }

  private static func appendImageDiffs(
    previous: RasterSurface,
    current: RasterSurface,
    to rowRanges: inout [Int: [Range<Int>]]
  ) {
    guard previous.imageAttachments != current.imageAttachments else {
      return
    }
    for attachment in previous.imageAttachments + current.imageAttachments {
      append(rect: attachment.visibleBounds, to: &rowRanges)
    }
  }

  private static func append(
    rect: CellRect,
    to rowRanges: inout [Int: [Range<Int>]]
  ) {
    guard rect.size.width > 0, rect.size.height > 0 else {
      return
    }
    let lowerRow = max(0, rect.origin.y)
    let upperRow = max(lowerRow, rect.origin.y + rect.size.height)
    let lowerColumn = max(0, rect.origin.x)
    let upperColumn = max(lowerColumn, rect.origin.x + rect.size.width)
    guard lowerColumn < upperColumn else {
      return
    }
    for row in lowerRow..<upperRow {
      rowRanges[row, default: []].append(lowerColumn..<upperColumn)
    }
  }

  private static func cell(
    in row: [RasterCell],
    at column: Int
  ) -> RasterCell {
    guard column >= 0, column < row.count else {
      return .empty
    }
    return row[column]
  }

  private static func occupiedRange(
    in row: [RasterCell],
    at column: Int,
    surfaceWidth: Int
  ) -> Range<Int> {
    guard column >= 0, column < row.count else {
      return column..<min(surfaceWidth, column + 1)
    }
    let rasterCell = row[column]
    let lead = rasterCell.continuationLeadX ?? column
    let span = max(1, cell(in: row, at: lead).spanWidth)
    return max(0, lead)..<min(surfaceWidth, lead + span)
  }
}
