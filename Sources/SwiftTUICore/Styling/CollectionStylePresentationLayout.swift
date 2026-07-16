extension CollectionStylePresentation {
  package func visibleListLayout(
    for payload: ListPayload,
    in bounds: CellRect
  ) -> ListVisibleLayout {
    let contentBounds = listContentBounds(in: bounds)
    let lines = visibleListLines(
      for: payload,
      viewportLineCount: contentBounds.size.height
    )

    return ListVisibleLayout(
      contentBounds: contentBounds,
      lines: lines,
      sectionChromeBounds: listChromeBounds(for: lines, in: contentBounds)
    )
  }

  package func listChromeBounds(
    for layout: ListVisibleLayout,
    in bounds: CellRect
  ) -> [CellRect] {
    guard listContainer != nil else {
      return []
    }

    switch listChromeScope {
    case .wholeList:
      return [bounds]
    case .eachSection:
      return layout.sectionChromeBounds
    }
  }

  package func measuredListIdealSize(
    for payload: ListPayload
  ) -> CellSize {
    if payload.isViewportBacked {
      let horizontalInset = listContentInsets.leading + listContentInsets.trailing
      let verticalInset = listContentInsets.top + listContentInsets.bottom
      let separatorCount = showsListRowSeparators ? max(0, payload.items.count - 1) : 0
      let markerWidth = payload.showsSelectionMarker && !payload.items.isEmpty ? 2 : 0
      return CellSize(
        width: markerWidth + horizontalInset,
        height: payload.items.count + separatorCount + verticalInset
      )
    }
    let horizontalInset = listContentInsets.leading + listContentInsets.trailing
    let perSectionVerticalInset = listContentInsets.top + listContentInsets.bottom
    let usesSectionChrome = listContainer != nil && listChromeScope == .eachSection
    let lineMetrics = payload.items.enumerated().reduce(
      into: (width: 0, height: 0, rowIndex: 0, sectionCount: 0, sectionHasContent: false)
    ) { partial, element in
      let (index, item) = element
      switch item.kind {
      case .header, .footer:
        partial.width = max(
          partial.width, layoutText(for: item.text, width: nil).size.width)
        partial.height += 1
        partial.sectionHasContent = true
      case .row:
        let prefix =
          if payload.showsSelectionMarker {
            partial.rowIndex == payload.selectedRowIndex ? "> " : "  "
          } else {
            ""
          }
        partial.width = max(
          partial.width,
          layoutText(for: prefix + item.text, width: nil).size.width
        )
        partial.height += 1
        partial.sectionHasContent = true
        if showsListRowSeparators,
          listRowSeparatorIsVisible(
            current: item,
            next: payload.items.dropFirst(index + 1).first
          )
        {
          partial.width = max(partial.width, 1)
          partial.height += 1
        }
        partial.rowIndex += 1
      case .sectionBreak:
        if usesSectionChrome {
          if partial.sectionHasContent {
            partial.sectionCount += 1
            partial.sectionHasContent = false
          }
          return
        }
        if showsListSectionSeparators, listSectionSeparatorIsVisible(item) {
          partial.height += 1
          partial.width = max(partial.width, 1)
        }
      }
    }
    let sectionCount =
      if usesSectionChrome {
        lineMetrics.sectionCount + (lineMetrics.sectionHasContent ? 1 : 0)
      } else {
        0
      }
    let verticalInset =
      if usesSectionChrome {
        max(1, sectionCount) * perSectionVerticalInset
      } else {
        perSectionVerticalInset
      }

    return CellSize(
      width: lineMetrics.width + horizontalInset,
      height: lineMetrics.height + verticalInset
    )
  }

  private func listContentBounds(
    in bounds: CellRect
  ) -> CellRect {
    let verticalInsets =
      listContainer != nil && listChromeScope == .eachSection
      ? (top: 0, bottom: 0)
      : (top: listContentInsets.top, bottom: listContentInsets.bottom)
    return CellRect(
      origin: .init(
        x: bounds.origin.x + listContentInsets.leading,
        y: bounds.origin.y + verticalInsets.top
      ),
      size: .init(
        width: max(0, bounds.size.width - listContentInsets.leading - listContentInsets.trailing),
        height: max(0, bounds.size.height - verticalInsets.top - verticalInsets.bottom)
      )
    )
  }

  private func visibleListLines(
    for payload: ListPayload,
    viewportLineCount: Int
  ) -> [ListDisplayLine] {
    if payload.isViewportBacked {
      return viewportBackedVisibleListLines(
        for: payload,
        viewportLineCount: viewportLineCount
      )
    }
    let displayLines = materializedListLines(for: payload)
    guard viewportLineCount > 0 else {
      return []
    }

    if displayLines.count > viewportLineCount {
      let visibleLineCount =
        payload.showsIndicators && viewportLineCount >= 3
        ? max(1, viewportLineCount - 2)
        : viewportLineCount
      let selectedLineIndex = selectedListLineIndex(
        in: displayLines,
        selectedRowIndex: payload.selectedRowIndex
      )
      let lineIndex = min(
        max(selectedLineIndex ?? 0, 0),
        max(0, displayLines.count - 1)
      )
      let offset = min(
        max(0, lineIndex - (visibleLineCount / 2)),
        max(0, displayLines.count - visibleLineCount)
      )
      let end = min(displayLines.count, offset + visibleLineCount)
      guard payload.showsIndicators, viewportLineCount >= 3 else {
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

  private func viewportBackedVisibleListLines(
    for payload: ListPayload,
    viewportLineCount: Int
  ) -> [ListDisplayLine] {
    guard viewportLineCount > 0, !payload.items.isEmpty else {
      return []
    }

    let usesSectionChrome = listContainer != nil && listChromeScope == .eachSection
    let sectionInsetCount = usesSectionChrome ? 2 : 0
    let rowSpan = showsListRowSeparators ? 2 : 1
    let bodyLineCount = payload.items.count * rowSpan - (rowSpan - 1)
    let displayLineCount = sectionInsetCount + bodyLineCount
    let visibleLineCount =
      displayLineCount > viewportLineCount && payload.showsIndicators && viewportLineCount >= 3
      ? max(1, viewportLineCount - 2)
      : viewportLineCount
    let selectedRow = min(
      max(payload.selectedRowIndex ?? 0, 0),
      payload.items.count - 1
    )
    let selectedLineIndex = (usesSectionChrome ? 1 : 0) + selectedRow * rowSpan
    let offset = min(
      max(0, selectedLineIndex - (visibleLineCount / 2)),
      max(0, displayLineCount - visibleLineCount)
    )
    let end = min(displayLineCount, offset + visibleLineCount)
    var visible = (offset..<end).map { position in
      viewportBackedListLine(
        at: position,
        payload: payload,
        usesSectionChrome: usesSectionChrome,
        rowSpan: rowSpan,
        bodyLineCount: bodyLineCount
      )
    }

    guard displayLineCount > viewportLineCount,
      payload.showsIndicators,
      viewportLineCount >= 3
    else {
      return visible
    }

    let indicatorStyle = TextStyle(
      foregroundStyle: .semantic(.separator),
      opacity: payload.opacity
    )
    visible.insert(
      .init(
        kind: .text(offset == 0 ? "" : "↑", indicatorStyle),
        isHeader: true,
        rowIndex: nil
      ),
      at: 0
    )
    visible.append(
      .init(
        kind: .text(end >= displayLineCount ? "" : "↓", indicatorStyle),
        isHeader: true,
        rowIndex: nil
      )
    )
    return visible
  }

  private func viewportBackedListLine(
    at position: Int,
    payload: ListPayload,
    usesSectionChrome: Bool,
    rowSpan: Int,
    bodyLineCount: Int
  ) -> ListDisplayLine {
    let bodyPosition = position - (usesSectionChrome ? 1 : 0)
    if bodyPosition < 0 || bodyPosition >= bodyLineCount {
      return .init(
        kind: .text("", .init(opacity: payload.opacity)),
        isHeader: true,
        rowIndex: nil,
        sectionIndex: usesSectionChrome ? 0 : nil
      )
    }
    if rowSpan == 2, bodyPosition % 2 == 1 {
      return .init(
        kind: .separator(payload.borderStyle ?? .semantic(.separator)),
        isHeader: false,
        rowIndex: nil,
        sectionIndex: usesSectionChrome ? 0 : nil
      )
    }

    let rowIndex = bodyPosition / rowSpan
    let item = payload.items[rowIndex]
    let isSelected = rowIndex == payload.selectedRowIndex
    var style = item.style
    if let rowForegroundStyle = item.rowForegroundStyle {
      style.foregroundStyle = rowForegroundStyle
    } else if style.foregroundStyle == nil {
      style.foregroundStyle = payload.foregroundStyle ?? .semantic(.foreground)
    }
    if isSelected, let selectedForegroundStyle = payload.selectedRowForegroundStyle {
      style.foregroundStyle = selectedForegroundStyle
    }
    style.opacity *= payload.opacity
    let marker = payload.showsSelectionMarker ? (isSelected ? "▌ " : "  ") : ""
    let markerStyle = TextStyle(
      foregroundStyle: isSelected
        ? (payload.selectedRowMarkerStyle ?? payload.selectedRowForegroundStyle
          ?? payload.foregroundStyle ?? .semantic(.foreground))
        : payload.borderStyle ?? .semantic(.separator),
      opacity: payload.opacity
    )
    return .init(
      kind: .row(
        marker: marker,
        markerStyle: markerStyle,
        text: item.text,
        textStyle: style,
        backgroundStyle: isSelected
          ? (payload.selectedRowBackgroundStyle ?? item.rowBackgroundStyle)
          : item.rowBackgroundStyle
      ),
      isHeader: false,
      rowIndex: rowIndex,
      sectionIndex: usesSectionChrome ? 0 : nil,
      itemIndex: rowIndex
    )
  }

  private func materializedListLines(
    for payload: ListPayload
  ) -> [ListDisplayLine] {
    var lines: [ListDisplayLine] = []
    var sectionLines: [ListDisplayLine] = []
    var sectionIndex = 0
    var rowIndex = 0
    let usesSectionChrome = listContainer != nil && listChromeScope == .eachSection

    func appendLine(_ line: ListDisplayLine) {
      if usesSectionChrome {
        sectionLines.append(line)
      } else {
        lines.append(line)
      }
    }

    func flushSection() {
      guard usesSectionChrome, !sectionLines.isEmpty else {
        return
      }

      let spacerStyle = TextStyle(opacity: payload.opacity)
      lines.append(
        .init(
          kind: .text("", spacerStyle),
          isHeader: true,
          rowIndex: nil,
          sectionIndex: sectionIndex
        )
      )
      lines.append(
        contentsOf: sectionLines.map { line in
          var sectionLine = line
          sectionLine.sectionIndex = sectionIndex
          return sectionLine
        }
      )
      lines.append(
        .init(
          kind: .text("", spacerStyle),
          isHeader: true,
          rowIndex: nil,
          sectionIndex: sectionIndex
        )
      )
      sectionLines.removeAll(keepingCapacity: true)
      sectionIndex += 1
    }

    for (index, item) in payload.items.enumerated() {
      switch item.kind {
      case .header:
        var styleOverride = item.style
        if styleOverride.foregroundStyle == nil {
          styleOverride.foregroundStyle = AnyShapeStyle(.terminalBorder(.accent))
        }
        styleOverride.opacity *= payload.opacity
        appendLine(
          .init(
            kind: .text(item.text, styleOverride),
            isHeader: true,
            rowIndex: nil,
            itemIndex: index
          )
        )
      case .footer:
        var styleOverride = item.style
        if styleOverride.foregroundStyle == nil {
          styleOverride.foregroundStyle = .semantic(.muted)
        }
        styleOverride.opacity *= payload.opacity
        appendLine(
          .init(
            kind: .text(item.text, styleOverride),
            isHeader: true,
            rowIndex: nil,
            itemIndex: index
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
        appendLine(
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
            rowIndex: rowIndex,
            itemIndex: index
          )
        )

        if showsListRowSeparators,
          listRowSeparatorIsVisible(
            current: item,
            next: payload.items.dropFirst(index + 1).first
          )
        {
          appendLine(
            .init(
              kind: .separator(payload.borderStyle ?? .semantic(.separator)),
              isHeader: false,
              rowIndex: nil
            )
          )
        }
        rowIndex += 1
      case .sectionBreak:
        if usesSectionChrome {
          flushSection()
          continue
        }
        guard showsListSectionSeparators,
          listSectionSeparatorIsVisible(item)
        else {
          continue
        }
        lines.append(
          .init(
            kind: .separator(payload.borderStyle ?? .semantic(.separator)),
            isHeader: true,
            rowIndex: nil,
            itemIndex: index
          )
        )
      }
    }

    if usesSectionChrome {
      flushSection()
      if payload.items.isEmpty {
        let spacerStyle = TextStyle(opacity: payload.opacity)
        lines.append(
          .init(
            kind: .text("", spacerStyle),
            isHeader: true,
            rowIndex: nil,
            sectionIndex: sectionIndex
          )
        )
        lines.append(
          .init(
            kind: .text("", spacerStyle),
            isHeader: true,
            rowIndex: nil,
            sectionIndex: sectionIndex
          )
        )
      }
    }

    return lines
  }

  private func listChromeBounds(
    for lines: [ListDisplayLine],
    in contentBounds: CellRect
  ) -> [CellRect] {
    guard listContainer != nil, listChromeScope == .eachSection, !lines.isEmpty else {
      return []
    }

    var bounds: [CellRect] = []
    var rangeStart: Int?
    var activeSectionIndex: Int?

    func appendRange(endingAt endIndex: Int) {
      guard let start = rangeStart else {
        return
      }
      bounds.append(
        CellRect(
          origin: .init(
            x: contentBounds.origin.x - listContentInsets.leading,
            y: contentBounds.origin.y + start
          ),
          size: .init(
            width: contentBounds.size.width + listContentInsets.leading
              + listContentInsets.trailing,
            height: endIndex - start
          )
        )
      )
    }

    for (index, line) in lines.enumerated() {
      guard let sectionIndex = line.sectionIndex else {
        appendRange(endingAt: index)
        rangeStart = nil
        activeSectionIndex = nil
        continue
      }

      if activeSectionIndex != sectionIndex {
        appendRange(endingAt: index)
        rangeStart = index
        activeSectionIndex = sectionIndex
      }
    }

    appendRange(endingAt: lines.count)
    return bounds
  }

  private func selectedListLineIndex(
    in lines: [ListDisplayLine],
    selectedRowIndex: Int?
  ) -> Int? {
    if let selectedRowIndex,
      let selectedIndex = lines.firstIndex(where: { line in
        line.rowIndex == selectedRowIndex
      })
    {
      return selectedIndex
    }

    return lines.firstIndex { line in line.rowIndex != nil }
  }

  private func listRowSeparatorIsVisible(
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
}
