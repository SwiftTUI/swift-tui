extension Rasterizer {
  /// Expands row damage to a paint-order-closed suffix when an existing image
  /// placement is going to be re-emitted.
  ///
  /// Incremental recording retains clean presentation layers and appends every
  /// repainted layer after them. That merge is order-preserving until damage
  /// intersects an image whose bounds also cover clean rows: a clean occluder
  /// recorded above the image would otherwise retain an older (lower) order
  /// than the re-emitted image. Repainting a closed suffix keeps the retained
  /// layers as an untouched prefix and records the suffix again in authored
  /// traversal order.
  ///
  /// The backward pass closes over layers before the first affected image whose
  /// bounds intersect rows introduced by the suffix. It scans the retained
  /// sidecar only; it does not walk the draw tree.
  internal func presentationOrderDamageClosure(
    _ dirtyRows: Set<Int>,
    previousLayers: [RasterPresentationLayer],
    surfaceHeight: Int
  ) -> PresentationOrderDamageClosure {
    guard surfaceHeight > 0,
      let dirtySpans = DirtyRowSpans(dirtyRows: dirtyRows),
      let firstAffectedImageIndex = previousLayers.firstIndex(where: { layer in
        guard case .image = layer.content else { return false }
        return dirtySpans.intersects(rows: layer.bounds)
      })
    else {
      return PresentationOrderDamageClosure(dirtyRows: dirtyRows)
    }

    func clampedRows(_ rows: Range<Int>) -> Range<Int>? {
      let lower = max(0, rows.lowerBound)
      let upper = min(surfaceHeight, rows.upperBound)
      guard lower < upper else { return nil }
      return lower..<upper
    }

    func clampedRows(in bounds: CellRect) -> Range<Int>? {
      clampedRows(bounds.origin.y..<bounds.maxY)
    }

    let layerRows = previousLayers.map { clampedRows(in: $0.bounds) }
    var layerIndex = PresentationLayerRowIndex(surfaceHeight: surfaceHeight)
    var indexedLayerCount = 0
    for (index, rows) in layerRows.enumerated() {
      guard let rows else { continue }
      layerIndex.record(layer: index, in: rows)
      indexedLayerCount += 1
    }

    // Every layer in the suffix is going to be recorded again. Querying each
    // of its row intervals discovers an earlier layer that must join the
    // suffix; newly included intervals are appended exactly once. The range
    // index makes each dependency query O(log H), independent of layer height.
    var cut = firstAffectedImageIndex
    var worklist = layerRows[cut...].compactMap { $0 }
    var worklistIndex = 0
    var queriedLayerCount = 0
    while worklistIndex < worklist.count {
      let rows = worklist[worklistIndex]
      worklistIndex += 1
      queriedLayerCount += 1
      guard let earlier = layerIndex.earliestLayer(intersecting: rows), earlier < cut else {
        continue
      }
      for rows in layerRows[earlier..<cut].compactMap({ $0 }) {
        worklist.append(rows)
      }
      cut = earlier
    }

    let finalRanges = normalizedRowRanges(
      dirtySpans.spans.compactMap(clampedRows)
        + layerRows[cut...].compactMap { $0 }
    )
    var closedRows = dirtyRows
    closedRows.reserveCapacity(max(closedRows.count, finalRanges.reduce(0) { $0 + $1.count }))
    for rows in finalRanges {
      closedRows.formUnion(rows)
    }
    return PresentationOrderDamageClosure(
      dirtyRows: closedRows,
      indexedLayerCount: indexedLayerCount,
      queriedLayerCount: queriedLayerCount,
      materializedSurfaceRowCount: finalRanges.reduce(0) { $0 + $1.count }
    )
  }

  private func normalizedRowRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
    let sorted = ranges.filter { !$0.isEmpty }.sorted {
      ($0.lowerBound, $0.upperBound) < ($1.lowerBound, $1.upperBound)
    }
    guard var current = sorted.first else { return [] }
    var result: [Range<Int>] = []
    result.reserveCapacity(sorted.count)
    for range in sorted.dropFirst() {
      if range.lowerBound <= current.upperBound {
        current = current.lowerBound..<max(current.upperBound, range.upperBound)
      } else {
        result.append(current)
        current = range
      }
    }
    result.append(current)
    return result
  }

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

