struct TableDisplaySegment {
  var content: String
  var style: TextStyle
}

struct TableDisplayLine {
  enum Role {
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
    let glyphs = payload.style.tableBorderGlyphs
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
