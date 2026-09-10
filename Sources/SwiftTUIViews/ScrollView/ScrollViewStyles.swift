public import SwiftTUICore

/// The scroll primitive's axes, permitted indicators, and host capabilities.
///
/// Every member is read-only render state: there is no authored view slot and no
/// binding here, because a scroll style resolves a value rather than building a
/// body. There is no `isFocused` flag; focus reaches a style as
/// ``focusedIndicatorAxes``, which names the indicators that should read as
/// focused.
public struct ScrollViewStyleConfiguration: Sendable {
  /// The axes the scroll view was declared to scroll along.
  public var axes: Axis.Set

  /// The axes whose indicators may be drawn, after the nearest
  /// `scrollIndicators(_:axes:)` value is applied. A style must not draw an
  /// indicator for an axis outside this set.
  public var visibleIndicatorAxes: Axis.Set

  /// The subset of ``visibleIndicatorAxes`` that should read as focused, either
  /// because focus rests on the scroll view itself (then every visible axis is
  /// listed) or because focus rests on one indicator. Empty when nothing here is
  /// focused.
  public var focusedIndicatorAxes: Axis.Set

  /// Whether the host's pointer paradigm supports drag-to-pan over content. It
  /// is reported so a style can adapt its indicators; a style cannot turn
  /// panning on, since that is the host's call.
  public var allowsDirectManipulation: Bool

  /// Whether the scroll view is enabled, from the nearest `disabled(_:)` value.
  public var isEnabled: Bool

  /// Whether the focus effect is enabled for this subtree. When it is `false`, a
  /// style should leave the focused indicator paint at the plain tint rather
  /// than the theme's focus chrome.
  public var showsFocusEffect: Bool

  /// The theme, appearance, inherited paints, and cell metrics captured from the
  /// environment, for deriving colors and opacity instead of hardcoding them.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs a fixture without registering scrolling or focus handlers.
  ///
  /// This is the framework's construction path, exposed to test targets through
  /// `@_spi(StyleFixtures)` so a style resolves against a fixture without a live
  /// render (see <doc:Testing-Styles>). Unlike the other style families' fixture
  /// initializers, `showsFocusEffect` has a default, so a test that does not
  /// care about focus chrome can omit it.
  @_spi(StyleFixtures)
  public init(
    axes: Axis.Set, visibleIndicatorAxes: Axis.Set, focusedIndicatorAxes: Axis.Set,
    allowsDirectManipulation: Bool, isEnabled: Bool, showsFocusEffect: Bool = true,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.axes = axes
    self.visibleIndicatorAxes = visibleIndicatorAxes
    self.focusedIndicatorAxes = focusedIndicatorAxes
    self.allowsDirectManipulation = allowsDirectManipulation
    self.isEnabled = isEnabled
    self.showsFocusEffect = showsFocusEffect
    self.styleEnvironment = styleEnvironment
  }
}

/// Indicator and container appearance; scrolling, clipping, and visibility stay primitive-owned.
///
/// Each field is validated independently when a scroll view resolves it. An
/// invalid field is replaced with ``AutomaticScrollViewStyle``'s value for that
/// field alone, the valid fields around it are kept, and one
/// `style.invalidPresentation` issue naming the style and this value's
/// ``snapshotLabel`` is recorded. There is deliberately no panning field: a
/// style cannot enable direct manipulation the host does not support.
public struct ScrollViewStylePresentation: Sendable, Equatable {
  /// Identifies the chosen presentation variant in invalid-field diagnostics,
  /// alongside the concrete style's label.
  ///
  /// Unlike the collection families, the scroll eraser passes this label through
  /// untouched, so a style that resolves several variants can tell them apart in
  /// a diagnostic.
  public var snapshotLabel: String

  /// Cells trimmed from each edge of the content viewport, on top of any space
  /// an indicator track reserves. Defaults to `.zero`. Each edge must be
  /// nonnegative and no larger than a quarter of `Int.max`, or all four fall
  /// back together.
  public var contentInsets: EdgeInsets

