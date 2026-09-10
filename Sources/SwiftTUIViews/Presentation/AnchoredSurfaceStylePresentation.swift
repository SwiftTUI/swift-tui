public import SwiftTUICore

/// Resolved chrome for a surface anchored to a source view: the insets, width
/// bounds, viewport height cap, and paint a menu popup or a popover renders.
///
/// ``PopoverStyle/resolvePresentation(for:)`` and the menu family both return
/// this one value, and the defaults below are the menu look. The popover
/// baseline overrides `borderStroke` with the rounded stroke, so a popover
/// style that transforms ``PopoverStyleConfiguration/defaultPresentation``
/// keeps rounded corners while one that builds a value from `init()` gets menu
/// chrome. All dimensions are terminal cells; the anchor, the placement search,
/// focus, modal policy, and dismissal belong to the declaration.
///
/// The surface validates the value before rendering it. A negative inset or
/// minimum width, a `maximumWidth` that is not positive or is below
/// `minimumWidth`, a `maximumHeight` that is not positive, or a cell count too
/// large to add to a terminal extent reports one `style.invalidPresentation`
/// runtime issue, and the declaration's baseline renders for that resolve. The
/// size bound is representability, not the terminal: a count larger than any
/// terminal is still valid. Nothing traps on a style value.
public struct AnchoredSurfaceStylePresentation: Sendable, Equatable {
  /// Insets in cells between the surface's border and its content. Defaults to
  /// one cell on every edge. Edges must be non-negative and representable.
  public var contentInsets: EdgeInsets
  /// The smallest outer width of the surface, in cells. Defaults to `0`, which
  /// lets the surface shrink to its content. Must be non-negative and
  /// representable.
  public var minimumWidth: Int
  /// The largest outer width of the surface, in cells. `nil` (the default)
  /// leaves the width unbounded. When set it must be positive, at least
  /// `minimumWidth`, and representable.
  public var maximumWidth: Int?
  /// The largest height of the content viewport, in cells, before insets.
  /// `Int.max` (the default) is unbounded; content taller than the cap scrolls
  /// inside the surface. Must be positive.
  public var maximumHeight: Int
  /// The fill behind the surface. Defaults to the theme's surface background.
  /// Unlike the sheet and prompt values this one is not optional, so a style
  /// always names a paint.
  public var backgroundStyle: AnyShapeStyle
  /// The stroke geometry of the surface's border. Defaults to the menu look, an
  /// outset inner half-block frame; the popover baseline supplies the rounded
  /// stroke instead.
  public var borderStroke: StrokeStyle
  /// The paint of the surface's border. `nil` (the default) uses the theme's
  /// accent border.
  public var borderStyle: AnyShapeStyle?

  /// Constructs anchored chrome, defaulting every field to the menu baseline.
  ///
  /// A popover style should transform
  /// ``PopoverStyleConfiguration/defaultPresentation`` rather than call this
  /// initializer, because the popover baseline differs from these defaults in
  /// `borderStroke`.
  ///
  /// - Parameters:
  ///   - contentInsets: Insets in cells inside the border; see
  ///     ``contentInsets``.
  ///   - minimumWidth: The smallest outer width in cells.
  ///   - maximumWidth: The largest outer width in cells, or `nil` for
  ///     unbounded.
  ///   - maximumHeight: The viewport height cap in cells; `Int.max` is
  ///     unbounded.
  ///   - backgroundStyle: The surface fill.
  ///   - borderStroke: The border's stroke geometry.
  ///   - borderStyle: The border paint, or `nil` for the theme's accent border.
  public init(
    contentInsets: EdgeInsets = .init(horizontal: 1, vertical: 1),
    minimumWidth: Int = 0,
    maximumWidth: Int? = nil,
    maximumHeight: Int = .max,
    backgroundStyle: AnyShapeStyle = AnyShapeStyle(.terminalSurfaceBackground),
    borderStroke: StrokeStyle = StrokeStyle(borderSet: .innerHalfBlock, placement: .outset),
    borderStyle: AnyShapeStyle? = nil
  ) {
    self.contentInsets = contentInsets
    self.minimumWidth = minimumWidth
    self.maximumWidth = maximumWidth
    self.maximumHeight = maximumHeight
    self.backgroundStyle = backgroundStyle
    self.borderStroke = borderStroke
    self.borderStyle = borderStyle
  }
}

extension AnchoredSurfaceStylePresentation {
  /// The largest cell count a presentation field may carry and still add to
  /// any terminal extent without overflowing.
  package static let representableCellCount = Int.max / 4

  package var validationProblems: [String] {
    var problems: [String] = []
    if minimumWidth < 0 { problems.append("minimumWidth must not be negative") }
    if let maximumWidth, maximumWidth <= 0 || maximumWidth < minimumWidth {
      problems.append("maximumWidth must be positive and at least minimumWidth")
    }
    if maximumHeight <= 0 { problems.append("maximumHeight must be positive") }
    let insets = [
      contentInsets.top, contentInsets.leading, contentInsets.bottom, contentInsets.trailing,
    ]
    if insets.contains(where: { $0 < 0 }) {
      problems.append("contentInsets must not be negative")
    }
    // Layout adds an inset to a content extent or origin without a check,
    // so one huge inset can overflow even when the opposing pair fits.
    if insets.contains(where: { $0 > Self.representableCellCount })
      || minimumWidth > Self.representableCellCount
    {
      problems.append("contentInsets and minimumWidth must be representable cell counts")
    }
    return problems
  }
}
