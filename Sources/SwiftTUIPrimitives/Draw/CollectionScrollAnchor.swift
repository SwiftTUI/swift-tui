/// The requested collection position. An edge stays attached to its section
/// chrome as measurements change; a row reveals that row's content instead.
package enum CollectionScrollAnchor: Equatable, Sendable {
  case start
  case row(Int)
  /// A cell position relative to a row, including positions inside tall rows.
  case position(row: Int, lineOffset: Int)
  case end

  /// Cell positioning is necessary for an end that lies inside a tall row
  /// or footer. Whole-row navigation still uses row anchors between edges.
  package var requiresCellWindow: Bool {
    switch self {
    case .position, .end: true
    case .start, .row: false
    }
  }

  package func rowIndex(rowCount: Int) -> Int {
    let last = max(0, rowCount - 1)
    switch self {
    case .start: return 0
    case .row(let index): return min(max(0, index), last)
    case .position(let index, _): return min(max(0, index), last)
    case .end: return last
    }
  }
}
