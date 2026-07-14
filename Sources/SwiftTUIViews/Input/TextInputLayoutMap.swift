package import SwiftTUICore

package struct TextInputLayoutMap: Equatable, Sendable {
  package var lines: [TextInputLayoutLine]
  package var contentSize: CellSize
  package var viewport: CellRect

  package init(
    lines: [TextInputLayoutLine],
    contentSize: CellSize,
    viewport: CellRect
  ) {
    self.lines = lines.isEmpty ? [.empty] : lines
    self.contentSize = contentSize
    self.viewport = viewport
  }

  package func caretPoint(for offset: TextOffset) -> CellPoint {
    let clamped = TextOffset(
      min(
        offset.rawValue,
        lines.map(\.sourceRange.upperBound.rawValue).max() ?? 0
      )
    )

    for line in lines {
      if clamped >= line.sourceRange.lowerBound,
        clamped <= line.sourceRange.upperBound
      {
        return CellPoint(
          x: line.origin.x + line.cellOffset(for: clamped),
          y: line.origin.y
        )
      }
    }

    if let previous = lines.last(where: { $0.sourceRange.upperBound <= clamped }) {
      return CellPoint(
        x: previous.origin.x + previous.cellWidth,
        y: previous.origin.y
      )
    }
    return lines.first?.origin ?? CellPoint(x: 0, y: 0)
  }

  package func nearestOffset(to point: CellPoint) -> TextOffset {
    let line = nearestLine(toY: point.y)
    guard let line else {
      return TextOffset(0)
    }
    let localX = max(0, point.x - line.origin.x)
    for cluster in line.clusters {
      let startX = cluster.originX
      let endX = cluster.originX + cluster.cellWidth
      guard localX < endX else {
        continue
      }
      let cellOffset = localX - startX
      return cellOffset * 2 < max(1, cluster.cellWidth)
        ? cluster.textRange.lowerBound
        : cluster.textRange.upperBound
    }
    return line.sourceRange.upperBound
  }

  package func selectionRects(for range: TextRange) -> [CellRect] {
    let clampedRange = range.clamped(
      to: TextOffset(lines.map(\.sourceRange.upperBound.rawValue).max() ?? 0)
    )
    guard !clampedRange.isEmpty else {
      return []
    }

    return lines.compactMap { line in
      let lowerBound = max(clampedRange.lowerBound, line.sourceRange.lowerBound)
      let upperBound = min(clampedRange.upperBound, line.sourceRange.upperBound)
      guard lowerBound < upperBound else {
        return nil
      }

      let startX = line.origin.x + line.cellOffset(for: lowerBound)
      let endX = line.origin.x + line.cellOffset(for: upperBound)
      guard endX > startX else {
        return nil
      }

      return CellRect(
        origin: CellPoint(x: startX, y: line.origin.y),
        size: CellSize(width: endX - startX, height: 1)
      )
    }
  }

  package func verticalOffset(
    from offset: TextOffset,
    delta: Int,
    preferredVisualColumn: Int?
  ) -> (offset: TextOffset, preferredVisualColumn: Int?) {
    guard !lines.isEmpty else {
      return (TextOffset(0), preferredVisualColumn)
    }

    let point = caretPoint(for: offset)
    let currentIndex = lines.firstIndex(where: { $0.origin.y == point.y }) ?? 0
    let preferredColumn = preferredVisualColumn ?? point.x
    let targetIndex = min(max(0, currentIndex + delta), lines.count - 1)
    let target = lines[targetIndex]
    return (
      target.offset(atCellColumn: preferredColumn),
      preferredColumn
    )
  }

  private func nearestLine(toY y: Int) -> TextInputLayoutLine? {
    guard !lines.isEmpty else {
      return nil
    }
    let index = min(max(0, y), lines.count - 1)
    return lines[index]
  }
}

package struct TextInputLayoutLine: Equatable, Sendable {
  package var sourceRange: TextRange
  package var clusters: [TextInputLayoutCluster]
  package var origin: CellPoint
  package var cellWidth: Int

  package static let empty = TextInputLayoutLine(
    sourceRange: TextRange(TextOffset(0)..<TextOffset(0)),
    clusters: [],
    origin: CellPoint(x: 0, y: 0),
    cellWidth: 0
  )

  package func cellOffset(for offset: TextOffset) -> Int {
    guard !clusters.isEmpty else {
      return 0
    }
    // Cell positions come from each cluster's `originX`, not a running sum:
    // on a continuation row the first content cluster sits AFTER the leading
    // wrap marker, which occupies a cell but owns no source offset.
    for cluster in clusters {
      if offset <= cluster.textRange.lowerBound {
        return cluster.originX
      }
      if offset <= cluster.textRange.upperBound {
        return cluster.originX + cluster.cellWidth
      }
    }
    // Offsets past the last content cluster (separator whitespace swallowed
    // at the wrap point) render at the end of the row's content, before any
    // trailing wrap marker.
    return clusters.last.map { $0.originX + $0.cellWidth } ?? cellWidth
  }

  package func offset(atCellColumn column: Int) -> TextOffset {
    guard !clusters.isEmpty else {
      return sourceRange.lowerBound
    }
    let clampedColumn = min(max(0, column), cellWidth)
    for cluster in clusters {
      let endX = cluster.originX + cluster.cellWidth
      guard clampedColumn < endX else {
        continue
      }
      let cellOffset = clampedColumn - cluster.originX
      return cellOffset * 2 < max(1, cluster.cellWidth)
        ? cluster.textRange.lowerBound
        : cluster.textRange.upperBound
    }
    return sourceRange.upperBound
  }
}

