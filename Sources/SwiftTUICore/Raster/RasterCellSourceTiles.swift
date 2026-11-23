import Synchronization

/// Only layers larger than the host surface budget use tiles. Cache the paint
/// at the requested coordinates so a retained sampler keeps its original values.
final class RasterCellSourceTiles: Sendable {
  private struct Storage {
    var layers: [CellPoint: CellLayer] = [:]
    var identities: Set<Identity> = []
  }
  private let storage = Mutex(Storage())

  var visibleIdentities: Set<Identity> { storage.withLock { $0.identities } }

  func sample(
    _ point: CellPoint, in bounds: CellRect,
    render: (CellRect, inout Set<Identity>) -> CellLayer
  ) -> CellSample {
    let x = SaturatingConversion.subtracting(point.x, bounds.origin.x)
    let y = SaturatingConversion.subtracting(point.y, bounds.origin.y)
    let key = CellPoint(x: x / 32, y: y / 8)
    if let cached = storage.withLock({ $0.layers[key] }) { return cached.sample(at: point) }
    let tileX = SaturatingConversion.adding(bounds.origin.x, key.x * 32)
    let tileY = SaturatingConversion.adding(bounds.origin.y, key.y * 8)
    // Include a lead and tail crossing either horizontal tile edge.
    let left = max(bounds.origin.x, SaturatingConversion.subtracting(tileX, 2))
    let right = min(bounds.maxX, SaturatingConversion.adding(tileX, 34))
    let tile = CellRect(
      origin: .init(x: left, y: tileY),
      size: .init(width: right - left, height: min(8, bounds.maxY - tileY)))
    var visible: Set<Identity> = []
    let result = render(tile, &visible)
    // Author callbacks run outside the lock. Concurrent readers agree on the
    // first completed snapshot for each tile.
    let installed = storage.withLock { state in
      if let existing = state.layers[key] { return existing }
      state.layers[key] = result
      state.identities.formUnion(visible)
      return result
    }
    return installed.sample(at: point)
  }
}

extension Rasterizer {
  /// Capture one bounded rectangle of a potentially much larger logical layer.
  func captureSourceTile(
    node: DrawNode, sourceBounds: CellRect, viewport: CellRect,
    targetOrigin: CellPoint, backdrop: CellLayer, tile: CellRect,
    visibleIdentities: inout Set<Identity>, strokeBackdrop: [[RasterCell]]? = nil,
    strokeArms: LineArmsTable? = nil
  ) -> CellLayer {
    let scratchOrigin = tile.origin
    let scratchSize = tile.size
    let origin = node.bounds.origin
    let scratch = RasterPresentationLayerRecorder.scratchOnly()
    let sourceNode = node.rebasedForCapture(at: scratchOrigin)
    let lowerInScratch = CellLayer(
      bounds: viewport.relative(to: scratchOrigin),
      readableBounds: viewport.relative(to: scratchOrigin)
    ) { point in
      backdrop.sample(
        at: .init(
          x: SaturatingConversion.subtracting(
            SaturatingConversion.adding(point.x, scratchOrigin.x), origin.x),
          y: SaturatingConversion.subtracting(
            SaturatingConversion.adding(point.y, scratchOrigin.y), origin.y)))
    }
    scratch.cellCapture = RasterCellCapture(
      size: scratchSize, inheritedBackdrop: lowerInScratch,
      originInRoot: .init(
        x: SaturatingConversion.adding(targetOrigin.x, scratchOrigin.x),
        y: SaturatingConversion.adding(targetOrigin.y, scratchOrigin.y)), defersCoverage: true,
      projectsImages: true, viewport: viewport.relative(to: scratchOrigin),
      paintDomain: sourceBounds.relative(to: scratchOrigin))
    var sourceCells =
      strokeBackdrop
      ?? Array(
        repeating: Array(repeating: RasterCell.empty, count: scratchSize.width),
        count: scratchSize.height)
    var attachments: [RasterImageAttachment] = []
    paint(
      node: sourceNode, cells: &sourceCells, imageAttachments: &attachments,
      clip: nil,
      dirtyRows: nil, dirtySpans: nil, visibleIdentities: &visibleIdentities,
      presentationRecorder: scratch, lineArms: strokeArms ?? LineArmsTable())
    return cellLayer(
      cells: sourceCells, capture: scratch.cellCapture,
      absoluteBounds: sourceBounds.relative(to: scratchOrigin),
      origin: sourceNode.bounds.origin, allowsLink: !node.isTransient)

  }
}
