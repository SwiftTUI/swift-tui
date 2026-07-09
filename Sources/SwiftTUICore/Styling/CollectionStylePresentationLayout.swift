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
            rowIndex: nil
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
            rowIndex: rowIndex
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
            rowIndex: nil
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
