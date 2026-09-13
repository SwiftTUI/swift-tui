/// Resolved table presentation carried by table payloads.
///
/// Split from the former combined collection presentation: border glyphs and
/// header paints are table concerns only. List treatments live in
/// `ListStylePresentation`.
///
/// There is deliberately no row-separator field: separator geometry is the
/// `middle` glyph family of `TableBorderGlyphs`, separator visibility is
/// per-row authored metadata, and separator paint is `borderStyle`.
///
/// This is the value a `TableStyle` resolves and the table payload carries into
/// layout and draw. Insets must be nonnegative, representable cell counts and
/// every border glyph must occupy one printable terminal cell. An invalid value
/// reports `style.invalidPresentation` and uses the automatic presentation for
/// that resolve, including its paints.
public struct TableStylePresentation:
  Equatable,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// Identifies the presentation variant in snapshots and diagnostics.
  ///
  /// Defaults to the empty string, in which case `description` reports the type
  /// name instead. The built-in variants label themselves
  /// `"TableStylePresentation.bordered"` and `"TableStylePresentation.inset"`,
  /// but `AnyTableStyle` overwrites this field with the style's own label, so a
  /// variant label survives only when a style's `resolvePresentation(for:)` is
  /// called directly.
  public var snapshotLabel: String

  /// Cells trimmed from each edge of the table, outside its border. Defaults to
  /// `.zero`.
  public var contentInsets: EdgeInsets

  /// The glyph set the frame, column joins, and horizontal rules are drawn with.
  /// Defaults to `TableBorderGlyphs.plain`, the square-cornered set.
  public var borderGlyphs: TableBorderGlyphs

  /// The paint for header cell text. `nil`, the default, leaves the header text
  /// in the inherited foreground paint.
  public var headerForegroundStyle: AnyShapeStyle?

  /// The fill painted behind the header row. `nil`, the default, gives the
  /// header no background of its own.
  public var headerBackgroundStyle: AnyShapeStyle?

  /// Border and separator paint. `nil` means theme-derived, and authored
  /// per-view chrome still wins over the style: the draw phase resolves
  /// authored chrome, then this paint, then the theme separator color.
  public var borderStyle: AnyShapeStyle?

  /// Creates a table presentation.
  ///
  /// Every parameter has a default, so a style can name only the fields it cares
  /// about. The defaults describe a square-bordered table with no insets and an
  /// unpainted header.
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

  /// The `snapshotLabel`, or `"TableStylePresentation"` when that is empty.
  public var description: String {
    snapshotLabel.isEmpty ? "TableStylePresentation" : snapshotLabel
  }

  /// The same text as `description`.
  public var debugDescription: String {
    description
  }

  /// The square-bordered treatment (the former plain collection result).
  ///
  /// Square `plain` glyphs, header text in the muted semantic paint, and no
  /// header background. Labeled `"TableStylePresentation.bordered"`.
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
  ///
  /// Rounded `insetGrouped` glyphs, header text in the accent border paint, and
  /// the header row on the odd-row background. Labeled
  /// `"TableStylePresentation.inset"`.
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
