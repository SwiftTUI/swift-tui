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
    blendMode: BlendMode? = nil,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder? = nil,
    presentationEffects: [DrawEffect] = []
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let shapeBounds = insetBounds(bounds, by: max(0, insetAmount))
    guard shapeBounds.size.width > 0, shapeBounds.size.height > 0 else {
      return
    }
    let foregroundColorMode = resolvedColorMode(
      from: style,
      environment: environment,
      bounds: shapeBounds
    )

    // Curved shapes draw their outline onto a Braille canvas so the
    // stroke resolves to sub-cell precision.
    switch geometry {
    case .circle, .ellipse, .capsule, .path:
      // Curved shapes and custom paths stroke their outline onto the Braille
      // canvas at sub-cell precision. For `.path`, `strokeBorder` keeps the
      // outline inside the filled interior (mask intersection).
      paintBrailleShape(
        geometry: geometry,
        shapeBounds: shapeBounds,
        colorMode: foregroundColorMode,
        stroke: true,
        strokeBorder: strokeBorder,
        environment: environment,
        cells: &cells,
        clip: clip,
        backgroundStyle: backgroundStyle,
        blendMode: blendMode,
        dirtyRows: dirtyRows,
        presentationRecorder: presentationRecorder,
        presentationEffects: presentationEffects
      )
      return
    case .rectangle, .roundedRectangle:
      break
    }

    let lineWidth = max(1, strokeStyle.lineWidth)
    for inset in 0..<lineWidth {
      let insetRect = insetBounds(shapeBounds, by: inset)
      guard insetRect.size.width > 0, insetRect.size.height > 0 else {
        continue
      }

      let resolvedSet = strokeStyle.borderSet
      let glyphs = BorderGlyphSet(borderSet: resolvedSet)

      let minX = insetRect.origin.x
      let maxX = insetRect.origin.x + insetRect.size.width - 1
      let minY = insetRect.origin.y
      let maxY = insetRect.origin.y + insetRect.size.height - 1

      // Per-row cull (D70). The top and bottom edges each occupy a single fixed
      // row, so the decision is hoisted out of the column loop rather than
      // retested per cell; the left/right edges are guarded per row below.
      let paintsTopRow = dirtyRows?.contains(minY) ?? true
      let paintsBottomRow = dirtyRows?.contains(maxY) ?? true

      if paintsTopRow || paintsBottomRow {
        for x in minX...maxX {
          if paintsTopRow {
            writeStrokeGlyph(
              glyphs.top,
              foregroundColorMode: foregroundColorMode,
              backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
              environment: environment,
              bounds: shapeBounds,
              x: x,
              y: minY,
              cells: &cells,
              clip: clip,
              blendMode: blendMode,
              dirtyRows: dirtyRows,
              presentationRecorder: presentationRecorder,
              presentationEffects: presentationEffects
            )
          }
          if maxY != minY, paintsBottomRow {
            writeStrokeGlyph(
              glyphs.bottom,
              foregroundColorMode: foregroundColorMode,
              backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
              environment: environment,
              bounds: shapeBounds,
              x: x,
              y: maxY,
              cells: &cells,
              clip: clip,
              blendMode: blendMode,
              dirtyRows: dirtyRows,
              presentationRecorder: presentationRecorder,
              presentationEffects: presentationEffects
            )
          }
        }
      }

      if maxY - minY > 1 {
        for y in (minY + 1)..<maxY {
          // Per-row cull (D70): the side edges walk rows, so each clean row
          // skips two `writeStrokeGlyph` calls and their colour resolution.
          if let dirtyRows, !dirtyRows.contains(y) {
            continue
          }
          writeStrokeGlyph(
            glyphs.left,
            foregroundColorMode: foregroundColorMode,
            backgroundStyle: backgroundStyle?.backgroundStyle(for: .left),
            environment: environment,
            bounds: shapeBounds,
            x: minX,
            y: y,
            cells: &cells,
            clip: clip,
            blendMode: blendMode,
            dirtyRows: dirtyRows,
            presentationRecorder: presentationRecorder,
            presentationEffects: presentationEffects
          )
          if maxX != minX {
            writeStrokeGlyph(
              glyphs.right,
              foregroundColorMode: foregroundColorMode,
              backgroundStyle: backgroundStyle?.backgroundStyle(for: .right),
              environment: environment,
              bounds: shapeBounds,
              x: maxX,
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
      }

      writeStrokeGlyph(
        glyphs.topLeading,
        foregroundColorMode: foregroundColorMode,
        backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
        environment: environment,
        bounds: shapeBounds,
        x: minX,
        y: minY,
        cells: &cells,
        clip: clip,
        blendMode: blendMode,
        dirtyRows: dirtyRows,
        presentationRecorder: presentationRecorder,
        presentationEffects: presentationEffects
      )
      if maxX != minX {
        writeStrokeGlyph(
          glyphs.topTrailing,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
          environment: environment,
          bounds: shapeBounds,
          x: maxX,
          y: minY,
          cells: &cells,
          clip: clip,
          blendMode: blendMode,
          dirtyRows: dirtyRows,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
        )
      }
      if maxY != minY {
        writeStrokeGlyph(
          glyphs.bottomLeading,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
          environment: environment,
          bounds: shapeBounds,
          x: minX,
          y: maxY,
          cells: &cells,
          clip: clip,
          blendMode: blendMode,
          dirtyRows: dirtyRows,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
        )
      }
      if maxX != minX, maxY != minY {
        writeStrokeGlyph(
          glyphs.bottomTrailing,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
          environment: environment,
          bounds: shapeBounds,
          x: maxX,
          y: maxY,
          cells: &cells,
          clip: clip,
          blendMode: blendMode,
          dirtyRows: dirtyRows,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
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
    blendMode: BlendMode? = nil,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder? = nil,
    presentationEffects: [DrawEffect] = []
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let foregroundColorMode = resolvedColorMode(
      from: style,
      environment: environment,
      bounds: bounds
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
      // Per-row cull (D70): a horizontal rule lives on one row, so one test
      // replaces the whole column walk.
      if let dirtyRows, !dirtyRows.contains(y) {
        return
      }
      for x in bounds.origin.x..<(bounds.origin.x + bounds.size.width) {
        writeStrokeGlyph(
          glyphs.horizontal,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: nil,
          environment: environment,
          bounds: bounds,
          x: x,
          y: y,
          cells: &cells,
          clip: clip,
          blendMode: blendMode,
          dirtyRows: dirtyRows,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
        )
      }
    } else {
      let x = bounds.origin.x + (bounds.size.width / 2)
      for y in bounds.origin.y..<(bounds.origin.y + bounds.size.height) {
        // Per-row cull (D70).
        if let dirtyRows, !dirtyRows.contains(y) {
          continue
        }
        writeStrokeGlyph(
          glyphs.vertical,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: nil,
          environment: environment,
          bounds: bounds,
          x: x,
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
  }

  internal func writeStrokeGlyph(
    _ character: Character,
    foregroundColorMode: ResolvedShapeColorMode,
    backgroundStyle: AnyShapeStyle?,
    environment: StyleEnvironmentSnapshot,
    bounds: CellRect,
    x: Int,
    y: Int,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    blendMode: BlendMode? = nil,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder? = nil,
    presentationEffects: [DrawEffect] = []
  ) {
    let resolvedStyle = ResolvedTextStyle(
      foregroundColor: resolveColor(
        from: foregroundColorMode,
        bounds: bounds,
        sampleX: x,
        sampleY: y
      ),
      backgroundColor: resolvedStrokeBackgroundColor(
        explicitBackgroundStyle: backgroundStyle,
        environment: environment,
        bounds: bounds,
        x: x,
        y: y
      )
    )
    write(
      character,
      style: resolvedStyle.isDefault ? nil : resolvedStyle,
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

  /// The background a stroke glyph carries, or `nil` to keep whatever the
  /// cell already holds.
  ///
  /// A stroke never reads another cell. With no explicit per-side background
  /// the glyph has no background of its own and `write` composites it over
  /// the cell's current style (`ResolvedTextStyle.composited(over:)` keeps
  /// the underlay's background), so a ring drawn over its own fill shows that
  /// fill and a ring on bare surface stays bare. The built-in control chrome
  /// insets its fill by the stroke width for exactly this reason: the ring
  /// cells are left holding the surface the control sits on.
  ///
  /// The painter used to infer the background from the neighbouring cell
  /// *outside* the ring. That let a highlighted row above a control, or a
  /// later-painted control below it, bleed into the ring — and because the
  /// read crossed rows it was a paint-order dependency the incremental raster
  /// had to replay (SwiftTUI/swift-tui#5). Keeping the underlay needs no read
  /// at all, and composes correctly under a blend mode, which feeding the
  /// cell's own colour back in as an overlay would not.
  internal func resolvedStrokeBackgroundColor(
    explicitBackgroundStyle: AnyShapeStyle?,
    environment: StyleEnvironmentSnapshot,
    bounds: CellRect,
    x: Int,
    y: Int
  ) -> Color? {
    guard let explicitBackgroundStyle else {
      return nil
    }
    return resolveColor(
      from: explicitBackgroundStyle,
      environment: environment,
      bounds: bounds,
      sampleX: x,
      sampleY: y
    )
  }
}
