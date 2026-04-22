/// Horizontal alignment used by low-level table payloads.
public enum TableCellAlignment: String, Equatable, Sendable {
  case leading
  case center
  case trailing
}

/// Column metadata consumed by the raster table renderer.
public struct TableColumnPayload: Equatable, Sendable {
  public var title: String
  public var width: Int?
  public var alignment: TableCellAlignment
  public var titleAlignment: TableCellAlignment

  public init(
    title: String,
    width: Int? = nil,
    alignment: TableCellAlignment = .leading,
    titleAlignment: TableCellAlignment? = nil
  ) {
    self.title = title
    self.width = width
    self.alignment = alignment
    self.titleAlignment = titleAlignment ?? alignment
  }
}

/// A single formatted table cell.
public struct TableCellPayload: Equatable, Sendable {
  public var text: String
  public var style: TextStyle

  public init(
    text: String,
    style: TextStyle = .init()
  ) {
    self.text = text
    self.style = style
  }
}

/// A single row in a low-level table payload.
public struct TableRowPayload: Equatable, Sendable {
  public var tag: SelectionTag?
  public var cells: [TableCellPayload]
  public var style: TextStyle
  public var rowForegroundStyle: AnyShapeStyle?
  public var rowBackgroundStyle: AnyShapeStyle?
  public var rowSeparators: ListSeparatorPreferences

  public init(
    tag: SelectionTag? = nil,
    cells: [TableCellPayload],
    style: TextStyle = .init(),
    rowForegroundStyle: AnyShapeStyle? = nil,
    rowBackgroundStyle: AnyShapeStyle? = nil,
    rowSeparators: ListSeparatorPreferences = .init()
  ) {
    self.tag = tag
    self.cells = cells
    self.style = style
    self.rowForegroundStyle = rowForegroundStyle
    self.rowBackgroundStyle = rowBackgroundStyle
    self.rowSeparators = rowSeparators
  }
}

/// Low-level payload used to draw tables in the render pipeline.
public struct TablePayload: Equatable, Sendable {
  public var columns: [TableColumnPayload]
  public var rows: [TableRowPayload]
  public var selectedRowIndex: Int?
  public var style: CollectionStylePresentation
  public var foregroundStyle: AnyShapeStyle?
  public var backgroundStyle: AnyShapeStyle?
  public var borderStyle: AnyShapeStyle?
  public var selectedRowForegroundStyle: AnyShapeStyle?
  public var selectedRowBackgroundStyle: AnyShapeStyle?
  public var selectedRowMarkerStyle: AnyShapeStyle?
  public var showsHeaders: Bool
  public var showsSelectionMarker: Bool
  public var showsIndicators: Bool
  public var opacity: Double

  public init(
    columns: [TableColumnPayload],
    rows: [TableRowPayload],
    selectedRowIndex: Int?,
    style: CollectionStylePresentation,
    foregroundStyle: AnyShapeStyle? = nil,
    backgroundStyle: AnyShapeStyle? = nil,
    borderStyle: AnyShapeStyle? = nil,
    selectedRowForegroundStyle: AnyShapeStyle? = nil,
    selectedRowBackgroundStyle: AnyShapeStyle? = nil,
    selectedRowMarkerStyle: AnyShapeStyle? = nil,
    showsHeaders: Bool = true,
    showsSelectionMarker: Bool = true,
    showsIndicators: Bool = true,
    opacity: Double = 1
  ) {
    self.columns = columns
    self.rows = rows
    self.selectedRowIndex = selectedRowIndex
    self.style = style
    self.foregroundStyle = foregroundStyle
    self.backgroundStyle = backgroundStyle
    self.borderStyle = borderStyle
    self.selectedRowForegroundStyle = selectedRowForegroundStyle
    self.selectedRowBackgroundStyle = selectedRowBackgroundStyle
    self.selectedRowMarkerStyle = selectedRowMarkerStyle
    self.showsHeaders = showsHeaders
    self.showsSelectionMarker = showsSelectionMarker
    self.showsIndicators = showsIndicators
    self.opacity = opacity
  }
}

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
