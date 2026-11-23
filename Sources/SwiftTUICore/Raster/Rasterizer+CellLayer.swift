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
    guard let viewport = surface.intersection(clip ?? surface) else { return }
    let origin = node.bounds.origin
    let localSource = CellRect(origin: .zero, size: node.bounds.size)
    let localViewport = viewport.relative(to: origin)
    let output = pass.shader.region.bounds(source: localSource, viewport: localViewport)
    guard !output.isEmpty else { return }
    let style = node.environmentSnapshot.style
    let context = CellEffectContext(
      sourceBounds: localSource, outputBounds: output, viewport: localViewport,
      originInRoot: origin, appearance: style.appearance, cellPixelMetrics: style.cellPixelMetrics)

    let backdrop = cellLayer(
      cells: cells, capture: recorder?.cellCapture, absoluteBounds: viewport, origin: origin,
      allowsLink: true, includeInherited: true)
    let scratch = RasterPresentationLayerRecorder.scratchOnly()
    let lowerInRoot = CellLayer(bounds: viewport, readableBounds: viewport) { point in
      backdrop.sample(
        at: .init(
          x: SaturatingConversion.subtracting(point.x, origin.x),
          y: SaturatingConversion.subtracting(point.y, origin.y)))
    }
    scratch.cellCapture = RasterCellCapture(size: size, inheritedBackdrop: lowerInRoot)
    var sourceCells = Array(
      repeating: Array(repeating: RasterCell.empty, count: size.width), count: size.height)
    var attachments: [RasterImageAttachment] = []
    paint(
      node: node, cells: &sourceCells, imageAttachments: &attachments, clip: node.bounds,
      dirtyRows: nil, dirtySpans: nil, visibleIdentities: &visibleIdentities,
      presentationRecorder: scratch, lineArms: LineArmsTable())
    let source = cellLayer(
      cells: sourceCells, capture: scratch.cellCapture, absoluteBounds: node.bounds, origin: origin,
      allowsLink: !node.isTransient, includeInherited: false)

    for localY in output.origin.y..<output.maxY {
      let y = localY + origin.y
      if let dirtyRows, !dirtyRows.contains(y) { continue }
      var claimedUntil = output.origin.x
      for localX in output.origin.x..<output.maxX {
        let position = CellPoint(x: localX, y: localY)
        let window = pass.offset.window(around: position, in: source.bounds)
        let lowerWindow = pass.offset.window(around: position, in: backdrop.bounds)
        let sample = pass.shader.raster(
          position, source.restricted(to: window),
          backdrop.restricted(to: lowerWindow), context)
        guard localX >= claimedUntil, case .glyph(let glyph) = sample,
          glyph.width > 0, glyph.width <= output.maxX - localX, glyph.paint.coverage > 0
        else { continue }
        let x = localX + origin.x
        var ink = glyph.paint.foreground.color(in: context.appearance)
        var paper = glyph.paint.background.color(in: context.appearance)
        if glyph.paint.coverage < 1 {
          let under = cells[y][x].style?.backgroundColor ?? context.appearance.backgroundColor
          let resolved = context.resolvedColors(
            for: glyph.paint, emphasis: glyph.emphasis, over: under)
          let mixedPaper = resolved.background.opacity(glyph.paint.coverage).composited(over: under)
          let mixedInk = resolved.foreground.opacity(glyph.paint.coverage).composited(
            over: mixedPaper)
          ink = glyph.emphasis.contains(.reverse) ? mixedPaper : mixedInk
          paper = glyph.emphasis.contains(.reverse) ? mixedInk : mixedPaper
        }
        let result = ResolvedTextStyle(
          foregroundColor: ink, backgroundColor: paper, emphasis: glyph.emphasis,
          underlineStyle: glyph.underline, strikethroughStyle: glyph.strikethrough,
          opacity: glyph.originalOpacity)
        write(
          glyph.character, width: glyph.width, style: result.isDefault ? nil : result,
          hyperlink: glyph.link?.rawValue, atX: x, y: y, cells: &cells, clip: viewport,
          blendMode: blendMode, presentationRecorder: recorder, presentationEffects: effects)
        claimedUntil = localX + glyph.width
      }
    }
  }
}
