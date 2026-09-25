extension Rasterizer {
  internal func paintFill(
    in bounds: CellRect,
    geometry: ShapeGeometry,
    insetAmount: Int,
    style: AnyShapeStyle,
    mode: ShapeFillMode,
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
    let colorMode = resolvedColorMode(
      from: style,
      environment: environment,
      bounds: shapeBounds
    )

    // A nil constant color means the fill is fully transparent — skip painting.
    if case .constant(nil) = colorMode {
      return
    }

    // Curved shapes normally use a Braille subpixel canvas so their
    // edges antialias onto the 2x4 dot grid. Tile styles are the
    // exception: they need per-cell glyph writes, so they fall through
    // to the general cell-walking loop below (which calls
    // `shapeContains`, and that now knows about curved geometry).
    switch geometry {
    case .circle, .ellipse, .capsule:
      // Curved shapes rasterize onto the Braille subpixel canvas (Route A).
      // Tile glyphs and inset background masks use the cell walk (Route B).
      if case .tile = colorMode {
        break
      }
      if case .interior = mode {
        break
      }
      paintBrailleShape(
        geometry: geometry,
        shapeBounds: shapeBounds,
        colorMode: colorMode,
        stroke: false,
        environment: environment,
        cells: &cells,
        clip: clip,
        blendMode: blendMode,
        dirtyRows: dirtyRows,
        presentationRecorder: presentationRecorder,
        presentationEffects: presentationEffects
      )
      return
    case .path:
      // Full foreground fills rasterize as Braille dots (Route A). Tile fills
      // and masked-background fills (`.interior` mode — e.g. a custom-path
      // border clipping a background) fall through to the cell-walk (Route B),
      // which writes per-cell glyphs / backgrounds and honors the inset, via
      // the now-path-aware `shapeContains`.
      if case .tile = colorMode {
        break
      }
      if case .interior = mode {
        break
      }
      paintBrailleShape(
        geometry: geometry,
        shapeBounds: shapeBounds,
        colorMode: colorMode,
        stroke: false,
        environment: environment,
        cells: &cells,
        clip: clip,
        blendMode: blendMode,
        dirtyRows: dirtyRows,
        presentationRecorder: presentationRecorder,
        presentationEffects: presentationEffects
      )
      return
    case .rectangle, .roundedRectangle:
      break
    }

    // Walk only the cells the writers could touch (STUI-618). `write` and
    // `tintCell` already no-op outside the surface and the clip and skip
    // non-dirty rows, so intersecting the walked rectangle with those first
    // changes no output; it only stops the geometry test and the per-cell
    // colour resolution from running for cells that were always going to be
    // dropped. The gradient stays anchored to `shapeBounds`: narrowing the
    // walk must not move its centre or change its colours.
    guard let walkRect = fillWalkRect(shapeBounds: shapeBounds, clip: clip, cells: cells) else {
      return
    }
    var work = RasterWorkCounters()
    work.fills = 1
    let probe = RasterWorkProbe.active()
    defer { probe?.record(work) }

    // Detect whether this fill carries alpha for the tint path.
    let constantColor: Color?
    let isTranslucent: Bool
    let tileStyle: ResolvedTileColorMode?
    switch colorMode {
    case .constant(let color):
      constantColor = color
      isTranslucent = (color?.alpha ?? 0) < 1
      tileStyle = nil
    case .sampled, .sampledRadial, .sampledAngular, .sampledMesh:
      constantColor = nil
      // Sampled (gradient) fills may have per-stop alpha.
      isTranslucent = false
      tileStyle = nil
    case .tile(let tile):
      constantColor = nil
      isTranslucent = false
      tileStyle = tile
    }

    // A radial fill whose stops prove a bounded transparent support visits
    // only the cells inside that support (§4C). Every other fill — and every
    // fill under the equivalence switch — takes the full walk below.
    if tileStyle == nil, constantColor == nil, !isTranslucent,
      case .sampledRadial(let prepared) = colorMode,
      let support = prepared.support,
      !Rasterizer.forceReferenceRadialWalk
    {
      paintRadialSupportFill(
        prepared: prepared,
        support: support,
        walkRect: walkRect,
        shapeBounds: shapeBounds,
        geometry: geometry,
        mode: mode,
        environment: environment,
        cells: &cells,
        clip: clip,
        blendMode: blendMode,
        dirtyRows: dirtyRows,
        presentationRecorder: presentationRecorder,
        presentationEffects: presentationEffects,
        work: &work
      )
      return
    }

    let rowStart = max(walkRect.origin.x, 0)
    for y in walkRect.origin.y..<(walkRect.origin.y + walkRect.size.height) {
      // Per-row cull (D70): skips `shapeContains` and the per-cell colour
      // resolution below for rows `write` would clamp away anyway.
      if let dirtyRows, !dirtyRows.contains(y) {
        continue
      }
      var x = rowStart
      let rowEnd = min(walkRect.origin.x + walkRect.size.width, cells[y].count)
      while x < rowEnd {
        work.visitedCells += 1
        guard
          shapeContains(
            pointX: x,
            pointY: y,
            in: shapeBounds,
            geometry: geometry,
            fillMode: mode,
            metrics: environment.cellPixelMetrics
          )
        else {
          x += 1
          continue
        }

        if let tileStyle {
          // Tile style: overwrite the cell with the pattern glyph using
          // the tile's foreground and optional background, resolved per
          // cell so gradient paints sample at the current point.
          let localX = x - shapeBounds.origin.x
          let localY = y - shapeBounds.origin.y
          write(
            tileStyle.pattern.character(atX: localX, y: localY),
            style: resolvedTileCellStyle(
              tileStyle,
              bounds: shapeBounds,
              sampleX: x,
              sampleY: y
            ),
            atX: x,
            y: y,
            cells: &cells,
            clip: clip,
            blendMode: blendMode,
            dirtyRows: dirtyRows,
            presentationRecorder: presentationRecorder,
            presentationEffects: presentationEffects
          )
          x += 1
          continue
        }

        if isTranslucent {
          if let color = constantColor, color.alpha > 0 {
            if let blendMode {
              let resolvedStyle = ResolvedTextStyle(backgroundColor: color)
              work.blendedWrites += 1
              write(
                " ",
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
            } else {
              // Translucent constant fill: tint existing cell in-place.
              tintCell(
                atX: x,
                y: y,
                with: color,
                cells: &cells,
                clip: clip,
                dirtyRows: dirtyRows,
                presentationRecorder: presentationRecorder,
                presentationEffects: presentationEffects
              )
            }
          }
        } else if let constantColor {
          // Opaque constant fill: overwrite cell.
          let resolvedStyle = ResolvedTextStyle(backgroundColor: constantColor)
          if blendMode != nil {
            work.blendedWrites += 1
          }
          write(
            " ",
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
        } else {
          // Sampled (gradient) fill: resolve per-cell.
          let fillColor = resolveColor(
            from: colorMode,
            bounds: shapeBounds,
            sampleX: x,
            sampleY: y
          )
          if case .sampledRadial = colorMode {
            work.radialSamples += 1
          }
          paintSampledFillCell(
            fillColor,
            colorMode: colorMode,
            shapeBounds: shapeBounds,
            atX: x,
            y: y,
            cells: &cells,
            clip: clip,
            blendMode: blendMode,
            dirtyRows: dirtyRows,
            presentationRecorder: presentationRecorder,
            presentationEffects: presentationEffects,
            work: &work
          )
        }
        x += 1
      }
    }
  }

  /// The rectangle a fill's cell walk has to visit: `shapeBounds` clipped to
  /// the surface's rows and to `clip`. Columns are clamped per row by the
  /// callers (`cells[y].count`), so a ragged surface is handled the way
  /// `write` handles it. `nil` when nothing can be painted.
  private func fillWalkRect(
    shapeBounds: CellRect,
    clip: CellRect?,
    cells: [[RasterCell]]
  ) -> CellRect? {
    let surfaceRows = CellRect(
      origin: CellPoint(x: shapeBounds.origin.x, y: 0),
      size: CellSize(width: shapeBounds.size.width, height: cells.count)
    )
    guard let onSurface = intersect(shapeBounds, surfaceRows) else {
      return nil
    }
    guard let clip else {
      return onSurface
    }
    return intersect(onSurface, clip)
  }

  /// Paints one sampled-fill cell from the colour already resolved for it.
  ///
  /// Mirrors the reference per-cell body: a partially transparent sample
  /// blends (or tints) the cell, a fully transparent one writes nothing and
  /// records nothing, and an opaque sample overwrites the cell. The reference
  /// resolved an opaque sample a second time to build its style; the sampler
  /// is a pure function of the colour mode, bounds, and cell, so the style
  /// built from the sample in hand is the same style. Under the equivalence
  /// switch the second resolution is kept so the switch reproduces the
  /// reference byte for byte.
  private func paintSampledFillCell(
    _ fillColor: Color?,
    colorMode: ResolvedShapeColorMode,
    shapeBounds: CellRect,
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    blendMode: BlendMode?,
    dirtyRows: Set<Int>?,
    presentationRecorder: RasterPresentationLayerRecorder?,
    presentationEffects: [DrawEffect],
    work: inout RasterWorkCounters
  ) {
    if let fillColor, fillColor.alpha < 1 {
      if fillColor.alpha > 0 {
        if let blendMode {
          let resolvedStyle = ResolvedTextStyle(backgroundColor: fillColor)
          work.blendedWrites += 1
          write(
            " ",
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
        } else {
          tintCell(
            atX: x,
            y: y,
            with: fillColor,
            cells: &cells,
            clip: clip,
            dirtyRows: dirtyRows,
            presentationRecorder: presentationRecorder,
            presentationEffects: presentationEffects
          )
        }
      } else {
        work.zeroAlphaSkips += 1
      }
      return
    }

    let style: ResolvedTextStyle?
    if Rasterizer.forceReferenceRadialWalk {
      style = resolvedBackgroundTextStyle(
        colorMode: colorMode,
        bounds: shapeBounds,
        x: x,
        y: y
      )
    } else {
      let resolvedStyle = ResolvedTextStyle(backgroundColor: fillColor)
      style = resolvedStyle.isDefault ? nil : resolvedStyle
    }
    if blendMode != nil {
      work.blendedWrites += 1
    }
    write(
      " ",
      style: style,
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

  /// Walks a radial fill's transparent support only (§4C).
  ///
  /// For each row the aspect-corrected vertical offset from the centre is
  /// fixed, so the cells whose centre distance can fall inside the open
  /// annulus `(inner, outer)` form at most two horizontal spans: the outer
  /// circle's chord, minus the inner circle's chord when the row crosses the
  /// hole. Each span is widened by one whole cell (the hole narrowed by one),
  /// and every candidate cell still goes through the reference sampler and the
  /// reference zero-alpha skip. That is why floating-point rounding in the
  /// chord arithmetic cannot omit a contributing cell: the arithmetic is
  /// accurate to far better than a cell, and a cell that lands inside the
  /// margin but samples to zero alpha is dropped by the same test the full
  /// walk applies. Rows are visited top to bottom and spans left to right,
  /// so the surviving writes — and their presentation-record fragments — occur
  /// in exactly the reference order.
  private func paintRadialSupportFill(
    prepared: PreparedRadialGradient,
    support: PreparedRadialGradient.Support,
    walkRect: CellRect,
    shapeBounds: CellRect,
    geometry: ShapeGeometry,
    mode: ShapeFillMode,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    blendMode: BlendMode?,
    dirtyRows: Set<Int>?,
    presentationRecorder: RasterPresentationLayerRecorder?,
    presentationEffects: [DrawEffect],
    work: inout RasterWorkCounters
  ) {
    let outerRadius = support.outerRadius
    let innerRadius = support.innerRadius
    // Whole-layer cull. The farthest cell centre is a corner cell (the
    // distance is convex), and half a cell of margin absorbs rounding.
    if outerRadius <= 0
      || innerRadius > prepared.farthestCellCenterDistance(in: walkRect) + 0.5
    {
      work.culledLayers += 1
      return
    }
    let outerSquared = outerRadius * outerRadius
    let innerSquared = innerRadius * innerRadius
    let centerX = prepared.centerX
    let rowStart = max(walkRect.origin.x, 0)
    var segmentHint = 0

    for y in walkRect.origin.y..<(walkRect.origin.y + walkRect.size.height) {
      if let dirtyRows, !dirtyRows.contains(y) {
        work.skippedRows += 1
        continue
      }
      let rowEnd = min(walkRect.origin.x + walkRect.size.width, cells[y].count)
      guard rowStart < rowEnd else {
        continue
      }
      let dy = (Double(y) + 0.5 - prepared.centerY) * prepared.aspectRatio
      let dySquared = dy * dy
      guard dySquared < outerSquared else {
        work.skippedRows += 1
        continue
      }
      work.spanRows += 1

      // Cells with `|dx| < outerHalfWidth` are the only candidates; in cell
      // indices that is the open interval `(cx - w - 0.5, cx + w - 0.5)`,
      // widened here by one cell on each side.
      let outerHalfWidth = (outerSquared - dySquared).squareRoot()
      let spanStart = Self.clampedCell(
        (centerX - outerHalfWidth - 0.5).rounded(.down),
        lower: rowStart, upper: rowEnd)
      let spanEnd = Self.clampedCell(
        (centerX + outerHalfWidth - 0.5).rounded(.up) + 1,
        lower: rowStart, upper: rowEnd)
      guard spanStart < spanEnd else {
        continue
      }

      // The hole: cells with `|dx| ≤ innerHalfWidth` sample inside the inner
      // radius. The closed interval `[cx - w - 0.5, cx + w - 0.5]` is
      // narrowed by one cell on each side before being cut out.
      var holeStart = spanEnd
      var holeEnd = spanEnd
      if innerSquared > dySquared {
        let innerHalfWidth = (innerSquared - dySquared).squareRoot()
        holeStart = Self.clampedCell(
          (centerX - innerHalfWidth - 0.5).rounded(.up) + 1,
          lower: spanStart, upper: spanEnd)
        holeEnd = Self.clampedCell(
          (centerX + innerHalfWidth - 0.5).rounded(.down),
          lower: spanStart, upper: spanEnd)
        if holeStart >= holeEnd {
          holeStart = spanEnd
          holeEnd = spanEnd
        }
      }

      for span in [spanStart..<holeStart, holeEnd..<spanEnd] where !span.isEmpty {
        for x in span {
          work.visitedCells += 1
          guard
            shapeContains(
              pointX: x,
              pointY: y,
              in: shapeBounds,
              geometry: geometry,
              fillMode: mode,
              metrics: environment.cellPixelMetrics
            )
          else {
            continue
          }
          work.radialSamples += 1
          let fillColor = prepared.color(atCellX: x, y: y, segmentHint: &segmentHint)
          paintSampledFillCell(
            fillColor,
            colorMode: .sampledRadial(prepared),
            shapeBounds: shapeBounds,
            atX: x,
            y: y,
            cells: &cells,
            clip: clip,
            blendMode: blendMode,
            dirtyRows: dirtyRows,
            presentationRecorder: presentationRecorder,
            presentationEffects: presentationEffects,
            work: &work
          )
        }
      }
    }
  }

  /// Converts a chord endpoint to a cell index, saturating at the row's
  /// bounds so an enormous radius cannot overflow the conversion.
  private static func clampedCell(_ value: Double, lower: Int, upper: Int) -> Int {
    guard !value.isNaN else {
      return lower
    }
    if value <= Double(lower) {
      return lower
    }
    if value >= Double(upper) {
      return upper
    }
    return Int(value)
  }

  /// Paints a ``Canvas`` view's drawing into the raster buffer.
  ///
  /// Canvas is the arbitrary-drawing escape hatch that sits alongside
  /// the shape pipeline: the layout engine reserves the cell frame, and
  /// here we build a ``CanvasContext`` sized to those cells, invoke the
  /// user's drawing, and copy its direct-cell and grid-glyph layers into
  /// the raster buffer.
  internal func paintCanvasDrawing(
    in bounds: CellRect,
    payload: CanvasPayload,
    foregroundStyle: AnyShapeStyle,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    blendMode: BlendMode? = nil,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder? = nil,
    presentationEffects: [DrawEffect] = []
  ) {
    let cellW = bounds.size.width
    let cellH = bounds.size.height
    guard cellW > 0, cellH > 0 else {
      return
    }

    let initialForeground =
      resolveColor(
        from: foregroundStyle,
        environment: environment,
        bounds: bounds,
        sampleX: bounds.origin.x,
        sampleY: bounds.origin.y
      )
      ?? environment.theme.foreground

    var context = CanvasContext(
      canvas: CanvasGridBuffer(
        size: CellSize(width: cellW, height: cellH),
        grid: payload.grid
      ),
      foreground: initialForeground,
      background: nil
    )
    guard context.size.width > 0, context.size.height > 0 else {
      return
    }
    payload.drawing.draw(into: &context)

    let originX = bounds.origin.x
    let originY = bounds.origin.y

    // Direct cells paint first so Braille drawing can layer foreground
    // dots over dense per-cell backgrounds.
    for cellY in 0..<cellH {
      // Per-row cull (D70). The subpixel loops that built this canvas write
      // only into the in-memory `CanvasGridBuffer`, never into `cells`, so this
      // cell-row loop is the only surface-touching one and it maps 1:1 to
      // surface rows.
      if let dirtyRows, !dirtyRows.contains(originY + cellY) {
        continue
      }
      for cellX in 0..<cellW {
        guard let cell = context.directCells[cellY][cellX] else {
          continue
        }
        let cellStyle = ResolvedTextStyle(
          foregroundColor: cell.foreground?.opacity(payload.opacity),
          backgroundColor: cell.background?.opacity(payload.opacity)
        )
        write(
          cell.character,
          style: cellStyle.isDefault ? nil : cellStyle,
          atX: originX + cellX,
          y: originY + cellY,
          cells: &cells,
          clip: clip,
          blendMode: blendMode,
          dirtyRows: dirtyRows,
          presentationRecorder: presentationRecorder,
          presentationEffects: presentationEffects
        )
      }
    }

    // Walk the grid canvas and emit a glyph for every cell the drawing
    // touched. Styled sample writes carry one style per terminal cell;
    // unstyled cells fall back to the context's final foreground/background
    // values.
    let finalForeground = context.foreground
    let finalBackground = context.background
    let fallbackStyle = ResolvedTextStyle(
      foregroundColor: finalForeground,
      backgroundColor: finalBackground
    )

    for cellY in 0..<cellH {
      // Per-row cull (D70).
      if let dirtyRows, !dirtyRows.contains(originY + cellY) {
        continue
      }
      for cellX in 0..<cellW {
        guard let character = context.canvas.character(x: cellX, y: cellY) else {
          continue
        }
        var resolvedStyle = context.gridCellStyles[cellY][cellX] ?? fallbackStyle
        resolvedStyle.foregroundColor = resolvedStyle.foregroundColor?.opacity(payload.opacity)
        resolvedStyle.backgroundColor = resolvedStyle.backgroundColor?.opacity(payload.opacity)
        let styleToWrite: ResolvedTextStyle? =
          resolvedStyle.isDefault ? nil : resolvedStyle
        write(
          character,
          style: styleToWrite,
          atX: originX + cellX,
          y: originY + cellY,
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

  /// Rasterizes a curved shape (`.circle`, `.ellipse`, `.capsule`)
  /// into the Braille subpixel canvas and writes each non-blank cell
  /// into the raster buffer with the resolved foreground color.
  ///
  /// - Parameter stroke: When `true` draws the outline only; otherwise
  ///   fills the interior.
  internal func paintBrailleShape(
    geometry: ShapeGeometry,
    shapeBounds: CellRect,
    colorMode: ResolvedShapeColorMode,
    stroke: Bool,
    strokeBorder: Bool = false,
    strokeStyle: StrokeStyle? = nil,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    backgroundStyle: BorderBackgroundStyle? = nil,
    blendMode: BlendMode? = nil,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder? = nil,
    presentationEffects: [DrawEffect] = []
  ) {
    let cellW = shapeBounds.size.width
    let cellH = shapeBounds.size.height
    guard cellW > 0, cellH > 0 else {
      return
    }

    var canvas = BrailleCanvas(width: cellW, height: cellH)
    let subW = canvas.subpixelWidth
    let subH = canvas.subpixelHeight
    guard subW > 0, subH > 0 else {
      return
    }
    // Center the shape in the subpixel grid.  `(subW - 1) / 2` keeps
    // the anchor on an integer subpixel even for odd/even widths.
    let cx = (subW - 1) / 2
    let cy = (subH - 1) / 2

    // A dash or a trim keeps part of the outline. The stroke is rasterized as
    // it always was, and the mask then clears the lit subpixels it turns off,
    // so a solid stroke is untouched. Each branch records its ordered outline
    // only when there is a mask to apply.
    let mask = stroke ? strokeStyle.map { StrokeMask($0) } : nil
    let needsOutline = mask.map { !$0.isSolid } ?? false
    let aspectRatio = environment.cellPixelMetrics.aspectRatio
    var outline: SampledStrokeTrack?

    switch geometry {
    case .circle:
      let radii = Self.subpixelCircleRadii(
        frameCells: CellSize(width: cellW, height: cellH),
        metrics: environment.cellPixelMetrics
      )
      // Preserve the (min-1)/2 inclusive-bound semantics of the pre-correction
      // code: at 8x16 metrics, radii.rx == radii.ry == old `(min(subW, subH) - 1) / 2 + 1`
      // (integer off-by-one irrelevant here — we subtract 1 to keep the
      // outline inside the (0...sub-1) coordinate range).
      let rx = max(0, radii.rx - 1)
      let ry = max(0, radii.ry - 1)
      if stroke {
        canvas.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
        if needsOutline {
          outline = .ellipse(
            centerX: cx, centerY: cy, radiusX: rx, radiusY: ry, aspectRatio: aspectRatio)
        }
      } else {
        canvas.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      }
    case .ellipse:
      // Compute semi-axes in pixel space, then convert back to sub-pixel
      // coordinates using the current sub-pixel dimensions. The `-1` preserves
      // inclusive-bound semantics so the outline stays within (0...sub-1).
      // At 8x16 metrics (the default), this reproduces the pre-correction
      // output exactly because sub-pixels are square.
      let radii = Self.subpixelEllipseRadii(
        frameCells: shapeBounds.size, metrics: environment.cellPixelMetrics)
      let rx = max(0, radii.rx - 1)
      let ry = max(0, radii.ry - 1)
      if stroke {
        canvas.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
        if needsOutline {
          outline = .ellipse(
            centerX: cx, centerY: cy, radiusX: rx, radiusY: ry, aspectRatio: aspectRatio)
        }
      } else {
        canvas.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      }
    case .capsule:
      drawCapsule(into: &canvas, stroke: stroke, metrics: environment.cellPixelMetrics)
      if needsOutline, subW > 1, subH > 1 {
        let cap = Self.capsuleCapParameters(
          subpixelWidth: subW, subpixelHeight: subH, metrics: environment.cellPixelMetrics)
        outline = .capsule(
          subpixelWidth: subW, subpixelHeight: subH,
          isHorizontal: cap.isHorizontal, radiusX: cap.radiusX, radiusY: cap.radiusY,
          aspectRatio: aspectRatio)
      }
    case .path(let boxed, let rule):
      if stroke {
        if strokeBorder {
          strokeBorderPath(boxed.path, rule: rule, into: &canvas)
        } else {
          strokePath(boxed.path, into: &canvas)
        }
        if needsOutline {
          outline = .path(
            boxed.path, subpixelWidth: subW, subpixelHeight: subH, aspectRatio: aspectRatio)
        }
      } else {
        fillPath(boxed.path, rule: rule, into: &canvas)
      }
    case .rectangle, .roundedRectangle:
      // Not reachable: the caller dispatches these to the cell-aligned
      // paint path.  We still need the case for exhaustiveness.
      return
    }

    if let mask, let outline {
      outline.apply(mask, to: &canvas)
    }

    // Walk each Braille cell and emit the glyph with the shape's
    // resolved foreground color.  Empty cells (mask == 0) are skipped
    // so we don't overwrite anything already on the surface.
    let originX = shapeBounds.origin.x
    let originY = shapeBounds.origin.y
    let backgroundMode: ResolvedShapeColorMode? =
      backgroundStyle
      .flatMap { $0.backgroundStyle(for: .top) }
      .map { style in
        resolvedColorMode(from: style, environment: environment, bounds: shapeBounds)
      }

    for cellY in 0..<cellH {
      // Per-row cull (D70): skips the per-cell `resolveColor` — gradient and
      // mesh sampling included — for rows outside the exact damage. The Braille
      // subpixel work above touches only the local canvas, so this is the one
      // loop that reaches the surface.
      if let dirtyRows, !dirtyRows.contains(originY + cellY) {
        continue
      }
      for cellX in 0..<cellW {
        let cell = canvas.cell(x: cellX, y: cellY)
        guard cell.mask != 0 else {
          continue
        }
        let targetX = originX + cellX
        let targetY = originY + cellY
        let foregroundColor = resolveColor(
          from: colorMode,
          bounds: shapeBounds,
          sampleX: targetX,
          sampleY: targetY
        )
        let resolved = ResolvedTextStyle(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundMode.flatMap {
            resolveColor(from: $0, bounds: shapeBounds, sampleX: targetX, sampleY: targetY)
          }
        )
        write(
          cell.glyph,
          style: resolved.isDefault ? nil : resolved,
          atX: targetX,
          y: targetY,
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

  /// Draws a capsule into the Braille canvas. A wide capsule (pxWidth >=
  /// pxHeight in pixel space) has a rectangular body flanked by two
  /// aspect-corrected half-ellipses at the left and right ends; a tall
  /// capsule has its semi-ellipses at the top and bottom.
  internal func drawCapsule(
    into canvas: inout BrailleCanvas,
    stroke: Bool,
    metrics: CellPixelMetrics
  ) {
    let subW = canvas.subpixelWidth
    let subH = canvas.subpixelHeight
    guard subW > 0, subH > 0 else {
      return
    }
    if subW == 1 || subH == 1 {
      // Degenerate: just fill/stroke the whole strip.
      canvas.fillRect(x: 0, y: 0, width: subW, height: subH)
      return
    }

    let cap = Self.capsuleCapParameters(
      subpixelWidth: subW, subpixelHeight: subH, metrics: metrics)
    let rx = cap.radiusX
    let ry = cap.radiusY

    if cap.isHorizontal {
      // Wide capsule: caps on left/right, body connects horizontally.
      let cy = (subH - 1) / 2
      let leftCx = rx
      let rightCx = subW - 1 - rx
      if stroke {
        strokeEllipseSegment(
          into: &canvas,
          centerX: leftCx,
          centerY: cy,
          radiusX: rx,
          radiusY: ry
        ) { x, _ in
          x <= leftCx
        }
        strokeEllipseSegment(
          into: &canvas,
          centerX: rightCx,
          centerY: cy,
          radiusX: rx,
          radiusY: ry
        ) { x, _ in
          x >= rightCx
        }
        // Top and bottom body edges between the two centers.
        if rightCx > leftCx {
          for x in leftCx...rightCx {
            canvas.setPixel(x: x, y: cy - ry)
            canvas.setPixel(x: x, y: cy + ry)
          }
        }
      } else {
        canvas.fillEllipse(centerX: leftCx, centerY: cy, radiusX: rx, radiusY: ry)
        canvas.fillEllipse(centerX: rightCx, centerY: cy, radiusX: rx, radiusY: ry)
        if rightCx > leftCx {
          let bodyWidth = rightCx - leftCx + 1
          canvas.fillRect(
            x: leftCx,
            y: max(0, cy - ry),
            width: bodyWidth,
            height: min(subH, 2 * ry + 1)
          )
        }
      }
    } else {
      // Tall capsule: caps on top/bottom, body connects vertically.
      let cx = (subW - 1) / 2
      let topCy = ry
      let bottomCy = subH - 1 - ry
      if stroke {
        strokeEllipseSegment(
          into: &canvas,
          centerX: cx,
          centerY: topCy,
          radiusX: rx,
          radiusY: ry
        ) { _, y in
          y <= topCy
        }
        strokeEllipseSegment(
          into: &canvas,
          centerX: cx,
          centerY: bottomCy,
          radiusX: rx,
          radiusY: ry
        ) { _, y in
          y >= bottomCy
        }
        if bottomCy > topCy {
          for y in topCy...bottomCy {
            canvas.setPixel(x: cx - rx, y: y)
            canvas.setPixel(x: cx + rx, y: y)
          }
        }
      } else {
        canvas.fillEllipse(centerX: cx, centerY: topCy, radiusX: rx, radiusY: ry)
        canvas.fillEllipse(centerX: cx, centerY: bottomCy, radiusX: rx, radiusY: ry)
        if bottomCy > topCy {
          let bodyHeight = bottomCy - topCy + 1
          canvas.fillRect(
            x: max(0, cx - rx),
            y: topCy,
            width: min(subW, 2 * rx + 1),
            height: bodyHeight
          )
        }
      }
    }
  }

  private func strokeEllipseSegment(
    into canvas: inout BrailleCanvas,
    centerX: Int,
    centerY: Int,
    radiusX: Int,
    radiusY: Int,
    include: (Int, Int) -> Bool
  ) {
    var ellipse = BrailleCanvas(width: canvas.width, height: canvas.height)
    ellipse.strokeEllipse(centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY)

    for y in 0..<ellipse.subpixelHeight {
      for x in 0..<ellipse.subpixelWidth where include(x, y) {
        guard brailleCanvasPixelIsLit(ellipse, x: x, y: y) else {
          continue
        }
        canvas.setPixel(x: x, y: y)
      }
    }
  }

  private func brailleCanvasPixelIsLit(_ canvas: BrailleCanvas, x: Int, y: Int) -> Bool {
    canvas.cell(x: x / 2, y: y / 4).contains(x: x % 2, y: y % 4)
  }

  internal func tintCell(
    atX x: Int,
    y: Int,
    with overlay: Color,
    cells: inout [[RasterCell]],
    clip: CellRect?,
    dirtyRows: Set<Int>? = nil,
    presentationRecorder: RasterPresentationLayerRecorder? = nil,
    presentationEffects: [DrawEffect] = []
  ) {
    // See `write(_:...dirtyRows:)` — the incremental exact-set clamp (F125).
    // Tinting reads the destination cell, so re-tinting an un-cleared row
    // is the canonical drift.
    if let dirtyRows, !dirtyRows.contains(y) {
      return
    }
    if let clip {
      guard
        x >= clip.origin.x,
        x < clip.origin.x + clip.size.width,
        y >= clip.origin.y,
        y < clip.origin.y + clip.size.height
      else {
        return
      }
    }
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }
    var cell = cells[y][x]
    cell.style = (cell.style ?? .init()).tinted(with: overlay)
    cells[y][x] = cell
    presentationRecorder?.appendCellFragment(
      from: cells,
      x: x,
      y: y,
      width: max(1, cell.spanWidth),
      effects: presentationEffects
    )
  }

}
