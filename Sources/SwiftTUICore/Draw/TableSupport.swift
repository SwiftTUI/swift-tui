package func measureTableColumnWidths(
  columns: [TableColumnPayload],
  rows: [TableRowPayload]
) -> [Int] {
  columns.enumerated().map { index, column in
    if let width = column.width {
      return max(1, width)
    }

    let titleWidth = layoutText(for: column.title, width: nil).size.width
    let rowWidth = rows.reduce(0) { partial, row in
      let cell = index < row.cells.count ? row.cells[index].text : ""
      return max(partial, layoutText(for: cell, width: nil).size.width)
    }
    return max(1, max(titleWidth, rowWidth))
  }
}

package func formattedTableLineWidth(
  widths: [Int],
  prefixWidth: Int = 0
) -> Int {
  let _ = prefixWidth
  guard !widths.isEmpty else {
    return 0
  }
  return widths.reduce(0, +) + widths.count + 1
}

package func borderedTableLineWidth(
  widths: [Int],
  glyphs: TableBorderGlyphs
) -> Int {
  guard !widths.isEmpty else {
    return 0
  }

  return max(
    borderedTableLineWidth(
      widths: widths,
      left: glyphs.left,
      join: glyphs.columnJoin,
      right: glyphs.right
    ),
    borderedTableLineWidth(
      widths: widths,
      left: glyphs.topLeft,
      join: glyphs.topJoin,
      right: glyphs.topRight
    ),
    borderedTableLineWidth(
      widths: widths,
      left: glyphs.middleLeft,
      join: glyphs.middleJoin,
      right: glyphs.middleRight
    ),
    borderedTableLineWidth(
      widths: widths,
      left: glyphs.bottomLeft,
      join: glyphs.bottomJoin,
      right: glyphs.bottomRight
    )
  )
}

package func renderTableLine(
  cells: [String],
  widths: [Int],
  columns: [TableColumnPayload],
  usesTitleAlignment: Bool = false
) -> String {
  widths.enumerated().map { index, width in
    let cell = index < cells.count ? cells[index] : ""
    let alignment =
      if index < columns.count {
        usesTitleAlignment ? columns[index].titleAlignment : columns[index].alignment
      } else {
        TableCellAlignment.leading
      }
    return renderTableCell(cell, width: width, alignment: alignment)
  }
  .joined(separator: " | ")
}

package func renderTableCell(
  _ content: String,
  width: Int,
  alignment: TableCellAlignment
) -> String {
  let resolvedWidth = max(1, width)
  let line = layoutText(
    for: content,
    width: resolvedWidth,
    lineLimit: 1,
    truncationMode: .tail,
    wrappingStrategy: .wordBoundary
  ).lines[0].text
  let usedWidth = layoutText(for: line, width: nil).size.width
  let remaining = max(0, resolvedWidth - usedWidth)

  switch alignment {
  case .trailing:
    return String(repeating: " ", count: remaining) + line
  case .center:
    let leading = remaining / 2
    let trailing = remaining - leading
    return String(repeating: " ", count: leading)
      + line
      + String(repeating: " ", count: trailing)
  case .leading:
    return line + String(repeating: " ", count: remaining)
  }
}

private func borderedTableLineWidth(
  widths: [Int],
  left: String,
  join: String,
  right: String
) -> Int {
  let cellsWidth = widths.reduce(0, +) + (widths.count * 2)
  let leftWidth = layoutText(for: left, width: nil).size.width
  let rightWidth = layoutText(for: right, width: nil).size.width
  let joinWidth = layoutText(for: join, width: nil).size.width * max(0, widths.count - 1)
  return cellsWidth + leftWidth + joinWidth + rightWidth
}

package func showsTableRowSeparator(
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
