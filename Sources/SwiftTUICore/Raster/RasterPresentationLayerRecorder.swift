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
    let rowWidth = cells[y].count
    let lower = max(0, x)
    let upper = min(rowWidth, max(lower, x + max(1, width)))
    guard lower < upper else {
      return
    }

    let bounds = CellRect(
      origin: CellPoint(x: lower, y: y),
      size: CellSize(width: upper - lower, height: 1)
    )
    // The cell payload is intentionally empty. Only `bounds`, `order`, and
    // `effects` are consumed: `RasterSurfaceDamageDiff` reads the `.cells` case
    // as a topology marker (never the cells), and the snapshot describer prints
    // only `bounds`. Copying the row slice here (`Array(row[lower..<upper])`)
    // allocated a heap array per painted glyph — ~1 per cell on a fresh raster —
    // for data nothing reads.
    layers.append(
      RasterPresentationLayer(
        order: consumeOrder(),
        bounds: bounds,
        content: .cells(
          RasterSurfaceFragment(bounds: bounds, cells: [])
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
