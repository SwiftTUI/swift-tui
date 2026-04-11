private enum ResolvedListStyle: Equatable {
  case plain
  case insetGrouped
}

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
}

package struct ListVisibleLayout {
  package var contentBounds: Rect
  package var lines: [ListDisplayLine]
}

extension DrawExtractor {
  func listCommands(
    for payload: ListPayload,
    in bounds: Rect
  ) -> [DrawCommand] {
    let layout = visibleListLayout(
      for: payload,
      in: bounds
    )
    let listStyle: ResolvedListStyle =
      payload.style == .plain ? .plain : .insetGrouped
    let contentBounds = layout.contentBounds
    guard contentBounds.size.width > 0, contentBounds.size.height > 0 else {
      return listChromeCommands(for: payload, in: bounds, style: listStyle)
    }

    var commands = listChromeCommands(for: payload, in: bounds, style: listStyle)
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
    style: ResolvedListStyle
  ) -> [DrawCommand] {
    guard style == .insetGrouped else {
      return []
    }

    return [
      .fill(
        bounds: bounds,
        geometry: .roundedRectangle(cornerRadius: 1),
        insetAmount: 0,
        style: payload.backgroundStyle ?? .semantic(.fill),
        mode: .interior(strokeWidth: 1)
      ),
      .stroke(
        bounds: bounds,
        geometry: .roundedRectangle(cornerRadius: 1),
        insetAmount: 0,
        style: payload.borderStyle ?? .semantic(.separator),
        strokeStyle: .init(borderSet: .rounded),
        strokeBorder: true,
        backgroundStyle: nil
      ),
    ]
  }

  private func listContentBounds(
    in bounds: Rect,
    style: ResolvedListStyle
  ) -> Rect {
    guard style == .insetGrouped else {
      return bounds
    }

    return Rect(
      origin: .init(x: bounds.origin.x + 1, y: bounds.origin.y + 1),
      size: .init(
        width: max(0, bounds.size.width - 2),
        height: max(0, bounds.size.height - 2)
      )
    )
  }

  package func visibleListLayout(
    for payload: ListPayload,
    in bounds: Rect
  ) -> ListVisibleLayout {
    let listStyle: ResolvedListStyle =
      payload.style == .plain ? .plain : .insetGrouped
    let contentBounds = listContentBounds(in: bounds, style: listStyle)
    let lines = visibleListLines(
      for: payload,
      style: listStyle,
      viewportLineCount: contentBounds.size.height,
      showsIndicators: payload.showsIndicators
    )

    return ListVisibleLayout(
      contentBounds: contentBounds,
      lines: lines
    )
  }

  private func visibleListLines(
    for payload: ListPayload,
    style: ResolvedListStyle,
    viewportLineCount: Int,
    showsIndicators: Bool
  ) -> [ListDisplayLine] {
    let displayLines = materializedListLines(for: payload, style: style)
    guard viewportLineCount > 0 else {
      return []
    }

    if displayLines.count > viewportLineCount {
      let visibleLineCount =
        showsIndicators && viewportLineCount >= 3
        ? max(1, viewportLineCount - 2)
        : viewportLineCount
      let selectedLineIndex = selectedListLineIndex(in: displayLines)
      let lineIndex = min(
        max(selectedLineIndex ?? 0, 0),
        max(0, displayLines.count - 1)
      )
      let offset = min(
        max(0, lineIndex - (visibleLineCount / 2)),
        max(0, displayLines.count - visibleLineCount)
      )
      let end = min(displayLines.count, offset + visibleLineCount)
      guard showsIndicators, viewportLineCount >= 3 else {
        return Array(displayLines[offset..<end])
      }
      var visible: [ListDisplayLine] = []
      visible.reserveCapacity(visibleLineCount + 2)
      visible.append(
        .init(
          kind: .text(
            "↑", .init(foregroundStyle: .semantic(.separator), opacity: payload.opacity)),
          isHeader: true,
          rowIndex: nil
        )
      )
      if offset == 0 {
        visible[0] = .init(
          kind: .text("", .init(foregroundStyle: .semantic(.muted), opacity: payload.opacity)),
          isHeader: true,
          rowIndex: nil
        )
      }
      visible.append(contentsOf: displayLines[offset..<end])
      visible.append(
        .init(
          kind: .text(
            "↓", .init(foregroundStyle: .semantic(.separator), opacity: payload.opacity)),
          isHeader: true,
          rowIndex: nil
        )
      )
      if end >= displayLines.count {
        visible[visible.count - 1] = .init(
          kind: .text("", .init(foregroundStyle: .semantic(.muted), opacity: payload.opacity)),
          isHeader: true,
          rowIndex: nil
        )
      }
      return visible
    }

    return Array(displayLines.prefix(viewportLineCount))
  }