package struct TextInputLayoutCluster: Equatable, Sendable {
  package var textRange: TextRange
  package var display: Character
  package var cellWidth: Int
  package var originX: Int

  package init(
    textRange: TextRange,
    display: Character,
    cellWidth: Int,
    originX: Int
  ) {
    self.textRange = textRange
    self.display = display
    self.cellWidth = max(0, cellWidth)
    self.originX = originX
  }
}

package enum TextInputLayoutMapBuilder {
  /// Source-indexed cluster payload run through the SHARED text-wrapping
  /// algorithm (`wrapTextLineClusters`), so the movement map's rows are the
  /// renderer's rows by construction (F140 — this builder previously
  /// re-implemented wrapping at character granularity, so Up/Down and
  /// click-to-caret targeted rows the renderer never drew). Synthesized
  /// continuation markers carry `sourceIndex == nil`: they occupy cells (the
  /// per-row `originX` accounting includes them) but own no source offsets.
  private struct IndexedWrapCluster: TextWrappableCluster {
    var character: Character
    var cellWidth: Int
    var sourceIndex: Int?

    static func continuationMarker(
      character: Character,
      cellWidth: Int
    ) -> IndexedWrapCluster {
      IndexedWrapCluster(character: character, cellWidth: cellWidth, sourceIndex: nil)
    }
  }

  package static func build(
    for clusters: [TextInputProjectedCluster],
    width: Int?
  ) -> TextInputLayoutMap {
    let maximumWidth = width.map { max(1, $0) }
    var lines: [TextInputLayoutLine] = []
    var y = 0

    func appendVisualRows(
      for lineClusters: [TextInputProjectedCluster],
      lineStart: TextOffset
    ) {
      let lineEnd = lineClusters.last?.textRange.upperBound ?? lineStart
      let indexed = lineClusters.enumerated().map { index, projected in
        IndexedWrapCluster(
          character: projected.display,
          cellWidth: cellWidth(of: projected.display),
          sourceIndex: index
        )
      }
      let rows = wrapTextLineClusters(
        indexed,
        width: maximumWidth,
        wrappingStrategy: .wordBoundary
      )

      for row in rows {
        var rowClusters: [TextInputLayoutCluster] = []
        var x = 0
        for wrapped in row {
          if let sourceIndex = wrapped.sourceIndex {
            let projected = lineClusters[sourceIndex]
            rowClusters.append(
              TextInputLayoutCluster(
                textRange: projected.textRange,
                display: projected.display,
                cellWidth: wrapped.cellWidth,
                originX: x
              )
            )
          }
          x += wrapped.cellWidth
        }

        // A row's range covers its own content only. Separator whitespace
        // swallowed at a wrap point falls between rows — `caretPoint`'s
        // previous-row fallback renders such offsets at the end of the row
        // the separator followed, matching the newline-gap policy (and the
        // renderer, which draws nothing for the swallowed separator).
        let lowerBound = rowClusters.first?.textRange.lowerBound ?? lineStart
        let upperBound = rowClusters.last?.textRange.upperBound ?? lineEnd
        lines.append(
          TextInputLayoutLine(
            sourceRange: TextRange(lowerBound: lowerBound, upperBound: upperBound),
            clusters: rowClusters,
            origin: CellPoint(x: 0, y: y),
            cellWidth: x
          )
        )
        y += 1
      }
    }

    var currentLine: [TextInputProjectedCluster] = []
    var currentLineStart = TextOffset(0)
    for projected in clusters {
      if projected.isNewline {
        appendVisualRows(for: currentLine, lineStart: currentLineStart)
        currentLine = []
        currentLineStart = projected.textRange.upperBound
        continue
      }
      currentLine.append(projected)
    }
    if !currentLine.isEmpty || lines.isEmpty || clusters.last?.isNewline == true {
      appendVisualRows(for: currentLine, lineStart: currentLineStart)
    }

    let contentSize = CellSize(
      width: lines.map(\.cellWidth).max() ?? 0,
      height: lines.count
    )
    return TextInputLayoutMap(
      lines: lines,
      contentSize: contentSize,
      viewport: CellRect(origin: CellPoint(x: 0, y: 0), size: contentSize)
    )
  }
}
