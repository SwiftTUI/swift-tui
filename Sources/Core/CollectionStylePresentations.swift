/// Resolved container chrome for grouped collection presentations.
public struct CollectionContainerChromePresentation: Equatable, Sendable {
  public var geometry: ShapeGeometry
  public var insetAmount: Int
  public var fillMode: ShapeFillMode
  public var strokeStyle: StrokeStyle
  public var strokeBorder: Bool

  public init(
    geometry: ShapeGeometry,
    insetAmount: Int = 0,
    fillMode: ShapeFillMode = .full,
    strokeStyle: StrokeStyle,
    strokeBorder: Bool = true
  ) {
    self.geometry = geometry
    self.insetAmount = max(0, insetAmount)
    self.fillMode = fillMode
    self.strokeStyle = strokeStyle
    self.strokeBorder = strokeBorder
  }

  public static var insetGrouped: Self {
    .init(
      geometry: .roundedRectangle(cornerRadius: 1),
      fillMode: .interior(strokeWidth: 1),
      strokeStyle: .init(borderSet: .rounded)
    )
  }
}

/// Resolved table border glyphs used by low-level table drawing.
public struct TableBorderGlyphs: Equatable, Sendable {
  public var topLeft: String
  public var top: String
  public var topJoin: String
  public var topRight: String
  public var left: String
  public var columnJoin: String
  public var right: String
  public var middleLeft: String
  public var middle: String
  public var middleJoin: String
  public var middleRight: String
  public var bottomLeft: String
  public var bottom: String
  public var bottomJoin: String
  public var bottomRight: String

  public init(
    topLeft: String,
    top: String,
    topJoin: String,
    topRight: String,
    left: String,
    columnJoin: String,
    right: String,
    middleLeft: String,
    middle: String,
    middleJoin: String,
    middleRight: String,
    bottomLeft: String,
    bottom: String,
    bottomJoin: String,
    bottomRight: String
  ) {
    self.topLeft = topLeft
    self.top = top
    self.topJoin = topJoin
    self.topRight = topRight
    self.left = left
    self.columnJoin = columnJoin
    self.right = right
    self.middleLeft = middleLeft
    self.middle = middle
    self.middleJoin = middleJoin
    self.middleRight = middleRight
    self.bottomLeft = bottomLeft
    self.bottom = bottom
    self.bottomJoin = bottomJoin
    self.bottomRight = bottomRight
  }

  public static var plain: Self {
    .init(
      topLeft: "┌",
      top: "─",
      topJoin: "┬",
      topRight: "┐",
      left: "│",
      columnJoin: "│",
      right: "│",
      middleLeft: "├",
      middle: "─",
      middleJoin: "┼",
      middleRight: "┤",
      bottomLeft: "└",
      bottom: "─",
      bottomJoin: "┴",
      bottomRight: "┘"
    )
  }

  public static var insetGrouped: Self {
    .init(
      topLeft: "╭",
      top: "─",
      topJoin: "┬",
      topRight: "╮",
      left: "│",
      columnJoin: "│",
      right: "│",
      middleLeft: "├",
      middle: "─",
      middleJoin: "┼",
      middleRight: "┤",
      bottomLeft: "╰",
      bottom: "─",
      bottomJoin: "┴",
      bottomRight: "╯"
    )
  }
}

/// Resolved collection presentation shared by list and table payloads.
public struct CollectionStylePresentation:
  Equatable,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  public var snapshotLabel: String
  public var listContainer: CollectionContainerChromePresentation?
  public var listContentInsets: EdgeInsets
  public var showsListRowSeparators: Bool
  public var showsListSectionSeparators: Bool
  public var tableBorderGlyphs: TableBorderGlyphs
  public var tableHeaderForegroundStyle: AnyShapeStyle?
  public var tableHeaderBackgroundStyle: AnyShapeStyle?

  public init(
    snapshotLabel: String = "",
    listContainer: CollectionContainerChromePresentation? = nil,
    listContentInsets: EdgeInsets = .zero,
    showsListRowSeparators: Bool = true,
    showsListSectionSeparators: Bool = true,
    tableBorderGlyphs: TableBorderGlyphs = .plain,
    tableHeaderForegroundStyle: AnyShapeStyle? = nil,
    tableHeaderBackgroundStyle: AnyShapeStyle? = nil
  ) {
    self.snapshotLabel = snapshotLabel
    self.listContainer = listContainer
    self.listContentInsets = listContentInsets
    self.showsListRowSeparators = showsListRowSeparators
    self.showsListSectionSeparators = showsListSectionSeparators
    self.tableBorderGlyphs = tableBorderGlyphs
    self.tableHeaderForegroundStyle = tableHeaderForegroundStyle
    self.tableHeaderBackgroundStyle = tableHeaderBackgroundStyle
  }

  public var description: String {
    snapshotLabel.isEmpty ? "CollectionStylePresentation" : snapshotLabel
  }

  public var debugDescription: String {
    description
  }

  public static var plain: Self {
    .init(
      snapshotLabel: "CollectionStylePresentation.plain",
      listContainer: nil,
      listContentInsets: .zero,
      showsListRowSeparators: true,
      showsListSectionSeparators: true,
      tableBorderGlyphs: .plain,
      tableHeaderForegroundStyle: .semantic(.muted),
      tableHeaderBackgroundStyle: nil
    )
  }

  public static var insetGrouped: Self {
    .init(
      snapshotLabel: "CollectionStylePresentation.insetGrouped",
      listContainer: .insetGrouped,
      listContentInsets: .init(top: 1, leading: 1, bottom: 1, trailing: 1),
      showsListRowSeparators: false,
      showsListSectionSeparators: false,
      tableBorderGlyphs: .insetGrouped,
      tableHeaderForegroundStyle: AnyShapeStyle(.terminalBorder(.accent)),
      tableHeaderBackgroundStyle: AnyShapeStyle(.terminalRow(.neutral, isOdd: true))
    )
  }
}

/// Resolved outline connector and indentation strings.
public struct OutlineStylePresentation:
  Equatable,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  public var snapshotLabel: String
  public var continuingIndenter: String
  public var emptyIndenter: String
  public var branchConnector: String
  public var leafConnector: String

  public init(
    snapshotLabel: String = "",
    continuingIndenter: String,
    emptyIndenter: String,
    branchConnector: String,
    leafConnector: String
  ) {
    self.snapshotLabel = snapshotLabel
    self.continuingIndenter = continuingIndenter
    self.emptyIndenter = emptyIndenter
    self.branchConnector = branchConnector
    self.leafConnector = leafConnector
  }

  public var description: String {
    snapshotLabel.isEmpty ? "OutlineStylePresentation" : snapshotLabel
  }

  public var debugDescription: String {
    description
  }

  public static var rounded: Self {
    .init(
      snapshotLabel: "OutlineStylePresentation.rounded",
      continuingIndenter: "│ ",
      emptyIndenter: "  ",
      branchConnector: "├─ ",
      leafConnector: "╰─ "
    )
  }

  public static var plain: Self {
    .init(
      snapshotLabel: "OutlineStylePresentation.plain",
      continuingIndenter: "│ ",
      emptyIndenter: "  ",
      branchConnector: "├─ ",
      leafConnector: "└─ "
    )
  }

  public static var ascii: Self {
    .init(
      snapshotLabel: "OutlineStylePresentation.ascii",
      continuingIndenter: "| ",
      emptyIndenter: "  ",
      branchConnector: "|- ",
      leafConnector: "`- "
    )
  }
}
