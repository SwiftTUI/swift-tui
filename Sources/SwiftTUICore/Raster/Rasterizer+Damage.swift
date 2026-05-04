extension Rasterizer {
  internal func clear(
    cells: inout [[RasterCell]],
    for damage: PresentationDamage,
    surfaceWidth: Int
  ) {
    let emptyRow = Array(repeating: RasterCell.empty, count: surfaceWidth)
    for textRow in damage.textRows {
      guard textRow.row >= 0, textRow.row < cells.count else {
        continue
      }
      if textRow.columnRanges.isEmpty {
        cells[textRow.row] = emptyRow
        continue
      }
      clear(
        columns: textRow.columnRanges,
        inRow: textRow.row,
        cells: &cells
      )
    }
  }

  internal func clear(
    columns ranges: [Range<Int>],
    inRow row: Int,
    cells: inout [[RasterCell]]
  ) {
    guard row >= 0, row < cells.count else {
      return
    }
    let rowWidth = cells[row].count
    for range in ranges {
      let lowerBound = max(0, range.lowerBound)
      let upperBound = min(rowWidth, max(lowerBound, range.upperBound))
      guard lowerBound < upperBound else {
        continue
      }
      for column in lowerBound..<upperBound {
        clearExistingGlyph(atX: column, y: row, cells: &cells)
      }
    }
  }

  internal func refinedPresentationDamage(
    from damage: PresentationDamage,
    previousSurface: RasterSurface,
    currentSurface: RasterSurface
  ) -> PresentationDamage {
    let rowCount = max(
      max(previousSurface.cells.count, currentSurface.cells.count),
      max(previousSurface.size.height, currentSurface.size.height)
    )
    let width = max(previousSurface.size.width, currentSurface.size.width)
    let refinedRows = damage.dirtyRows
      .filter { $0 >= 0 && $0 < rowCount }
      .sorted()
      .compactMap { row -> PresentationDamage.TextRow? in
        let previousRow = row < previousSurface.cells.count ? previousSurface.cells[row] : []
        let currentRow = row < currentSurface.cells.count ? currentSurface.cells[row] : []
        let changedRanges = changedRanges(
          previousRow: previousRow,
          currentRow: currentRow,
          width: max(width, previousRow.count, currentRow.count)
        )
        guard !changedRanges.isEmpty else {
          return nil
        }
        return .init(row: row, columnRanges: changedRanges)
      }

    return PresentationDamage(
      textRows: refinedRows,
      graphicsInvalidation: damage.graphicsInvalidation,
      requiresFullTextRepaint: damage.requiresFullTextRepaint,
      requiresFullGraphicsReplay: damage.requiresFullGraphicsReplay
    )
  }

  internal func changedRanges(
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int
  ) -> [Range<Int>] {
    guard width > 0 else {
      return []
    }

    var changed: [Range<Int>] = []
    var index = 0
    while index < width {
      guard cell(at: index, in: previousRow) != cell(at: index, in: currentRow) else {
        index += 1
        continue
      }

      let start = index
      index += 1
      while index < width,
        cell(at: index, in: previousRow) != cell(at: index, in: currentRow)
      {
        index += 1
      }

      let normalized = normalizeChangedSpan(
        start..<index,
        previousRow: previousRow,
        currentRow: currentRow,
        width: width
      )
      if let last = changed.last,
        last.upperBound >= normalized.lowerBound
      {
        changed[changed.count - 1] = last.lowerBound..<max(last.upperBound, normalized.upperBound)
      } else {
        changed.append(normalized)
      }
    }

    return changed
  }

  internal func normalizeChangedSpan(
    _ span: Range<Int>,
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int
  ) -> Range<Int> {
    guard !span.isEmpty else {
      return span
    }

    var start = max(0, min(span.lowerBound, width))
    var end = max(start, min(span.upperBound, width))

    while start > 0 {
      let candidate = min(
        leadIndexIfContinuation(at: start, in: currentRow),
        leadIndexIfContinuation(at: start, in: previousRow)
      )
      guard candidate < start else {
        break
      }
      start = candidate
    }

    while end < width {
      if cell(at: end, in: currentRow).isContinuation
        || cell(at: end, in: previousRow).isContinuation
      {
        end += 1
        continue
      }
      break
    }

    return start..<end
  }

  internal func leadIndexIfContinuation(
    at index: Int,
    in row: [RasterCell]
  ) -> Int {
    guard cell(at: index, in: row).isContinuation else {
      return index
    }
    return max(0, min(index, cell(at: index, in: row).continuationLeadX ?? index))
  }

  internal func cell(
    at index: Int,
    in row: [RasterCell]
  ) -> RasterCell {
    row.indices.contains(index) ? row[index] : .empty
  }
}

