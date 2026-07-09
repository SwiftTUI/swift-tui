package struct SurfaceTopologySignature: Equatable, Sendable {
  package var entries: [SurfaceTopologyEntry]

  package init(entries: [SurfaceTopologyEntry] = []) {
    self.entries = entries.sorted()
  }

  package init(placedRoot: PlacedNode) {
    var entries: [SurfaceTopologyEntry] = []
    Self.collect(from: placedRoot, into: &entries)
    self.init(entries: entries)
  }

  package func differs(from previous: Self?) -> Bool {
    guard let previous else {
      return false
    }
    return self != previous
  }

  private static func collect(
    from node: PlacedNode,
    into entries: inout [SurfaceTopologyEntry]
  ) {
    var stack: [PlacedNode] = [node]
    while let node = stack.popLast() {
      appendEntry(from: node, into: &entries)
      stack.append(contentsOf: node.children.reversed())
    }
  }

  private static func appendEntry(
    from node: PlacedNode,
    into entries: inout [SurfaceTopologyEntry]
  ) {
    if node.surfaceComposition.participatesInTopologySignature {
      entries.append(
        SurfaceTopologyEntry(
          role: node.surfaceComposition.role,
          stableKey: node.surfaceComposition.stableKey,
          invalidationScope: node.surfaceComposition.invalidationScope,
          bounds: node.bounds,
          zIndex: node.zIndex
        )
      )
    }
  }
}

package struct SurfaceTopologyEntry: Equatable, Sendable, Comparable {
  // Deliberately carries no runtime `Identity`: a `ViewNodeID` re-key of a
  // portal/overlay root must not perturb the topology signature (which would
  // force a spurious full-surface diff). Participating nodes are distinguished
  // by their structural `stableKey` (Stage 4) plus role/scope/geometry.
  package var role: SurfaceCompositionRole
  package var stableKey: String?
  package var invalidationScope: SurfaceInvalidationScope
  package var bounds: CellRect
  package var zIndex: Double

  package static func < (lhs: Self, rhs: Self) -> Bool {
    comparisonTuple(lhs).lexicographicallyPrecedes(comparisonTuple(rhs))
  }

  private static func comparisonTuple(_ entry: Self) -> [String] {
    [
      entry.stableKey.map { "1:\($0)" } ?? "0:",
      String(describing: entry.role),
      String(describing: entry.invalidationScope),
      "\(entry.bounds.origin.x),\(entry.bounds.origin.y)",
      "\(entry.bounds.size.width),\(entry.bounds.size.height)",
      "\(entry.zIndex)",
    ]
  }
}
