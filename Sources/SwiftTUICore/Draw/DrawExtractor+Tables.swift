import Synchronization

/// Test instrumentation (the F118 probe pattern), the table twin of
/// ``ListLayoutDerivationProbe``: counts how many times a table's visible
/// layout is DERIVED, as opposed to consumed from the measured product.
/// Increments compile out of release.
package enum TableLayoutDerivationProbe {
  private static let counter = Mutex<Int>(0)

  package static var derivationCount: Int {
    counter.withLock { $0 }
  }

  package static func recordDerivation() {
    #if DEBUG
      counter.withLock { $0 += 1 }
    #endif
  }

  package static func reset() {
    #if DEBUG
      counter.withLock { $0 = 0 }
    #endif
  }
}

/// The visible display lines of a table, the column widths they were laid out
/// against, and the rect they occupy.
///
/// The table twin of ``ListVisibleLayout``: derived once at measure from the
/// real measured row heights, translated by placement, and consumed by draw
/// and semantics rather than re-derived by each.
package struct TableVisibleLayout: Equatable, Sendable {
  package var contentBounds: CellRect
  package var lines: [TableDisplayLine]
  package var widths: [Int]
  /// Total cells the visible lines occupy, which exceeds `lines.count`
  /// whenever a hosted row measured taller than one cell.
  package var totalContentHeight: Int

  package init(
    contentBounds: CellRect,
    lines: [TableDisplayLine],
    widths: [Int],
    totalContentHeight: Int? = nil
  ) {
    self.contentBounds = contentBounds
    self.lines = lines
    self.widths = widths
    self.totalContentHeight =
      totalContentHeight ?? lines.reduce(0) { $0 + max(1, $1.height) }
  }

  /// Returns a copy translated into absolute coordinates by `delta`.
  package func translated(by delta: CellPoint) -> TableVisibleLayout {
    var copy = self
    copy.contentBounds = CellRect(
      origin: .init(x: contentBounds.origin.x + delta.x, y: contentBounds.origin.y + delta.y),
      size: contentBounds.size
    )
    return copy
  }
}

extension DrawExtractor {
  func tableCommands(
    for payload: TablePayload,
    in bounds: CellRect,
    hostsCommittedItems: Bool = false,
    columnWidths: [Int]? = nil,
    placedLayout: TableVisibleLayout? = nil
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

    // The placed product when there is one — that is what keeps a tall row's
    // borders on the same cells as its content. The recompute stays for
    // payload-only callers, whose rows are all one cell tall.
    let layout =
      placedLayout
      ?? visibleTableLayout(
        for: payload,
        in: bounds,
        columnWidths: columnWidths
      )
    let contentBounds = layout.contentBounds
    let lines = layout.lines

    for line in lines {
      let lineBounds = CellRect(
        origin: .init(x: contentBounds.origin.x, y: contentBounds.origin.y + line.yOffset),
        size: .init(width: contentBounds.size.width, height: max(1, line.height))
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

      // A hosted row taller than one cell needs its outer border on every cell
      // it spans, not just its first — the border is chrome the table owns,
      // and the committed child only paints the interior.
      let cellCount = hostsCommittedItems && line.role == .row ? lineBounds.size.height : 1
      for cellOffset in 0..<max(1, cellCount) {
        var cursorX = lineBounds.origin.x
        let lineMaxX = lineBounds.origin.x + lineBounds.size.width

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
                origin: .init(x: cursorX, y: lineBounds.origin.y + cellOffset),
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
    }

    return commands
  }

  /// The visible display lines for `payload` inside `bounds`, with each line's
  /// height and content-relative `yOffset` resolved.
  ///
  /// `rowHeights` maps a row index to the cells its hosted child measured.
  /// Absent (payload-only callers, and any row not in the map) a row is one
  /// cell tall — the historical model, so those callers are unaffected.
  /// Supplying it is what makes measure, place, draw, and semantics agree on
  /// where a tall row's borders and separators go (register item D19).
  func visibleTableLayout(
    for payload: TablePayload,
    in bounds: CellRect,
    columnWidths: [Int]? = nil,
    rowHeights: [Int: Int]? = nil
  ) -> TableVisibleLayout {
    TableLayoutDerivationProbe.recordDerivation()
    let widths =
      columnWidths
      ?? measureTableColumnWidths(
        columns: payload.columns,
        rows: payload.isViewportBacked ? [] : payload.rows
      )
    var lines = visibleTableLines(
      for: payload,
      viewportLineCount: bounds.size.height,
      showsIndicators: payload.showsIndicators,
      widths: widths
    )
    var cursor = 0
    for index in lines.indices {
      let height =
        lines[index].role == .row
        ? (lines[index].rowIndex.flatMap { rowHeights?[$0] }.map { max(1, $0) } ?? 1)
        : 1
      lines[index].height = height
      lines[index].yOffset = cursor
      cursor += height
    }
    return TableVisibleLayout(
      contentBounds: bounds,
      lines: lines,
      widths: widths,
      totalContentHeight: cursor
    )
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
    // A stored anchor pins the top of the body window; without one the window
    // stays centred on the selection, which is what payload-only callers get.
    let anchorLine = payload.scrollAnchorRowIndex.map { rowIndex in
      min(max(0, rowIndex) * 2, max(0, bodyLineCount - 1))
    }
    func window(capacity: Int) -> (offset: Int, end: Int) {
      let maxOffset = max(0, bodyLineCount - capacity)
      let offset =
        if let anchorLine {
          min(anchorLine, maxOffset)
        } else {
          min(max(0, selectedLine - capacity / 2), maxOffset)
        }
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
