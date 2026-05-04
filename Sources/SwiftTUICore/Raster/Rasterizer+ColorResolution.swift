extension Rasterizer {
  internal func shapeContains(
    pointX x: Int,
    pointY y: Int,
    in bounds: CellRect,
    geometry: ShapeGeometry,
    fillMode: ShapeFillMode = .full
  ) -> Bool {
    let targetBounds: CellRect
    switch fillMode {
    case .full:
      targetBounds = bounds
    case .interior(let strokeWidth):
      let insetRect = insetBounds(bounds, by: strokeWidth, strokeBorder: true)
      guard insetRect.size.width > 0, insetRect.size.height > 0 else {
        return false
      }
      targetBounds = insetRect
    }

    switch geometry {
    case .rectangle:
      return x >= targetBounds.origin.x
        && x < targetBounds.origin.x + targetBounds.size.width
        && y >= targetBounds.origin.y
        && y < targetBounds.origin.y + targetBounds.size.height
    case .circle, .ellipse, .capsule:
      return curvedShapeContains(
        pointX: x,
        pointY: y,
        in: targetBounds,
        geometry: geometry
      )
    case .roundedRectangle(let cornerRadius):
      if case .interior = fillMode {
        return x >= targetBounds.origin.x
          && x < targetBounds.origin.x + targetBounds.size.width
          && y >= targetBounds.origin.y
          && y < targetBounds.origin.y + targetBounds.size.height
      }
      guard targetBounds.origin.x <= x,
        x < targetBounds.origin.x + targetBounds.size.width,
        targetBounds.origin.y <= y,
        y < targetBounds.origin.y + targetBounds.size.height
      else {
        return false
      }
      guard cornerRadius > 0, targetBounds.size.width > 1, targetBounds.size.height > 1 else {
        return true
      }
      let minX = targetBounds.origin.x
      let maxX = targetBounds.origin.x + targetBounds.size.width - 1
      let minY = targetBounds.origin.y
      let maxY = targetBounds.origin.y + targetBounds.size.height - 1
      let isCorner =
        (x == minX || x == maxX) && (y == minY || y == maxY)
      return !isCorner
    }
  }

  /// Tests whether the cell at `(x, y)` is inside a curved shape
  /// (``ShapeGeometry/circle``, ``ShapeGeometry/ellipse``,
  /// ``ShapeGeometry/capsule``) at cell resolution.
  ///
  /// The math mirrors the Braille subpixel renderer in
  /// ``paintBrailleShape(geometry:shapeBounds:colorMode:stroke:environment:cells:clip:backgroundStyle:)``
  /// so that a cell the test reports as "inside" is a cell the Braille
  /// rasterizer would actually paint dots into.
  ///
  /// For each cell, the test projects the cell's visual center into the
  /// canvas subpixel grid (every cell is 2 subpixels wide and 4 tall)
  /// and evaluates the same parametric inequality that `fillCircle`,
  /// `fillEllipse`, and `drawCapsule` use.
  internal func curvedShapeContains(
    pointX x: Int,
    pointY y: Int,
    in bounds: CellRect,
    geometry: ShapeGeometry
  ) -> Bool {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return false
    }
    let cellRelX = x - bounds.origin.x
    let cellRelY = y - bounds.origin.y
    guard cellRelX >= 0, cellRelX < bounds.size.width,
      cellRelY >= 0, cellRelY < bounds.size.height
    else {
      return false
    }

    // Project the cell's visual center onto the subpixel grid used by
    // `paintBrailleShape`.  A cell is 2 subpixels wide and 4 tall, so
    // the center of cell (cx, cy) in subpixel space is
    // (cx*2 + 0.5, cy*4 + 1.5).  We compute `subW`, `subH`, and the
    // per-shape center/radius in Int space to match `paintBrailleShape`
    // exactly (which uses Int floor division), then convert to Double
    // only for the parametric test.  This guarantees the pattern-fill
    // silhouette matches the Braille disc silhouette cell-for-cell.
    let subW = bounds.size.width * 2
    let subH = bounds.size.height * 4
    let px = Double(cellRelX * 2) + 0.5
    let py = Double(cellRelY * 4) + 1.5

    switch geometry {
    case .circle:
      // Matches `paintBrailleShape`'s circle case:
      //   radius = (min(subW, subH) - 1) / 2  (Int floor)
      //   cx = (subW - 1) / 2, cy = (subH - 1) / 2
      let radius = Double(max(0, (min(subW, subH) - 1) / 2))
      let cxSub = Double((subW - 1) / 2)
      let cySub = Double((subH - 1) / 2)
      let dx = px - cxSub
      let dy = py - cySub
      return dx * dx + dy * dy <= radius * radius
    case .ellipse:
      // Matches `paintBrailleShape`'s ellipse case.
      let rx = max(0, (subW - 1) / 2)
      let ry = max(0, (subH - 1) / 2)
      guard rx > 0, ry > 0 else { return false }
      let cxSub = Double((subW - 1) / 2)
      let cySub = Double((subH - 1) / 2)
      let dx = (px - cxSub) / Double(rx)
      let dy = (py - cySub) / Double(ry)
      return dx * dx + dy * dy <= 1
    case .capsule:
      // Matches `drawCapsule`: wide capsules get left/right semicircles
      // joined by a horizontal body rect, tall capsules are transposed.
      if subW == 1 || subH == 1 {
        return true
      }
      if subW >= subH {
        let radius = Double(max(0, (subH - 1) / 2))
        let cySub = Double((subH - 1) / 2)
        let leftCx = radius
        let rightCx = Double(subW - 1) - radius
        if px < leftCx {
          let dx = px - leftCx
          let dy = py - cySub
          return dx * dx + dy * dy <= radius * radius
        } else if px > rightCx {
          let dx = px - rightCx
          let dy = py - cySub
          return dx * dx + dy * dy <= radius * radius
        } else {
          return py >= cySub - radius && py <= cySub + radius
        }
      } else {
        let radius = Double(max(0, (subW - 1) / 2))
        let cxSub = Double((subW - 1) / 2)
        let topCy = radius
        let bottomCy = Double(subH - 1) - radius
        if py < topCy {
          let dx = px - cxSub
          let dy = py - topCy
          return dx * dx + dy * dy <= radius * radius
        } else if py > bottomCy {
          let dx = px - cxSub
          let dy = py - bottomCy
          return dx * dx + dy * dy <= radius * radius
        } else {
          return px >= cxSub - radius && px <= cxSub + radius
        }
      }
    case .rectangle, .roundedRectangle:
      assertionFailure("curvedShapeContains called with non-curved geometry")
      return false
    }
  }

  internal func insetBounds(
    _ bounds: CellRect,
    by inset: Int,
    strokeBorder _: Bool
  ) -> CellRect {
    CellRect(
      origin: CellPoint(
        x: bounds.origin.x + inset,
        y: bounds.origin.y + inset
      ),
      size: CellSize(
        width: max(0, bounds.size.width - (inset * 2)),
        height: max(0, bounds.size.height - (inset * 2))
      )
    )
  }

  /// Returns the background color currently on the raster surface at
  /// the given cell coordinates, or nil if the cell is unstyled or
  /// out of bounds.  Used by ``resolveTextStyle`` to bake fractional
  /// opacity against the actual underlying background (gap item 3).
  internal func currentCellBackground(
    cells: [[RasterCell]],
    x: Int,
    y: Int
  ) -> Color? {
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return nil
    }
    return cells[y][x].style?.backgroundColor
  }

  internal func resolveTextStyle(
    _ style: TextStyle,
    environment: StyleEnvironmentSnapshot,
    bounds: CellRect,
    sampleX: Int,
    sampleY: Int,
    width: Int,
    currentCellBackground: Color? = nil
  ) -> ResolvedTextStyle {
    var foregroundColor = resolveColor(
      from: style.foregroundStyle ?? environment.foregroundStyle ?? .semantic(.foreground),
      environment: environment,
      bounds: bounds,
      sampleX: sampleX + max(0, width - 1) / 2,
      sampleY: sampleY
    )
    let backgroundColor = style.backgroundStyle.flatMap {
      resolveColor(
        from: $0,
        environment: environment,
        bounds: bounds,
        sampleX: sampleX + max(0, width - 1) / 2,
        sampleY: sampleY
      )
    }

    // Bake fractional opacity into the foreground color so animations and
    // `.opacity()` modifiers produce continuously different rendered
    // colors.  Without this, the presentation layer only sees the binary
    // SGR "faint" attribute (`TerminalPresentation.swift`), which gives
    // a single visible "dimmed" step regardless of progress.
    //
    // Blend target priority:
    // 1. Explicit backgroundColor if set — overrides everything.
    // 2. currentCellBackground — whatever is on the raster surface
    //    at this cell right now (typically the background of whatever
    //    container was drawn first at this position).
    // 3. Theme background — ultimate fallback when nothing has been
    //    drawn at this cell yet.
    //
    // The per-cell path closes a gap where fading text rendered over
    // an opaque colored container silently blended toward the theme
    // background instead of the actual background beneath the cell.
    let opacity = style.opacity
    let bakeOpacityIntoForeground = opacity < 1 && opacity >= 0
    if bakeOpacityIntoForeground, let fg = foregroundColor {
      let blendTarget =
        backgroundColor
        ?? currentCellBackground
        ?? environment.theme.background
      foregroundColor = fg.mixed(with: blendTarget, amount: 1 - opacity)
    }

    return ResolvedTextStyle(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      emphasis: style.emphasis,
      underlineStyle: style.underlineStyle,
      strikethroughStyle: style.strikethroughStyle,
      // Reset opacity to 1 after baking so presentation doesn't also
      // emit the SGR "faint" attribute on top of the blended color.
      opacity: bakeOpacityIntoForeground ? 1.0 : opacity
    )
  }

  internal func resolveColor(
    from style: AnyShapeStyle,
    environment: StyleEnvironmentSnapshot,
    bounds: CellRect,
    sampleX: Int,
    sampleY: Int,
    depth: Int = 0
  ) -> Color? {
    resolveColor(
      from: resolvedColorMode(
        from: style,
        environment: environment,
        depth: depth
      ),
      bounds: bounds,
      sampleX: sampleX,
      sampleY: sampleY
    )
  }

  internal func resolvedColorMode(
    from style: AnyShapeStyle,
    environment: StyleEnvironmentSnapshot,
    depth: Int = 0
  ) -> ResolvedShapeColorMode {
    guard depth < 8 else {
      return .constant(nil)
    }

    switch style {
    case .color(let color):
      return .constant(color)
    case .linearGradient(let gradient):
      return .sampled(gradient)
    case .radialGradient(let gradient):
      return .sampledRadial(gradient)
    case .tileStyle(let tile):
      return .tile(tile)
    case .terminalChrome(let chromeStyle):
      return resolvedColorMode(
        from: environment.theme.resolvedStyle(
          for: chromeStyle,
          appearance: environment.appearance
        ),
        environment: environment,
        depth: depth + 1
      )
    case .semantic(let role):
      let candidate = semanticStyleCandidate(
        for: role,
        environment: environment
      )
      let fallback = semanticStyleFallback(
        for: role,
        environment: environment
      )
      let resolvedStyle = candidate == style ? fallback : candidate
      guard resolvedStyle != style else {
        return .constant(nil)
      }
      return resolvedColorMode(
        from: resolvedStyle,
        environment: environment,
        depth: depth + 1
      )
    case .opacity(let inner, let amount):
      guard amount > 0 else {
        return .constant(nil)
      }
      let innerMode = resolvedColorMode(
        from: inner,
        environment: environment,
        depth: depth + 1
      )
      switch innerMode {
      case .constant(let color):
        guard let color else { return .constant(nil) }
        return .constant(color.opacity(amount))
      case .sampled(let gradient):
        let faded = LinearGradient(
          gradient: Gradient(
            stops: gradient.gradient.stops.map {
              .init(color: $0.color.opacity(amount), location: $0.location)
            }),
          startPoint: gradient.startPoint,
          endPoint: gradient.endPoint
        )
        return .sampled(faded)
      case .sampledRadial(let gradient):
        let faded = RadialGradient(
          gradient: Gradient(
            stops: gradient.gradient.stops.map {
              .init(color: $0.color.opacity(amount), location: $0.location)
            }),
          center: gradient.center,
          startRadius: gradient.startRadius,
          endRadius: gradient.endRadius
        )
        return .sampledRadial(faded)
      case .tile(let tile):
        return .tile(tile.applyingOpacity(amount))
      }
    }
  }

  internal func resolveColor(
    from mode: ResolvedShapeColorMode,
    bounds: CellRect,
    sampleX: Int,
    sampleY: Int
  ) -> Color? {
    switch mode {
    case .constant(let color):
      return color
    case .sampled(let gradient):
      return sample(
        gradient,
        in: bounds,
        x: sampleX,
        y: sampleY
      )
    case .sampledRadial(let gradient):
      return sample(
        gradient,
        in: bounds,
        x: sampleX,
        y: sampleY
      )
    case .tile(let tile):
      // Callers that reduce a tile style to a scalar color use the
      // foreground's representative color when one is available. The
      // per-cell glyph write path bypasses this helper and consults the
      // ``TileStyle`` directly via ``resolvedTileCellStyle``.
      return tile.foreground.representativeColor
    }
  }

  internal func resolvedTileCellStyle(
    _ tile: TileStyle,
    bounds: CellRect,
    sampleX: Int,
    sampleY: Int,
    environment: StyleEnvironmentSnapshot
  ) -> ResolvedTextStyle? {
    let fg = resolveColor(
      from: resolvedColorMode(from: tile.foreground.style, environment: environment),
      bounds: bounds,
      sampleX: sampleX,
      sampleY: sampleY
    )
    let bg = tile.background.flatMap {
      resolveColor(
        from: resolvedColorMode(from: $0.style, environment: environment),
        bounds: bounds,
        sampleX: sampleX,
        sampleY: sampleY
      )
    }
    let resolved = ResolvedTextStyle(
      foregroundColor: fg,
      backgroundColor: bg
    )
    return resolved.isDefault ? nil : resolved
  }

  internal func resolvedBackgroundTextStyle(
    colorMode: ResolvedShapeColorMode,
    bounds: CellRect,
    x: Int,
    y: Int
  ) -> ResolvedTextStyle? {
    let resolvedStyle = ResolvedTextStyle(
      backgroundColor: resolveColor(
        from: colorMode,
        bounds: bounds,
        sampleX: x,
        sampleY: y
      )
    )
    return resolvedStyle.isDefault ? nil : resolvedStyle
  }

  internal func semanticStyleCandidate(
    for role: SemanticStyleRole,
    environment: StyleEnvironmentSnapshot
  ) -> AnyShapeStyle {
    environment.resolvedStyle(for: role)
  }

  internal func semanticStyleFallback(
    for role: SemanticStyleRole,
    environment: StyleEnvironmentSnapshot
  ) -> AnyShapeStyle {
    environment.themeStyle(for: role)
  }

}
