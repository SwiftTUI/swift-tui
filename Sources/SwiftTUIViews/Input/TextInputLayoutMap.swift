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
    var cellOffset = 0
    for cluster in clusters {
      if offset <= cluster.textRange.lowerBound {
        return cellOffset
      }
      if offset <= cluster.textRange.upperBound {
        return cellOffset + cluster.cellWidth
      }
      cellOffset += cluster.cellWidth
    }
    return cellWidth
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
  package static func build(
    for clusters: [TextInputProjectedCluster],
    width: Int?
  ) -> TextInputLayoutMap {
    var lines: [TextInputLayoutLine] = []
    var currentClusters: [TextInputLayoutCluster] = []
    var currentStart: TextOffset?
    var currentWidth = 0
    var y = 0
    let maximumWidth = width.map { max(1, $0) }

    func finishLine(nextStart: TextOffset?) {
      let sourceRange: TextRange
      if let first = currentStart {
        sourceRange = TextRange(
          lowerBound: first,
          upperBound: currentClusters.last?.textRange.upperBound ?? first
        )
      } else {
        let offset = nextStart ?? TextOffset(0)
        sourceRange = TextRange(offset..<offset)
      }
      lines.append(
        TextInputLayoutLine(
          sourceRange: sourceRange,
          clusters: currentClusters,
          origin: CellPoint(x: 0, y: y),
          cellWidth: currentWidth
        )
      )
      currentClusters.removeAll(keepingCapacity: true)
      currentStart = nextStart
      currentWidth = 0
      y += 1
    }

    for projected in clusters {
      if projected.isNewline {
        finishLine(nextStart: projected.textRange.upperBound)
        continue
      }

      let cellWidth = cellWidth(of: projected.display)
      if let maximumWidth,
        currentWidth > 0,
        currentWidth + cellWidth > maximumWidth
      {
        finishLine(nextStart: projected.textRange.lowerBound)
      }

      if currentStart == nil {
        currentStart = projected.textRange.lowerBound
      }
      currentClusters.append(
        TextInputLayoutCluster(
          textRange: projected.textRange,
          display: projected.display,
          cellWidth: cellWidth,
          originX: currentWidth
        )
      )
      currentWidth += cellWidth
    }

    if !currentClusters.isEmpty || lines.isEmpty || clusters.last?.isNewline == true {
      finishLine(nextStart: TextOffset(clusters.last?.textRange.upperBound.rawValue ?? 0))
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
