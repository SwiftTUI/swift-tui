/// Resolved list presentation carried by list payloads.
///
/// Split from the former combined collection presentation: a list's chrome,
/// insets, and separators are list concerns only. Table treatments live in
/// `TableStylePresentation`.
///
/// This is the value a `ListStyle` resolves and the list payload carries into
/// layout and draw. Insets, container inset, fill stroke width, and corner radius
/// must be nonnegative, representable cell counts; stroke line width must be
/// positive and representable. Invalid geometry reports `style.invalidPresentation`
/// and uses the automatic presentation for that resolve. It carries geometry and visibility only; the
/// container's border and background paints come from the authored per-view
/// chrome or the theme, not from here.
/// Closed enum and Boolean combinations remain valid. Custom paths follow the
/// ordinary shape-rendering contract rather than a List-specific path validator.
public struct ListStylePresentation:
  Equatable,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// Identifies the presentation variant in snapshots and diagnostics.
  ///
  /// Defaults to the empty string, in which case `description` reports the type
  /// name instead. The built-in variants label themselves
  /// `"ListStylePresentation.plain"` and `"ListStylePresentation.insetGrouped"`,
  /// but `AnyListStyle` overwrites this field with the style's own label, so a
  /// variant label survives only when a style's `resolvePresentation(for:)` is
  /// called directly.
  public var snapshotLabel: String

  /// The container chrome painted around the list, or `nil` to paint none.
  ///
  /// It carries geometry only. The fill and outline paints come from the
  /// authored chrome on the list, falling back to the theme's fill and separator
  /// colors.
  public var container: CollectionContainerChromePresentation?

  /// Whether `container` is painted once around the whole list or once around
  /// each section. It has no effect while `container` is `nil`. Defaults to
  /// `wholeList`.
  public var chromeScope: ListChromeScope

  /// Cells trimmed from each edge of the list's content, inside any container
  /// chrome. Defaults to `.zero`.
  public var contentInsets: EdgeInsets

  /// Whether a horizontal rule is drawn between adjacent rows. Defaults to
  /// `true`. It is load-bearing for layout as well as appearance: rows are
  /// spaced two lines apart when it is `true` and one line apart when it is
  /// `false`.
  public var showsRowSeparators: Bool

  /// Whether a horizontal rule is drawn between adjacent sections. Defaults to
  /// `true`, and it is ignored for a section that suppresses its own separator.
  public var showsSectionSeparators: Bool

  /// Creates a list presentation.
  ///
  /// Every parameter has a default, so a style can name the fields it cares
  /// about. The defaults describe an unchromed, uninset list with both kinds of
  /// separator drawn, which is the `plain` variant apart from its label.
  public init(
    snapshotLabel: String = "",
    container: CollectionContainerChromePresentation? = nil,
    chromeScope: ListChromeScope = .wholeList,
    contentInsets: EdgeInsets = .zero,
    showsRowSeparators: Bool = true,
    showsSectionSeparators: Bool = true
  ) {
    self.snapshotLabel = snapshotLabel
    self.container = container
    self.chromeScope = chromeScope
    self.contentInsets = contentInsets
    self.showsRowSeparators = showsRowSeparators
    self.showsSectionSeparators = showsSectionSeparators
  }

  /// The `snapshotLabel`, or `"ListStylePresentation"` when that is empty.
  public var description: String {
    snapshotLabel.isEmpty ? "ListStylePresentation" : snapshotLabel
  }

  /// The same text as `description`.
  public var debugDescription: String {
    description
  }

  /// No container chrome and no insets, with both row and section separators
  /// drawn, so rows read as a flat divided run of lines.
  ///
  /// Labeled `"ListStylePresentation.plain"`.
  public static var plain: Self {
    .init(
      snapshotLabel: "ListStylePresentation.plain",
      container: nil,
      contentInsets: .zero,
      showsRowSeparators: true,
      showsSectionSeparators: true
    )
  }

  /// Rounded container chrome around each section, one cell of content inset on
  /// every edge, and no separators, since the chrome already divides the
  /// sections.
  ///
  /// Labeled `"ListStylePresentation.insetGrouped"`.
  public static var insetGrouped: Self {
    .init(
      snapshotLabel: "ListStylePresentation.insetGrouped",
      container: .insetGrouped,
      chromeScope: .eachSection,
      contentInsets: .init(top: 1, leading: 1, bottom: 1, trailing: 1),
      showsRowSeparators: false,
      showsSectionSeparators: false
    )
  }
}
