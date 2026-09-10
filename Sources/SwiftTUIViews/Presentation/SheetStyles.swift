public import SwiftTUICore

/// Which portal primitive a sheet's resolved presentation composes.
///
/// This is a within-family composition choice, not a surface-kind
/// discriminator: both cases belong to the sheet family and select between
/// two portal primitives of it.
public enum SheetSurfaceContainer: Equatable, Sendable {
  /// The centered, bordered surface a sheet renders by default.
  ///
  /// The surface sits at the center of the terminal inside a one-cell host
  /// inset. It draws a header row holding the title and a close button on the
  /// presentation's `headerTone`, a vertically scrolling content viewport
  /// bounded by the scroll heights, and a border in the presentation's stroke
  /// and paint, clamped to the width bounds. It honors every field of
  /// ``SheetSurfaceStylePresentation``.
  case standard
  /// A flat, edge-to-edge strip flush against the window's top edge, with a
  /// soft divider beneath it instead of a border.
  ///
  /// The strip spans the terminal width and has no header, close button, or
  /// border. It honors the scroll heights, `contentInsets`, `backdropOpacity`,
  /// and `backgroundStyle`, and paints `borderStyle` as the divider beneath
  /// it. It ignores `minimumWidth`, `maximumWidth`, `headerTone`, and
  /// `borderStroke`.
  case dropdown
}

/// Resolved sheet chrome: the container, backdrop, header tone, size bounds,
/// insets, and paint a sheet surface renders.
///
/// A ``SheetStyle`` returns this value from
/// ``SheetStyle/resolvePresentation(for:)``, usually by transforming the
/// ``SheetStyleConfiguration/defaultPresentation`` it is handed. The field set
/// here is the shared portal chrome vocabulary the remaining presentation
/// families reuse additively; `container` is the sheet family's own
/// composition choice. All dimensions are terminal cells.
///
/// Which fields the surface honors depends on the container: the standard
/// surface honors every field, and the dropdown strip ignores `minimumWidth`,
/// `maximumWidth`, `headerTone`, and `borderStroke` (see
/// ``SheetSurfaceContainer``).
///
/// The surface validates the value before rendering it. A negative width,
/// inset, or scroll height, a `maximumWidth` that is not positive or is below
/// `minimumWidth`, misordered scroll heights, a `backdropOpacity` outside
/// `0...1`, or a cell count too large to add to a terminal extent reports one
/// `style.invalidPresentation` runtime issue, and the declaration's baseline
/// renders for that resolve. A count larger than any terminal is still valid.
/// Nothing traps on a style value.
public struct SheetSurfaceStylePresentation: Sendable, Equatable {
  /// Which portal primitive renders the sheet. Defaults to `.standard`.
  public var container: SheetSurfaceContainer
  /// The opacity of the dim painted over the base content behind the
  /// surface, from `0` (no backdrop, the default) to `1`. Must be finite and
  /// within that range.
  public var backdropOpacity: Double
  /// The `TerminalTone` behind the standard surface's header row, which holds
  /// the title and the close button. Defaults to `.accent`; the dropdown strip
  /// has no header and ignores it.
  public var headerTone: TerminalTone
  /// The smallest outer width of the standard surface, in cells. Defaults to
  /// `20`; the dropdown baseline uses `0` and the strip ignores it. Must be
  /// non-negative and representable.
  public var minimumWidth: Int
  /// The largest outer width of the standard surface, in cells. `nil` (the
  /// default) lets the surface grow to the terminal width inside the host
  /// inset. When set it must be positive, at least `minimumWidth`, and
  /// representable.
  public var maximumWidth: Int?
  /// The smallest height of the scrolling content viewport, in cells, before
  /// insets and the header. Defaults to `4`.
  public var scrollMinimumHeight: Int
  /// The height of the content viewport when no height is proposed, in cells,
  /// before insets and the header. Defaults to `12`.
  public var scrollIdealHeight: Int
  /// The largest height of the scrolling content viewport, in cells, before
  /// insets and the header. Defaults to `20`. The three scroll heights must be
  /// non-negative, ordered minimum, ideal, maximum, and representable.
  public var scrollMaximumHeight: Int
  /// Insets in cells. On the standard surface they surround the header and
  /// viewport inside the border, while the viewport keeps a further fixed
  /// one-cell inset around the authored content; on the dropdown strip they
  /// surround the authored content inside the scrolling viewport. Both
  /// initializers default them to one cell on every edge. Edges must be
  /// non-negative and representable.
  public var contentInsets: EdgeInsets
  /// The fill behind the surface. `nil` (the default) uses the theme's
  /// surface background.
  public var backgroundStyle: AnyShapeStyle?
  /// The paint of the standard surface's border, or of the divider beneath
  /// the dropdown strip. `nil` (the default) uses the theme's accent border on
  /// the standard surface and the separator paint on the strip.
  public var borderStyle: AnyShapeStyle?
  /// The stroke geometry of the standard surface's border. Defaults to
  /// `.single`; the dropdown strip draws a divider instead and ignores it.
  public var borderStroke: StrokeStyle

