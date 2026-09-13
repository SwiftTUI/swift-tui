/// Resolved container chrome for grouped collection presentations.
///
/// It is the geometry half of a list's container: the shape to draw, how far it
/// is inset, whether the fill covers the whole shape or only its interior, and
/// how the outline is stroked. It carries no paint. The fill and outline colors
/// come from the authored chrome on the list, falling back to the theme's fill
/// and separator colors.
public struct CollectionContainerChromePresentation: Equatable, Sendable {
  /// The shape the chrome is drawn as, such as a rectangle or a rounded
  /// rectangle of a given corner radius.
  public var geometry: ShapeGeometry

  /// Cells the shape is inset from the bounds it is given, on every edge.
  /// Clamped to zero or more by the initializer. Defaults to `0`.
  public var insetAmount: Int

  /// Whether the fill covers the whole shape or only the area inside a stroke of
  /// the given width. Defaults to `full`.
  public var fillMode: ShapeFillMode

  /// The stroke geometry of the outline: its line width, glyph border set, and
  /// inset or outset placement.
  ///
  /// This is geometry, not paint, despite the `…Style` name, which predates the
  /// convention of naming paint fields `…Style` and stroke geometry `…Stroke`.
  /// The outline's color comes from the authored chrome or the theme.
  public var strokeStyle: StrokeStyle

  /// Whether the outline is drawn inside the shape's own bounds, the way
  /// `Shape.strokeBorder` does, rather than centered on its edge. Defaults to
  /// `true`.
  public var strokeBorder: Bool

  /// Creates a container chrome presentation.
  ///
  /// - Parameters:
  ///   - geometry: The shape to draw.
  ///   - insetAmount: Cells to inset the shape on every edge. A negative value
  ///     is clamped to `0`.
  ///   - fillMode: Whether the fill covers the whole shape or its interior only.
  ///   - strokeStyle: The outline's stroke geometry.
  ///   - strokeBorder: Whether the outline stays inside the shape's bounds.
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

  /// A rounded rectangle of corner radius one, filled inside a one-cell stroke
  /// and outlined with the rounded border set. It is the chrome
  /// `ListStylePresentation.insetGrouped` paints around each section.
  public static var insetGrouped: Self {
    .init(
      geometry: .roundedRectangle(cornerRadius: 1),
      fillMode: .interior(strokeWidth: 1),
      strokeStyle: .init(borderSet: .rounded)
    )
  }
}

/// Controls where list container chrome is painted.
///
/// It has an effect only while `ListStylePresentation.container` is non-`nil`.
public enum ListChromeScope: Equatable, Sendable {
  /// One run of chrome is painted around the list as a whole.
  case wholeList
  /// A separate run of chrome is painted around each section.
  case eachSection
}

/// Resolved table border glyphs used by low-level table drawing.
///
/// The fifteen fields cover the three horizontal rules a table can draw, each as
/// a left cap, a repeated fill, a per-column join, and a right cap, plus the
/// three vertical pieces of a content row. Every field should be a single
/// terminal cell; the drawing code measures the rules from these strings, so a
/// wider glyph widens the rule against the columns it should align with.
public struct TableBorderGlyphs: Equatable, Sendable {
  /// The top rule's left cap.
  public var topLeft: String
  /// The glyph repeated across the top rule.
  public var top: String
  /// The top rule's cap where a column boundary meets it.
  public var topJoin: String
  /// The top rule's right cap.
  public var topRight: String
  /// The left edge of a content row.
  public var left: String
  /// The divider between two cells within a content row.
  public var columnJoin: String
  /// The right edge of a content row.
  public var right: String
  /// The left cap of an interior rule, such as the one under the header.
  public var middleLeft: String
  /// The glyph repeated across an interior rule.
  public var middle: String
  /// An interior rule's cap where a column boundary meets it.
  public var middleJoin: String
  /// The right cap of an interior rule.
  public var middleRight: String
  /// The bottom rule's left cap.
  public var bottomLeft: String
  /// The glyph repeated across the bottom rule.
  public var bottom: String
  /// The bottom rule's cap where a column boundary meets it.
  public var bottomJoin: String
  /// The bottom rule's right cap.
  public var bottomRight: String

