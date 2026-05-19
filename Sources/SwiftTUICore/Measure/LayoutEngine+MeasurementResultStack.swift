extension LayoutEngine {
  func scheduleChildren(
    _ children: [ResolvedNode],
    proposal: ProposedSize,
    finish: MeasurementWorkItem,
    work: inout [MeasurementWorkItem]
  ) {
    work.append(finish)
    for child in children.reversed() {
      work.append(.measure(child, proposal))
    }
  }

  func popMeasurement(
    from results: inout [MeasuredNode]
  ) -> MeasuredNode {
    precondition(!results.isEmpty, "measurement work stack expected a child result")
    return results.removeLast()
  }

  func popMeasurements(
    from results: inout [MeasuredNode],
    count: Int
  ) -> [MeasuredNode] {
    guard count > 0 else {
      return []
    }
    precondition(results.count >= count, "measurement work stack expected \(count) child results")
    let start = results.count - count
    let childMeasurements = Array(results[start..<results.count])
    results.removeLast(count)
    return childMeasurements
  }
}