  /// Constructs the established sheet baseline with default insets and paint.
  ///
  /// Every parameter defaults to the value a `sheet(...)` declaration renders
  /// without a style: the standard container, no backdrop, an accent header, a
  /// minimum width of 20 cells, no maximum width, scroll heights of 4, 12, and
  /// 20 cells, and a single-line stroke. Content insets are one cell on every
  /// edge and both paints are `nil`, so they follow the theme. Use the other
  /// initializer to set insets or paint.
  public init(
    container: SheetSurfaceContainer = .standard,
    backdropOpacity: Double = 0,
    headerTone: TerminalTone = .accent,
    minimumWidth: Int = 20,
    maximumWidth: Int? = nil,
    scrollMinimumHeight: Int = 4,
    scrollIdealHeight: Int = 12,
    scrollMaximumHeight: Int = 20,
    borderStroke: StrokeStyle = .single
  ) {
    self.init(
      container: container, backdropOpacity: backdropOpacity, headerTone: headerTone,
      minimumWidth: minimumWidth, maximumWidth: maximumWidth,
      scrollMinimumHeight: scrollMinimumHeight, scrollIdealHeight: scrollIdealHeight,
      scrollMaximumHeight: scrollMaximumHeight, borderStroke: borderStroke,
      contentInsets: .init(horizontal: 1, vertical: 1))
  }

  /// Constructs sheet chrome with explicit content insets and optional paint.
  ///
  /// The chrome parameters share the defaults of the paint-free initializer.
  /// `contentInsets` has no default, so a call that sets only a paint must
  /// still pass it (one cell on every edge reproduces the baseline), and
  /// `borderStroke` precedes `contentInsets` in this parameter list even
  /// though it is declared after the paints.
  ///
  /// - Parameters:
  ///   - container: Which portal primitive the sheet composes.
  ///   - backdropOpacity: Opacity of the dimming behind the surface, where
  ///     zero leaves the content behind it undimmed.
  ///   - headerTone: The semantic tone of the header chrome.
  ///   - minimumWidth: The narrowest the surface may be, in cells.
  ///   - maximumWidth: The widest the surface may be in cells, or `nil` for
  ///     unbounded.
  ///   - scrollMinimumHeight: The shortest the scrolling body may be, in cells.
  ///   - scrollIdealHeight: The height the scrolling body takes when the
  ///     content allows it, in cells.
  ///   - scrollMaximumHeight: The tallest the scrolling body may be, in cells.
  ///   - borderStroke: The border's stroke geometry.
  ///   - contentInsets: Insets in cells around the surface content; see
  ///     ``contentInsets``.
  ///   - backgroundStyle: The surface fill, or `nil` for the theme's surface
  ///     background.
  ///   - borderStyle: The border or divider paint, or `nil` for the theme's
  ///     accent border on the standard surface and the separator paint on the
  ///     dropdown strip.
  public init(
    container: SheetSurfaceContainer = .standard,
    backdropOpacity: Double = 0,
    headerTone: TerminalTone = .accent,
    minimumWidth: Int = 20,
    maximumWidth: Int? = nil,
    scrollMinimumHeight: Int = 4,
    scrollIdealHeight: Int = 12,
    scrollMaximumHeight: Int = 20,
    borderStroke: StrokeStyle = .single,
    contentInsets: EdgeInsets,
    backgroundStyle: AnyShapeStyle? = nil,
    borderStyle: AnyShapeStyle? = nil
  ) {
    self.container = container
    self.backdropOpacity = backdropOpacity
    self.headerTone = headerTone
    self.minimumWidth = minimumWidth
    self.maximumWidth = maximumWidth
    self.scrollMinimumHeight = scrollMinimumHeight
    self.scrollIdealHeight = scrollIdealHeight
    self.scrollMaximumHeight = scrollMaximumHeight
    self.borderStroke = borderStroke
    self.contentInsets = contentInsets
    self.backgroundStyle = backgroundStyle
    self.borderStyle = borderStyle
  }
}

