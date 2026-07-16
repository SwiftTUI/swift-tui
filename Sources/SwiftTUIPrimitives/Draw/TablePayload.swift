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
  package var isViewportBacked: Bool = false

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