  /// Creates a border glyph set.
  ///
  /// There are no defaults: a custom set names all fifteen glyphs, so a missing
  /// piece cannot silently fall back to a different family. Start from `plain`
  /// or `insetGrouped` and vary what you need instead.
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

  /// The square-cornered single-line set: `┌ ┬ ┐` on top, `├ ┼ ┤` inside,
  /// `└ ┴ ┘` at the bottom, with `─` fills and `│` verticals.
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

  /// The rounded-cornered set: the same interior and vertical glyphs as `plain`
  /// with `╭ ╮ ╰ ╯` corners.
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

/// Resolved outline connector and indentation strings.
///
/// An outline row's prefix is one indenter per ancestor level, then one
/// connector for the row itself. This is the value an `OutlineStyle` resolves.
/// The strings may be empty or span multiple terminal cells, but must contain
/// only printable single-line text. Invalid text reports `style.invalidPresentation`
/// and uses the automatic presentation for that resolve. Matching the widths
/// within each pair of indenters and connectors keeps levels aligned; the
/// indenter pair need not match the connector pair. Widths are author choices.
/// The presentation resolves per outline level; an invalid style reports once
/// for each level that resolves it.
public struct OutlineStylePresentation:
  Equatable,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// Identifies the presentation variant in snapshots and diagnostics.
  ///
  /// Defaults to the empty string, in which case `description` reports the type
  /// name instead. The built-in variants label themselves
  /// `"OutlineStylePresentation.rounded"` and `"OutlineStylePresentation.plain"`,
  /// but `AnyOutlineStyle` overwrites this field with the style's own label, so
  /// a variant label survives only when a style's `resolvePresentation(for:)` is
  /// called directly.
  public var snapshotLabel: String

  /// The indenter drawn for an ancestor level that still has rows below it, so
  /// the vertical guide continues past this row.
  public var continuingIndenter: String

  /// The indenter drawn for an ancestor level whose rows are exhausted, so
  /// nothing is drawn under that level.
  public var emptyIndenter: String

  /// The connector drawn for a row that has siblings after it within its level.
  public var branchConnector: String

  /// The connector drawn for the last row of a level.
  public var leafConnector: String

  /// Creates an outline presentation.
  ///
  /// Only `snapshotLabel` has a default: the four strings are all required,
  /// because a partial set would mix connector families within one outline.
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

  /// The `snapshotLabel`, or `"OutlineStylePresentation"` when that is empty.
  public var description: String {
    snapshotLabel.isEmpty ? "OutlineStylePresentation" : snapshotLabel
  }

  /// The same text as `description`.
  public var debugDescription: String {
    description
  }

  /// Box-drawing connectors with a curved last-child corner: `"│ "` and `"  "`
  /// indenters, `"├─ "` for a row with siblings after it, and `"╰─ "` for the
  /// last row of a level. Labeled `"OutlineStylePresentation.rounded"`.
  public static var rounded: Self {
    .init(
      snapshotLabel: "OutlineStylePresentation.rounded",
      continuingIndenter: "│ ",
      emptyIndenter: "  ",
      branchConnector: "├─ ",
      leafConnector: "╰─ "
    )
  }

  /// The same set as `rounded` with a square last-child corner, `"└─ "` in place
  /// of `"╰─ "`. Labeled `"OutlineStylePresentation.plain"`.
  public static var plain: Self {
    .init(
      snapshotLabel: "OutlineStylePresentation.plain",
      continuingIndenter: "│ ",
      emptyIndenter: "  ",
      branchConnector: "├─ ",
      leafConnector: "└─ "
    )
  }
}
