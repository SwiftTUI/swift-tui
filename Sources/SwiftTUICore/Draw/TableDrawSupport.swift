package struct TableDisplaySegment: Equatable, Sendable {
  var content: String
  var style: TextStyle
}

package struct TableDisplayLine: Equatable, Sendable {
  enum Role: Equatable, Sendable {
    case topBorder
    case header
    case headerSeparator
    case row
    case rowSeparator
    case overflow
    case bottomBorder
  }
  var segments: [TableDisplaySegment]
  var backgroundStyle: AnyShapeStyle?
  var role: Role
  var isSelectedRow: Bool
  var rowIndex: Int?
  /// Cells this line occupies. Greater than 1 when the hosted row measured
  /// taller than one cell; 1 for every chrome line and for the payload-only
  /// line model, whose rows are single-line text.
  package var height: Int
  /// This line's first cell, relative to the layout's content bounds.
  ///
  /// Tables carried the same D19 convention split lists did: draw painted
  /// every line at `bounds.y + lineIndex` with height 1 while placement
  /// separately accumulated an `additionalYOffset` for tall rows, so the two
  /// disagreed for every line after a multi-cell row.
  package var yOffset: Int

  init(
    segments: [TableDisplaySegment],
    backgroundStyle: AnyShapeStyle?,
    role: Role,
    isSelectedRow: Bool,
    rowIndex: Int?,
    height: Int = 1,
    yOffset: Int = 0
  ) {
    self.segments = segments
    self.backgroundStyle = backgroundStyle
    self.role = role
    self.isSelectedRow = isSelectedRow
    self.rowIndex = rowIndex
    self.height = height
    self.yOffset = yOffset
  }
}

enum TableBorderPosition {
  case top
  case middle
  case bottom
}

extension DrawExtractor {
  func overflowIndicatorLine(
    widths: [Int],
    payload: TablePayload,
    symbol: String
  ) -> TableDisplayLine {
    let glyphs = payload.style.borderGlyphs
    let borderStyle = TextStyle(
      foregroundStyle: payload.borderStyle ?? .semantic(.separator),
      opacity: payload.opacity
    )
    var textStyle = TextStyle(
      foregroundStyle: payload.foregroundStyle ?? .semantic(.foreground)
    )
    textStyle.opacity *= payload.opacity

    return .init(
      segments: rowSegments(
        cells: widths.enumerated().map { index, width in
          TableDisplaySegment(
            content: renderTableCell(
              symbol,
              width: width,
              alignment: payload.columns[index].alignment
            ),
            style: textStyle
          )
        },
        borderStyle: borderStyle,
        glyphs: glyphs
      ),
      backgroundStyle: nil,
      role: .overflow,
      isSelectedRow: false,
      rowIndex: nil
    )
  }

  func resolvedTableRowTextStyle(
    row: TableRowPayload,
    payload: TablePayload,
    isSelected: Bool
  ) -> TextStyle {
    var style = row.style
    if let rowForegroundStyle = row.rowForegroundStyle {
      style.foregroundStyle = rowForegroundStyle
    } else if style.foregroundStyle == nil {
      style.foregroundStyle = payload.foregroundStyle ?? .semantic(.foreground)
    }
    if isSelected, let selectedForegroundStyle = payload.selectedRowForegroundStyle {
      style.foregroundStyle = selectedForegroundStyle
    }
    style.opacity *= payload.opacity
    return style
  }

  func resolvedTableCellTextStyle(
    cell: TableCellPayload,
    rowStyle: TextStyle,
    payload: TablePayload,
    isSelected: Bool
  ) -> TextStyle {
    var style = TextStyle()
    style.baseStyle = rowStyle.baseStyle.merging(cell.style.baseStyle)
    if isSelected, let selectedForegroundStyle = payload.selectedRowForegroundStyle {
      style.foregroundStyle = selectedForegroundStyle
    }
    return style
  }

  func rowSegments(
    cells: [TableDisplaySegment],
    borderStyle: TextStyle,
    glyphs: TableBorderGlyphs
  ) -> [TableDisplaySegment] {
    var segments: [TableDisplaySegment] = [
      .init(content: glyphs.left, style: borderStyle)
    ]
    for (index, cell) in cells.enumerated() {
      segments.append(
        .init(
          content: " \(cell.content) ",
          style: cell.style
        )
      )
      if index < cells.count - 1 {
        segments.append(
          .init(content: glyphs.columnJoin, style: borderStyle)
        )
      }
    }

    segments.append(
      .init(content: glyphs.right, style: borderStyle)
    )
    return segments
  }

  func borderSegments(
    widths: [Int],
    glyphs: TableBorderGlyphs,
    position: TableBorderPosition,
    style: TextStyle
  ) -> [TableDisplaySegment] {
    guard !widths.isEmpty else {
      return []
    }

    let left: String
    let fill: String
    let join: String
    let right: String

    switch position {
    case .top:
      left = glyphs.topLeft
      fill = glyphs.top
      join = glyphs.topJoin
      right = glyphs.topRight
    case .middle:
      left = glyphs.middleLeft
      fill = glyphs.middle
      join = glyphs.middleJoin
      right = glyphs.middleRight
    case .bottom:
      left = glyphs.bottomLeft
      fill = glyphs.bottom
      join = glyphs.bottomJoin
      right = glyphs.bottomRight
    }

    var segments: [TableDisplaySegment] = [
      .init(content: left, style: style)
    ]

    for (index, width) in widths.enumerated() {
      segments.append(
        .init(
          content: String(repeating: fill, count: width + 2),
          style: style
        )
      )
      if index < widths.count - 1 {
        segments.append(
          .init(content: join, style: style)
        )
      }
    }

    segments.append(
      .init(content: right, style: style)
    )
    return segments
  }
}
