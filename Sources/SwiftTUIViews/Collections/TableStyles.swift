public import SwiftTUICore

/// Resolves the border glyphs, header paints, and insets a table renders with.
///
/// A table style is a presentation-value style: it implements
/// ``TableStyle/resolvePresentation(for:)`` and returns a
/// `TableStylePresentation` holding the border glyph set, the header foreground
/// and background paints, the content insets, and the border paint. It never
/// builds a body, so the table primitive keeps virtualization, selection, header
/// semantics, cell layout, pointer routes, and scroll currency; a style cannot
/// change them. List treatments are a separate family; see ``ListStyle``.
///
/// Apply a style with `tableStyle(_:)`. The value is stored in the
/// environment for the subtree, so the nearest modifier above a table wins. The
/// built-ins are ``AnyTableStyle/automatic``, ``AnyTableStyle/inset``, and
/// ``AnyTableStyle/bordered``; `.automatic` is a fixed alias of `.inset`.
///
/// A conforming type must be a value type and `Sendable`, because the
/// environment carries it across resolves. The resolved presentation is not
/// validated and has no per-field fallback: every field is used as returned.
///
/// ```swift
/// struct AlertTableStyle: TableStyle {
///   var snapshotLabel: String { "AlertTableStyle" }
///
///   func resolvePresentation(
///     for configuration: TableStyleConfiguration
///   ) -> TableStylePresentation {
///     .init(
///       borderGlyphs: .plain,
///       headerForegroundStyle: .semantic(.warning),
///       borderStyle: .semantic(.danger)
///     )
///   }
/// }
/// ```
///
/// See <doc:Style-System>, <doc:Authoring-Styles>, and <doc:Collections>.
public protocol TableStyle: Sendable {
  /// The label reported in snapshots and diagnostics.
  ///
  /// Diagnostic text, not identity: do not branch on it. ``AnyTableStyle`` stamps
  /// this label onto the resolved presentation's `snapshotLabel`, replacing the
  /// variant label the presentation carried.
  var snapshotLabel: String { get }

  /// Resolves the presentation a table renders with for the given render state.
  ///
  /// Called on the main actor once per table resolve. The returned value is used
  /// as returned; nothing about it is clamped or replaced.
  ///
  /// - Parameter configuration: The table's column count, header visibility,
  ///   selectability, enablement, focus, and style environment for this resolve.
  /// - Returns: The border glyphs, header paints, insets, and border paint for
  ///   the table.
  @MainActor
  func resolvePresentation(
    for configuration: TableStyleConfiguration
  ) -> TableStylePresentation
}

extension TableStyle {
  /// The reflected type name, supplied when a conforming type declares no label.
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// The render state a table style may consult.
///
/// Every member is read-only render state: there is no authored view slot and no
/// binding here, because a table style resolves a value rather than building a
/// body. The built-in styles resolve the same presentation for every state; the
/// state is supplied so a custom style can vary its result without a second
/// resolution path.
public struct TableStyleConfiguration: Sendable {
  /// How many columns the table declared, so a style can vary its glyphs or
  /// insets by width. It counts declared columns, not visible cells.
  public var columnCount: Int

  /// Whether a header row is drawn, from the nearest `tableHeaderVisibility`
  /// value. When it is `false`, the header paints in the presentation go unused.
  public var showsHeaders: Bool

  /// Whether the table was declared with a selection binding, so rows can take
  /// selection. It does not say that anything is selected.
  public var isSelectable: Bool

  /// Whether the table is enabled, from the nearest `disabled(_:)` value.
  public var isEnabled: Bool

  /// Whether focus currently rests on the table itself.
  public var isFocused: Bool

  /// Whether the focus effect is enabled for this subtree. A style that paints
  /// focus chrome should do so only when this is `true` and ``isFocused`` is
  /// `true`.
  public var showsFocusEffect: Bool

  /// The theme, appearance, inherited paints, and cell metrics captured from the
  /// environment, for deriving colors instead of hardcoding them.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// The framework's construction path, exposed to test targets through
  /// `@_spi(StyleFixtures)` so a style resolves against a fixture without a
  /// live render (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    columnCount: Int,
    showsHeaders: Bool,
    isSelectable: Bool,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.columnCount = columnCount
    self.showsHeaders = showsHeaders
    self.isSelectable = isSelectable
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.styleEnvironment = styleEnvironment
  }
}

private protocol AnyTableStyleBox: AnyStyleBox {
  var snapshotLabel: String { get }
  var debugDescription: String { get }

  @MainActor
  func presentation(for configuration: TableStyleConfiguration) -> TableStylePresentation
}

