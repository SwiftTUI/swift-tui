public struct PresentationDamageDiagnostics: Equatable, Sendable {
  public var textRowCount: Int
  public var rangeAwareTextRowCount: Int
  public var textSpanCount: Int
  public var textCellCount: Int
  public var graphicsInvalidationCount: Int
  public var requiresFullTextRepaint: Bool
  public var requiresFullGraphicsReplay: Bool

  public init(
    textRowCount: Int = 0,
    rangeAwareTextRowCount: Int = 0,
    textSpanCount: Int = 0,
    textCellCount: Int = 0,
    graphicsInvalidationCount: Int = 0,
    requiresFullTextRepaint: Bool = false,
    requiresFullGraphicsReplay: Bool = false
  ) {
    self.textRowCount = max(0, textRowCount)
    self.rangeAwareTextRowCount = max(0, rangeAwareTextRowCount)
    self.textSpanCount = max(0, textSpanCount)
    self.textCellCount = max(0, textCellCount)
    self.graphicsInvalidationCount = max(0, graphicsInvalidationCount)
    self.requiresFullTextRepaint = requiresFullTextRepaint
    self.requiresFullGraphicsReplay = requiresFullGraphicsReplay
  }
}

extension PresentationDamageDiagnostics {
  package init(
    damage: PresentationDamage,
    surfaceWidth: Int
  ) {
    let clampedSurfaceWidth = max(0, surfaceWidth)
    var rangeAwareTextRowCount = 0
    var textSpanCount = 0
    var textCellCount = 0

    for textRow in damage.textRows {
      if textRow.columnRanges.isEmpty {
        textSpanCount += 1
        textCellCount += clampedSurfaceWidth
        continue
      }

      rangeAwareTextRowCount += 1
      textSpanCount += textRow.columnRanges.count
      textCellCount += textRow.columnRanges.reduce(0) { partial, range in
        partial + max(0, range.upperBound - range.lowerBound)
      }
    }

    self.init(
      textRowCount: damage.textRows.count,
      rangeAwareTextRowCount: rangeAwareTextRowCount,
      textSpanCount: textSpanCount,
      textCellCount: textCellCount,
      graphicsInvalidationCount: damage.graphicsInvalidation.count,
      requiresFullTextRepaint: damage.requiresFullTextRepaint,
      requiresFullGraphicsReplay: damage.requiresFullGraphicsReplay
    )
  }
}
package struct PresentationDamage: Equatable, Sendable {
  package struct TextRow: Equatable, Sendable {
    package var row: Int
    package var columnRanges: [Range<Int>]

    package init(
      row: Int,
      columnRanges: [Range<Int>] = []
    ) {
      self.row = row
      self.columnRanges = PresentationDamage.normalizeColumnRanges(columnRanges)
    }
  }

  package var textRows: [TextRow]
  package var graphicsInvalidation: Set<Identity>
  package var requiresFullTextRepaint: Bool
  package var requiresFullGraphicsReplay: Bool

  package init(
    dirtyRows: Set<Int> = [],
    graphicsInvalidation: Set<Identity> = [],
    requiresFullTextRepaint: Bool = false,
    requiresFullGraphicsReplay: Bool = false
  ) {
    self.init(
      textRows: dirtyRows.sorted().map { TextRow(row: $0) },
      graphicsInvalidation: graphicsInvalidation,
      requiresFullTextRepaint: requiresFullTextRepaint,
      requiresFullGraphicsReplay: requiresFullGraphicsReplay
    )
  }

  package init(
    textRows: [TextRow] = [],
    graphicsInvalidation: Set<Identity> = [],
    requiresFullTextRepaint: Bool = false,
    requiresFullGraphicsReplay: Bool = false
  ) {
    self.textRows = PresentationDamage.normalizeTextRows(textRows)
    self.graphicsInvalidation = graphicsInvalidation
    self.requiresFullTextRepaint = requiresFullTextRepaint
    self.requiresFullGraphicsReplay = requiresFullGraphicsReplay
  }

  package var dirtyRows: Set<Int> {
    Set(textRows.map(\.row))
  }

  package func columnRanges(for row: Int) -> [Range<Int>]? {
    textRows.first { $0.row == row }?.columnRanges
  }

  private static func normalizeTextRows(
    _ textRows: [TextRow]
  ) -> [TextRow] {
    var groupedRanges: [Int: [Range<Int>]] = [:]
    var fullRows: Set<Int> = []

    for textRow in textRows {
      if textRow.columnRanges.isEmpty {
        fullRows.insert(textRow.row)
        groupedRanges[textRow.row] = []
        continue
      }
      if fullRows.contains(textRow.row) {
        continue
      }
      groupedRanges[textRow.row, default: []].append(contentsOf: textRow.columnRanges)
    }

    return groupedRanges.keys.sorted().map { row in
      if fullRows.contains(row) {
        return TextRow(row: row)
      }
      return TextRow(row: row, columnRanges: groupedRanges[row] ?? [])
    }
  }

  private static func normalizeColumnRanges(
    _ columnRanges: [Range<Int>]
  ) -> [Range<Int>] {
    let normalized =
      columnRanges
      .map { range in
        let lowerBound = max(0, range.lowerBound)
        let upperBound = max(lowerBound, range.upperBound)
        return lowerBound..<upperBound
      }
      .filter { !$0.isEmpty }
      .sorted { lhs, rhs in
        if lhs.lowerBound == rhs.lowerBound {
          return lhs.upperBound < rhs.upperBound
        }
        return lhs.lowerBound < rhs.lowerBound
      }

    guard let first = normalized.first else {
      return []
    }

    var merged: [Range<Int>] = [first]
    for range in normalized.dropFirst() {
      let lastIndex = merged.index(before: merged.endIndex)
      let lastRange = merged[lastIndex]
      if range.lowerBound <= lastRange.upperBound {
        merged[lastIndex] = lastRange.lowerBound..<max(lastRange.upperBound, range.upperBound)
      } else {
        merged.append(range)
      }
    }
    return merged
  }
}

