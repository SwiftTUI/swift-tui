extension Rasterizer {
  /// Decomposes a cell mask into disjoint rectangles. Equal runs in adjacent
  /// rows share one rectangle, so a rectangular clip paints its subtree once.
  internal func shapeClipRegions(node: DrawNode, clip: CellRect?) -> [CellRect] {
    guard let bounds = intersect(node.bounds, clip ?? node.bounds), !bounds.isEmpty else {
      return []
    }
    let masks = node.metadata.shapeClips.map { mask in
      let maximumInset = min(node.bounds.size.width, node.bounds.size.height) / 2
      return (
        mask.geometry,
        mask.insetAmount > maximumInset ? nil : insetBounds(node.bounds, by: mask.insetAmount)
      )
    }
    var rectangles: [CellRect] = []
    var previousRuns: [CellRect: Int] = [:]
    for y in bounds.origin.y..<bounds.maxY {
      var runs: [CellRect: Int] = [:]
      var x = bounds.origin.x
      func contains(_ x: Int) -> Bool {
        masks.allSatisfy { geometry, maskBounds in
          guard let maskBounds, !maskBounds.isEmpty else { return false }
          return shapeContains(
            pointX: x, pointY: y, in: maskBounds, geometry: geometry,
            metrics: node.environmentSnapshot.style.cellPixelMetrics)
        }
      }
      while x < bounds.maxX {
        guard contains(x) else {
          x += 1
          continue
        }
        let start = x
        repeat { x += 1 } while x < bounds.maxX && contains(x)
        let key = CellRect(origin: .init(x: start, y: 0), size: .init(width: x - start, height: 1))
        if let index = previousRuns[key] {
          rectangles[index].size.height += 1
          runs[key] = index
        } else {
          runs[key] = rectangles.count
          rectangles.append(.init(origin: .init(x: start, y: y), size: key.size))
        }
      }
      previousRuns = runs
    }
    return rectangles
  }

  /// Image masks split a placement into several clips. Retained attachment
  /// ordering currently assumes one placement per command; fresh rasterization
  /// keeps fragments and their paint-order sidecar together until that invariant
  /// can be widened. Cell-only masks retain ordinary incremental rasterization.
  internal func hasImageCommands(_ draw: DrawNode) -> Bool {
    var stack = [draw]
    while let node = stack.popLast() {
      if (node.commands + node.postCommands).contains(where: { command in
        if case .image = command { return true }
        return false
      }) {
        return true
      }
      stack.append(contentsOf: node.children)
    }
    return false
  }
}
