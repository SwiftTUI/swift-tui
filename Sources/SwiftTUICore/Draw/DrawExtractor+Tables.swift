extension DrawExtractor {
  func tableCommands(
    for payload: TablePayload,
    in bounds: CellRect,
    hostsCommittedItems: Bool = false,
    columnWidths: [Int]? = nil
  ) -> [DrawCommand] {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return []
    }

    var commands: [DrawCommand] = []
    if let backgroundStyle = payload.backgroundStyle {
      commands.append(
        .fill(
          bounds: bounds,
          geometry: .rectangle,
          insetAmount: 0,
          style: backgroundStyle,
          mode: .full
        )
      )
    }

    let layout = visibleTableLayout(
      for: payload,
      in: bounds,
      columnWidths: columnWidths
    )
    let lines = layout.lines

    for (index, line) in lines.enumerated() {
      let lineBounds = CellRect(
        origin: .init(x: bounds.origin.x, y: bounds.origin.y + index),
        size: .init(width: bounds.size.width, height: 1)
      )

      if let backgroundStyle = line.backgroundStyle {
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

      var cursorX = lineBounds.origin.x
      let lineMaxX = lineBounds.origin.x + lineBounds.size.width

      let segments: [TableDisplaySegment]
      if hostsCommittedItems, line.role == .row, line.segments.count >= 2 {
        // Keep the row's outer border behind committed cell nodes. Column
        // separators are drawn between the hosted cell frames below.
        let borderStyle = TextStyle(
          foregroundStyle: payload.borderStyle ?? .semantic(.separator),
          opacity: payload.opacity
        )
        let widths = layout.widths
        segments = rowSegments(
          cells: widths.map { width in
            .init(content: String(repeating: " ", count: width), style: .init())
          },
          borderStyle: borderStyle,
          glyphs: payload.style.tableBorderGlyphs
        )
      } else {
        segments = line.segments
      }

      for segment in segments {
        let segmentWidth = layoutText(for: segment.content, width: nil).size.width
        guard segmentWidth > 0 else {
          continue
        }
        if cursorX >= lineMaxX {
          break
        }

        let visibleWidth = min(segmentWidth, lineMaxX - cursorX)
        guard visibleWidth > 0 else {
          continue
        }

        commands.append(
          .text(
            bounds: .init(
              origin: .init(x: cursorX, y: lineBounds.origin.y),
              size: .init(width: visibleWidth, height: 1)
            ),
            content: segment.content,
            style: segment.style,
            lineLimit: 1,
            truncationMode: .tail,
            wrappingStrategy: .wordBoundary
          )
        )
        cursorX += segmentWidth
      }
    }

    return commands
  }

  func visibleTableLayout(
    for payload: TablePayload,
    in bounds: CellRect,
    columnWidths: [Int]? = nil
  ) -> (lines: [TableDisplayLine], widths: [Int]) {
    let widths =
      columnWidths
      ?? measureTableColumnWidths(
        columns: payload.columns,
        rows: payload.isViewportBacked ? [] : payload.rows
      )
    let lines = visibleTableLines(
      for: payload,
      viewportLineCount: bounds.size.height,
      showsIndicators: payload.showsIndicators,
      widths: widths
    )
    return (lines, widths)
  }

  private func visibleTableLines(
    for payload: TablePayload,
    viewportLineCount: Int,
    showsIndicators: Bool,
    widths: [Int]
  ) -> [TableDisplayLine] {
    if payload.isViewportBacked {
      return viewportBackedVisibleTableLines(
        for: payload,
        viewportLineCount: viewportLineCount,
        showsIndicators: showsIndicators,
        widths: widths
      )
    }
    let displayLines = materializedTableLines(
      for: payload,
      widths: widths
    )

    guard viewportLineCount > 0 else {
      return []
    }
    guard displayLines.count > viewportLineCount else {
      return displayLines
    }

    let fixedTopCount = min(displayLines.count, payload.showsHeaders ? 3 : 1)
    let fixedBottomCount = displayLines.isEmpty ? 0 : 1
    guard viewportLineCount > fixedTopCount + fixedBottomCount else {
      return Array(displayLines.prefix(viewportLineCount))
    }

    let bodyStart = fixedTopCount
    let bodyEnd = max(bodyStart, displayLines.count - fixedBottomCount)
    let bodyLines = Array(displayLines[bodyStart..<bodyEnd])
    let bodyCapacity = viewportLineCount - fixedTopCount - fixedBottomCount

    if bodyLines.count <= bodyCapacity {
      return Array(displayLines.prefix(fixedTopCount))
        + bodyLines
        + Array(displayLines.suffix(fixedBottomCount))
    }

    if !showsIndicators {
      let window = visibleTableBodyWindow(
        from: bodyLines,
        lineCapacity: bodyCapacity
      )
      return Array(displayLines.prefix(fixedTopCount))
        + window.lines
        + Array(displayLines.suffix(fixedBottomCount))
    }

    let anchoredOffset =
      selectedTableLineIndex(in: bodyLines).map {
        min(
          max(0, $0 - (bodyCapacity / 2)),
          max(0, bodyLines.count - bodyCapacity)
        )
      } ?? 0
    let anchoredEnd = min(bodyLines.count, anchoredOffset + bodyCapacity)
    let initialHiddenAbove = anchoredOffset > 0
    let initialHiddenBelow = anchoredEnd < bodyLines.count
    let reservedIndicators =
      (initialHiddenAbove ? 1 : 0)
      + (initialHiddenBelow ? 1 : 0)
    let bodyWindowCapacity = max(1, bodyCapacity - reservedIndicators)
    let window = visibleTableBodyWindow(
      from: bodyLines,
      lineCapacity: bodyWindowCapacity
    )
    let hiddenAbove = window.offset > 0
    let hiddenBelow = window.offset + window.lines.count < bodyLines.count

    var visibleBody: [TableDisplayLine] = []
    visibleBody.reserveCapacity(bodyCapacity)
    if hiddenAbove {
      visibleBody.append(
        overflowIndicatorLine(
          widths: widths,
          payload: payload,
          symbol: "↑"
        )
      )
    }
    visibleBody.append(contentsOf: window.lines)
    if hiddenBelow, visibleBody.count < bodyCapacity {
      visibleBody.append(
        overflowIndicatorLine(
          widths: widths,
          payload: payload,
          symbol: "↓"
        )
      )
    }

    return Array(displayLines.prefix(fixedTopCount))
      + Array(visibleBody.prefix(bodyCapacity))
      + Array(displayLines.suffix(fixedBottomCount))
  }

  private func viewportBackedVisibleTableLines(
    for payload: TablePayload,
    viewportLineCount: Int,
    showsIndicators: Bool,
    widths: [Int]
  ) -> [TableDisplayLine] {
    guard viewportLineCount > 0 else {
      return []
    }

    var chromePayload = payload
    chromePayload.rows = []
    chromePayload.selectedRowIndex = nil
    chromePayload.isViewportBacked = false
    let chrome = materializedTableLines(for: chromePayload, widths: widths)
    let top = Array(chrome.dropLast())
    let bottom = chrome.last.map { [$0] } ?? []
    guard viewportLineCount > top.count + bottom.count else {
      return Array(top.prefix(viewportLineCount))
    }

    let bodyLineCount = payload.rows.isEmpty ? 0 : payload.rows.count * 2 - 1
    let bodyCapacity = viewportLineCount - top.count - bottom.count
    guard bodyLineCount > bodyCapacity else {
      return top
        + viewportBackedTableBodyLines(
          positions: 0..<bodyLineCount,
          payload: payload,
          widths: widths
        )
        + bottom
    }

    let selectedLine = min(
      max((payload.selectedRowIndex ?? 0) * 2, 0),
      max(0, bodyLineCount - 1)
    )
    func window(capacity: Int) -> (offset: Int, end: Int) {
      let offset = min(
        max(0, selectedLine - capacity / 2),
        max(0, bodyLineCount - capacity)
      )
      return (offset, min(bodyLineCount, offset + capacity))
    }

    guard showsIndicators else {
      let range = window(capacity: bodyCapacity)
      return top
        + viewportBackedTableBodyLines(
          positions: range.offset..<range.end,
          payload: payload,
          widths: widths
        )
        + bottom
    }

    let initial = window(capacity: bodyCapacity)
    let reservedIndicators =
      (initial.offset > 0 ? 1 : 0)
      + (initial.end < bodyLineCount ? 1 : 0)
    let bodyWindowCapacity = max(1, bodyCapacity - reservedIndicators)
    let range = window(capacity: bodyWindowCapacity)
    var visibleBody: [TableDisplayLine] = []
    visibleBody.reserveCapacity(bodyCapacity)
    if range.offset > 0 {
      visibleBody.append(
        overflowIndicatorLine(widths: widths, payload: payload, symbol: "↑")
      )
    }
    visibleBody.append(
      contentsOf: viewportBackedTableBodyLines(
        positions: range.offset..<range.end,
        payload: payload,
        widths: widths
      )
    )
    if range.end < bodyLineCount, visibleBody.count < bodyCapacity {
      visibleBody.append(
        overflowIndicatorLine(widths: widths, payload: payload, symbol: "↓")
      )
    }
    return top + Array(visibleBody.prefix(bodyCapacity)) + bottom
  }

  private func viewportBackedTableBodyLines(
    positions: Range<Int>,
    payload: TablePayload,
    widths: [Int]
  ) -> [TableDisplayLine] {
    let borderStyle = TextStyle(
      foregroundStyle: payload.borderStyle ?? .semantic(.separator),
      opacity: payload.opacity
    )
    let glyphs = payload.style.tableBorderGlyphs
    return positions.map { position in
      if position % 2 == 1 {
        return TableDisplayLine(
          segments: borderSegments(
            widths: widths,
            glyphs: glyphs,
            position: .middle,
            style: borderStyle
          ),
          backgroundStyle: nil,
          role: .rowSeparator,
          isSelectedRow: false,
          rowIndex: nil
        )
      }

      let rowIndex = position / 2
      let row = payload.rows[rowIndex]
      let isSelected = rowIndex == payload.selectedRowIndex
      let rowTextStyle = resolvedTableRowTextStyle(
        row: row,
        payload: payload,
        isSelected: isSelected
      )
      let cellSegments = widths.enumerated().map { columnIndex, width in
        let content = columnIndex < row.cells.count ? row.cells[columnIndex].text : ""
        let cellStyle =
          columnIndex < row.cells.count
          ? resolvedTableCellTextStyle(
            cell: row.cells[columnIndex],
            rowStyle: rowTextStyle,
            payload: payload,
            isSelected: isSelected
          )
          : rowTextStyle
        return TableDisplaySegment(
          content: renderTableCell(
            content,
            width: width,
            alignment: payload.columns[columnIndex].alignment
          ),
          style: cellStyle
        )
      }
      return TableDisplayLine(
        segments: rowSegments(
          cells: cellSegments,
          borderStyle: borderStyle,
          glyphs: glyphs
        ),
        backgroundStyle: isSelected
          ? (payload.selectedRowBackgroundStyle ?? row.rowBackgroundStyle)
          : row.rowBackgroundStyle,
        role: .row,
        isSelectedRow: isSelected,
        rowIndex: rowIndex
      )
    }
  }

  private func materializedTableLines(
    for payload: TablePayload,
    widths: [Int]
  ) -> [TableDisplayLine] {
    let borderStyle = TextStyle(
      foregroundStyle: payload.borderStyle ?? .semantic(.separator),
      opacity: payload.opacity
    )
    let glyphs = payload.style.tableBorderGlyphs
    var lines: [TableDisplayLine] = [
      .init(
        segments: borderSegments(
          widths: widths,
          glyphs: glyphs,
          position: .top,
          style: borderStyle
        ),
        backgroundStyle: nil,
        role: .topBorder,
        isSelectedRow: false,
        rowIndex: nil
      )
    ]

    if payload.showsHeaders {
      var headerStyle = TextStyle(
        foregroundStyle: payload.style.tableHeaderForegroundStyle ?? .semantic(.muted)
      )
      headerStyle.opacity *= payload.opacity
      lines.append(
        .init(
          segments: rowSegments(
            cells: payload.columns.enumerated().map { index, column in
              .init(
                content: renderTableCell(
                  column.title,
                  width: widths[index],
                  alignment: column.titleAlignment
                ),
                style: headerStyle
              )
            },
            borderStyle: borderStyle,
            glyphs: glyphs
          ),
          backgroundStyle: payload.style.tableHeaderBackgroundStyle,
          role: .header,
          isSelectedRow: false,
          rowIndex: nil
        )
      )
      lines.append(
        .init(
          segments: borderSegments(
            widths: widths,
            glyphs: glyphs,
            position: .middle,
            style: borderStyle
          ),
          backgroundStyle: nil,
          role: .headerSeparator,
          isSelectedRow: false,
          rowIndex: nil
        )
      )
    }

    for (index, row) in payload.rows.enumerated() {
      let isSelected = index == payload.selectedRowIndex
      let rowTextStyle = resolvedTableRowTextStyle(
        row: row,
        payload: payload,
        isSelected: isSelected
      )
      let cellSegments = widths.enumerated().map { columnIndex, width in
        let content = columnIndex < row.cells.count ? row.cells[columnIndex].text : ""
        let cellStyle =
          columnIndex < row.cells.count
          ? resolvedTableCellTextStyle(
            cell: row.cells[columnIndex],
            rowStyle: rowTextStyle,
            payload: payload,
            isSelected: isSelected
          )
          : rowTextStyle
        return TableDisplaySegment(
          content: renderTableCell(
            content,
            width: width,
            alignment: payload.columns[columnIndex].alignment
          ),
          style: cellStyle
        )
      }

      lines.append(
        .init(
          segments: rowSegments(
            cells: cellSegments,
            borderStyle: borderStyle,
            glyphs: glyphs
          ),
          backgroundStyle: isSelected
            ? (payload.selectedRowBackgroundStyle ?? row.rowBackgroundStyle)
            : row.rowBackgroundStyle,
          role: .row,
          isSelectedRow: isSelected,
          rowIndex: index
        )
      )

      if shouldRenderTableRowSeparator(
        current: row,
        next: payload.rows.dropFirst(index + 1).first
      ) {
        lines.append(
          .init(
            segments: borderSegments(
              widths: widths,
              glyphs: glyphs,
              position: .middle,
              style: borderStyle
            ),
            backgroundStyle: nil,
            role: .rowSeparator,
            isSelectedRow: false,
            rowIndex: nil
          )
        )
      }
    }

    lines.append(
      .init(
        segments: borderSegments(
          widths: widths,
          glyphs: glyphs,
          position: .bottom,
          style: borderStyle
        ),
        backgroundStyle: nil,
        role: .bottomBorder,
        isSelectedRow: false,
        rowIndex: nil
      )
    )

    return lines
  }

  private func visibleTableBodyWindow(
    from bodyLines: [TableDisplayLine],
    lineCapacity: Int
  ) -> (offset: Int, lines: [TableDisplayLine]) {
    guard lineCapacity > 0 else {
      return (0, [])
    }

    let selectedIndex = selectedTableLineIndex(in: bodyLines) ?? 0
    let offset = min(
      max(0, selectedIndex - (lineCapacity / 2)),
      max(0, bodyLines.count - lineCapacity)
    )
    let end = min(bodyLines.count, offset + lineCapacity)
    return (offset, Array(bodyLines[offset..<end]))
  }

  private func shouldRenderTableRowSeparator(
    current: TableRowPayload,
    next: TableRowPayload?
  ) -> Bool {
    guard let next else {
      return false
    }
    if current.rowSeparators.bottom == .hidden || next.rowSeparators.top == .hidden {
      return false
    }
    return true
  }

  private func selectedTableLineIndex(
    in lines: [TableDisplayLine]
  ) -> Int? {
    lines.firstIndex(where: \.isSelectedRow)
  }
}
