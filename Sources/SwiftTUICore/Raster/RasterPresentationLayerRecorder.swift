final class RasterPresentationLayerRecorder {
  private(set) var layers: [RasterPresentationLayer]
  private var nextOrder: Int

  init(layers: [RasterPresentationLayer] = []) {
    self.layers = layers
    self.nextOrder = (layers.map(\.order).max() ?? -1) + 1
  }

  func appendCellFragment(
    from cells: [[RasterCell]],
    x: Int,
    y: Int,
    width: Int,
    effects: [DrawEffect]
  ) {
    guard y >= 0, y < cells.count else {
      return
    }
    let row = cells[y]
    let lower = max(0, x)
    let upper = min(row.count, max(lower, x + max(1, width)))
    guard lower < upper else {
      return
    }

    let bounds = CellRect(
      origin: CellPoint(x: lower, y: y),
      size: CellSize(width: upper - lower, height: 1)
    )
    layers.append(
      RasterPresentationLayer(
        order: consumeOrder(),
        bounds: bounds,
        content: .cells(
          RasterSurfaceFragment(
            bounds: bounds,
            cells: [Array(row[lower..<upper])]
          )
        ),
        effects: effects
      )
    )
  }

  func appendImageAttachment(
    _ attachment: RasterImageAttachment,
    effects: [DrawEffect]
  ) {
    guard attachment.visibleBounds.size.width > 0,
      attachment.visibleBounds.size.height > 0
    else {
      return
    }

    layers.append(
      RasterPresentationLayer(
        order: consumeOrder(),
        bounds: attachment.visibleBounds,
        content: .image(attachment),
        effects: effects
      )
    )
  }

  private func consumeOrder() -> Int {
    defer { nextOrder += 1 }
    return nextOrder
  }
}
