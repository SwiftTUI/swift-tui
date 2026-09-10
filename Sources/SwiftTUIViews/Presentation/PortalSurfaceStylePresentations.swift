public import SwiftTUICore

/// Resolved prompt chrome: the backdrop, header tone, size bounds, insets, and
/// paint an alert or a confirmation dialog renders.
///
/// A ``PromptStyle`` returns this value from
/// ``PromptStyle/resolvePresentation(for:)``, usually by transforming the
/// ``PromptStyleConfiguration/defaultPresentation`` it is handed. The defaults
/// below are the alert's baseline; a confirmation dialog is handed a narrower,
/// accent-headed one. The field set is the shared portal chrome vocabulary,
/// minus the sheet family's container choice. All dimensions are terminal
/// cells.
///
/// Alignment, accessibility, default actions, and dismissal belong to the
/// declaration and are intentionally absent from this value.
///
/// The surface validates the value before rendering it. A negative width,
/// inset, or scroll height, a `maximumWidth` that is not positive or is below
/// `minimumWidth`, misordered scroll heights, a `backdropOpacity` outside
/// `0...1`, or a cell count too large to add to a terminal extent reports one
/// `style.invalidPresentation` runtime issue, and the declaration's baseline
/// renders for that resolve. A count larger than any terminal is still valid.
/// Nothing traps on a style value.
public struct PromptSurfaceStylePresentation: Sendable, Equatable {
  /// The opacity of the dim painted over the base content behind the surface,
  /// from `0` (no backdrop, the default) to `1`. Must be finite and within that
  /// range.
  public var backdropOpacity: Double
  /// The `TerminalTone` behind the header row that holds the prompt's title.
  /// Defaults to `.neutral` for an alert; the confirmation dialog's baseline
  /// uses `.accent`.
  public var headerTone: TerminalTone
  /// The smallest outer width of the surface, in cells. Defaults to `24` for an
  /// alert and `20` for a confirmation dialog. Must be non-negative and
  /// representable.
  public var minimumWidth: Int
  /// The largest outer width of the surface, in cells. Defaults to `48` for an
  /// alert; the confirmation dialog's baseline leaves it `nil`, letting the
  /// surface grow to the terminal width inside the host inset. When set it must
  /// be positive, at least `minimumWidth`, and representable.
  public var maximumWidth: Int?
  /// The smallest height of the scrolling content viewport, in cells, before
  /// insets and the header. Defaults to `2` for an alert and `3` for a
  /// confirmation dialog.
  public var scrollMinimumHeight: Int
  /// The height of the content viewport when no height is proposed, in cells,
  /// before insets and the header. Defaults to `6` for an alert and `4` for a
  /// confirmation dialog.
  public var scrollIdealHeight: Int
  /// The largest height of the scrolling content viewport, in cells, before
  /// insets and the header. Defaults to `10` for an alert and `6` for a
  /// confirmation dialog. The three scroll heights must be non-negative,
  /// ordered minimum, ideal, maximum, and representable.
  public var scrollMaximumHeight: Int
  /// Insets in cells around the header and viewport inside the border.
  /// Defaults to one cell on every edge. Edges must be non-negative and
  /// representable.
  public var contentInsets: EdgeInsets
  /// The fill behind the surface. `nil` (the default) uses the theme's surface
  /// background.
  public var backgroundStyle: AnyShapeStyle?
  /// The stroke geometry of the surface's border. Defaults to `.single`.
  public var borderStroke: StrokeStyle
  /// The paint of the surface's border. `nil` (the default) uses the theme's
  /// accent border.
  public var borderStyle: AnyShapeStyle?

  /// Constructs prompt chrome, defaulting every field to the alert baseline.
  ///
  /// A style normally transforms
  /// ``PromptStyleConfiguration/defaultPresentation`` instead, because a
  /// confirmation dialog's baseline differs from these defaults in its header
  /// tone, width bounds, and scroll heights.
  ///
  /// - Parameters:
  ///   - backdropOpacity: The dim over the content behind the surface, `0` to
  ///     `1`.
  ///   - headerTone: The tone behind the title row.
  ///   - minimumWidth: The smallest outer width in cells.
  ///   - maximumWidth: The largest outer width in cells, or `nil` for the
  ///     terminal width inside the host inset.
  ///   - scrollMinimumHeight: The viewport's smallest height in cells.
  ///   - scrollIdealHeight: The viewport's height when none is proposed.
  ///   - scrollMaximumHeight: The viewport's largest height in cells.
  ///   - contentInsets: Insets in cells inside the border.
  ///   - backgroundStyle: The surface fill, or `nil` for the theme's surface
  ///     background.
  ///   - borderStroke: The border's stroke geometry.
  ///   - borderStyle: The border paint, or `nil` for the theme's accent border.
  public init(
    backdropOpacity: Double = 0,
    headerTone: TerminalTone = .neutral,
    minimumWidth: Int = 24,
    maximumWidth: Int? = 48,
    scrollMinimumHeight: Int = 2,
    scrollIdealHeight: Int = 6,
    scrollMaximumHeight: Int = 10,
    contentInsets: EdgeInsets = .init(horizontal: 1, vertical: 1),
    backgroundStyle: AnyShapeStyle? = nil,
    borderStroke: StrokeStyle = .single,
    borderStyle: AnyShapeStyle? = nil
  ) {
    self.backdropOpacity = backdropOpacity
    self.headerTone = headerTone
    self.minimumWidth = minimumWidth
    self.maximumWidth = maximumWidth
    self.scrollMinimumHeight = scrollMinimumHeight
    self.scrollIdealHeight = scrollIdealHeight
    self.scrollMaximumHeight = scrollMaximumHeight
    self.contentInsets = contentInsets
    self.backgroundStyle = backgroundStyle
    self.borderStroke = borderStroke
    self.borderStyle = borderStyle
  }
}

