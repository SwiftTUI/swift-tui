extension DrawExtractor {
  func tableCommands(
    for payload: TablePayload,
    in bounds: CellRect
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

    let lines = visibleTableLayout(
      for: payload,
      in: bounds
    ).lines

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

      for segment in line.segments {
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
    in bounds: CellRect
  ) -> (lines: [TableDisplayLine], widths: [Int]) {
    let widths = measureTableColumnWidths(
      columns: payload.columns,
      rows: payload.rows
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
