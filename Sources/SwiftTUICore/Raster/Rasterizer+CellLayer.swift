extension Rasterizer {
  /// Applies one isolation boundary. Implicit capture keeps a snapshot of its enclosing
  /// destination available to nested readers. Explicit compositing groups start a new target.
  func paintCellLayer(
    _ node: DrawNode, pass: CellEffectPass, clip: CellRect?, blendMode: BlendMode?,
    effects: [DrawEffect], dirtyRows: Set<Int>?, cells: inout [[RasterCell]],
    visibleIdentities: inout Set<Identity>, recorder: RasterPresentationLayerRecorder?
  ) {
    let size = CellSize(width: cells.first?.count ?? 0, height: cells.count)
    let surface = CellRect(origin: .zero, size: size)
    guard let target = surface.intersection(clip ?? surface) else { return }
    let inheritedViewport = recorder?.cellCapture?.viewport ?? surface
    let viewport = clip.map { inheritedViewport.intersection($0) ?? .zero } ?? inheritedViewport
    let origin = node.bounds.origin
    // A previous pass can paint beyond layout. Preserve that ink for an outer
    // shader without changing the subject's local coordinate origin.
    var sourceBounds = node.subtreeHasCellEffect ? node.subtreeBounds : node.bounds
    if node.subtreeDrawsInViewport { sourceBounds = sourceBounds.union(viewport) }
    let localSource = sourceBounds.relative(to: origin)
    let localViewport = viewport.relative(to: origin)
    // Captures must be able to paint offscreen source before a later mapping
    // brings it back into view. An explicitly requested viewport remains the
    // real enclosing viewport regardless of the current scratch dimensions.
    let writeBounds =
      pass.shader.region == .viewport ? target.intersection(viewport) ?? .zero : target
    let output = pass.shader.region.bounds(
      source: localSource, viewport: writeBounds.relative(to: origin))
    guard !output.isEmpty else { return }
    if let probe = RasterWorkProbe.active() {
      var work = RasterWorkCounters()
      work.cellEffectCaptures = 1
      probe.record(work)
    }
    let style = node.environmentSnapshot.style
    let targetOrigin = recorder?.cellCapture?.originInRoot ?? .zero
    let rootOrigin = CellPoint(
      x: SaturatingConversion.adding(targetOrigin.x, origin.x),
      y: SaturatingConversion.adding(targetOrigin.y, origin.y))
    let context = CellEffectContext(
      sourceBounds: localSource, outputBounds: output, viewport: localViewport,
      originInRoot: rootOrigin, appearance: style.appearance,
      cellPixelMetrics: style.cellPixelMetrics)

    // A single source-only pass never depends on prior paint. Avoid retaining
    // destination rows and forcing a COW copy for every row we overwrite.
    let backdrop: CellLayer
    if pass.shader.readsBackdrop || node.subtreeHasCellEffect {
      backdrop = cellLayer(
        cells: cells, capture: recorder?.cellCapture, absoluteBounds: viewport,
        origin: origin, allowsLink: true, includeInherited: true)
    } else {
      backdrop = CellLayer(bounds: .zero, readableBounds: .zero) { _ in .empty }
    }
    // Reuse absolute coordinates for an on-screen capture. For off-screen
    // content the scratch origin travels to the needed source rectangle.
    let input: CellRect
    switch pass.offset {
    case .layerBounds: input = sourceBounds
    case .cells(let dx, let dy):
      // A read at a continuation also needs the lead just outside the window.
      let reach = CellDrawingRegion.outset(x: SaturatingConversion.adding(max(0, dx), 2), y: dy)
      let readBounds = reach.bounds(source: output, viewport: localSource)
      input = .init(
        origin: .init(
          x: SaturatingConversion.adding(origin.x, readBounds.origin.x),
          y: SaturatingConversion.adding(origin.y, readBounds.origin.y)), size: readBounds.size)
    }
    let captureBounds = sourceBounds
    let tiles: RasterCellSourceTiles?
    let source: CellLayer
    if Self.boundedSurfaceSize(input.size, maximum: nil) != input.size {
      let cache = RasterCellSourceTiles()
      tiles = cache
      source = CellLayer(bounds: localSource, readableBounds: localSource) { position in
        cache.sample(position, in: localSource) { tile, identities in
          let absolute = CellRect(
            origin: .init(
              x: SaturatingConversion.adding(tile.origin.x, origin.x),
              y: SaturatingConversion.adding(tile.origin.y, origin.y)), size: tile.size)
          return captureSourceTile(
            node: node, sourceBounds: captureBounds, viewport: viewport,
            targetOrigin: targetOrigin, backdrop: backdrop, tile: absolute,
            visibleIdentities: &identities)
        }
      }
    } else {
      tiles = nil
      let tile = input.intersection(surface) == input ? surface : input
      source = captureSourceTile(
        node: node, sourceBounds: captureBounds, viewport: viewport,
        targetOrigin: targetOrigin, backdrop: backdrop, tile: tile,
        visibleIdentities: &visibleIdentities)
    }
    defer {
      if let tiles { visibleIdentities.formUnion(tiles.visibleIdentities) }
    }

    for localY in output.origin.y..<output.maxY {
      let y = localY + origin.y
      if let dirtyRows, !dirtyRows.contains(y) { continue }
      var claimedUntil = output.origin.x
      for localX in output.origin.x..<output.maxX {
        let position = CellPoint(x: localX, y: localY)
        let window = pass.offset.window(around: position, in: source.bounds)
        let lower =
          pass.shader.readsBackdrop
          ? backdrop.restricted(
            to: pass.offset.window(around: position, in: backdrop.bounds), pass: pass)
          : backdrop
        let sample = pass.shader.raster(
          position, source.restricted(to: window, pass: pass), lower, context)
        guard localX >= claimedUntil, case .glyph(let glyph) = sample,
          glyph.width > 0, glyph.width <= output.maxX - localX, glyph.paint.coverage > 0
        else { continue }
        let x = localX + origin.x
        var ink = glyph.paint.foreground.color(in: context.appearance)
        var paper = glyph.paint.background.color(in: context.appearance)
        let fraction = glyph.paint.coverage
        let deferCoverage =
          recorder?.cellCapture?.defersCoverage == true
          && recorder?.cellCapture?.written[y][x] == false
        if fraction < 1 && !deferCoverage {
          let under = cells[y][x].style?.backgroundColor ?? context.appearance.backgroundColor
          let resolved = context.resolvedColors(
            for: glyph.paint, emphasis: glyph.emphasis, over: under)
          let mixedPaper = resolved.background.opacity(glyph.paint.coverage).composited(over: under)
          let mixedInk = resolved.foreground.opacity(glyph.paint.coverage).composited(
            over: mixedPaper)
          ink = glyph.emphasis.contains(.reverse) ? mixedPaper : mixedInk
          paper = glyph.emphasis.contains(.reverse) ? mixedInk : mixedPaper
        }
        var result = ResolvedTextStyle(
          foregroundColor: ink, backgroundColor: paper, emphasis: glyph.emphasis,
          underlineStyle: glyph.underline, strikethroughStyle: glyph.strikethrough,
          opacity: glyph.originalOpacity)
        if fraction == 1 || deferCoverage {
          result.foregroundPaletteIndex = glyph.paint.foreground.paletteIndex
          result.backgroundPaletteIndex = glyph.paint.background.paletteIndex
        }
        write(
          glyph.character, width: glyph.width, style: result.isDefault ? nil : result,
          hyperlink: node.isTransient ? nil : glyph.link?.rawValue, atX: x, y: y, cells: &cells,
          clip: target,
          blendMode: blendMode, presentationRecorder: recorder, presentationEffects: effects)
        if fraction < 1 && deferCoverage {
          recorder?.cellCapture?.fractionalCoverage[.init(x: x, y: y)] = fraction
        }
        claimedUntil = localX + glyph.width
      }
    }
  }
}

extension Rasterizer {
  /// Project at the image paint command so later text and borders occlude it normally.
  func paintEffectImage(
    _ attachment: RasterImageAttachment, appearance: TerminalAppearance,
    cells: inout [[RasterCell]], recorder: RasterPresentationLayerRecorder?, effects: [DrawEffect]
  ) {
    guard let image = effectImageProjection?(attachment, appearance.backgroundColor),
      let visible = attachment.visibleBounds.intersection(image.bounds)?.intersection(
        .init(origin: .zero, size: .init(width: cells.first?.count ?? 0, height: cells.count)))
    else { return }
    for y in visible.origin.y..<visible.maxY {
      let row = y - image.bounds.origin.y
      guard image.cells.indices.contains(row) else { continue }
      for x in visible.origin.x..<visible.maxX {
        let column = x - image.bounds.origin.x
        guard image.cells[row].indices.contains(column), let cell = image.cells[row][column] else {
          continue
        }
        write(
          cell.character, width: cell.spanWidth, attributes: cell.attributes,
          atX: x, y: y, cells: &cells, clip: visible, presentationRecorder: recorder,
          presentationEffects: effects)
      }
    }
  }
}
