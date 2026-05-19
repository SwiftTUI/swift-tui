extension LayoutEngine {
  func popPlacements(
    from results: inout [PlacedNode],
    count: Int
  ) -> [PlacedNode] {
    guard count > 0 else {
      return []
    }
    precondition(results.count >= count, "placement work stack expected \(count) child results")
    let start = results.count - count
    let children = Array(results[start..<results.count])
    results.removeLast(count)
    return children
  }
}