extension ConcreteStyleBox: AnyTableStyleBox where S: TableStyle {

  var snapshotLabel: String {
    style.snapshotLabel
  }

  var debugDescription: String {
    String(reflecting: style)
  }

  @MainActor
  func presentation(for configuration: TableStyleConfiguration) -> TableStylePresentation {
    var presentation = style.resolvePresentation(for: configuration)
    presentation.snapshotLabel = style.snapshotLabel
    return presentation
  }

}

/// Type-erased storage for a table style, the value the environment carries.
///
/// Resolving through the eraser overwrites the presentation's `snapshotLabel`
/// with the wrapped style's label, so a presentation variant label such as
/// `"TableStylePresentation.inset"` survives only when
/// ``TableStyle/resolvePresentation(for:)`` is called directly.
public struct AnyTableStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyTableStyleBox

  /// Wraps a concrete table style for storage in the environment.
  ///
  /// - Parameter style: The style to erase. It is kept boxed, so reuse
  ///   comparisons still see the concrete value.
  public init<S: TableStyle>(
    _ style: S
  ) {
    box = ConcreteStyleBox(style: style)
  }

  /// The default table style, a fixed alias of ``inset``.
  public static var automatic: Self {
    Self(AutomaticTableStyle())
  }

  /// Rounded box-drawing corners with an accented header drawn on the odd-row
  /// background.
  public static var inset: Self {
    Self(InsetTableStyle())
  }

  /// Square box-drawing corners with a muted header and no header background.
  public static var bordered: Self {
    Self(BorderedTableStyle())
  }

  /// The wrapped style's ``TableStyle/snapshotLabel``.
  public var description: String {
    box.snapshotLabel
  }

  /// The wrapped style's ``TableStyle/snapshotLabel``, the same text as
  /// ``description``.
  public var debugDescription: String {
    box.snapshotLabel
  }

  @MainActor
  package func presentation(for configuration: TableStyleConfiguration) -> TableStylePresentation {
    box.presentation(for: configuration)
  }
}

extension AnyTableStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The default table style: a fixed alias of ``InsetTableStyle``.
///
/// It resolves the same rounded inset treatment, preserving the table result the
/// former automatic list style produced, and it does not consult the
/// configuration to do so.
public struct AutomaticTableStyle: TableStyle, Sendable {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"TableStyle.automatic"`.
  public var snapshotLabel: String {
    "TableStyle.automatic"
  }

  /// Resolves the rounded inset presentation for every render state.
  ///
  /// - Parameter configuration: The table's render state, which this style
  ///   ignores.
  /// - Returns: `TableStylePresentation.inset`.
  @MainActor
  public func resolvePresentation(
    for configuration: TableStyleConfiguration
  ) -> TableStylePresentation {
    .inset
  }
}

/// The rounded inset treatment (the former inset-grouped collection result).
///
/// The frame is drawn with rounded corners (`╭ ╮ ╰ ╯`) over single-line edges
/// and joins, the header text takes the accent border paint, and the header row
/// sits on the odd-row background.
public struct InsetTableStyle: TableStyle, Sendable {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"TableStyle.inset"`.
  public var snapshotLabel: String {
    "TableStyle.inset"
  }

  /// Resolves the rounded inset presentation for every render state.
  ///
  /// - Parameter configuration: The table's render state, which this style
  ///   ignores.
  /// - Returns: `TableStylePresentation.inset`.
  @MainActor
  public func resolvePresentation(
    for configuration: TableStyleConfiguration
  ) -> TableStylePresentation {
    .inset
  }
}

/// The square-bordered treatment (the former plain collection result).
///
/// The frame is drawn with square corners (`┌ ┐ └ ┘`) over the same single-line
/// edges and joins, the header text takes the muted semantic paint, and the
/// header row has no background of its own.
public struct BorderedTableStyle: TableStyle, Sendable {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"TableStyle.bordered"`.
  public var snapshotLabel: String {
    "TableStyle.bordered"
  }

  /// Resolves the square-bordered presentation for every render state.
  ///
  /// - Parameter configuration: The table's render state, which this style
  ///   ignores.
  /// - Returns: `TableStylePresentation.bordered`.
  @MainActor
  public func resolvePresentation(
    for configuration: TableStyleConfiguration
  ) -> TableStylePresentation {
    .bordered
  }
}

extension AutomaticTableStyle: ReuseTransparentStyle {}
extension InsetTableStyle: ReuseTransparentStyle {}
extension BorderedTableStyle: ReuseTransparentStyle {}
