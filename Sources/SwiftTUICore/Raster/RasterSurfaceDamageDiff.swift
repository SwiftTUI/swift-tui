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
    appendPresentationLayerTopologyDiffs(previous: previous, current: current, to: &rowRanges)

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
      // Unchanged rows compare equal here without the per-column walk below.
      // Incremental rasterization copies untouched rows from the previous
      // surface, so this comparison usually hits the stdlib's identical-storage
      // fast path and the whole-surface diff costs O(rows + changed cells)
      // rather than O(W×H) per committed frame (F36). Equal rows cannot
      // produce damage: columns beyond both counts read as `.empty` on both
      // sides.
      guard previousRow != currentRow else {
        continue
      }
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

  private static func appendPresentationLayerTopologyDiffs(
    previous: RasterSurface,
    current: RasterSurface,
    to rowRanges: inout [Int: [Range<Int>]]
  ) {
    guard
      !compositingLayerTopologiesMatch(
        previous: previous.presentationLayers,
        current: current.presentationLayers
      )
    else {
      return
    }

    for layer in previous.presentationLayers where isCompositingSignificant(layer) {
      append(rect: layer.bounds, to: &rowRanges)
    }
    for layer in current.presentationLayers where isCompositingSignificant(layer) {
      append(rect: layer.bounds, to: &rowRanges)
    }
  }

  /// Plain cell fragments are fully represented in the collapsed cell grid,
  /// which ``appendCellDiffs`` already compares cell by cell; hosts consume
  /// only cells + image attachments (the layer sidecar is a diagnostics /
  /// future-replay record), so those fragments carry no host-visible
  /// information beyond the grid. Only layers that add compositing information
  /// participate in the topology signature: image layers and effect-carrying
  /// fragments. Including every glyph fragment made the signature O(painted
  /// cells) and unioned the whole screen into damage on any mismatch (F36).
  private static func isCompositingSignificant(
    _ layer: RasterPresentationLayer
  ) -> Bool {
    if case .image = layer.content {
      return true
    }
    return !layer.effects.isEmpty
  }

  /// Lockstep comparison of the compositing-significant layer subsequences,
  /// early-exiting on the first mismatch and never materializing signature
  /// arrays. Absolute `order` values are deliberately not compared: stacking
  /// is already encoded by subsequence position, and incremental
  /// rasterization re-mints fresh order numbers for repainted layers, so
  /// comparing them made every incremental frame "differ" from its visually
  /// identical predecessor (F36).
  private static func compositingLayerTopologiesMatch(
    previous: [RasterPresentationLayer],
    current: [RasterPresentationLayer]
  ) -> Bool {
    var previousIndex = previous.startIndex
    var currentIndex = current.startIndex
    while true {
      while previousIndex < previous.endIndex,
        !isCompositingSignificant(previous[previousIndex])
      {
        previousIndex += 1
      }
      while currentIndex < current.endIndex,
        !isCompositingSignificant(current[currentIndex])
      {
        currentIndex += 1
      }
      let previousExhausted = previousIndex == previous.endIndex
      let currentExhausted = currentIndex == current.endIndex
      if previousExhausted || currentExhausted {
        return previousExhausted && currentExhausted
      }
      guard
        compositingTopologyMatches(
          previous[previousIndex],
          current[currentIndex]
        )
      else {
        return false
      }
      previousIndex += 1
      currentIndex += 1
    }
  }

  private static func compositingTopologyMatches(
    _ previous: RasterPresentationLayer,
    _ current: RasterPresentationLayer
  ) -> Bool {
    guard previous.bounds == current.bounds,
      previous.effects == current.effects
    else {
      return false
    }
    switch (previous.content, current.content) {
    case (.cells, .cells):
      return true
    case (.image(let previousImage), .image(let currentImage)):
      return previousImage.identity == currentImage.identity
        && previousImage.bounds == currentImage.bounds
        && previousImage.visibleBounds == currentImage.visibleBounds
        && previousImage.compositing?.backdropSignature
          == currentImage.compositing?.backdropSignature
    default:
      return false
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
