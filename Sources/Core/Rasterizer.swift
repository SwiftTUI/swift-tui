/// Converts draw commands into a terminal cell surface.
public struct Rasterizer {
  private static let emptyCompositingStyle = ResolvedTextStyle()
  private enum ResolvedShapeColorMode {
    case constant(Color?)
    case sampled(LinearGradient)
  }

  public init() {}

  /// Rasterizes a draw tree into a ``RasterSurface``.
  public func rasterize(_ draw: DrawNode) -> RasterSurface {
    let extent = maximumExtent(for: draw, clip: nil)
    let surfaceSize = Size(width: extent.x, height: extent.y)
    guard surfaceSize.width > 0, surfaceSize.height > 0 else {
      return RasterSurface()
    }

    var cells = Array(
      repeating: Array(repeating: RasterCell.empty, count: surfaceSize.width),
      count: surfaceSize.height
    )
    var imageAttachments: [RasterImageAttachment] = []
    paint(
      node: draw,
      cells: &cells,
      imageAttachments: &imageAttachments,
      clip: nil
    )

    return RasterSurface(
      size: surfaceSize,
      cells: cells,
      imageAttachments: imageAttachments
    )
  }
}

extension Rasterizer {
  private func maximumExtent(
    for node: DrawNode,
    clip: Rect?
  ) -> (x: Int, y: Int) {
    let effectiveClip = intersect(clip, node.clipBounds)
    let visibleBounds =
      effectiveClip.flatMap { clip in
        intersect(node.bounds, clip)
      } ?? node.bounds

    var maxX = visibleBounds.origin.x + visibleBounds.size.width
    var maxY = visibleBounds.origin.y + visibleBounds.size.height

    for child in node.children {
      let childExtent = maximumExtent(for: child, clip: effectiveClip)
      maxX = max(maxX, childExtent.x)
      maxY = max(maxY, childExtent.y)
    }

    return (x: maxX, y: maxY)
  }

  private func paint(
    node: DrawNode,
    cells: inout [[RasterCell]],
    imageAttachments: inout [RasterImageAttachment],
    clip: Rect?
  ) {
    let effectiveClip = intersect(clip, node.clipBounds)
    for command in node.commands {
      paint(
        command: command,
        environment: node.environmentSnapshot.style,
        cells: &cells,
        imageAttachments: &imageAttachments,
        clip: effectiveClip
      )
    }

    for child in node.children {
      paint(
        node: child,
        cells: &cells,
        imageAttachments: &imageAttachments,
        clip: effectiveClip
      )
    }
  }

