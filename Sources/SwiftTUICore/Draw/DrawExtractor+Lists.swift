package struct ListDisplayLine: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case text(String, TextStyle)
    case row(
      marker: String,
      markerStyle: TextStyle,
      text: String,
      textStyle: TextStyle,
      backgroundStyle: AnyShapeStyle?
    )
    case separator(AnyShapeStyle)
  }

  var kind: Kind
  var isHeader: Bool
  var rowIndex: Int?
  var sectionIndex: Int?
  var itemIndex: Int?
  /// The truncation mode for this line's flattened text, carried from the
  /// item payload so authored/ambient modes survive the flattening.
  package var truncationMode: TextTruncationMode
  /// Cells this line occupies. Greater than 1 when the hosted row measured
  /// taller than one cell; 1 for every chrome line and for the payload-only
  /// line model, which has no measured children to ask.
  package var height: Int
  /// This line's first cell, relative to the layout's content bounds.
  ///
  /// The line model used to have no height concept at all: every consumer
  /// assumed `y == lineIndex`, while placement separately accumulated an
  /// `additionalYOffset` for tall rows. That is register item D19 — the two
  /// conventions disagree for every line after a multi-cell row, which is
  /// what painted a selection marker one cell above its own content.
  package var yOffset: Int

  init(
    kind: Kind,
    isHeader: Bool,
    rowIndex: Int?,
    sectionIndex: Int? = nil,
    itemIndex: Int? = nil,
    height: Int = 1,
    yOffset: Int = 0,
    truncationMode: TextTruncationMode = .tail
  ) {
    self.kind = kind
    self.isHeader = isHeader
    self.rowIndex = rowIndex
    self.sectionIndex = sectionIndex
    self.itemIndex = itemIndex
    self.height = height
    self.yOffset = yOffset
    self.truncationMode = truncationMode
  }
}

package struct ListVisibleLayout: Equatable, Sendable {
  package var contentBounds: CellRect
  package var lines: [ListDisplayLine]
  package var sectionChromeBounds: [CellRect]
  /// Total cells the visible lines occupy, which exceeds `lines.count`
  /// whenever any row measured taller than one cell.
  package var totalContentHeight: Int

  package init(
    contentBounds: CellRect,
    lines: [ListDisplayLine],
    sectionChromeBounds: [CellRect],
    totalContentHeight: Int? = nil
  ) {
    self.contentBounds = contentBounds
    self.lines = lines
    self.sectionChromeBounds = sectionChromeBounds
    self.totalContentHeight =
      totalContentHeight ?? lines.reduce(0) { $0 + max(1, $1.height) }
  }

  /// Returns a copy translated into absolute coordinates by `delta`.
  package func translated(by delta: CellPoint) -> ListVisibleLayout {
    var copy = self
    copy.contentBounds = CellRect(
      origin: .init(x: contentBounds.origin.x + delta.x, y: contentBounds.origin.y + delta.y),
      size: contentBounds.size
    )
    copy.sectionChromeBounds = sectionChromeBounds.map { rect in
      CellRect(
        origin: .init(x: rect.origin.x + delta.x, y: rect.origin.y + delta.y),
        size: rect.size
      )
    }
    return copy
  }
}

