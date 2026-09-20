extension Rasterizer {
  /// Paints a layout-reserved border into the cells that
  /// ``LayoutBehavior/border(_:foreground:background:blend:blendPhase:sides:)``
  /// reserved during the layout pass.
  ///
  /// For `.outset` placement the frame grew by the border's width and the
  /// glyphs are written into those reserved outer cells without touching the
  /// child's interior. For `.inset` placement no cells were reserved and the
  /// glyphs overdraw the view's outermost rows and columns.
  ///
  /// The border is a rectangle track, walked by the same
  /// ``RectangleStrokeTrack/forEachGlyph(pen:sides:dash:dashOrigin:rows:_:)``
  /// that draws a rectangle stroke and a rule. This function resolves the paint
  /// for each cell and writes it.
  internal func drawLayoutBorder(
    in outer: CellRect,
    stroke: StrokeStyle,
    foreground: BorderEdgeStyle?,
    background: BorderBackgroundStyle?,
    blend: BorderBlend?,
    blendPhase: Double,
    sides: Edge.Set,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    blendMode: BlendMode? = nil,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder? = nil,
    presentationEffects: [DrawEffect] = [],
    lineArms: LineArmsTable? = nil
  ) {
    guard outer.size.width > 0, outer.size.height > 0 else {
      return
    }

    // A set with no glyphs reserves no cells and draws nothing. These widths
    // match the insets reserved by `LayoutEngine.borderLayoutInsets(set:sides:)`.
    let set = stroke.borderSet
    let drawsTop = sides.contains(.top) && set.topDisplayWidth > 0
    let drawsBottom = sides.contains(.bottom) && set.bottomDisplayWidth > 0
    let drawsLeft = sides.contains(.leading) && set.leftDisplayWidth > 0
    let drawsRight = sides.contains(.trailing) && set.rightDisplayWidth > 0
    guard drawsTop || drawsBottom || drawsLeft || drawsRight else {
      return
    }
    var drawnSides: Edge.Set = []
    if drawsTop { drawnSides.insert(.top) }
    if drawsBottom { drawnSides.insert(.bottom) }
    if drawsLeft { drawnSides.insert(.leading) }
    if drawsRight { drawnSides.insert(.trailing) }

    // Perimeter-sampled colors override per-side foregrounds when a
    // ``BorderBlend`` is attached. They are sampled once for the whole rect and
    // looked up by clockwise perimeter index per cell.
    let perimeterColors: [Color]? = blend.flatMap { blend in
      let samples = blend.samplePerimeter(
        width: outer.size.width,
        height: outer.size.height,
        phase: blendPhase
      )
      return samples.isEmpty ? nil : samples
    }

    // Each distinct side style is prepared once, so gradient geometry is shared
    // by every cell on that side. A nil foreground falls back to the theme
    // foreground. A nil background means no background paint.
    func modes(
      _ style: (BorderSide) -> AnyShapeStyle?
    ) -> (
      top: ResolvedShapeColorMode?, right: ResolvedShapeColorMode?,
      bottom: ResolvedShapeColorMode?, left: ResolvedShapeColorMode?
    ) {
      (
        resolvedBorderSideColorMode(style(.top), environment: environment, bounds: outer),
        resolvedBorderSideColorMode(style(.right), environment: environment, bounds: outer),
        resolvedBorderSideColorMode(style(.bottom), environment: environment, bounds: outer),
        resolvedBorderSideColorMode(style(.left), environment: environment, bounds: outer)
      )
    }
    let foregroundModes = modes { foreground?.foregroundStyle(for: $0) }
    let backgroundModes = modes { background?.backgroundStyle(for: $0) }
    func mode(
      _ modes: (
        top: ResolvedShapeColorMode?, right: ResolvedShapeColorMode?,
        bottom: ResolvedShapeColorMode?, left: ResolvedShapeColorMode?
      ),
      for side: BorderSide
    ) -> ResolvedShapeColorMode? {
      switch side {
      case .top: modes.top
      case .right: modes.right
      case .bottom: modes.bottom
      case .left: modes.left
      }
    }

    let track = RectangleStrokeTrack(
      width: outer.size.width,
      height: outer.size.height,
      aspectRatio: environment.cellPixelMetrics.aspectRatio
    )
    track.forEachInk(
      pen: StrokePen(borderSet: set, roundsCorners: stroke.lineJoin == .round),
      sides: drawnSides,
      mask: StrokeMask(stroke),
      // Per-row cull (D70).
      rows: dirtyRows.map { dirtyRows in { dirtyRows.contains(outer.origin.y + $0) } }
    ) { ink in
      let cell = ink.cell
      let x = outer.origin.x + cell.x
      let y = outer.origin.y + cell.y
      let glyph = mergedGlyph(
        ink, atX: x, y: y, cells: cells, clip: clip, dirtyRows: dirtyRows, lineArms: lineArms)
      let side = track.paintSide(for: cell, sides: drawnSides)
      let cellForeground =
        perimeterColor(
          atLocalX: cell.x,
          localY: cell.y,
          width: outer.size.width,
          height: outer.size.height,
          perimeter: perimeterColors
        )
        ?? resolvedBorderSideColor(mode(foregroundModes, for: side), bounds: outer, x: x, y: y)
        ?? environment.theme.foreground
      writeBorderGlyph(
        glyph,
        width: 1,
        foreground: cellForeground,
        background: resolvedBorderSideColor(
          mode(backgroundModes, for: side), bounds: outer, x: x, y: y),
        atX: x,
        y: y,
        cells: &cells,
        clip: clip,
        blendMode: blendMode,
        dirtyRows: dirtyRows,
        presentationRecorder: presentationRecorder,
        presentationEffects: presentationEffects
      )
    }
  }

  internal func perimeterColor(
    atLocalX localX: Int,
    localY: Int,
    width: Int,
    height: Int,
    perimeter: [Color]?
  ) -> Color? {
    guard let perimeter, !perimeter.isEmpty else {
      return nil
    }
    guard
      let index = perimeterIndex(
        localX: localX,
        localY: localY,
        width: width,
        height: height
      )
    else {
      return nil
    }
    let total = perimeter.count
    let normalized = ((index % total) + total) % total
    return perimeter[normalized]
  }

  internal func perimeterIndex(
    localX: Int,
    localY: Int,
    width: Int,
    height: Int
  ) -> Int? {
    guard width > 0, height > 0 else { return nil }
    guard localX >= 0, localX < width, localY >= 0, localY < height else { return nil }
    if width == 1 && height == 1 {
      return 0
    }
    if localY == 0 {
      return localX
    }
    if localX == width - 1 {
      return width + (localY - 1)
    }
    if localY == height - 1 {
      return 2 * width + height - 3 - localX
    }
    if localX == 0 {
      return 2 * width + 2 * height - 4 - localY
    }
    return nil
  }

  internal func resolvedBorderSideColorMode(
    _ style: AnyShapeStyle?,
    environment: StyleEnvironmentSnapshot,
    bounds: CellRect
  ) -> ResolvedShapeColorMode? {
    guard let style else {
      return nil
    }
    return resolvedColorMode(
      from: style,
      environment: environment,
      bounds: bounds
    )
  }

  internal func resolvedBorderSideColor(
    _ mode: ResolvedShapeColorMode?,
    bounds: CellRect,
    x: Int,
    y: Int
  ) -> Color? {
    mode.flatMap {
      resolveColor(
        from: $0,
        bounds: bounds,
        sampleX: x,
        sampleY: y
      )
    }
  }

  internal func writeBorderGlyph(
    _ character: Character,
    width: Int,
    foreground: Color?,
    background: Color?,
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    blendMode: BlendMode? = nil,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder? = nil,
    presentationEffects: [DrawEffect] = []
  ) {
    var resolved = ResolvedTextStyle()
    resolved.foregroundColor = foreground
    resolved.backgroundColor = background
    write(
      character,
      width: max(1, width),
      style: resolved.isDefault ? nil : resolved,
      atX: x,
      y: y,
      cells: &cells,
      clip: clip,
      blendMode: blendMode,
      dirtyRows: dirtyRows,
      presentationRecorder: presentationRecorder,
      presentationEffects: presentationEffects
    )
  }
}