  private func paint(
    command: DrawCommand,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    imageAttachments: inout [RasterImageAttachment],
    clip: Rect?
  ) {
    switch command {
    case .group(_, let children):
      for child in children {
        paint(
          command: child,
          environment: environment,
          cells: &cells,
          imageAttachments: &imageAttachments,
          clip: clip
        )
      }
    case .text(
      let bounds,
      let content,
      let style,
      let lineLimit,
      let truncationMode,
      let wrappingStrategy
    ):
      guard bounds.size.height > 0, bounds.size.width > 0 else {
        return
      }

      let layout = layoutText(
        for: content,
        width: bounds.size.width,
        lineLimit: lineLimit,
        truncationMode: truncationMode,
        wrappingStrategy: wrappingStrategy
      )

      for (lineIndex, line) in layout.lines.prefix(bounds.size.height).enumerated() {
        var x = bounds.origin.x
        for cluster in line.clusters {
          guard x + cluster.cellWidth <= bounds.origin.x + bounds.size.width else {
            break
          }

          let resolvedStyle = resolveTextStyle(
            style,
            environment: environment,
            bounds: bounds,
            sampleX: x,
            sampleY: bounds.origin.y + lineIndex,
            width: cluster.cellWidth
          )

          write(
            cluster.character,
            width: cluster.cellWidth,
            style: resolvedStyle.isDefault ? nil : resolvedStyle,
            atX: x,
            y: bounds.origin.y + lineIndex,
            cells: &cells,
            clip: clip
          )
          x += cluster.cellWidth
          if x >= bounds.origin.x + bounds.size.width {
            break
          }
        }
      }
    case .richText(
      let bounds,
      let payload,
      let lineLimit,
      let truncationMode,
      let wrappingStrategy
    ):
      guard bounds.size.height > 0, bounds.size.width > 0 else {
        return
      }

      let layout = layoutRichText(
        for: payload,
        options: .init(
          width: bounds.size.width,
          lineLimit: lineLimit,
          truncationMode: truncationMode,
          wrappingStrategy: wrappingStrategy
        )
      )

      for (lineIndex, line) in layout.lines.prefix(bounds.size.height).enumerated() {
        var x = bounds.origin.x
        for cluster in line.clusters {
          guard x + cluster.cellWidth <= bounds.origin.x + bounds.size.width else {
            break
          }

          let run = cluster.runIndex.flatMap { runIndex in
            payload.runs.indices.contains(runIndex) ? payload.runs[runIndex] : nil
          }
          let resolvedStyle = resolveTextStyle(
            run?.style ?? .init(),
            environment: environment,
            bounds: bounds,
            sampleX: x,
            sampleY: bounds.origin.y + lineIndex,
            width: cluster.cellWidth
          )

          write(
            cluster.character,
            width: cluster.cellWidth,
            style: resolvedStyle.isDefault ? nil : resolvedStyle,
            hyperlink: run?.destination?.rawValue,
            atX: x,
            y: bounds.origin.y + lineIndex,
            cells: &cells,
            clip: clip
          )
          x += cluster.cellWidth
          if x >= bounds.origin.x + bounds.size.width {
            break
          }
        }
      }
    case .image(let bounds, let identity, let payload):
      imageAttachments.append(
        RasterImageAttachment(
          identity: identity,
          bounds: bounds,
          source: payload.source,
          resolvedReference: payload.resolvedAsset?.reference,
          pixelSize: payload.resolvedAsset?.pixelSize,
          isResizable: payload.isResizable,
          scalingMode: payload.scalingMode
        )
      )
    case .fill(let bounds, let geometry, let style, let mode):
      paintFill(
        in: bounds,
        geometry: geometry,
        style: style,
        mode: mode,
        environment: environment,
        cells: &cells,
        clip: clip
      )
    case .stroke(
      let bounds, let geometry, let style, let strokeStyle, let strokeBorder, let backgroundStyle):
      paintStroke(
        in: bounds,
        geometry: geometry,
        style: style,
        strokeStyle: strokeStyle,
        strokeBorder: strokeBorder,
        backgroundStyle: backgroundStyle,
        environment: environment,
        cells: &cells,
        clip: clip
      )
    case .rule(let bounds, let style, let strokeStyle):
      paintRule(
        in: bounds,
        style: style,
        strokeStyle: strokeStyle,
        environment: environment,
        cells: &cells,
        clip: clip
      )
    case .clip(let bounds, let child):
      paint(
        command: child,
        environment: environment,
        cells: &cells,
        imageAttachments: &imageAttachments,
        clip: bounds
      )
    }
  }

  private func paintFill(
    in bounds: Rect,
    geometry: ShapeGeometry,
    style: AnyShapeStyle,
    mode: ShapeFillMode,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let colorMode = resolvedColorMode(
      from: style,
      environment: environment
    )
    let constantStyle: ResolvedTextStyle?
    switch colorMode {
    case .constant(let backgroundColor):
      let resolvedStyle = ResolvedTextStyle(backgroundColor: backgroundColor)
      constantStyle = resolvedStyle.isDefault ? nil : resolvedStyle
    case .sampled:
      constantStyle = nil
    }

    for y in bounds.origin.y..<(bounds.origin.y + bounds.size.height) {
      for x in bounds.origin.x..<(bounds.origin.x + bounds.size.width) {
        guard
          shapeContains(
            pointX: x,
            pointY: y,
            in: bounds,
            geometry: geometry,
            fillMode: mode
          )
        else {
          continue
        }

        write(
          " ",
          style: constantStyle
            ?? resolvedBackgroundTextStyle(
              colorMode: colorMode,
              bounds: bounds,
              x: x,
              y: y
            ),
          atX: x,
          y: y,
          cells: &cells,
          clip: clip
        )
      }
    }
  }