extension DrawExtractor {
  func listCommands(
    for payload: ListPayload,
    in bounds: CellRect,
    hostsCommittedItems: Bool = false,
    placedLayout: ListVisibleLayout? = nil,
    effectiveOpacity: Double = 1
  ) -> [DrawCommand] {
    // The ancestor opacity cascade applies at emission: line styles are baked
    // into the (possibly placed) layout product with the payload's own chrome
    // factor already folded in, so the inherited factor multiplies on top.
    func fadedText(_ style: TextStyle) -> TextStyle {
      guard effectiveOpacity != 1 else {
        return style
      }
      var faded = style
      faded.opacity = faded.opacity * effectiveOpacity
      return faded
    }
    func fadedShape(_ style: AnyShapeStyle) -> AnyShapeStyle {
      effectiveOpacity == 1 ? style : style.opacity(effectiveOpacity)
    }
    // The placed product when there is one — that is what keeps a tall row's
    // marker and separators on the same cells as its content. The recompute
    // stays for payload-only callers, whose rows are all one cell tall.
    let layout =
      placedLayout
      ?? payload.style.visibleListLayout(
        for: payload,
        in: bounds
      )
    let contentBounds = layout.contentBounds
    guard contentBounds.size.width > 0, contentBounds.size.height > 0 else {
      return listChromeCommands(
        for: payload, in: bounds, layout: layout, effectiveOpacity: effectiveOpacity)
    }

    var commands = listChromeCommands(
      for: payload, in: bounds, layout: layout, effectiveOpacity: effectiveOpacity)
    let lines = layout.lines

    for line in lines {
      let lineBounds = CellRect(
        origin: .init(x: contentBounds.origin.x, y: contentBounds.origin.y + line.yOffset),
        size: .init(width: contentBounds.size.width, height: max(1, line.height))
      )

      switch line.kind {
      case .text(let content, let style):
        if !hostsCommittedItems || line.itemIndex == nil {
          commands.append(
            .text(
              bounds: lineBounds,
              content: content,
              style: fadedText(style),
              lineLimit: 1,
              truncationMode: line.truncationMode,
              wrappingStrategy: .wordBoundary
            )
          )
        }
      case .row(let marker, let markerStyle, let text, let textStyle, let backgroundStyle):
        if let backgroundStyle {
          commands.append(
            .fill(
              bounds: lineBounds,
              geometry: .rectangle,
              insetAmount: 0,
              style: fadedShape(backgroundStyle),
              mode: .full
            )
          )
        }

        let markerWidth = layoutText(for: marker, width: nil).size.width
        let markerBounds = CellRect(
          origin: lineBounds.origin,
          size: .init(
            width: min(lineBounds.size.width, markerWidth), height: lineBounds.size.height)
        )
        let textBounds = CellRect(
          origin: .init(x: lineBounds.origin.x + markerBounds.size.width, y: lineBounds.origin.y),
          size: .init(width: max(0, lineBounds.size.width - markerBounds.size.width), height: 1)
        )

        if markerBounds.size.width > 0 {
          commands.append(
            .text(
              bounds: markerBounds,
              content: marker,
              style: fadedText(markerStyle),
              lineLimit: 1,
              truncationMode: .tail,
              wrappingStrategy: .wordBoundary
            )
          )
        }
        if textBounds.size.width > 0, !hostsCommittedItems {
          commands.append(
            .text(
              bounds: textBounds,
              content: text,
              style: fadedText(textStyle),
              lineLimit: 1,
              truncationMode: line.truncationMode,
              wrappingStrategy: .wordBoundary
            )
          )
        }
      case .separator(let style):
        commands.append(
          .rule(
            bounds: lineBounds,
            style: fadedShape(style),
            strokeStyle: .init(borderSet: .single),
            stackAxis: nil
          )
        )
      }
    }

    return commands
  }

  private func listChromeCommands(
    for payload: ListPayload,
    in bounds: CellRect,
    layout: ListVisibleLayout,
    effectiveOpacity: Double
  ) -> [DrawCommand] {
    guard let container = payload.style.container else {
      return []
    }

    func fadedShape(_ style: AnyShapeStyle) -> AnyShapeStyle {
      effectiveOpacity == 1 ? style : style.opacity(effectiveOpacity)
    }

    let chromeBounds = payload.style.listChromeBounds(for: layout, in: bounds)
    return chromeBounds.flatMap { sectionBounds in
      [
        .fill(
          bounds: sectionBounds,
          geometry: container.geometry,
          insetAmount: container.insetAmount,
          style: fadedShape(payload.backgroundStyle ?? .semantic(.fill)),
          mode: container.fillMode
        ),
        .stroke(
          bounds: sectionBounds,
          geometry: container.geometry,
          insetAmount: container.insetAmount,
          style: fadedShape(payload.borderStyle ?? .semantic(.separator)),
          strokeStyle: container.strokeStyle,
          strokeBorder: container.strokeBorder,
          backgroundStyle: nil
        ),
      ]
    }
  }