/// The state a sheet style resolves against.
///
/// `defaultPresentation` is the declaring modifier's own baseline, so a
/// style transforms the declaration's constants rather than restating them,
/// the same pattern as `ButtonStyle.resolvedProminence(base:)`. `.automatic`
/// returns it unchanged, which is what makes the automatic style reproduce
/// the current descriptor exactly. The remaining members are read-only render
/// state captured from the declaring modifier's environment; nothing here is
/// a binding or an authored view, because the sheet's title and content stay
/// with the declaration.
public struct SheetStyleConfiguration: Sendable {
  /// The chrome the `sheet(...)` declaration renders without a style: the
  /// defaults of ``SheetSurfaceStylePresentation`` with the container and
  /// backdrop the declaration selects. Return it unchanged to keep the
  /// framework look, or copy and adjust it.
  public var defaultPresentation: SheetSurfaceStylePresentation
  /// The terminal's size in cells when the surface resolved, for sizing
  /// relative to the terminal rather than to a fixed width.
  public var terminalSize: CellSize
  /// The `ControlProminence` in effect at the declaration.
  public var controlProminence: ControlProminence
  /// The `StyleEnvironmentSnapshot` at the declaration: the detected
  /// appearance, the active theme, the ambient paints, and the enabled state,
  /// from which a style derives its colors.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// The framework's construction path, exposed to test targets through
  /// `@_spi(StyleFixtures)` so a style resolves against a fixture without a
  /// live render (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    defaultPresentation: SheetSurfaceStylePresentation,
    terminalSize: CellSize,
    controlProminence: ControlProminence,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.defaultPresentation = defaultPresentation
    self.terminalSize = terminalSize
    self.controlProminence = controlProminence
    self.styleEnvironment = styleEnvironment
  }
}

/// Defines the chrome a sheet presentation renders.
///
/// A sheet style is a presentation-value style:
/// ``SheetStyle/resolvePresentation(for:)`` returns a
/// ``SheetSurfaceStylePresentation`` rather than a view body. The
/// ``SheetStyleConfiguration`` hands it the declaration's own baseline as
/// ``SheetStyleConfiguration/defaultPresentation`` plus the terminal size,
/// control prominence, and style environment; a style transforms the baseline
/// rather than restating it.
///
/// The portal coordinator keeps stacking, modal policy, focus scopes,
/// Escape, dismissal, source environments, and lifecycle; a style resolves
/// chrome only. The authored content, the title, and the header's close
/// button belong to the declaration.
///
/// The declaring modifier reads the style from the environment while the
/// sheet is closed, so a change made then applies on the next opening, but it
/// calls and validates the style only when the surface presents. An invalid
/// value reports one `style.invalidPresentation` runtime issue and the
/// baseline renders for that resolve; a closed declaration reports nothing.
///
/// Built-ins: ``AnySheetStyle/surface`` returns the baseline unchanged,
/// ``AnySheetStyle/dropdown`` switches to the full-width strip, and
/// ``AnySheetStyle/automatic`` is a fixed alias of `surface`. Apply one with
/// `sheetStyle(_:)`; the nearest modifier wins for every `sheet(...)`
/// declaration in the subtree. The command palette's sheet is styled by
/// ``PaletteStyle`` instead. Conform with a `Sendable` struct or enum.
///
/// ```swift
/// struct WideSheetStyle: SheetStyle {
///   func resolvePresentation(
///     for configuration: SheetStyleConfiguration
///   ) -> SheetSurfaceStylePresentation {
///     var presentation = configuration.defaultPresentation
///     presentation.minimumWidth = max(
///       presentation.minimumWidth, configuration.terminalSize.width * 3 / 4)
///     return presentation
///   }
/// }
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol SheetStyle: Sendable {
  /// The label reported in snapshots and diagnostics. Defaults to the
  /// reflected type name; the built-ins pin `"SheetStyle.surface"` and
  /// `"SheetStyle.dropdown"`. It is diagnostic text, not identity.
  var snapshotLabel: String { get }

  /// Resolves the chrome the presented sheet renders.
  ///
  /// Called on the main actor each time the presenting declaration resolves
  /// while the sheet is presented, never while it is closed. Start from
  /// ``SheetStyleConfiguration/defaultPresentation`` so fields the style does
  /// not touch keep the declaration's constants.
  ///
  /// - Parameter configuration: The declaration's baseline and render state.
  /// - Returns: The chrome for this resolve; an invalid value falls back to
  ///   the baseline after reporting.
  @MainActor
  func resolvePresentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation
}

extension SheetStyle {
  /// The reflected type name, used when a conformance does not pin a label.
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

private protocol AnySheetStyleBox: AnyStyleBox {
  var snapshotLabel: String { get }

