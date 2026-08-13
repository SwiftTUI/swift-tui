/// Resolved table presentation carried by table payloads.
///
/// Split from the former combined collection presentation: border glyphs and
/// header paints are table concerns only. List treatments live in
/// ``ListStylePresentation``.
///
/// There is deliberately no row-separator field: separator geometry is the
/// `middle` glyph family of ``TableBorderGlyphs``, separator visibility is
/// per-row authored metadata, and separator paint is `borderStyle`.
public struct TableStylePresentation:
  Equatable,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  public var snapshotLabel: String
  public var contentInsets: EdgeInsets
  public var borderGlyphs: TableBorderGlyphs
  public var headerForegroundStyle: AnyShapeStyle?
  public var headerBackgroundStyle: AnyShapeStyle?
  /// Border and separator paint. `nil` means theme-derived, and authored
  /// per-view chrome still wins over the style: the draw phase resolves
  /// authored chrome, then this paint, then the theme separator color.
  public var borderStyle: AnyShapeStyle?

  public init(
    snapshotLabel: String = "",
    contentInsets: EdgeInsets = .zero,
    borderGlyphs: TableBorderGlyphs = .plain,
    headerForegroundStyle: AnyShapeStyle? = nil,
    headerBackgroundStyle: AnyShapeStyle? = nil,
    borderStyle: AnyShapeStyle? = nil
  ) {
    self.snapshotLabel = snapshotLabel
    self.contentInsets = contentInsets
    self.borderGlyphs = borderGlyphs
    self.headerForegroundStyle = headerForegroundStyle
    self.headerBackgroundStyle = headerBackgroundStyle
    self.borderStyle = borderStyle
  }

  public var description: String {
    snapshotLabel.isEmpty ? "TableStylePresentation" : snapshotLabel
  }

  public var debugDescription: String {
    description
  }

  /// The square-bordered treatment (the former plain collection result).
  public static var bordered: Self {
    .init(
      snapshotLabel: "TableStylePresentation.bordered",
      contentInsets: .zero,
      borderGlyphs: .plain,
      headerForegroundStyle: .semantic(.muted),
      headerBackgroundStyle: nil
    )
  }

  /// The rounded inset treatment (the former inset-grouped collection
  /// result, and what the automatic table style renders today).
  public static var inset: Self {
    .init(
      snapshotLabel: "TableStylePresentation.inset",
      contentInsets: .zero,
      borderGlyphs: .insetGrouped,
      headerForegroundStyle: AnyShapeStyle(.terminalBorder(.accent)),
      headerBackgroundStyle: AnyShapeStyle(.terminalRow(.neutral, isOdd: true))
    )
  }
}
