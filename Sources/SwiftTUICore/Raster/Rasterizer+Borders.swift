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

    let roundsCorners: Bool
    let startsAtTrailingEdge: Bool
    if case .roundedRectangle(let cornerRadius) = geometry, cornerRadius > 0 {
      roundsCorners = true
      startsAtTrailingEdge = true
    } else {
      roundsCorners = strokeStyle.lineJoin == .round
      startsAtTrailingEdge = false
    }
    let pen = StrokePen(borderSet: strokeStyle.borderSet, roundsCorners: roundsCorners)
    let dash = StrokeDashPattern(dash: strokeStyle.dash, phase: strokeStyle.dashPhase)

    let lineWidth = max(1, strokeStyle.lineWidth)
    for inset in 0..<lineWidth {
      let insetRect = insetBounds(shapeBounds, by: inset)
      guard insetRect.size.width > 0, insetRect.size.height > 0 else {
        continue
      }
      let track = RectangleStrokeTrack(
        width: insetRect.size.width,
        height: insetRect.size.height,
        aspectRatio: environment.cellPixelMetrics.aspectRatio
      )
      track.forEachGlyph(
        pen: pen,
        dash: dash,
        // SwiftUI starts a rounded rectangle's path at the middle of its
        // trailing edge, and a rectangle's at its top-leading corner.
        dashOrigin: startsAtTrailingEdge ? track.trailingEdgeMidpoint : 0,
        // Per-row cull (D70).
        rows: dirtyRows.map { dirtyRows in { dirtyRows.contains(insetRect.origin.y + $0) } }
      ) { cell, glyph in
        let side = track.paintSide(for: cell, sides: .all)
        writeStrokeGlyph(
          glyph,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: side),
          environment: environment,
          bounds: shapeBounds,
          x: insetRect.origin.x + cell.x,
          y: insetRect.origin.y + cell.y,
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
    let drawsHorizontal =
      switch stackAxis {
      case .vertical?:
        true
      case .horizontal?:
        false
      case nil:
        bounds.size.width >= bounds.size.height
      }
    // A rule is a rectangle one row high or one column wide, which the track
    // walks as a line.
    let line: CellRect =
      drawsHorizontal
      ? CellRect(
        origin: .init(x: bounds.origin.x, y: bounds.origin.y + (bounds.size.height / 2)),
        size: .init(width: bounds.size.width, height: 1))
      : CellRect(
        origin: .init(x: bounds.origin.x + (bounds.size.width / 2), y: bounds.origin.y),
        size: .init(width: 1, height: bounds.size.height))
    let track = RectangleStrokeTrack(
      width: line.size.width,
      height: line.size.height,
      aspectRatio: environment.cellPixelMetrics.aspectRatio
    )
    track.forEachGlyph(
      pen: StrokePen(
        borderSet: strokeStyle.borderSet, roundsCorners: strokeStyle.lineJoin == .round),
      dash: StrokeDashPattern(dash: strokeStyle.dash, phase: strokeStyle.dashPhase),
      // Per-row cull (D70).
      rows: dirtyRows.map { dirtyRows in { dirtyRows.contains(line.origin.y + $0) } }
    ) { cell, glyph in
      writeStrokeGlyph(
        glyph,
        foregroundColorMode: foregroundColorMode,
        backgroundStyle: nil,
        environment: environment,
        bounds: bounds,
        x: line.origin.x + cell.x,
        y: line.origin.y + cell.y,
        cells: &cells,
        clip: clip,
        blendMode: blendMode,
        dirtyRows: dirtyRows,
        presentationRecorder: presentationRecorder,
        presentationEffects: presentationEffects
      )
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
