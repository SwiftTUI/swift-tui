/// The requested collection position. An edge stays attached to its section
/// chrome as measurements change; a row reveals that row's content instead.
package enum CollectionScrollAnchor: Equatable, Sendable {
  case start
  case row(Int)
  case end

  package func rowIndex(rowCount: Int) -> Int {
    let last = max(0, rowCount - 1)
    switch self {
    case .start: return 0
    case .row(let index): return min(max(0, index), last)
    case .end: return last
    }
  }
}
