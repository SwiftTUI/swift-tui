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
    blendMode: BlendMode? = nil
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

    // Pre-resolve per-side foreground colors so we don't re-run the
    // shape-style resolver once per cell.  A nil per-side color falls
    // back to the theme foreground at draw time.  When a perimeter
    // blend is active these are unused (the per-cell lookup wins).
    let topForeground = resolvedBorderSideColor(
      foreground?.foregroundStyle(for: .top),
      environment: environment,
      bounds: outer
    )
    let bottomForeground = resolvedBorderSideColor(
      foreground?.foregroundStyle(for: .bottom),
      environment: environment,
      bounds: outer
    )
    let leftForeground = resolvedBorderSideColor(
      foreground?.foregroundStyle(for: .left),
      environment: environment,
      bounds: outer
    )
    let rightForeground = resolvedBorderSideColor(
      foreground?.foregroundStyle(for: .right),
      environment: environment,
      bounds: outer
    )

    let topBackground = resolvedBorderSideColor(
      background?.backgroundStyle(for: .top),
      environment: environment,
      bounds: outer
    )
    let bottomBackground = resolvedBorderSideColor(
      background?.backgroundStyle(for: .bottom),
      environment: environment,
      bounds: outer
    )
    let leftBackground = resolvedBorderSideColor(
      background?.backgroundStyle(for: .left),
      environment: environment,
      bounds: outer
    )
    let rightBackground = resolvedBorderSideColor(
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
          ) ?? topForeground ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: glyphWidth,
          foreground: cellForeground,
          background: topBackground,
          atX: x,
          y: y,
          cells: &cells,
          clip: clip,
          blendMode: blendMode
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
          ) ?? bottomForeground ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: glyphWidth,
          foreground: cellForeground,
          background: bottomBackground,
          atX: x,
          y: y,
          cells: &cells,
          clip: clip,
          blendMode: blendMode
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
          ) ?? leftForeground ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: leftWidth,
          foreground: cellForeground,
          background: leftBackground,
          atX: x,
          y: y,
          cells: &cells,
          clip: clip,
          blendMode: blendMode
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
          ) ?? rightForeground ?? environment.theme.foreground
        writeBorderGlyph(
          character,
          width: rightWidth,
          foreground: cellForeground,
          background: rightBackground,
          atX: x,
          y: y,
          cells: &cells,
          clip: clip,
          blendMode: blendMode
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
      blendMode: blendMode
    )
  }

  private func drawLayoutBorderCorners(
    in outer: CellRect,
    set: BorderSet,
    topWidth: Int,
    bottomWidth: Int,
    leftWidth: Int,
    rightWidth: Int,
    topForeground: Color?,
    bottomForeground: Color?,
    topBackground: Color?,
    bottomBackground: Color?,
    perimeterColors: [Color]?,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    blendMode: BlendMode?
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
        ) ?? topForeground ?? environment.theme.foreground
      writeBorderGlyphs(
        set.topLeading,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: topBackground,
        cells: &cells,
        clip: clip,
        blendMode: blendMode
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
        ) ?? topForeground ?? environment.theme.foreground
      writeBorderGlyphs(
        set.topTrailing,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: topBackground,
        cells: &cells,
        clip: clip,
        blendMode: blendMode
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
        ) ?? bottomForeground ?? environment.theme.foreground
      writeBorderGlyphs(
        set.bottomLeading,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: bottomBackground,
        cells: &cells,
        clip: clip,
        blendMode: blendMode
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
        ) ?? bottomForeground ?? environment.theme.foreground
      writeBorderGlyphs(
        set.bottomTrailing,
        atX: cornerX,
        y: cornerY,
        foreground: cornerForeground,
        background: bottomBackground,
        cells: &cells,
        clip: clip,
        blendMode: blendMode
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

  internal func resolvedBorderSideColor(
    _ style: AnyShapeStyle?,
    environment: StyleEnvironmentSnapshot,
    bounds: CellRect
  ) -> Color? {
    guard let style else {
      return nil
    }
    return resolveColor(
      from: style,
      environment: environment,
      bounds: bounds,
      sampleX: bounds.origin.x,
      sampleY: bounds.origin.y
    )
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
    blendMode: BlendMode? = nil
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
      blendMode: blendMode
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
    blendMode: BlendMode? = nil
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
        blendMode: blendMode
      )
      cursor += glyphWidth
    }
  }
}