  /// The glyph painted in the vertical indicator track. Defaults to `"▐"`. It
  /// must be exactly one grapheme that occupies one terminal cell and contains
  /// no control or line/paragraph separator scalars.
  public var verticalIndicatorGlyph: String

  /// The glyph painted in the horizontal indicator track. Defaults to `"▂"`,
  /// under the same one-cell rule as ``verticalIndicatorGlyph``.
  public var horizontalIndicatorGlyph: String

  /// The paint for an indicator that is not focused. Defaults to the muted
  /// semantic paint.
  public var indicatorStyle: AnyShapeStyle

  /// The paint for an indicator named by
  /// ``ScrollViewStyleConfiguration/focusedIndicatorAxes``. Defaults to the tint
  /// semantic paint.
  public var focusedIndicatorStyle: AnyShapeStyle

  /// A fill painted behind the scrolled content. `nil`, the default, leaves the
  /// enclosing background showing through.
  public var backgroundStyle: AnyShapeStyle?

  /// The opacity applied to the scroll view's drawing, in `0...1`. Defaults to
  /// `1`. It must be finite and within that range, or it falls back.
  public var opacity: Double

  /// Whether the indicator takes a column or row of its own out of the content
  /// viewport (`true`, the default) or is drawn over the content's last column
  /// or row.
  public var reservesIndicatorSpace: Bool

  /// Creates a scroll presentation.
  ///
  /// Every parameter but `snapshotLabel` has a default that reproduces the
  /// automatic appearance, so a custom style can name itself and override only
  /// the fields it cares about.
  ///
  /// - Parameters:
  ///   - snapshotLabel: The variant name reported beside the style's own label
  ///     in an invalid-field diagnostic. It has no default, because it
  ///     identifies the value in that report.
  ///   - contentInsets: Insets in cells between the scroll view's bounds and
  ///     its content; see ``contentInsets``.
  ///   - verticalIndicatorGlyph: The vertical indicator's thumb glyph; see
  ///     ``verticalIndicatorGlyph``.
  ///   - horizontalIndicatorGlyph: The horizontal indicator's thumb glyph; see
  ///     ``horizontalIndicatorGlyph``.
  ///   - indicatorStyle: The paint for an unfocused indicator.
  ///   - focusedIndicatorStyle: The paint for an indicator on the focused axis.
  ///   - backgroundStyle: A fill painted behind the scrolled content, or `nil`
  ///     to leave the enclosing background showing through.
  ///   - opacity: The opacity applied to the scroll view's drawing, in `0...1`.
  ///   - reservesIndicatorSpace: Whether an indicator takes a column or row out
  ///     of the content viewport rather than drawing over the content.
  public init(
    snapshotLabel: String, contentInsets: EdgeInsets = .zero,
    verticalIndicatorGlyph: String = "▐", horizontalIndicatorGlyph: String = "▂",
    indicatorStyle: AnyShapeStyle = .semantic(.muted),
    focusedIndicatorStyle: AnyShapeStyle = .semantic(.tint),
    backgroundStyle: AnyShapeStyle? = nil, opacity: Double = 1,
    reservesIndicatorSpace: Bool = true
  ) {
    self.snapshotLabel = snapshotLabel
    self.contentInsets = contentInsets
    self.verticalIndicatorGlyph = verticalIndicatorGlyph
    self.horizontalIndicatorGlyph = horizontalIndicatorGlyph
    self.indicatorStyle = indicatorStyle
    self.focusedIndicatorStyle = focusedIndicatorStyle
    self.backgroundStyle = backgroundStyle
    self.opacity = opacity
    self.reservesIndicatorSpace = reservesIndicatorSpace
  }
}

