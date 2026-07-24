extension Rasterizer {
  /// Paints a layout-reserved border into the cells that
  /// ``LayoutBehavior/border(_:foreground:background:blend:blendPhase:sides:)``
  /// reserved during the layout pass.
  ///
  /// The entry point for the new layout-aware `.border(...)` view
  /// modifier.  For `.outset` border sets the frame
  /// grew by the per-side display widths and the glyphs are written
  /// into those reserved outer cells without ever touching the child's
  /// interior.  For `.inset` sets no frame insets were reserved and
  /// the glyphs overdraw the view's outermost rows / cols.
  internal func drawLayoutBorder(
    in outer: CellRect,
    set: BorderSet,
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
    presentationEffects: [DrawEffect] = []
  ) {
    guard outer.size.width > 0, outer.size.height > 0 else {
      return
    }

    // Resolved side widths, masked by the requested `sides` set.
    // These match the layout insets reserved during the layout pass
    // by `LayoutEngine.borderLayoutInsets(set:sides:)`.
    let topWidth = sides.contains(.top) ? set.topDisplayWidth : 0
    let bottomWidth = sides.contains(.bottom) ? set.bottomDisplayWidth : 0
    let leftWidth = sides.contains(.leading) ? set.leftDisplayWidth : 0
    let rightWidth = sides.contains(.trailing) ? set.rightDisplayWidth : 0

    guard topWidth > 0 || bottomWidth > 0 || leftWidth > 0 || rightWidth > 0 else {
      return
    }

    // Perimeter-sampled colors override per-side foregrounds when a
    // ``BorderBlend`` is attached.  We sample once for the whole outer
    // rect and look up by clockwise perimeter index per cell below.
    let perimeterColors: [Color]?
    if let blend {
      let samples = blend.samplePerimeter(
        width: outer.size.width,
        height: outer.size.height,
        phase: blendPhase
      )
      perimeterColors = samples.isEmpty ? nil : samples
    } else {
      perimeterColors = nil
    }

    // Prepare each distinct side style once so gradient geometry is shared
    // by every perimeter sample. A nil per-side mode falls back to the theme
    // foreground at draw time. When a perimeter
    // blend is active these are unused (the per-cell lookup wins).
    let topForeground = resolvedBorderSideColorMode(
      foreground?.foregroundStyle(for: .top),
      environment: environment,
      bounds: outer
    )
    let bottomForeground = resolvedBorderSideColorMode(
      foreground?.foregroundStyle(for: .bottom),
      environment: environment,
      bounds: outer
    )
    let leftForeground = resolvedBorderSideColorMode(
      foreground?.foregroundStyle(for: .left),
      environment: environment,
      bounds: outer
    )
    let rightForeground = resolvedBorderSideColorMode(
      foreground?.foregroundStyle(for: .right),
      environment: environment,
      bounds: outer
    )

    let topBackground = resolvedBorderSideColorMode(
      background?.backgroundStyle(for: .top),
      environment: environment,
      bounds: outer
    )
    let bottomBackground = resolvedBorderSideColorMode(
      background?.backgroundStyle(for: .bottom),
      environment: environment,
      bounds: outer
    )
    let leftBackground = resolvedBorderSideColorMode(
      background?.backgroundStyle(for: .left),
      environment: environment,
      bounds: outer
    )
    let rightBackground = resolvedBorderSideColorMode(
      background?.backgroundStyle(for: .right),
      environment: environment,
      bounds: outer
    )

    if topWidth > 0 {
      let y = outer.origin.y
      let startX = outer.origin.x + leftWidth
      let endX = outer.origin.x + outer.size.width - rightWidth
      var x = startX
      var glyphIndex = 0
      while x < endX {
        guard let character = set.topGlyph(at: glyphIndex) else {
          break
        }
        let glyphWidth = max(1, cellWidth(of: character))
        guard x + glyphWidth <= endX else {
          break
        }
        let cellForeground =
          perimeterColor(
            atLocalX: x - outer.origin.x,
            localY: y - outer.origin.y,
            width: outer.size.width,
            height: outer.size.height,
            perimeter: perimeterColors
          )
          ?? resolvedBorderSideColor(topForeground, bounds: outer, x: x, y: y)
          ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: glyphWidth,
          foreground: cellForeground,
          background: resolvedBorderSideColor(topBackground, bounds: outer, x: x, y: y),
          atX: x,
          y: y,
          cells: &cells,
          clip: clip,
          blendMode: blendMode,
          dirtyRows: dirtyRows,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
        )
        x += glyphWidth
        glyphIndex += 1
      }
    }

    if bottomWidth > 0 {
      let y = outer.origin.y + outer.size.height - 1
      let startX = outer.origin.x + leftWidth
      let endX = outer.origin.x + outer.size.width - rightWidth
      var x = startX
      var glyphIndex = 0
      while x < endX {
        guard let character = set.bottomGlyph(at: glyphIndex) else {
          break
        }
        let glyphWidth = max(1, cellWidth(of: character))
        guard x + glyphWidth <= endX else {
          break
        }
        let cellForeground =
          perimeterColor(
            atLocalX: x - outer.origin.x,
            localY: y - outer.origin.y,
            width: outer.size.width,
            height: outer.size.height,
            perimeter: perimeterColors
          )
          ?? resolvedBorderSideColor(bottomForeground, bounds: outer, x: x, y: y)
          ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: glyphWidth,
          foreground: cellForeground,
          background: resolvedBorderSideColor(bottomBackground, bounds: outer, x: x, y: y),
          atX: x,
          y: y,
          cells: &cells,
          clip: clip,
          blendMode: blendMode,
          dirtyRows: dirtyRows,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
        )
        x += glyphWidth
        glyphIndex += 1
      }
    }

    if leftWidth > 0 {
      let x = outer.origin.x
      let topExclusive = topWidth > 0 ? outer.origin.y + topWidth : outer.origin.y
      let bottomExclusive =
        bottomWidth > 0
        ? outer.origin.y + outer.size.height - bottomWidth
        : outer.origin.y + outer.size.height
      var y = topExclusive
      var glyphIndex = 0
      while y < bottomExclusive {
        guard let character = set.leftGlyph(at: glyphIndex) else {
          break
        }
        let cellForeground =
          perimeterColor(
            atLocalX: x - outer.origin.x,
            localY: y - outer.origin.y,
            width: outer.size.width,
            height: outer.size.height,
            perimeter: perimeterColors
          )
          ?? resolvedBorderSideColor(leftForeground, bounds: outer, x: x, y: y)
          ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: leftWidth,
          foreground: cellForeground,
          background: resolvedBorderSideColor(leftBackground, bounds: outer, x: x, y: y),
          atX: x,
          y: y,
          cells: &cells,
          clip: clip,
          blendMode: blendMode,
          dirtyRows: dirtyRows,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
        )
        y += 1
        glyphIndex += 1
      }
    }

    if rightWidth > 0 {
      let x = outer.origin.x + outer.size.width - rightWidth
      let topExclusive = topWidth > 0 ? outer.origin.y + topWidth : outer.origin.y
      let bottomExclusive =
        bottomWidth > 0
        ? outer.origin.y + outer.size.height - bottomWidth
        : outer.origin.y + outer.size.height
      var y = topExclusive
      var glyphIndex = 0
      while y < bottomExclusive {
        guard let character = set.rightGlyph(at: glyphIndex) else {
          break
        }
        let cellForeground =
          perimeterColor(
            atLocalX: x - outer.origin.x,
            localY: y - outer.origin.y,
            width: outer.size.width,
            height: outer.size.height,
            perimeter: perimeterColors
          )
          ?? resolvedBorderSideColor(rightForeground, bounds: outer, x: x, y: y)
          ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: rightWidth,
          foreground: cellForeground,
          background: resolvedBorderSideColor(rightBackground, bounds: outer, x: x, y: y),
          atX: x,
          y: y,
          cells: &cells,
          clip: clip,
          blendMode: blendMode,
          dirtyRows: dirtyRows,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
        )
        y += 1
        glyphIndex += 1
      }
    }

    drawLayoutBorderCorners(
      in: outer,
      set: set,
      topWidth: topWidth,
      bottomWidth: bottomWidth,
      leftWidth: leftWidth,
      rightWidth: rightWidth,
      topForeground: topForeground,
      bottomForeground: bottomForeground,
      topBackground: topBackground,
      bottomBackground: bottomBackground,
      perimeterColors: perimeterColors,
      environment: environment,
      cells: &cells,
      clip: clip,
      blendMode: blendMode,
      dirtyRows: dirtyRows,
      presentationRecorder: presentationRecorder,
      presentationEffects: presentationEffects
    )
  }

  private func drawLayoutBorderCorners(
    in outer: CellRect,
    set: BorderSet,
    topWidth: Int,
    bottomWidth: Int,
    leftWidth: Int,
    rightWidth: Int,
    topForeground: ResolvedShapeColorMode?,
    bottomForeground: ResolvedShapeColorMode?,
    topBackground: ResolvedShapeColorMode?,
    bottomBackground: ResolvedShapeColorMode?,
    perimeterColors: [Color]?,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    blendMode: BlendMode?,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder?,
    presentationEffects: [DrawEffect]
  ) {
    if topWidth > 0 && leftWidth > 0 {
      let cornerX = outer.origin.x
      let cornerY = outer.origin.y
      let cornerForeground =
        perimeterColor(
          atLocalX: cornerX - outer.origin.x,
          localY: cornerY - outer.origin.y,
          width: outer.size.width,
          height: outer.size.height,
          perimeter: perimeterColors
        )
        ?? resolvedBorderSideColor(
          topForeground,
          bounds: outer,
          x: cornerX,
          y: cornerY
        )
        ?? environment.theme.foreground
      writeBorderGlyphs(
        set.topLeading,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: resolvedBorderSideColor(
          topBackground,
          bounds: outer,
          x: cornerX,
          y: cornerY
        ),
        cells: &cells,
        clip: clip,
        blendMode: blendMode,
        dirtyRows: dirtyRows,
        presentationRecorder: presentationRecorder,
        presentationEffects: presentationEffects
      )
    }
    if topWidth > 0 && rightWidth > 0 {
      let cornerX = outer.origin.x + outer.size.width - rightWidth
      let cornerY = outer.origin.y
      let cornerForeground =
        perimeterColor(
          atLocalX: cornerX - outer.origin.x,
          localY: cornerY - outer.origin.y,
          width: outer.size.width,
          height: outer.size.height,
          perimeter: perimeterColors
        )
        ?? resolvedBorderSideColor(
          topForeground,
          bounds: outer,
          x: cornerX,
          y: cornerY
        )
        ?? environment.theme.foreground
      writeBorderGlyphs(
        set.topTrailing,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: resolvedBorderSideColor(
          topBackground,
          bounds: outer,
          x: cornerX,
          y: cornerY
        ),
        cells: &cells,
        clip: clip,
        blendMode: blendMode,
        dirtyRows: dirtyRows,
        presentationRecorder: presentationRecorder,
        presentationEffects: presentationEffects
      )
    }
    if bottomWidth > 0 && leftWidth > 0 {
      let cornerX = outer.origin.x
      let cornerY = outer.origin.y + outer.size.height - 1
      let cornerForeground =
        perimeterColor(
          atLocalX: cornerX - outer.origin.x,
          localY: cornerY - outer.origin.y,
          width: outer.size.width,
          height: outer.size.height,
          perimeter: perimeterColors
        )
        ?? resolvedBorderSideColor(
          bottomForeground,
          bounds: outer,
          x: cornerX,
          y: cornerY
        )
        ?? environment.theme.foreground
      writeBorderGlyphs(
        set.bottomLeading,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: resolvedBorderSideColor(
          bottomBackground,
          bounds: outer,
          x: cornerX,
          y: cornerY
        ),
        cells: &cells,
        clip: clip,
        blendMode: blendMode,
        dirtyRows: dirtyRows,
        presentationRecorder: presentationRecorder,
        presentationEffects: presentationEffects
      )
    }
    if bottomWidth > 0 && rightWidth > 0 {
      let cornerX = outer.origin.x + outer.size.width - rightWidth
      let cornerY = outer.origin.y + outer.size.height - 1
      let cornerForeground =
        perimeterColor(
          atLocalX: cornerX - outer.origin.x,
          localY: cornerY - outer.origin.y,
          width: outer.size.width,
          height: outer.size.height,
          perimeter: perimeterColors
        )
        ?? resolvedBorderSideColor(
          bottomForeground,
          bounds: outer,
          x: cornerX,
          y: cornerY
        )
        ?? environment.theme.foreground
      writeBorderGlyphs(
        set.bottomTrailing,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: resolvedBorderSideColor(
          bottomBackground,
          bounds: outer,
          x: cornerX,
          y: cornerY
        ),
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

  internal func writeBorderGlyphs(
    _ text: String,
    atX x: Int,
    y: Int,
    foreground: Color?,
    background: Color?,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    blendMode: BlendMode? = nil,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder? = nil,
    presentationEffects: [DrawEffect] = []
  ) {
    guard !text.isEmpty else {
      return
    }
    var cursor = x
    for character in text {
      let glyphWidth = max(1, cellWidth(of: character))
      writeBorderGlyph(
        character,
        width: glyphWidth,
        foreground: foreground,
        background: background,
        atX: cursor,
        y: y,
        cells: &cells,
        clip: clip,
        blendMode: blendMode,
        dirtyRows: dirtyRows,
        presentationRecorder: presentationRecorder,
        presentationEffects: presentationEffects
      )
      cursor += glyphWidth
    }
  }
}