  func scrollIndicatorCommands(
    bounds: CellRect,
    drawMetadata: DrawMetadata,
    children: [PlacedNode],
    effectiveOpacity: Double = 1
  ) -> [DrawCommand] {
    guard let axes = drawMetadata.scrollIndicatorAxes,
      let content = children.first
    else {
      return []
    }

    let appearance = drawMetadata.scrollIndicatorAppearance
    let viewportBounds = appearance?.insetBounds(bounds) ?? bounds
    let offsetX = max(0, viewportBounds.origin.x - content.bounds.origin.x)
    let offsetY = max(0, viewportBounds.origin.y - content.bounds.origin.y)
    var commands: [DrawCommand] = []
    if let metrics = resolvedScrollIndicatorMetrics(
      viewportRect: viewportBounds,
      contentBounds: content.contentBounds,
      axes: axes,
      axis: .vertical,
      reservesSpace: appearance?.reservesSpace ?? true
    ) {
      commands.append(
        contentsOf: verticalScrollIndicatorCommands(
          metrics: metrics,
          offset: offsetY,
          glyph: appearance?.verticalGlyph ?? "▐",
          style: scrollIndicatorStyle(
            for: .vertical, drawMetadata: drawMetadata, effectiveOpacity: effectiveOpacity)
        )
      )
    }
    if let metrics = resolvedScrollIndicatorMetrics(
      viewportRect: viewportBounds,
      contentBounds: content.contentBounds,
      axes: axes,
      axis: .horizontal,
      reservesSpace: appearance?.reservesSpace ?? true
    ) {
      commands.append(
        contentsOf: horizontalScrollIndicatorCommands(
          metrics: metrics,
          offset: offsetX,
          glyph: appearance?.horizontalGlyph ?? "▂",
          style: scrollIndicatorStyle(
            for: .horizontal, drawMetadata: drawMetadata, effectiveOpacity: effectiveOpacity)
        )
      )
    }
    return commands
  }

  private func scrollIndicatorStyle(
    for axis: ScrollIndicatorAxis,
    drawMetadata: DrawMetadata,
    effectiveOpacity: Double
  ) -> TextStyle {
    let indicatorAxis: AxisSet = axis == .vertical ? .vertical : .horizontal
    let foregroundStyle =
      drawMetadata.focusedScrollIndicatorAxes?.contains(indicatorAxis) == true
      ? (drawMetadata.scrollIndicatorAppearance?.focusedForegroundStyle
        ?? drawMetadata.scrollIndicatorForegroundStyle ?? .semantic(.tint))
      : (drawMetadata.scrollIndicatorAppearance?.foregroundStyle ?? .semantic(.muted))
    // The cascade product; equals `drawMetadata.opacity` with no faded
    // ancestor.
    return .init(foregroundStyle: foregroundStyle, opacity: effectiveOpacity)
  }

  private func verticalScrollIndicatorCommands(
    metrics: ScrollIndicatorMetrics,
    offset: Int,
    glyph: String,
    style: TextStyle
  ) -> [DrawCommand] {
    let bounds = metrics.rect

    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return []
    }

    guard let thumbRange = metrics.thumbRange(for: offset) else {
      return []
    }

    let x = bounds.origin.x + bounds.size.width - 1
    return thumbRange.flatMap { y in
      singleCellIndicatorCommand(x: x, y: y, glyph: glyph, style: style)
    }
  }

  private func horizontalScrollIndicatorCommands(
    metrics: ScrollIndicatorMetrics,
    offset: Int,
    glyph: String,
    style: TextStyle
  ) -> [DrawCommand] {
    let bounds = metrics.rect
    let trackWidth = bounds.size.width
    guard trackWidth > 0, bounds.size.height > 0 else {
      return []
    }

    guard let thumbRange = metrics.thumbRange(for: offset) else {
      return []
    }

    let y = bounds.origin.y + bounds.size.height - 1
    return thumbRange.flatMap { x in
      singleCellIndicatorCommand(x: x, y: y, glyph: glyph, style: style)
    }
  }

  private func singleCellIndicatorCommand(
    x: Int,
    y: Int,
    glyph: String,
    style: TextStyle
  ) -> [DrawCommand] {
    guard !glyph.isEmpty else {
      return []
    }

    return [
      .text(
        bounds: .init(origin: .init(x: x, y: y), size: .init(width: 1, height: 1)),
        content: glyph,
        style: style,
        lineLimit: 1,
        truncationMode: .tail,
        wrappingStrategy: .wordBoundary
      )
    ]
  }

}