  private func materializedListLines(
    for payload: ListPayload,
    style: ResolvedListStyle
  ) -> [ListDisplayLine] {
    var lines: [ListDisplayLine] = []
    var rowIndex = 0

    for (index, item) in payload.items.enumerated() {
      switch item.kind {
      case .header:
        var styleOverride = item.style
        if styleOverride.foregroundStyle == nil {
          styleOverride.foregroundStyle = AnyShapeStyle(.terminalBorder(.accent))
        }
        styleOverride.opacity *= payload.opacity
        lines.append(
          .init(
            kind: .text(item.text, styleOverride),
            isHeader: true,
            rowIndex: nil
          )
        )
      case .footer:
        var styleOverride = item.style
        if styleOverride.foregroundStyle == nil {
          styleOverride.foregroundStyle = .semantic(.muted)
        }
        styleOverride.opacity *= payload.opacity
        lines.append(
          .init(
            kind: .text(item.text, styleOverride),
            isHeader: true,
            rowIndex: nil
          )
        )
      case .row:
        var styleOverride = item.style
        if let rowForegroundStyle = item.rowForegroundStyle {
          styleOverride.foregroundStyle = rowForegroundStyle
        } else if styleOverride.foregroundStyle == nil {
          styleOverride.foregroundStyle = payload.foregroundStyle ?? .semantic(.foreground)
        }
        styleOverride.opacity *= payload.opacity
        let isSelected = rowIndex == payload.selectedRowIndex
        let marker =
          payload.showsSelectionMarker
          ? (isSelected ? "▌ " : "  ")
          : ""
        let markerStyle = TextStyle(
          foregroundStyle: isSelected
            ? (payload.selectedRowMarkerStyle ?? payload.selectedRowForegroundStyle ?? payload
              .foregroundStyle ?? .semantic(.foreground))
            : payload.borderStyle ?? .semantic(.separator),
          opacity: payload.opacity
        )
        if isSelected, let selectedForegroundStyle = payload.selectedRowForegroundStyle {
          styleOverride.foregroundStyle = selectedForegroundStyle
        }
        lines.append(
          .init(
            kind: .row(
              marker: marker,
              markerStyle: markerStyle,
              text: item.text,
              textStyle: styleOverride,
              backgroundStyle: isSelected
                ? (payload.selectedRowBackgroundStyle ?? item.rowBackgroundStyle)
                : item.rowBackgroundStyle
            ),
            isHeader: false,
            rowIndex: rowIndex
          )
        )

        if style == .plain,
          shouldRenderRowSeparator(
            current: item,
            next: payload.items.dropFirst(index + 1).first
          )
        {
          lines.append(
            .init(
              kind: .separator(payload.borderStyle ?? .semantic(.separator)),
              isHeader: false,
              rowIndex: nil
            )
          )
        }
        rowIndex += 1
      case .sectionBreak:
        guard style == .plain, listSectionSeparatorIsVisible(item) else {
          continue
        }
        lines.append(
          .init(
            kind: .separator(payload.borderStyle ?? .semantic(.separator)),
            isHeader: true,
            rowIndex: nil
          )
        )
      }
    }

    return lines
  }

  private func shouldRenderRowSeparator(
    current: ListItemPayload,
    next: ListItemPayload?
  ) -> Bool {
    guard let next, next.kind == .row else {
      return false
    }
    if current.rowSeparators.bottom == .hidden || next.rowSeparators.top == .hidden {
      return false
    }
    return true
  }

  private func listSectionSeparatorIsVisible(
    _ item: ListItemPayload
  ) -> Bool {
    if item.sectionSeparators.bottom == .hidden || item.sectionSeparators.top == .hidden {
      return false
    }
    return true
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

  private func selectedListLineIndex(
    in lines: [ListDisplayLine]
  ) -> Int? {
    lines.firstIndex { line in
      switch line.kind {
      case .text(let content, _):
        return content.hasPrefix("> ")
      case .row(let marker, _, _, _, _):
        return marker != "  "
      case .separator:
        return false
      }
    }
  }
}
