package struct ListDisplayLine {
  enum Kind {
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

  init(
    kind: Kind,
    isHeader: Bool,
    rowIndex: Int?,
    sectionIndex: Int? = nil
  ) {
    self.kind = kind
    self.isHeader = isHeader
    self.rowIndex = rowIndex
    self.sectionIndex = sectionIndex
  }
}

package struct ListVisibleLayout {
  package var contentBounds: Rect
  package var lines: [ListDisplayLine]
  package var sectionChromeBounds: [Rect]
}

extension DrawExtractor {
  func listCommands(
    for payload: ListPayload,
    in bounds: Rect
  ) -> [DrawCommand] {
    let layout = payload.style.visibleListLayout(
      for: payload,
      in: bounds
    )
    let contentBounds = layout.contentBounds
    guard contentBounds.size.width > 0, contentBounds.size.height > 0 else {
      return listChromeCommands(for: payload, in: bounds, layout: layout)
    }

    var commands = listChromeCommands(for: payload, in: bounds, layout: layout)
    let lines = layout.lines

    for (index, line) in lines.enumerated() {
      let lineBounds = Rect(
        origin: .init(x: contentBounds.origin.x, y: contentBounds.origin.y + index),
        size: .init(width: contentBounds.size.width, height: 1)
      )

      switch line.kind {
      case .text(let content, let style):
        commands.append(
          .text(
            bounds: lineBounds,
            content: content,
            style: style,
            lineLimit: 1,
            truncationMode: .tail,
            wrappingStrategy: .wordBoundary
          )
        )
      case .row(let marker, let markerStyle, let text, let textStyle, let backgroundStyle):
        if let backgroundStyle {
          commands.append(
            .fill(
              bounds: lineBounds,
              geometry: .rectangle,
              insetAmount: 0,
              style: backgroundStyle,
              mode: .full
            )
          )
        }

        let markerWidth = layoutText(for: marker, width: nil).size.width
        let markerBounds = Rect(
          origin: lineBounds.origin,
          size: .init(width: min(lineBounds.size.width, markerWidth), height: 1)
        )
        let textBounds = Rect(
          origin: .init(x: lineBounds.origin.x + markerBounds.size.width, y: lineBounds.origin.y),
          size: .init(width: max(0, lineBounds.size.width - markerBounds.size.width), height: 1)
        )

        if markerBounds.size.width > 0 {
          commands.append(
            .text(
              bounds: markerBounds,
              content: marker,
              style: markerStyle,
              lineLimit: 1,
              truncationMode: .tail,
              wrappingStrategy: .wordBoundary
            )
          )
        }
        if textBounds.size.width > 0 {
          commands.append(
            .text(
              bounds: textBounds,
              content: text,
              style: textStyle,
              lineLimit: 1,
              truncationMode: .tail,
              wrappingStrategy: .wordBoundary
            )
          )
        }
      case .separator(let style):
        commands.append(
          .rule(
            bounds: lineBounds,
            style: style,
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
    in bounds: Rect,
    layout: ListVisibleLayout
  ) -> [DrawCommand] {
    guard let container = payload.style.listContainer else {
      return []
    }

    let chromeBounds = payload.style.listChromeBounds(for: layout, in: bounds)
    return chromeBounds.flatMap { sectionBounds in
      [
        .fill(
          bounds: sectionBounds,
          geometry: container.geometry,
          insetAmount: container.insetAmount,
          style: payload.backgroundStyle ?? .semantic(.fill),
          mode: container.fillMode
        ),
        .stroke(
          bounds: sectionBounds,
          geometry: container.geometry,
          insetAmount: container.insetAmount,
          style: payload.borderStyle ?? .semantic(.separator),
          strokeStyle: container.strokeStyle,
          strokeBorder: container.strokeBorder,
          backgroundStyle: nil
        ),
      ]
    }
  }

  func scrollIndicatorCommands(
    bounds: Rect,
    drawMetadata: DrawMetadata,
    children: [PlacedNode]
  ) -> [DrawCommand] {
    guard let axes = drawMetadata.scrollIndicatorAxes,
      let content = children.first
    else {
      return []
    }

    let indicatorInsets = resolvedScrollIndicatorInsets(
      viewportRect: bounds,
      contentBounds: content.contentBounds,
      axes: axes
    )
    guard indicatorInsets.trailing > 0 || indicatorInsets.bottom > 0 else {
      return []
    }

    let offsetX = max(0, bounds.origin.x - content.bounds.origin.x)
    let offsetY = max(0, bounds.origin.y - content.bounds.origin.y)
    var commands: [DrawCommand] = []
    if let metrics = resolvedScrollIndicatorMetrics(
      viewportRect: bounds,
      contentBounds: content.contentBounds,
      axes: axes,
      axis: .vertical
    ) {
      commands.append(
        contentsOf: verticalScrollIndicatorCommands(
          metrics: metrics,
          offset: offsetY,
          style: scrollIndicatorStyle(for: .vertical, drawMetadata: drawMetadata)
        )
      )
    }
    if let metrics = resolvedScrollIndicatorMetrics(
      viewportRect: bounds,
      contentBounds: content.contentBounds,
      axes: axes,
      axis: .horizontal
    ) {
      commands.append(
        contentsOf: horizontalScrollIndicatorCommands(
          metrics: metrics,
          offset: offsetX,
          style: scrollIndicatorStyle(for: .horizontal, drawMetadata: drawMetadata)
        )
      )
    }
    return commands
  }

  private func scrollIndicatorStyle(
    for axis: ScrollIndicatorAxis,
    drawMetadata: DrawMetadata
  ) -> TextStyle {
    let indicatorAxis: AxisSet = axis == .vertical ? .vertical : .horizontal
    let foregroundStyle =
      drawMetadata.focusedScrollIndicatorAxes?.contains(indicatorAxis) == true
      ? (drawMetadata.scrollIndicatorForegroundStyle ?? .semantic(.tint))
      : .semantic(.muted)
    return .init(foregroundStyle: foregroundStyle, opacity: drawMetadata.opacity)
  }

  private func verticalScrollIndicatorCommands(
    metrics: ScrollIndicatorMetrics,
    offset: Int,
    style: TextStyle
  ) -> [DrawCommand] {
    let bounds = metrics.rect
    let maxOffset = metrics.maxOffset

    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return []
    }

    let x = bounds.origin.x + bounds.size.width - 1
    if bounds.size.height == 1 {
      let glyph = compactIndicatorGlyph(
        offset: offset,
        maxOffset: maxOffset,
        backward: "▲",
        forward: "▼"
      )
      return singleCellIndicatorCommand(x: x, y: bounds.origin.y, glyph: glyph, style: style)
    }

    var commands = singleCellIndicatorCommand(
      x: x,
      y: bounds.origin.y,
      glyph: offset > 0 ? "▲" : "█",
      style: style
    )
    commands.append(
      contentsOf: singleCellIndicatorCommand(
        x: x,
        y: bounds.origin.y + bounds.size.height - 1,
        glyph: offset < maxOffset ? "▼" : "█",
        style: style
      )
    )

    guard bounds.size.height > 2 else {
      return commands
    }

    let trackStart = bounds.origin.y + 1
    let trackLength = bounds.size.height - 2
    let thumbRange = metrics.thumbRange(for: offset)

    for y in trackStart..<(trackStart + trackLength) {
      commands.append(
        contentsOf: singleCellIndicatorCommand(
          x: x,
          y: y,
          glyph: thumbRange?.contains(y) == true ? "█" : "┃",
          style: style
        )
      )
    }
    return commands
  }

  private func horizontalScrollIndicatorCommands(
    metrics: ScrollIndicatorMetrics,
    offset: Int,
    style: TextStyle
  ) -> [DrawCommand] {
    let bounds = metrics.rect
    let maxOffset = metrics.maxOffset
    let trackWidth = bounds.size.width
    guard trackWidth > 0, bounds.size.height > 0 else {
      return []
    }

    let y = bounds.origin.y + bounds.size.height - 1
    if trackWidth == 1 {
      let glyph = compactIndicatorGlyph(
        offset: offset,
        maxOffset: maxOffset,
        backward: "◀",
        forward: "▶"
      )
      return singleCellIndicatorCommand(x: bounds.origin.x, y: y, glyph: glyph, style: style)
    }

    var commands = singleCellIndicatorCommand(
      x: bounds.origin.x,
      y: y,
      glyph: offset > 0 ? "◀" : "█",
      style: style
    )
    commands.append(
      contentsOf: singleCellIndicatorCommand(
        x: bounds.origin.x + trackWidth - 1,
        y: y,
        glyph: offset < maxOffset ? "▶" : "█",
        style: style
      )
    )

    guard trackWidth > 2 else {
      return commands
    }

    let trackStart = bounds.origin.x + 1
    let trackLength = trackWidth - 2
    let thumbRange = metrics.thumbRange(for: offset)

    for x in trackStart..<(trackStart + trackLength) {
      commands.append(
        contentsOf: singleCellIndicatorCommand(
          x: x,
          y: y,
          glyph: thumbRange?.contains(x) == true ? "█" : "━",
          style: style
        )
      )
    }
    return commands
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

  private func compactIndicatorGlyph(
    offset: Int,
    maxOffset: Int,
    backward: String,
    forward: String
  ) -> String {
    if maxOffset <= 0 {
      return " "
    }
    if offset <= 0 {
      return forward
    }
    if offset >= maxOffset {
      return backward
    }
    return "█"
  }

}