  @MainActor
  func presentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation
}

extension ConcreteStyleBox: AnySheetStyleBox where S: SheetStyle {

  var snapshotLabel: String {
    style.snapshotLabel
  }

  @MainActor
  func presentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation {
    style.resolvePresentation(for: configuration)
  }

}

/// Type-erased storage for a sheet style, the value the environment carries.
///
/// `sheetStyle(_:)` stores one of these for a subtree; a presenting sheet
/// reads the nearest one. Every built-in is available as a static, and
/// ``AnySheetStyle/init(_:)`` wraps a custom conformance. The built-ins
/// compare equal for retained reuse by type; a custom style compares by value
/// when it is `Equatable`.
public struct AnySheetStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnySheetStyleBox

  /// Wraps `style` for storage in the environment.
  ///
  /// - Parameter style: The concrete ``SheetStyle`` to erase.
  public init<S: SheetStyle>(
    _ style: S
  ) {
    box = ConcreteStyleBox(style: style)
  }

  /// A documented *fixed* alias of ``surface``.
  public static var automatic: Self {
    Self(SurfaceSheetStyle())
  }

  /// The centered, bordered ``SheetSurfaceContainer/standard`` surface with a
  /// header row, rendered from the declaration's baseline unchanged
  /// (``SurfaceSheetStyle``).
  public static var surface: Self {
    Self(SurfaceSheetStyle())
  }

  /// The full-width ``SheetSurfaceContainer/dropdown`` strip flush against
  /// the top edge, with no header or border and a divider beneath
  /// (``DropdownSheetStyle``).
  public static var dropdown: Self {
    Self(DropdownSheetStyle())
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String {
    box.snapshotLabel
  }

  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String {
    description
  }

  @MainActor
  package func presentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation {
    box.presentation(for: configuration)
  }
}

extension AnySheetStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The sheet chrome a declaration renders by default: the modifier's own
/// baseline, returned unchanged.
///
/// With the framework baseline the result is the centered
/// ``SheetSurfaceContainer/standard`` surface: a header row on the accent
/// tone with the title and a close button, a scrolling content viewport, a
/// single-line border in the theme's accent border paint, one cell of inset,
/// and no backdrop.
public struct SurfaceSheetStyle: SheetStyle, Sendable {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"SheetStyle.surface"`.
  public var snapshotLabel: String { "SheetStyle.surface" }

  /// Returns ``SheetStyleConfiguration/defaultPresentation`` unchanged.
  @MainActor
  public func resolvePresentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation {
    configuration.defaultPresentation
  }
}

/// Flat, edge-to-edge chrome flush against the window's top edge.
///
/// The result is the declaration's baseline with `container` set to
/// ``SheetSurfaceContainer/dropdown`` and `minimumWidth` set to `0`: a strip
/// spanning the terminal width with no header, close button, or border, the
/// scrolling content inside the baseline's insets, and a divider in the
/// border paint beneath. Every other baseline field is kept, so a backdrop or
/// paint the declaration supplies still applies.
public struct DropdownSheetStyle: SheetStyle, Sendable {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"SheetStyle.dropdown"`.
  public var snapshotLabel: String { "SheetStyle.dropdown" }

  /// Returns the baseline with the dropdown container and a zero minimum
  /// width; every other field is preserved.
  @MainActor
  public func resolvePresentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation {
    var presentation = configuration.defaultPresentation
    presentation.container = .dropdown
    presentation.minimumWidth = 0
    return presentation
  }
}

extension SheetStyle where Self == SurfaceSheetStyle {
  /// A documented *fixed* alias of ``surface``.
  public static var automatic: SurfaceSheetStyle { .init() }
  /// The centered, bordered standard surface; see ``SurfaceSheetStyle``.
  public static var surface: SurfaceSheetStyle { .init() }
}

extension SheetStyle where Self == DropdownSheetStyle {
  /// The full-width dropdown strip; see ``DropdownSheetStyle``.
  public static var dropdown: DropdownSheetStyle { .init() }
}

extension SurfaceSheetStyle: ReuseTransparentStyle {}
extension DropdownSheetStyle: ReuseTransparentStyle {}

extension ResolveContext {
  /// The eager form, for callers that need the value at resolve time.
  @MainActor
  package func resolvedSheetPresentation(
    baseline: SheetSurfaceStylePresentation
  ) -> SheetSurfaceStylePresentation {
    PortalStyleResolveInputs(self).resolvedSheetPresentation(
      style: environmentValues.sheetStyle, baseline: baseline)
  }
}
