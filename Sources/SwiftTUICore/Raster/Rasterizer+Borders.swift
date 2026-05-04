extension Rasterizer {
  internal func paintStroke(
    in bounds: CellRect,
    geometry: ShapeGeometry,
    insetAmount: Int,
    style: AnyShapeStyle,
    strokeStyle: StrokeStyle,
    strokeBorder: Bool,
    backgroundStyle: BorderBackgroundStyle?,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let shapeBounds = insetBounds(bounds, by: max(0, insetAmount), strokeBorder: true)
    guard shapeBounds.size.width > 0, shapeBounds.size.height > 0 else {
      return
    }
    let foregroundColorMode = resolvedColorMode(
      from: style,
      environment: environment
    )

    // Curved shapes draw their outline onto a Braille canvas so the
    // stroke resolves to sub-cell precision.
    switch geometry {
    case .circle, .ellipse, .capsule:
      paintBrailleShape(
        geometry: geometry,
        shapeBounds: shapeBounds,
        colorMode: foregroundColorMode,
        stroke: true,
        environment: environment,
        cells: &cells,
        clip: clip,
        backgroundStyle: backgroundStyle
      )
      return
    case .rectangle, .roundedRectangle:
      break
    }

    let lineWidth = max(1, strokeStyle.lineWidth)
    for inset in 0..<lineWidth {
      let insetRect = insetBounds(shapeBounds, by: inset, strokeBorder: strokeBorder)
      guard insetRect.size.width > 0, insetRect.size.height > 0 else {
        continue
      }

      let resolvedSet = strokeStyle.borderSet
      let glyphs = BorderGlyphSet(borderSet: resolvedSet)

      let minX = insetRect.origin.x
      let maxX = insetRect.origin.x + insetRect.size.width - 1
      let minY = insetRect.origin.y
      let maxY = insetRect.origin.y + insetRect.size.height - 1

      for x in minX...maxX {
        writeStrokeGlyph(
          glyphs.top,
          borderSet: resolvedSet,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
          fallbackBackgroundSides: [.top],
          environment: environment,
          bounds: shapeBounds,
          x: x,
          y: minY,
          cells: &cells,
          clip: clip
        )
        if maxY != minY {
          writeStrokeGlyph(
            glyphs.bottom,
            borderSet: resolvedSet,
            foregroundColorMode: foregroundColorMode,
            backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
            fallbackBackgroundSides: [.bottom],
            environment: environment,
            bounds: shapeBounds,
            x: x,
            y: maxY,
            cells: &cells,
            clip: clip
          )
        }
      }

      if maxY - minY > 1 {
        for y in (minY + 1)..<maxY {
          writeStrokeGlyph(
            glyphs.left,
            borderSet: resolvedSet,
            foregroundColorMode: foregroundColorMode,
            backgroundStyle: backgroundStyle?.backgroundStyle(for: .left),
            fallbackBackgroundSides: [.left],
            environment: environment,
            bounds: shapeBounds,
            x: minX,
            y: y,
            cells: &cells,
            clip: clip
          )
          if maxX != minX {
            writeStrokeGlyph(
              glyphs.right,
              borderSet: resolvedSet,
              foregroundColorMode: foregroundColorMode,
              backgroundStyle: backgroundStyle?.backgroundStyle(for: .right),
              fallbackBackgroundSides: [.right],
              environment: environment,
              bounds: shapeBounds,
              x: maxX,
              y: y,
              cells: &cells,
              clip: clip
            )
          }
        }
      }

      writeStrokeGlyph(
        glyphs.topLeading,
        borderSet: resolvedSet,
        foregroundColorMode: foregroundColorMode,
        backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
        fallbackBackgroundSides: [.top, .left],
        environment: environment,
        bounds: shapeBounds,
        x: minX,
        y: minY,
        cells: &cells,
        clip: clip
      )
      if maxX != minX {
        writeStrokeGlyph(
          glyphs.topTrailing,
          borderSet: resolvedSet,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
          fallbackBackgroundSides: [.top, .right],
          environment: environment,
          bounds: shapeBounds,
          x: maxX,
          y: minY,
          cells: &cells,
          clip: clip
        )
      }
      if maxY != minY {
        writeStrokeGlyph(
          glyphs.bottomLeading,
          borderSet: resolvedSet,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
          fallbackBackgroundSides: [.bottom, .left],
          environment: environment,
          bounds: shapeBounds,
          x: minX,
          y: maxY,
          cells: &cells,
          clip: clip
        )
      }
      if maxX != minX, maxY != minY {
        writeStrokeGlyph(
          glyphs.bottomTrailing,
          borderSet: resolvedSet,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
          fallbackBackgroundSides: [.bottom, .right],
          environment: environment,
          bounds: shapeBounds,
          x: maxX,
          y: maxY,
          cells: &cells,
          clip: clip
        )
      }
    }
  }

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
    clip: CellRect?
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

    // For `.inset` placements the border draws into the view's
    // outermost rows and columns (so the `inner` region equals the
    // outer minus zero — the border overdraws the outer frame).  For
    // `.outset` placements the outer frame already
    // grew by the per-side display widths, so the top/bottom/left/right
    // sides lie entirely within the reserved inset and the content
    // sits in the interior rectangle `[leftWidth..width-rightWidth,
    // topWidth..height-bottomWidth]`.

    // Top edge cells: the non-corner region is
    // [outer.origin.x + leftWidth, outer.origin.x + width - rightWidth).
    // The glyph index starts at 0 at the leftmost non-corner cell and
    // cycles through the border set's top edge string for dashed
    // patterns.
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
          clip: clip
        )
        x += glyphWidth
        glyphIndex += 1
      }
    }

    // Bottom edge cells: draw along y = outer bottom - 1.
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
          clip: clip
        )
        x += glyphWidth
        glyphIndex += 1
      }
    }

    // Left edge cells: draw along x = outer.origin.x, between the top
    // and bottom edges (inclusive if those edges are not drawn).
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
          clip: clip
        )
        y += 1
        glyphIndex += 1
      }
    }

    // Right edge cells: draw along x = outer right - rightWidth.
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
          clip: clip
        )
        y += 1
        glyphIndex += 1
      }
    }

    // Corner glyphs.  Lipgloss semantics: corners inherit the adjacent
    // horizontal edge's color (top for top corners, bottom for bottom
    // corners).  When a perimeter blend is active each corner instead
    // takes the perimeter-array color for its cell position.
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
        clip: clip
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
        clip: clip
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
        clip: clip
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
        clip: clip
      )
    }

  }

  /// Maps a cell at local coordinates `(localX, localY)` inside an
  /// `(width × height)` rectangle to its position in the clockwise
  /// perimeter walk used by ``BorderBlend/samplePerimeter(width:height:phase:)``.
  ///
  /// The walk visits cells in this order:
  ///   top edge L→R, right edge T→B (excluding the top-right corner),
  ///   bottom edge R→L (excluding the bottom-right corner), left edge
  ///   B→T (excluding the bottom-left and top-left corners).
  ///
  /// Returns nil for non-perimeter (interior) cells, for out-of-range
  /// coordinates, or when no perimeter colors are available.
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

  /// Returns the clockwise perimeter index for `(localX, localY)` in a
  /// rectangle of size `(width × height)`, or nil if the cell is not on
  /// the perimeter or the inputs are degenerate.
  ///
  /// Walk order (matching ``BorderBlend/samplePerimeter(width:height:phase:)``):
  ///   1. Top edge L→R: indices `[0, width)`.
  ///   2. Right column T→B (excluding TR corner): indices `[width, width + h - 1)`.
  ///   3. Bottom row R→L (excluding BR corner): indices
  ///      `[width + h - 1, 2*width + h - 2)`.
  ///   4. Left column B→T (excluding BL and TL corners): indices
  ///      `[2*width + h - 2, 2*width + 2*h - 4)`.
  ///
  /// Hand-traced against a 4×3 fixture (10 perimeter cells):
  ///   (0,0)=0 (1,0)=1 (2,0)=2 (3,0)=3   ← top
  ///   (3,1)=4 (3,2)=5                   ← right (excl. TR)
  ///   (2,2)=6 (1,2)=7 (0,2)=8           ← bottom (excl. BR)
  ///   (0,1)=9                           ← left (excl. BL+TL)
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
    // Top edge wins for y == 0 (handles the height == 1 row case too).
    if localY == 0 {
      return localX
    }
    // Right column for x == width - 1, y >= 1.
    if localX == width - 1 {
      return width + (localY - 1)
    }
    // Bottom row R→L for y == height - 1, x < width - 1.
    if localY == height - 1 {
      return 2 * width + height - 3 - localX
    }
    // Left column B→T for x == 0, 1 <= y <= height - 2.
    if localX == 0 {
      return 2 * width + 2 * height - 4 - localY
    }
    // Interior cell — not on the perimeter.
    return nil
  }

  /// Eagerly resolves a border side's foreground/background style into a
  /// constant color.  Returns nil for gradient fills (which are not
  /// supported on borders in M2.B) or for nil styles; callers fall back
  /// to the theme defaults in that case.
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

  /// Writes a single border glyph at the given cell coordinates,
  /// applying the resolved foreground and optional background color.
  internal func writeBorderGlyph(
    _ character: Character,
    width: Int,
    foreground: Color?,
    background: Color?,
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]],
    clip: CellRect?
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
      clip: clip
    )
  }

  /// Writes a multi-character glyph string (used for corners, which are
  /// stored as strings so they can be empty or multi-rune).  Advances
  /// by each glyph's display width.
  internal func writeBorderGlyphs(
    _ text: String,
    atX x: Int,
    y: Int,
    foreground: Color?,
    background: Color?,
    cells: inout [[RasterCell]],
    clip: CellRect?
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
        clip: clip
      )
      cursor += glyphWidth
    }
  }

  internal func paintRule(
    in bounds: CellRect,
    style: AnyShapeStyle,
    strokeStyle: StrokeStyle,
    stackAxis: Axis?,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let foregroundColorMode = resolvedColorMode(
      from: style,
      environment: environment
    )
    let resolvedSet = strokeStyle.borderSet
    let glyphs = BorderGlyphSet(borderSet: resolvedSet)
    let drawsHorizontal =
      switch stackAxis {
      case .vertical?:
        true
      case .horizontal?:
        false
      case nil:
        bounds.size.width >= bounds.size.height
      }
    if drawsHorizontal {
      let y = bounds.origin.y + (bounds.size.height / 2)
      for x in bounds.origin.x..<(bounds.origin.x + bounds.size.width) {
        writeStrokeGlyph(
          glyphs.horizontal,
          borderSet: resolvedSet,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: nil,
          fallbackBackgroundSides: [],
          environment: environment,
          bounds: bounds,
          x: x,
          y: y,
          cells: &cells,
          clip: clip
        )
      }
    } else {
      let x = bounds.origin.x + (bounds.size.width / 2)
      for y in bounds.origin.y..<(bounds.origin.y + bounds.size.height) {
        writeStrokeGlyph(
          glyphs.vertical,
          borderSet: resolvedSet,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: nil,
          fallbackBackgroundSides: [],
          environment: environment,
          bounds: bounds,
          x: x,
          y: y,
          cells: &cells,
          clip: clip
        )
      }
    }
  }

  internal func writeStrokeGlyph(
    _ character: Character,
    borderSet: BorderSet,
    foregroundColorMode: ResolvedShapeColorMode,
    backgroundStyle: AnyShapeStyle?,
    fallbackBackgroundSides: [BorderSide],
    environment: StyleEnvironmentSnapshot,
    bounds: CellRect,
    x: Int,
    y: Int,
    cells: inout [[RasterCell]],
    clip: CellRect?
  ) {
    let resolvedStyle = ResolvedTextStyle(
      foregroundColor: resolveColor(
        from: foregroundColorMode,
        bounds: bounds,
        sampleX: x,
        sampleY: y
      ),
      backgroundColor: resolvedStrokeBackgroundColor(
        borderSet: borderSet,
        explicitBackgroundStyle: backgroundStyle,
        fallbackSides: fallbackBackgroundSides,
        environment: environment,
        bounds: bounds,
        x: x,
        y: y,
        cells: cells
      )
    )
    write(
      character,
      style: resolvedStyle.isDefault ? nil : resolvedStyle,
      atX: x,
      y: y,
      cells: &cells,
      clip: clip
    )
  }

  internal func resolvedStrokeBackgroundColor(
    borderSet: BorderSet,
    explicitBackgroundStyle: AnyShapeStyle?,
    fallbackSides: [BorderSide],
    environment: StyleEnvironmentSnapshot,
    bounds: CellRect,
    x: Int,
    y: Int,
    cells: [[RasterCell]]
  ) -> Color? {
    if let explicitBackgroundStyle {
      return resolveColor(
        from: explicitBackgroundStyle,
        environment: environment,
        bounds: bounds,
        sampleX: x,
        sampleY: y
      )
    }

    // Inner half-block borders (used for presentation chrome) draw into the
    // inset region of their owning container (popovers, toasts, menus), so
    // their glyph cells should inherit the interior fill rather than the
    // surrounding background.
    if borderSet == .innerHalfBlock {
      for side in fallbackSides {
        if let inferred = sampledBackgroundColor(
          inside: side,
          fromX: x,
          y: y,
          cells: cells
        ) {
          return inferred
        }
      }
    }

    for side in fallbackSides {
      if let inferred = sampledBackgroundColor(
        outside: side,
        fromX: x,
        y: y,
        cells: cells
      ) {
        return inferred
      }
    }

    return nil
  }

}