  private func paintStroke(
    in bounds: Rect,
    geometry: ShapeGeometry,
    style: AnyShapeStyle,
    strokeStyle: StrokeStyle,
    strokeBorder: Bool,
    backgroundStyle: BorderBackgroundStyle?,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let foregroundColorMode = resolvedColorMode(
      from: style,
      environment: environment
    )
    let lineWidth = max(1, strokeStyle.lineWidth)
    for inset in 0..<lineWidth {
      let insetRect = insetBounds(bounds, by: inset, strokeBorder: strokeBorder)
      guard insetRect.size.width > 0, insetRect.size.height > 0 else {
        continue
      }

      let glyphs = borderGlyphs(
        for: geometry,
        variant: strokeStyle.lineVariant
      )

      let minX = insetRect.origin.x
      let maxX = insetRect.origin.x + insetRect.size.width - 1
      let minY = insetRect.origin.y
      let maxY = insetRect.origin.y + insetRect.size.height - 1

      for x in minX...maxX {
        writeStrokeGlyph(
          glyphs.top,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
          fallbackBackgroundSides: [.top],
          environment: environment,
          bounds: bounds,
          x: x,
          y: minY,
          cells: &cells,
          clip: clip
        )
        if maxY != minY {
          writeStrokeGlyph(
            glyphs.bottom,
            foregroundColorMode: foregroundColorMode,
            backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
            fallbackBackgroundSides: [.bottom],
            environment: environment,
            bounds: bounds,
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
            foregroundColorMode: foregroundColorMode,
            backgroundStyle: backgroundStyle?.backgroundStyle(for: .left),
            fallbackBackgroundSides: [.left],
            environment: environment,
            bounds: bounds,
            x: minX,
            y: y,
            cells: &cells,
            clip: clip
          )
          if maxX != minX {
            writeStrokeGlyph(
              glyphs.right,
              foregroundColorMode: foregroundColorMode,
              backgroundStyle: backgroundStyle?.backgroundStyle(for: .right),
              fallbackBackgroundSides: [.right],
              environment: environment,
              bounds: bounds,
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
        foregroundColorMode: foregroundColorMode,
        backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
        fallbackBackgroundSides: [.top, .left],
        environment: environment,
        bounds: bounds,
        x: minX,
        y: minY,
        cells: &cells,
        clip: clip
      )
      if maxX != minX {
        writeStrokeGlyph(
          glyphs.topTrailing,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .top),
          fallbackBackgroundSides: [.top, .right],
          environment: environment,
          bounds: bounds,
          x: maxX,
          y: minY,
          cells: &cells,
          clip: clip
        )
      }
      if maxY != minY {
        writeStrokeGlyph(
          glyphs.bottomLeading,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
          fallbackBackgroundSides: [.bottom, .left],
          environment: environment,
          bounds: bounds,
          x: minX,
          y: maxY,
          cells: &cells,
          clip: clip
        )
      }
      if maxX != minX, maxY != minY {
        writeStrokeGlyph(
          glyphs.bottomTrailing,
          foregroundColorMode: foregroundColorMode,
          backgroundStyle: backgroundStyle?.backgroundStyle(for: .bottom),
          fallbackBackgroundSides: [.bottom, .right],
          environment: environment,
          bounds: bounds,
          x: maxX,
          y: maxY,
          cells: &cells,
          clip: clip
        )
      }
    }
  }

  private func paintRule(
    in bounds: Rect,
    style: AnyShapeStyle,
    strokeStyle: StrokeStyle,
    environment: StyleEnvironmentSnapshot,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }

    let foregroundColorMode = resolvedColorMode(
      from: style,
      environment: environment
    )
    let glyphs = borderGlyphs(for: .rectangle, variant: strokeStyle.lineVariant)
    if bounds.size.width >= bounds.size.height {
      let y = bounds.origin.y + (bounds.size.height / 2)
      for x in bounds.origin.x..<(bounds.origin.x + bounds.size.width) {
        writeStrokeGlyph(
          glyphs.horizontal,
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

  private func writeStrokeGlyph(
    _ character: Character,
    foregroundColorMode: ResolvedShapeColorMode,
    backgroundStyle: AnyShapeStyle?,
    fallbackBackgroundSides: [BorderSide],
    environment: StyleEnvironmentSnapshot,
    bounds: Rect,
    x: Int,
    y: Int,
    cells: inout [[RasterCell]],
    clip: Rect?
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

  private func resolvedStrokeBackgroundColor(
    explicitBackgroundStyle: AnyShapeStyle?,
    fallbackSides: [BorderSide],
    environment: StyleEnvironmentSnapshot,
    bounds: Rect,
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

  private func shapeContains(
    pointX x: Int,
    pointY y: Int,
    in bounds: Rect,
    geometry: ShapeGeometry,
    fillMode: ShapeFillMode = .full
  ) -> Bool {
    let targetBounds: Rect
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

  private func insetBounds(
    _ bounds: Rect,
    by inset: Int,
    strokeBorder _: Bool
  ) -> Rect {
    Rect(
      origin: Point(
        x: bounds.origin.x + inset,
        y: bounds.origin.y + inset
      ),
      size: Size(
        width: max(0, bounds.size.width - (inset * 2)),
        height: max(0, bounds.size.height - (inset * 2))
      )
    )
  }

  private func resolveTextStyle(
    _ style: TextStyle,
    environment: StyleEnvironmentSnapshot,
    bounds: Rect,
    sampleX: Int,
    sampleY: Int,
    width: Int
  ) -> ResolvedTextStyle {
    ResolvedTextStyle(
      foregroundColor: resolveColor(
        from: style.foregroundStyle ?? environment.foregroundStyle ?? .semantic(.foreground),
        environment: environment,
        bounds: bounds,
        sampleX: sampleX + max(0, width - 1) / 2,
        sampleY: sampleY
      ),
      backgroundColor: style.backgroundStyle.flatMap {
        resolveColor(
          from: $0,
          environment: environment,
          bounds: bounds,
          sampleX: sampleX + max(0, width - 1) / 2,
          sampleY: sampleY
        )
      },
      emphasis: style.emphasis,
      underlineStyle: style.underlineStyle,
      strikethroughStyle: style.strikethroughStyle,
      opacity: style.opacity
    )
  }

  private func resolveColor(
    from style: AnyShapeStyle,
    environment: StyleEnvironmentSnapshot,
    bounds: Rect,
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

  private func resolvedColorMode(
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
    case .terminalChrome(let chromeStyle):
      return resolvedColorMode(
        from: environment.appearance.resolvedStyle(for: chromeStyle),
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
    }
  }

  private func resolveColor(
    from mode: ResolvedShapeColorMode,
    bounds: Rect,
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
    }
  }

  private func resolvedBackgroundTextStyle(
    colorMode: ResolvedShapeColorMode,
    bounds: Rect,
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

  private func semanticStyleCandidate(
    for role: SemanticStyleRole,
    environment: StyleEnvironmentSnapshot
  ) -> AnyShapeStyle {
    switch role {
    case .foreground:
      return environment.foregroundStyle ?? environment.theme.foreground
    case .tint:
      return environment.tintStyle ?? environment.theme.tint
    default:
      return environment.theme.style(for: role)
    }
  }

  private func semanticStyleFallback(
    for role: SemanticStyleRole,
    environment: StyleEnvironmentSnapshot
  ) -> AnyShapeStyle {
    switch role {
    case .foreground:
      return environment.theme.foreground
    case .tint:
      return environment.theme.tint
    default:
      return environment.theme.style(for: role)
    }
  }

  private func sample(
    _ gradient: LinearGradient,
    in bounds: Rect,
    x: Int,
    y: Int
  ) -> Color? {
    let stops = gradient.gradient.stops
    guard let first = stops.first else {
      return nil
    }
    guard stops.count > 1, bounds.size.width > 0, bounds.size.height > 0 else {
      return first.color
    }

    let start = unitCoordinates(for: gradient.startPoint)
    let end = unitCoordinates(for: gradient.endPoint)
    let point = (
      x: Double(x - bounds.origin.x) + 0.5,
      y: Double(y - bounds.origin.y) + 0.5
    )
    let normalizedPoint = (
      x: point.x / Double(max(1, bounds.size.width)),
      y: point.y / Double(max(1, bounds.size.height))
    )

    let axis = (x: end.x - start.x, y: end.y - start.y)
    let axisLengthSquared = (axis.x * axis.x) + (axis.y * axis.y)
    let t: Double
    if axisLengthSquared == 0 {
      t = 0
    } else {
      let offset = (x: normalizedPoint.x - start.x, y: normalizedPoint.y - start.y)
      t = min(
        1,
        max(
          0,
          ((offset.x * axis.x) + (offset.y * axis.y)) / axisLengthSquared
        )
      )
    }

    if t <= first.location {
      return first.color
    }
    if let last = stops.last, t >= last.location {
      return last.color
    }

    for index in 0..<(stops.count - 1) {
      let lower = stops[index]
      let upper = stops[index + 1]
      guard t >= lower.location, t <= upper.location else {
        continue
      }

      let range = max(0.0001, upper.location - lower.location)
      let localT = (t - lower.location) / range
      return interpolate(from: lower.color, to: upper.color, t: localT)
    }

    return stops.last?.color
  }

  private func unitCoordinates(
    for alignment: Alignment
  ) -> (x: Double, y: Double) {
    let x: Double =
      switch alignment.horizontal {
      case .leading:
        0
      case .center:
        0.5
      case .trailing:
        1
      default:
        0.5
      }

    let y: Double =
      switch alignment.vertical {
      case .top:
        0
      case .center:
        0.5
      case .bottom, .firstTextBaseline, .lastTextBaseline:
        1
      default:
        0.5
      }

    return (x, y)
  }

  private func interpolate(
    from lhs: Color,
    to rhs: Color,
    t: Double
  ) -> Color {
    Color(
      red: interpolatedComponent(from: lhs.red, to: rhs.red, t: t),
      green: interpolatedComponent(from: lhs.green, to: rhs.green, t: t),
      blue: interpolatedComponent(from: lhs.blue, to: rhs.blue, t: t)
    )
  }

  private func interpolatedComponent(
    from lhs: Int,
    to rhs: Int,
    t: Double
  ) -> Int {
    Int((Double(lhs) + ((Double(rhs) - Double(lhs)) * t)).rounded())
  }

  private func intersect(
    _ lhs: Rect?,
    _ rhs: Rect?
  ) -> Rect? {
    switch (lhs, rhs) {
    case (nil, nil):
      return nil
    case (let rect?, nil), (nil, let rect?):
      return rect
    case (let lhsRect?, let rhsRect?):
      return intersect(lhsRect, rhsRect)
    }
  }

  private func intersect(
    _ lhs: Rect,
    _ rhs: Rect
  ) -> Rect? {
    let minX = max(lhs.origin.x, rhs.origin.x)
    let minY = max(lhs.origin.y, rhs.origin.y)
    let maxX = min(lhs.origin.x + lhs.size.width, rhs.origin.x + rhs.size.width)
    let maxY = min(lhs.origin.y + lhs.size.height, rhs.origin.y + rhs.size.height)

    guard maxX > minX, maxY > minY else {
      return nil
    }

    return Rect(
      origin: Point(x: minX, y: minY),
      size: Size(width: maxX - minX, height: maxY - minY)
    )
  }

  private func borderGlyphs(
    for geometry: ShapeGeometry,
    variant: LineVariant
  ) -> BorderGlyphSet {
    switch variant {
    case .ascii:
      return .ascii
    case .single:
      switch geometry {
      case .roundedRectangle(let cornerRadius) where cornerRadius > 0:
        return .rounded
      default:
        return .singleLine
      }
    case .rounded:
      return .rounded
    case .double:
      return .doubleLine
    case .heavy:
      return .heavy
    case .block:
      return .block
    case .outerHalfBlock:
      return .outerHalfBlock
    case .innerHalfBlock:
      return .innerHalfBlock
    case .hidden:
      return .hidden
    case .markdown:
      return .markdown
    case .automatic:
      switch geometry {
      case .roundedRectangle(let cornerRadius) where cornerRadius > 0:
        return .rounded
      default:
        return .singleLine
      }
    }
  }

  private struct BorderGlyphSet {
    let top: Character
    let bottom: Character
    let left: Character
    let right: Character
    let topLeading: Character
    let topTrailing: Character
    let bottomLeading: Character
    let bottomTrailing: Character

    var horizontal: Character { top }
    var vertical: Character { left }

    static let ascii = Self(
      top: "-",
      bottom: "-",
      left: "|",
      right: "|",
      topLeading: "+",
      topTrailing: "+",
      bottomLeading: "+",
      bottomTrailing: "+"
    )

    static let singleLine = Self(
      top: "─",
      bottom: "─",
      left: "│",
      right: "│",
      topLeading: "┌",
      topTrailing: "┐",
      bottomLeading: "└",
      bottomTrailing: "┘"
    )

    static let rounded = Self(
      top: "─",
      bottom: "─",
      left: "│",
      right: "│",
      topLeading: "╭",
      topTrailing: "╮",
      bottomLeading: "╰",
      bottomTrailing: "╯"
    )

    static let doubleLine = Self(
      top: "═",
      bottom: "═",
      left: "║",
      right: "║",
      topLeading: "╔",
      topTrailing: "╗",
      bottomLeading: "╚",
      bottomTrailing: "╝"
    )

    static let heavy = Self(
      top: "━",
      bottom: "━",
      left: "┃",
      right: "┃",
      topLeading: "┏",
      topTrailing: "┓",
      bottomLeading: "┗",
      bottomTrailing: "┛"
    )

    static let block = Self(
      top: "█",
      bottom: "█",
      left: "█",
      right: "█",
      topLeading: "█",
      topTrailing: "█",
      bottomLeading: "█",
      bottomTrailing: "█"
    )

    static let outerHalfBlock = Self(
      top: "▀",
      bottom: "▄",
      left: "▌",
      right: "▐",
      topLeading: "▛",
      topTrailing: "▜",
      bottomLeading: "▙",
      bottomTrailing: "▟"
    )

    static let innerHalfBlock = Self(
      top: "▄",
      bottom: "▀",
      left: "▐",
      right: "▌",
      topLeading: "▗",
      topTrailing: "▖",
      bottomLeading: "▝",
      bottomTrailing: "▘"
    )

    static let hidden = Self(
      top: " ",
      bottom: " ",
      left: " ",
      right: " ",
      topLeading: " ",
      topTrailing: " ",
      bottomLeading: " ",
      bottomTrailing: " "
    )

    static let markdown = Self(
      top: "-",
      bottom: "-",
      left: "|",
      right: "|",
      topLeading: "|",
      topTrailing: "|",
      bottomLeading: "|",
      bottomTrailing: "|"
    )
  }

  private func write(
    _ character: Character,
    width: Int = 1,
    style: ResolvedTextStyle? = nil,
    hyperlink: String? = nil,
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]],
    clip: Rect?
  ) {
    let glyphWidth = max(1, width)
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }
    if let clip {
      guard x >= clip.origin.x,
        x + glyphWidth <= clip.origin.x + clip.size.width,
        y >= clip.origin.y,
        y < clip.origin.y + clip.size.height
      else {
        return
      }
    }

    let underlayStyle = cells[y][x].style
    let finalStyle: ResolvedTextStyle?
    switch (style, underlayStyle) {
    case (nil, nil):
      finalStyle = nil
    case (let overlayStyle?, nil):
      finalStyle = overlayStyle.isDefault ? nil : overlayStyle
    case (nil, let underlayStyle?):
      let compositedStyle = Self.emptyCompositingStyle.composited(over: underlayStyle)
      finalStyle = compositedStyle.isDefault ? nil : compositedStyle
    case (let overlayStyle?, let underlayStyle?):
      let compositedStyle = overlayStyle.composited(over: underlayStyle)
      finalStyle = compositedStyle.isDefault ? nil : compositedStyle
    }

    for offset in 0..<glyphWidth {
      let targetX = x + offset
      guard targetX >= 0, targetX < cells[y].count else {
        continue
      }
      clearExistingGlyph(atX: targetX, y: y, cells: &cells)
    }

    cells[y][x] = RasterCell(
      character: character,
      spanWidth: glyphWidth,
      style: finalStyle,
      hyperlink: hyperlink
    )

    guard glyphWidth > 1 else {
      return
    }

    for offset in 1..<glyphWidth {
      let targetX = x + offset
      guard targetX >= 0, targetX < cells[y].count else {
        continue
      }
      cells[y][targetX] = RasterCell(
        character: " ",
        spanWidth: 0,
        continuationLeadX: x,
        style: finalStyle,
        hyperlink: hyperlink
      )
    }
  }

  private func clearExistingGlyph(
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]]
  ) {
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }

    let cell = cells[y][x]
    if let leadX = cell.continuationLeadX {
      clearLeadGlyph(atX: leadX, y: y, cells: &cells)
      return
    }

    if cell.spanWidth > 1 {
      clearLeadGlyph(atX: x, y: y, cells: &cells)
      return
    }

    cells[y][x] = .empty
  }

  private func clearLeadGlyph(
    atX x: Int,
    y: Int,
    cells: inout [[RasterCell]]
  ) {
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return
    }

    let spanWidth = max(1, cells[y][x].spanWidth)
    for offset in 0..<spanWidth {
      let targetX = x + offset
      guard targetX >= 0, targetX < cells[y].count else {
        continue
      }
      cells[y][targetX] = .empty
    }
  }
}
