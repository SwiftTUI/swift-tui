extension Rasterizer {
  internal func visibleBounds(
    _ bounds: CellRect,
    intersectsAnyOf dirtyRows: Set<Int>
  ) -> Bool {
    guard bounds.size.height > 0, !dirtyRows.isEmpty else {
      return false
    }

    let lowerBound = bounds.origin.y
    let upperBound = bounds.origin.y + bounds.size.height
    return dirtyRows.contains(where: { row in
      row >= lowerBound && row < upperBound
    })
  }

  /// Clears every dirty row **in full**, even when the damage carries column
  /// ranges.
  ///
  /// Every incremental clamp in the paint walk — `write`, `tintCell`, the
  /// per-line text culls, the fill and grid-copy row culls — is row-granular,
  /// so painters rewrite the un-damaged columns of a dirty row regardless of
  /// what was cleared. Rewriting is only sound over a cleanly rebuilt
  /// underlay: over the previous frame's *final* composited cells,
  /// destination-reading paints drift — a translucent fill re-tints its own
  /// prior output and an opacity-baked foreground re-bakes against the stale
  /// committed background. That is the column analog of the F125 gap-row
  /// drift, and honoring the ranges here is what let it ship. Column ranges
  /// stay meaningful on host-facing damage (the wire diff); they must not
  /// narrow this clear.
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
      cells[textRow.row] = emptyRow
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
