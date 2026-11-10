final class RasterPresentationLayerRecorder {
  private(set) var layers: [RasterPresentationLayer]
  private var nextOrder: Int
  /// Layers carried over from a previous surface by incremental rasterization.
  /// New fragments never merge into these: a retained layer's bounds describe a
  /// paint event from an earlier frame, and extending it with current-frame
  /// content would misattribute paint recency in the diagnostic sidecar.
  private let retainedPrefixCount: Int
  /// `false` for the scratch surface of an isolated compositing group, whose
  /// writes are not paint events of the destination surface.
  private let recordsLayers: Bool
  /// The recorder is the one per-raster object every cell writer receives, so
  /// it also carries the scratch that lets a run of cells share attributes.
  let attributeMemo = RasterAttributeMemo()

  init(layers: [RasterPresentationLayer] = []) {
    self.layers = layers
    self.nextOrder = (layers.map(\.order).max() ?? -1) + 1
    self.retainedPrefixCount = layers.count
    self.recordsLayers = true
  }

  private init(recordsLayers: Bool) {
    self.layers = []
    self.nextOrder = 0
    self.retainedPrefixCount = 0
    self.recordsLayers = recordsLayers
  }

  /// A recorder that keeps no layers and only lends its attribute scratch.
  static func scratchOnly() -> RasterPresentationLayerRecorder {
    RasterPresentationLayerRecorder(recordsLayers: false)
  }

  func appendCellFragment(
    from cells: [[RasterCell]],
    x: Int,
    y: Int,
    width: Int,
    effects: [DrawEffect]
  ) {
    guard recordsLayers, y >= 0, y < cells.count else {
      return
    }
    let rowWidth = cells[y].count
    let lower = max(0, x)
    let upper = min(rowWidth, max(lower, x + max(1, width)))
    guard lower < upper else {
      return
    }

    // Coalesce contiguous same-row fragments recorded back to back with
    // identical effects. Painting calls this once per glyph, so an uncoalesced
    // recorder allocates one layer per painted cell — O(W×H) layers on a fresh
    // raster (F36). Merging only the immediately preceding layer preserves the
    // sidecar's paint-order semantics: no other layer can sit between two
    // merged fragments.
    if layers.count > retainedPrefixCount,
      let last = layers.last,
      case .cells = last.content,
      last.bounds.origin.y == y,
      last.effects == effects,
      lower <= last.bounds.maxX,
      upper >= last.bounds.origin.x
    {
      let mergedLower = min(lower, last.bounds.origin.x)
      let mergedUpper = max(upper, last.bounds.maxX)
      let mergedBounds = CellRect(
        origin: CellPoint(x: mergedLower, y: y),
        size: CellSize(width: mergedUpper - mergedLower, height: 1)
      )
      layers[layers.count - 1].bounds = mergedBounds
      layers[layers.count - 1].content = .cells(
        RasterSurfaceFragment(bounds: mergedBounds, cells: [])
      )
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
    guard recordsLayers, attachment.visibleBounds.size.width > 0,
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