/// Resolved cover chrome: the insets and fill of a surface that always fills
/// the terminal.
///
/// A ``FullScreenCoverStyle`` returns this value from
/// ``FullScreenCoverStyle/resolvePresentation(for:)``. A full-screen cover has
/// no framework header, close button, or border, so there are only two fields;
/// everything else the cover shows is authored content. Insets are terminal
/// cells.
///
/// The surface validates the value before rendering it: a negative or
/// unrepresentable inset reports one `style.invalidPresentation` runtime issue
/// and the declaration's baseline renders for that resolve. Nothing traps on a
/// style value.
public struct FullScreenSurfaceStylePresentation: Sendable, Equatable {
  /// Insets in cells between the terminal's edges and the authored content.
  /// Defaults to `.zero`, so the content starts at the edges. Edges must be
  /// non-negative and representable.
  public var contentInsets: EdgeInsets
  /// The fill behind the cover, painted over the whole terminal. Defaults to
  /// the theme's surface background; unlike the sheet and prompt values this
  /// one is not optional, so a style always names a paint.
  public var backgroundStyle: AnyShapeStyle

  /// Constructs cover chrome with no insets and the theme's surface background.
  ///
  /// - Parameters:
  ///   - contentInsets: Insets in cells around the authored content.
  ///   - backgroundStyle: The fill painted over the terminal.
  public init(
    contentInsets: EdgeInsets = .zero,
    backgroundStyle: AnyShapeStyle = AnyShapeStyle(.terminalSurfaceBackground)
  ) {
    self.contentInsets = contentInsets
    self.backgroundStyle = backgroundStyle
  }
}

extension PromptSurfaceStylePresentation {
  package var validationProblems: [String] {
    portalSurfaceValidationProblems(
      backdropOpacity: backdropOpacity, minimumWidth: minimumWidth, maximumWidth: maximumWidth,
      scrollMinimumHeight: scrollMinimumHeight, scrollIdealHeight: scrollIdealHeight,
      scrollMaximumHeight: scrollMaximumHeight, contentInsets: contentInsets)
  }
}

extension SheetSurfaceStylePresentation {
  package var validationProblems: [String] {
    portalSurfaceValidationProblems(
      backdropOpacity: backdropOpacity, minimumWidth: minimumWidth, maximumWidth: maximumWidth,
      scrollMinimumHeight: scrollMinimumHeight, scrollIdealHeight: scrollIdealHeight,
      scrollMaximumHeight: scrollMaximumHeight, contentInsets: contentInsets)
  }
}

extension FullScreenSurfaceStylePresentation {
  package var validationProblems: [String] {
    AnchoredSurfaceStylePresentation(contentInsets: contentInsets).validationProblems
  }
}

private func portalSurfaceValidationProblems(
  backdropOpacity: Double, minimumWidth: Int, maximumWidth: Int?,
  scrollMinimumHeight: Int, scrollIdealHeight: Int, scrollMaximumHeight: Int,
  contentInsets: EdgeInsets
) -> [String] {
  var problems = AnchoredSurfaceStylePresentation(
    contentInsets: contentInsets, minimumWidth: minimumWidth, maximumWidth: maximumWidth
  ).validationProblems
  if !backdropOpacity.isFinite || !(0...1).contains(backdropOpacity) {
    problems.append("backdropOpacity must be finite and between zero and one")
  }
  if scrollMinimumHeight < 0 || scrollIdealHeight < scrollMinimumHeight
    || scrollMaximumHeight < scrollIdealHeight
  {
    problems.append("scroll heights must be nonnegative and ordered minimum, ideal, maximum")
  }
  // The scroll frame and the surface add insets and chrome to these bounds
  // without a check, so an unrepresentable count overflows just as an
  // unrepresentable inset does. Larger than any terminal is still valid.
  let representable = AnchoredSurfaceStylePresentation.representableCellCount
  if max(scrollMinimumHeight, scrollIdealHeight, scrollMaximumHeight) > representable {
    problems.append("scroll heights must be representable cell counts")
  }
  if let maximumWidth, maximumWidth > representable {
    problems.append("maximumWidth must be a representable cell count")
  }
  return problems
}
