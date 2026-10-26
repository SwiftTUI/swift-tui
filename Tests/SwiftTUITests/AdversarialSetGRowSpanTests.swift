@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// An explicit line model: row `i` takes `max(1, height)` lines and then
/// `span - 1` separator lines, one fewer when its following separator is
/// hidden (`span > 1`), and none after the last row.
private struct SetGRowModel {
  var count: Int
  var span: Int
  var heights: [Int: Int]
  var hidden: Set<Int>
  var ranges: [Range<Int>] = []
  var total = 0

  init(_ n: [Int], span forcedSpan: Int? = nil) {
    count = n[0] % 13
    span = forcedSpan ?? (n[1] % 2 + 1)
    heights = [:]
    hidden = []
    for index in 0..<count {
      let raw = n[2 + index]
      if raw % 6 < 5 { heights[index] = raw % 6 }
      if raw / 6 % 3 == 0 { hidden.insert(index) }
    }
    if n[1] / 2 % 2 == 1 {
      heights[count] = 3
      heights[-1] = 2
      hidden.formUnion([-1, count, count - 1])
    }
    var line = 0
    for index in 0..<count {
      let height = max(1, heights[index] ?? 1)
      ranges.append(line..<(line + height))
      line += height
      if index < count - 1 {
        line += span > 1 && hidden.contains(index) ? span - 2 : span - 1
      }
    }
    total = line
  }

  var geometry: CollectionScrollGeometry {
    CollectionScrollGeometry(
      rowCount: count, rowSpan: span, rowHeights: heights, hiddenSeparators: hidden)
  }

  func clamped(_ row: Int) -> Int { min(max(0, row), max(0, count - 1)) }

  func range(_ row: Int) -> Range<Int> { count == 0 ? 0..<0 : ranges[clamped(row)] }

  func rowAtOrBefore(_ line: Int) -> Int {
    ranges.lastIndex { $0.lowerBound <= line } ?? 0
  }

  func rowAtOrAfter(_ line: Int) -> Int {
    clamped(ranges.firstIndex { $0.lowerBound >= line } ?? count)
  }
}

@MainActor
@Suite("Campaign F5 pass 2 line-span properties", .serialized)
struct AdversarialSetGRowSpanTests {
  @Test(arguments: Array(126...130))
  func rowSpan(id: Int) {
    switch id {
    case 126: lineRanges(id)
    case 127: displayLineCount(id)
    case 128: lineLookups(id)
    case 129: maximumAnchorAndMaterialized(id)
    default: visibleRowCount(id)
    }
  }

  private func lineRanges(_ id: Int) {
    setGProperty(id, setGDraws(15)) { n in
      let model = SetGRowModel(n)
      let geometry = model.geometry
      for row in -1...model.count where geometry.lineRange(forRow: row) != model.range(row) {
        return "row \(row): \(geometry.lineRange(forRow: row)), model \(model.range(row))"
      }
      return nil
    }
  }

  private func displayLineCount(_ id: Int) {
    setGProperty(id, setGDraws(15)) { n in
      let model = SetGRowModel(n)
      let count = model.geometry.displayLineCount
      return count == model.total ? nil : "displayLineCount \(count), model \(model.total)"
    }
  }

  private func lineLookups(_ id: Int) {
    setGProperty(id, setGDraws(15)) { n in
      let model = SetGRowModel(n)
      let geometry = model.geometry
      for line in -2...(model.total + 2) {
        let before = geometry.row(atOrBeforeLine: line)
        let after = geometry.row(atOrAfterLine: line)
        if before != model.rowAtOrBefore(line) || after != model.rowAtOrAfter(line) {
          return
            "line \(line): before \(before)/\(model.rowAtOrBefore(line)), after \(after)/\(model.rowAtOrAfter(line))"
        }
      }
      return nil
    }
  }

  private func maximumAnchorAndMaterialized(_ id: Int) {
    setGProperty(id, setGDraws(15)) { n in
      let model = SetGRowModel(n)
      let geometry = model.geometry
      let materialized = CollectionScrollGeometry(
        rowRanges: model.ranges, displayLineCount: model.total)
      for viewport in 1...(model.total + 2) {
        let expected = model.rowAtOrBefore(max(0, model.total - viewport))
        if geometry.maxAnchorRow(viewportLineCount: viewport) != expected
          || materialized.maxAnchorRow(viewportLineCount: viewport) != expected
        {
          return
            "viewport \(viewport): max anchor \(geometry.maxAnchorRow(viewportLineCount: viewport)), materialized \(materialized.maxAnchorRow(viewportLineCount: viewport)), model \(expected)"
        }
      }
      if materialized.displayLineCount != geometry.displayLineCount {
        return
          "materialized \(materialized.displayLineCount) lines, indexed \(geometry.displayLineCount)"
      }
      for line in -2...(model.total + 2)
      where materialized.row(atOrBeforeLine: line) != geometry.row(atOrBeforeLine: line)
        || materialized.row(atOrAfterLine: line) != geometry.row(atOrAfterLine: line)
      {
        return "line \(line): materialized and indexed lookups differ"
      }
      return nil
    }
  }

  private func visibleRowCount(_ id: Int) {
    setGProperty(id, setGDraws(17)) { n in
      var draws = n
      draws[0] = 2 + n[0] % 11
      let model = SetGRowModel(draws, span: 2)
      guard model.total > 0 else { return nil }
      let lower = n[15] % model.total
      let upper = lower + 1 + n[16] % (model.total - lower)
      let window = lower..<upper
      let expected = model.ranges.filter { $0.overlaps(window) }.count
      guard expected > 0 else { return nil }
      let identity = testIdentity("SetG130VisibleRows")
      let geometry = model.geometry
      let registry = LocalScrollPositionRegistry()
      var route = ScrollRoute(
        identity: identity,
        viewportRect: CellRect(origin: .zero, size: CellSize(width: 20, height: window.count)),
        contentBounds: CellRect(origin: .zero, size: CellSize(width: 20, height: model.total)))
      route.collectionScrollLayout = CollectionScrollLayout(
        geometry: geometry, visibleLines: window)
      registry.updateGeometry(scrollRoutes: [route], scrollTargets: [])
      let currency = CollectionScrollCurrency(
        identity: identity, geometry: geometry, ownerNode: nil, registry: registry,
        windowMetrics: { _, _ in (offset: 0, visibleLineCount: window.count) })
      let actual = currency.visibleRowCount
      return actual == expected
        ? nil
        : "window \(window) over \(model.ranges): \(actual) rows counted, \(expected) shown"
    }
  }
}
