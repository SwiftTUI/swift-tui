/// Row extents in the collection body's display-line coordinates. Materialized
/// lists include interleaved section chrome; indexed collections estimate only
/// rows that have not been measured yet.
package struct CollectionScrollGeometry: Equatable, Sendable {
  private enum Rows: Equatable, Sendable {
    case indexed(count: Int, span: Int, measured: [MeasuredRow])
    case materialized(ranges: [Range<Int>], displayLineCount: Int)
  }

  private struct MeasuredRow: Equatable, Sendable {
    let index: Int
    let height: Int
    let precedingExtraLines: Int
    /// Lines this row adds beyond the one-line-per-row stride: the cells a
    /// taller row spans, minus its following separator line when hidden.
    let extraLines: Int
  }

  private let rows: Rows

  /// `hiddenSeparators` names rows whose FOLLOWING separator line is not
  /// drawn (a table row with `listRowSeparator(.hidden)`); it applies only to
  /// strides that interleave a separator (`rowSpan > 1`) and never to the
  /// last row, which has no following separator.
  package init(
    rowCount: Int,
    rowSpan: Int,
    rowHeights: [Int: Int] = [:],
    hiddenSeparators: Set<Int> = []
  ) {
    let count = max(0, rowCount)
    let span = max(1, rowSpan)
    let hidden = span > 1 ? hiddenSeparators.filter { $0 >= 0 && $0 < count - 1 } : []
    var extraLines = 0
    let indices = Set(rowHeights.keys).union(hidden).sorted()
    let measured = indices.compactMap { index -> MeasuredRow? in
      guard index >= 0, index < count else { return nil }
      let height = max(1, rowHeights[index] ?? 1)
      let extra = (height - 1) - (hidden.contains(index) ? 1 : 0)
      guard height > 1 || extra != 0 else { return nil }
      let row = MeasuredRow(
        index: index, height: height, precedingExtraLines: extraLines, extraLines: extra)
      extraLines += extra
      return row
    }
    rows = .indexed(count: count, span: span, measured: measured)
  }

  package init(rowRanges: [Range<Int>], displayLineCount: Int) {
    rows = .materialized(ranges: rowRanges, displayLineCount: max(0, displayLineCount))
  }

  package var rowCount: Int {
    switch rows {
    case .indexed(let count, _, _): count
    case .materialized(let ranges, _): ranges.count
    }
  }

  /// The minimum stride used to bound an interaction band before measurement.
  package var rowSpan: Int {
    switch rows {
    case .indexed(_, let span, _): span
    case .materialized: 1
    }
  }

  package var lastRowIndex: Int { max(0, rowCount - 1) }

  package var displayLineCount: Int {
    switch rows {
    case .indexed(let count, let span, let measured):
      guard count > 0 else { return 0 }
      let last = measured.last
      let extraLines = last.map { $0.precedingExtraLines + $0.extraLines } ?? 0
      return count * span - (span - 1) + extraLines
    case .materialized(_, let displayLineCount):
      return displayLineCount
    }
  }

  package func line(forRow rowIndex: Int) -> Int {
    lineRange(forRow: rowIndex).lowerBound
  }

  /// The row's content cells, excluding its following separator.
  package func lineRange(forRow rowIndex: Int) -> Range<Int> {
    let index = min(max(0, rowIndex), lastRowIndex)
    switch rows {
    case .indexed(let count, let span, let measured):
      guard count > 0 else { return 0..<0 }
      let insertion = firstMeasuredRow(atOrAfter: index, in: measured)
      let previous = insertion > 0 ? measured[insertion - 1] : nil
      let extraLines = previous.map { $0.precedingExtraLines + $0.extraLines } ?? 0
      let start = index * span + extraLines
      let height =
        insertion < measured.count && measured[insertion].index == index
        ? measured[insertion].height : 1
      return start..<(start + height)
    case .materialized(let ranges, _):
      return ranges.isEmpty ? 0..<0 : ranges[index]
    }
  }

  /// Reveal rounds forward so a partially covered row does not become the anchor.
  package func row(atOrAfterLine line: Int) -> Int {
    var lower = 0
    var upper = rowCount
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if self.line(forRow: middle) < line {
        lower = middle + 1
      } else {
        upper = middle
      }
    }
    return min(lower, lastRowIndex)
  }

  package func row(atOrBeforeLine line: Int) -> Int {
    let next = row(atOrAfterLine: line)
    return self.line(forRow: next) > line ? max(0, next - 1) : next
  }

  package func maxAnchorRow(viewportLineCount: Int) -> Int {
    guard viewportLineCount > 0 else { return lastRowIndex }
    return row(atOrBeforeLine: max(0, displayLineCount - viewportLineCount))
  }

  package func positionedOffset(for anchor: CollectionScrollAnchor?, capacity: Int) -> Int? {
    let maximum = max(0, displayLineCount - capacity)
    switch anchor {
    case .end: return maximum
    case .position(let row, let offset):
      return min(max(0, line(forRow: row) + offset), maximum)
    default: return nil
    }
  }

  private func firstMeasuredRow(atOrAfter index: Int, in measured: [MeasuredRow]) -> Int {
    var lower = 0
    var upper = measured.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if measured[middle].index < index {
        lower = middle + 1
      } else {
        upper = middle
      }
    }
    return lower
  }
}