/// Supplies appearance while the scroll view owns its layout and input behavior.
///
/// A scroll style is a presentation-value style: it implements
/// ``ScrollViewStyle/resolvePresentation(for:)`` and returns a
/// ``ScrollViewStylePresentation``. It never builds a body, so the scroll view
/// keeps its offset, clamping, clipping, wheel and key handling, indicator
/// dragging, focus, and pointer capture whatever the style resolves. Indicator
/// *visibility* stays with `scrollIndicators(_:axes:)`, and panning stays with
/// the host.
///
/// Apply a style with `scrollViewStyle(_:)`. The value is stored in the
/// environment for the subtree, so the nearest modifier above a scroll view
/// wins. The built-ins are ``AnyScrollViewStyle/automatic`` and
/// ``AnyScrollViewStyle/minimal``, also reachable through the leading-dot
/// accessors ``ScrollViewStyle/automatic`` and ``ScrollViewStyle/minimal``.
///
/// A conforming type must be a value type and `Sendable`, because the
/// environment carries it across resolves. The presentation it returns is
/// validated field by field: see ``ScrollViewStylePresentation``.
///
/// ```swift
/// struct DotScrollViewStyle: ScrollViewStyle {
///   var snapshotLabel: String { "DotScrollViewStyle" }
///
///   func resolvePresentation(
///     for configuration: ScrollViewStyleConfiguration
///   ) -> ScrollViewStylePresentation {
///     .init(
///       snapshotLabel: "dots",
///       verticalIndicatorGlyph: "●",
///       horizontalIndicatorGlyph: "•"
///     )
///   }
/// }
/// ```
///
/// See <doc:Style-System>, <doc:Authoring-Styles>, and <doc:Scrolling>.
public protocol ScrollViewStyle: Sendable {
  /// The label reported in snapshots and diagnostics.
  ///
  /// Diagnostic text, not identity: do not branch on it. It is reported beside
  /// the resolved presentation's own label when a field fails validation.
  var snapshotLabel: String { get }
  /// Resolves the indicator and container appearance for the given scroll state.
  ///
  /// Called on the main actor once per scroll-view resolve, before per-field
  /// validation.
  ///
  /// - Parameter configuration: The scroll view's axes, permitted and focused
  ///   indicator axes, host capability, enablement, and style environment.
  /// - Returns: The glyphs, paints, insets, opacity, and track policy to draw
  ///   with.
  @MainActor
  func resolvePresentation(for configuration: ScrollViewStyleConfiguration)
    -> ScrollViewStylePresentation
}

extension ScrollViewStyle {
  /// The reflected type name, supplied when a conforming type declares no label.
  public var snapshotLabel: String { String(reflecting: Self.self) }
}

private protocol AnyScrollViewStyleBox: AnyStyleBox {
  var snapshotLabel: String { get }
  @MainActor
  func presentation(for configuration: ScrollViewStyleConfiguration) -> ScrollViewStylePresentation
}

extension ConcreteStyleBox: AnyScrollViewStyleBox where S: ScrollViewStyle {
  var snapshotLabel: String { style.snapshotLabel }
  @MainActor
  func presentation(for configuration: ScrollViewStyleConfiguration) -> ScrollViewStylePresentation
  {
    style.resolvePresentation(for: configuration)
  }
}

/// Type-erased scroll styling with comparison of its concrete style value.
///
/// This is the value the environment carries. Unlike the collection erasers, it
/// passes the resolved presentation through untouched, so the presentation keeps
/// the ``ScrollViewStylePresentation/snapshotLabel`` the style gave it and a
/// diagnostic can report both labels.
public struct AnyScrollViewStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyScrollViewStyleBox
  /// Wraps a concrete scroll style for storage in the environment.
  ///
  /// - Parameter style: The style to erase. It is kept boxed, so reuse
  ///   comparisons still see the concrete value.
  public init<S: ScrollViewStyle>(_ style: S) { box = ConcreteStyleBox(style: style) }
  /// The wrapped style's ``ScrollViewStyle/snapshotLabel``.
  public var description: String { box.snapshotLabel }
  /// The wrapped style's ``ScrollViewStyle/snapshotLabel``, the same text as
  /// ``description``.
  public var debugDescription: String { description }
  /// The default scroll style: reserved indicator tracks drawn with `"▐"` and
  /// `"▂"`, theme-derived focus paint, and the theme's disabled dimming.
  public static var automatic: Self { Self(AutomaticScrollViewStyle()) }
  /// The automatic appearance with no reserved track, so the indicator is drawn
  /// over the content's last column or row.
  public static var minimal: Self { Self(MinimalScrollViewStyle()) }

  @MainActor
  package func presentation(for configuration: ScrollViewStyleConfiguration)
    -> ScrollViewStylePresentation
  {
    box.presentation(for: configuration)
  }
}