internal struct PresentationOrderDamageClosure: Sendable, Equatable {
  internal var dirtyRows: Set<Int>
  internal var indexedLayerCount: Int
  internal var queriedLayerCount: Int
  internal var materializedSurfaceRowCount: Int

  internal init(
    dirtyRows: Set<Int>,
    indexedLayerCount: Int = 0,
    queriedLayerCount: Int = 0,
    materializedSurfaceRowCount: Int = 0
  ) {
    self.dirtyRows = dirtyRows
    self.indexedLayerCount = indexedLayerCount
    self.queriedLayerCount = queriedLayerCount
    self.materializedSurfaceRowCount = materializedSurfaceRowCount
  }
}

/// Range-min index from surface rows to the earliest retained layer that
/// touches them. Range insertion and intersection-min queries are O(log H), so
/// tall presentation layers cost the same as one-row fragments.
private struct PresentationLayerRowIndex {
  private let surfaceHeight: Int
  private var minimumLayer: [Int]
  private var coveringLayer: [Int]

  init(surfaceHeight: Int) {
    self.surfaceHeight = surfaceHeight
    let nodeCount = max(1, surfaceHeight * 4)
    self.minimumLayer = Array(repeating: .max, count: nodeCount)
    self.coveringLayer = Array(repeating: .max, count: nodeCount)
  }

  mutating func record(layer: Int, in rows: Range<Int>) {
    record(
      layer: layer,
      rows: rows,
      node: 0,
      nodeRows: 0..<surfaceHeight
    )
  }

  func earliestLayer(intersecting rows: Range<Int>) -> Int? {
    let value = earliestLayer(
      intersecting: rows,
      node: 0,
      nodeRows: 0..<surfaceHeight
    )
    return value == .max ? nil : value
  }

  private mutating func record(
    layer: Int,
    rows: Range<Int>,
    node: Int,
    nodeRows: Range<Int>
  ) {
    guard rows.lowerBound < nodeRows.upperBound, rows.upperBound > nodeRows.lowerBound else {
      return
    }
    if rows.lowerBound <= nodeRows.lowerBound, rows.upperBound >= nodeRows.upperBound {
      coveringLayer[node] = min(coveringLayer[node], layer)
      minimumLayer[node] = min(minimumLayer[node], layer)
      return
    }

    let middle = nodeRows.lowerBound + (nodeRows.count / 2)
    let left = (node * 2) + 1
    let right = left + 1
    record(layer: layer, rows: rows, node: left, nodeRows: nodeRows.lowerBound..<middle)
    record(layer: layer, rows: rows, node: right, nodeRows: middle..<nodeRows.upperBound)
    minimumLayer[node] = min(coveringLayer[node], min(minimumLayer[left], minimumLayer[right]))
  }

  private func earliestLayer(
    intersecting rows: Range<Int>,
    node: Int,
    nodeRows: Range<Int>
  ) -> Int {
    guard rows.lowerBound < nodeRows.upperBound, rows.upperBound > nodeRows.lowerBound else {
      return .max
    }
    if rows.lowerBound <= nodeRows.lowerBound, rows.upperBound >= nodeRows.upperBound {
      return minimumLayer[node]
    }

    let middle = nodeRows.lowerBound + (nodeRows.count / 2)
    let left = (node * 2) + 1
    let right = left + 1
    return min(
      coveringLayer[node],
      min(
        earliestLayer(intersecting: rows, node: left, nodeRows: nodeRows.lowerBound..<middle),
        earliestLayer(intersecting: rows, node: right, nodeRows: middle..<nodeRows.upperBound)
      )
    )
  }
}
