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
    clip: CellRect?,
    blendMode: BlendMode? = nil
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
        backgroundStyle: backgroundStyle,
        blendMode: blendMode
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
          clip: clip,
          blendMode: blendMode
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
            clip: clip,
            blendMode: blendMode
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
            clip: clip,
            blendMode: blendMode
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
              clip: clip,
              blendMode: blendMode
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
        clip: clip,
        blendMode: blendMode
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
          clip: clip,
          blendMode: blendMode
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
          clip: clip,
          blendMode: blendMode
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
          clip: clip,
          blendMode: blendMode
        )
      }
    }
  }

  internal func paintRule(
    in bounds: CellRect,
    style: AnyShapeStyle,
    strokeStyle: StrokeStyle,
    stackAxis: Axis?,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    blendMode: BlendMode? = nil
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
          clip: clip,
          blendMode: blendMode
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
          clip: clip,
          blendMode: blendMode
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
    clip: CellRect?,
    blendMode: BlendMode? = nil
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
      clip: clip,
      blendMode: blendMode
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