extension AnyScrollViewStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// Preserves the current indicator glyphs, reserved tracks, and theme treatment.
///
/// Indicators keep the default `"▐"` and `"▂"` glyphs on a reserved track, the
/// unfocused paint stays muted, and the opacity comes from the theme's control
/// chrome, so a disabled scroll view dims. When the focus effect is enabled the
/// focused indicator takes the theme's focused control border paint; otherwise
/// it stays the plain tint.
public struct AutomaticScrollViewStyle: ScrollViewStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics,
  /// `"ScrollViewStyle.automatic"`.
  public var snapshotLabel: String { "ScrollViewStyle.automatic" }
  /// Resolves the default appearance, taking focused indicator paint and
  /// opacity from the configuration's theme.
  ///
  /// - Parameter configuration: The scroll view's render state; its enablement,
  ///   focus-effect flag, and style environment are read.
  /// - Returns: The default presentation with a reserved indicator track.
  @MainActor
  public func resolvePresentation(for configuration: ScrollViewStyleConfiguration)
    -> ScrollViewStylePresentation
  {
    let environment = configuration.styleEnvironment
    return .init(
      snapshotLabel: snapshotLabel,
      focusedIndicatorStyle: configuration.showsFocusEffect
        ? environment.controlChrome(isEnabled: configuration.isEnabled, isFocused: true).borderStyle
        : .semantic(.tint),
      opacity: environment.controlChrome(isEnabled: configuration.isEnabled, isFocused: false)
        .opacity)
  }
}

/// Draws a muted thumb over the content without reserving an indicator track.
///
/// It resolves ``AutomaticScrollViewStyle``'s presentation, relabels it, and
/// clears ``ScrollViewStylePresentation/reservesIndicatorSpace``, so the content
/// keeps the full viewport width and the indicator overlays its last column or
/// row.
public struct MinimalScrollViewStyle: ScrollViewStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics,
  /// `"ScrollViewStyle.minimal"`.
  public var snapshotLabel: String { "ScrollViewStyle.minimal" }
  /// Resolves the automatic appearance with the indicator track released.
  ///
  /// - Parameter configuration: The scroll view's render state, forwarded to
  ///   ``AutomaticScrollViewStyle``.
  /// - Returns: The automatic presentation with `reservesIndicatorSpace` off.
  @MainActor
  public func resolvePresentation(for configuration: ScrollViewStyleConfiguration)
    -> ScrollViewStylePresentation
  {
    var presentation = AutomaticScrollViewStyle().resolvePresentation(for: configuration)
    presentation.snapshotLabel = snapshotLabel
    presentation.reservesIndicatorSpace = false
    return presentation
  }
}

extension ScrollViewStyle where Self == AutomaticScrollViewStyle {
  /// The default scroll style, as a leading-dot value of the protocol's own
  /// type: `.scrollViewStyle(.automatic)`.
  public static var automatic: Self { .init() }
}
extension ScrollViewStyle where Self == MinimalScrollViewStyle {
  /// The overlaid-thumb scroll style, as a leading-dot value of the protocol's
  /// own type: `.scrollViewStyle(.minimal)`.
  public static var minimal: Self { .init() }
}
extension AutomaticScrollViewStyle: ReuseTransparentStyle {}
extension MinimalScrollViewStyle: ReuseTransparentStyle {}
