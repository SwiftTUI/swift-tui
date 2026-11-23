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
  /// A deferred source can outlive this logical sample. Its tiles must never
  /// hold the frame that owns the shader retaining those very tiles.
  func deferredSourceRasterizer(
    node: DrawNode, sourceBounds: CellRect,
    viewport: CellRect, targetOrigin: CellPoint, backdrop: CellLayer
  ) -> Self {
    var sampler = self
    sampler.cellPreparationFrame = nil
    guard node.subtreeHasPreparedCells, let parent = cellPreparationFrame else { return sampler }
    let dependencies = CellPreparationFrame(at: parent.instant)
    sampler.cellPreparationFrame = dependencies
    // Keep each mask's placed geometry, since a single tile near an origin
    // can be completely outside a custom path.
    var pending: [(DrawNode, CellRect, [DrawNode])] = [(node, sourceBounds, [])]
    var sites: [(any CellPreparationBinding, CellRect)] = []
    while let (child, inherited, inheritedMasks) = pending.popLast() {
      guard child.subtreeHasPreparedCells,
        let clip = inherited.intersection(child.clipBounds ?? inherited)
      else { continue }
      var masks = inheritedMasks
      if !child.metadata.shapeClips.isEmpty { masks.append(child) }
      for case .cellLayer(let pass) in child.drawEffects.ordered {
        guard case .prepared(let site) = pass.shader.program else { continue }
        site.transfer(from: parent, to: dependencies)
        let area = child.bounds.intersection(clip) ?? clip
        guard let point = preparationPoint(in: area, masks: masks) else { continue }
        // A small sample triggers preparation; each preparer then receives
        // its own complete declared source window through the normal painter.
        let tile = CellRect(
          origin: point, size: .init(width: 1, height: 1))
        sites.append((site, tile))
      }
      for nested in child.children.reversed() { pending.append((nested, clip, masks)) }
    }
    var ignored: Set<Identity> = []
    for (site, tile) in sites where site.cached(in: dependencies) == nil {
      _ = sampler.captureSourceTile(
        node: node, sourceBounds: sourceBounds,
        viewport: viewport, targetOrigin: targetOrigin, backdrop: backdrop, tile: tile,
        visibleIdentities: &ignored)
    }
    for (site, _) in sites { site.transfer(from: dependencies, to: parent) }
    return sampler
  }

  /// Find an output cell that actually enters the prepared descriptor. This
  /// path only runs for oversized sources with nested state. The common plain
  /// and centered masks take one probe, while a free-form path may cover any
  /// cell. Test coverage without allocating a surface matching the layer.
  private func preparationPoint(in area: CellRect, masks: [DrawNode]) -> CellPoint? {
    guard !area.isEmpty else { return nil }
    if masks.isEmpty { return area.origin }
    var domain = area
    var constraints: [(ShapeGeometry, CellRect, CellPixelMetrics)] = []
    for node in masks {
      for mask in node.metadata.shapeClips {
        guard let bounds = shapeInsetBounds(node.bounds, by: mask.insetAmount),
          let visible = domain.intersection(bounds)
        else { return nil }
        domain = visible
        constraints.append((mask.geometry, bounds, node.environmentSnapshot.style.cellPixelMetrics))
      }
    }
    func covered(_ point: CellPoint) -> Bool {
      constraints.allSatisfy { geometry, bounds, metrics in
        shapeContains(
          pointX: point.x, pointY: point.y, in: bounds, geometry: geometry, metrics: metrics)
      }
    }
    let center = CellPoint(
      x: domain.origin.x + domain.size.width / 2,
      y: domain.origin.y + domain.size.height / 2)
    if covered(center) { return center }
    for y in domain.origin.y..<domain.maxY {
      for x in domain.origin.x..<domain.maxX {
        let point = CellPoint(x: x, y: y)
        if covered(point) { return point }
      }
    }
    return nil
  }

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
