public import SwiftTUICore

/// Resolves the chrome, insets, and separators a list renders with.
///
/// A list style is a presentation-value style: it implements
/// ``ListStyle/resolvePresentation(for:)`` and returns a `ListStylePresentation`
/// describing the container chrome, the scope that chrome is painted at, the
/// content insets, and whether row and section separators are drawn. It never
/// builds a body, so the list primitive keeps row virtualization, selection,
/// focus, keyboard navigation, scroll currency, and accessibility semantics
/// whatever the style resolves. Table treatments are a separate family; see
/// ``TableStyle``.
///
/// Apply a style with `listStyle(_:)`. The value is stored in the
/// environment for the subtree, so the nearest modifier above a list wins. The
/// built-ins are ``AnyListStyle/automatic``, ``AnyListStyle/plain``, and
/// ``AnyListStyle/insetGrouped``; `.automatic` is a fixed alias of
/// `.insetGrouped`.
///
/// A conforming type must be a value type and `Sendable`, because the
/// environment carries it across resolves. The resolved presentation is not
/// validated and has no per-field fallback: every field is used as returned.
///
/// ```swift
/// struct BareListStyle: ListStyle {
///   var snapshotLabel: String { "BareListStyle" }
///
///   func resolvePresentation(
///     for configuration: ListStyleConfiguration
///   ) -> ListStylePresentation {
///     .init(showsRowSeparators: false, showsSectionSeparators: false)
///   }
/// }
/// ```
///
/// See <doc:Style-System>, <doc:Authoring-Styles>, and <doc:Collections>.
public protocol ListStyle: Sendable {
  /// The label reported in snapshots and diagnostics.
  ///
  /// Diagnostic text, not identity: do not branch on it. ``AnyListStyle`` stamps
  /// this label onto the resolved presentation's `snapshotLabel`, replacing the
  /// variant label the presentation carried, so a list snapshot reports the
  /// style rather than the presentation constant it returned.
  var snapshotLabel: String { get }

  /// Resolves the presentation a list renders with for the given render state.
  ///
  /// Called on the main actor once per list resolve. The returned value is used
  /// as returned; nothing about it is clamped or replaced.
  ///
  /// - Parameter configuration: The list's selectability, enablement, focus, and
  ///   style environment for this resolve.
  /// - Returns: The container chrome, insets, and separator visibility for the
  ///   list.
  @MainActor
  func resolvePresentation(
    for configuration: ListStyleConfiguration
  ) -> ListStylePresentation
}

extension ListStyle {
  /// The reflected type name, supplied when a conforming type declares no label.
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// The render state a list style may consult.
///
/// Every member is read-only render state: there is no authored view slot and no
/// binding here, because a list style resolves a value rather than building a
/// body. List chrome is focus- and enabled-sensitive; built-in styles currently
/// resolve the same presentation for every state, and the state is supplied so
/// custom styles can do better without a second resolution path.
public struct ListStyleConfiguration: Sendable {
  /// Whether the list was declared with a selection binding, so rows can take
  /// selection. It does not say that anything is selected.
  public var isSelectable: Bool

  /// Whether the list is enabled, from the nearest `disabled(_:)` value.
  public var isEnabled: Bool

  /// Whether focus currently rests on the list itself.
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
    isSelectable: Bool,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.isSelectable = isSelectable
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.styleEnvironment = styleEnvironment
  }
}

private protocol AnyListStyleBox: AnyStyleBox {
  var snapshotLabel: String { get }
  var debugDescription: String { get }

  @MainActor
  func presentation(for configuration: ListStyleConfiguration) -> ListStylePresentation
}

extension ConcreteStyleBox: AnyListStyleBox where S: ListStyle {

  var snapshotLabel: String {
    style.snapshotLabel
  }

  var debugDescription: String {
    String(reflecting: style)
  }

  @MainActor
  func presentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    var presentation = style.resolvePresentation(for: configuration)
    presentation.snapshotLabel = style.snapshotLabel
    return presentation
  }

}

/// Type-erased storage for a list style, the value the environment carries.
///
/// Resolving through the eraser overwrites the presentation's `snapshotLabel`
/// with the wrapped style's label, so a presentation variant label such as
/// `"ListStylePresentation.plain"` survives only when
/// ``ListStyle/resolvePresentation(for:)`` is called directly.
public struct AnyListStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyListStyleBox

  /// Wraps a concrete list style for storage in the environment.
  ///
  /// - Parameter style: The style to erase. It is kept boxed, so reuse
  ///   comparisons still see the concrete value.
  public init<S: ListStyle>(
    _ style: S
  ) {
    box = ConcreteStyleBox(style: style)
  }

  /// The default list style, a fixed alias of ``insetGrouped``: rounded chrome
  /// around each section, one cell of content inset, and no separators.
  public static var automatic: Self {
    Self(AutomaticListStyle())
  }

  /// A list with no container chrome and no insets, where rows are divided by
  /// horizontal row and section separators.
  public static var plain: Self {
    Self(PlainListStyle())
  }

  /// A list where each section sits inside rounded box-drawing chrome with one
  /// cell of content inset on every edge, and no separators are drawn.
  public static var insetGrouped: Self {
    Self(InsetGroupedListStyle())
  }

  /// The wrapped style's ``ListStyle/snapshotLabel``.
  public var description: String {
    box.snapshotLabel
  }

  /// The wrapped style's ``ListStyle/snapshotLabel``, the same text as
  /// ``description``.
  public var debugDescription: String {
    box.snapshotLabel
  }

  @MainActor
  package func presentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    let resolved = box.presentation(for: configuration)
    return StyleMisuse.validatedPresentation(
      resolved, problems: resolved.validationProblems, family: "ListStyle",
      styleLabel: description, identity: ViewNodeContext.current?.identity,
      report: { ImperativeRuntimeIssueQueue.record($0) },
      fallback: { Self.automatic.box.presentation(for: configuration) }
    )
  }
}

extension AnyListStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The default list style: a fixed alias of ``InsetGroupedListStyle``.
///
/// It resolves the same rounded per-section chrome, one-cell content insets, and
/// suppressed separators, and it does not consult the configuration to do so.
public struct AutomaticListStyle: ListStyle, Sendable {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"ListStyle.automatic"`.
  public var snapshotLabel: String {
    "ListStyle.automatic"
  }

  /// Resolves the inset-grouped presentation for every render state.
  ///
  /// - Parameter configuration: The list's render state, which this style
  ///   ignores.
  /// - Returns: `ListStylePresentation.insetGrouped`.
  @MainActor
  public func resolvePresentation(
    for configuration: ListStyleConfiguration
  ) -> ListStylePresentation {
    .insetGrouped
  }
}

/// A separator-driven list style with no outer chrome.
///
/// It paints no container, applies no content insets, and draws both row and
/// section separators, so rows read as a flat divided run of lines.
public struct PlainListStyle: ListStyle, Sendable {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"ListStyle.plain"`.
  public var snapshotLabel: String {
    "ListStyle.plain"
  }

  /// Resolves the separator-driven presentation for every render state.
  ///
  /// - Parameter configuration: The list's render state, which this style
  ///   ignores.
  /// - Returns: `ListStylePresentation.plain`.
  @MainActor
  public func resolvePresentation(
    for configuration: ListStyleConfiguration
  ) -> ListStylePresentation {
    .plain
  }
}

/// A grouped list style with rounded section chrome.
///
/// Each section is boxed in rounded box-drawing glyphs, content is inset one cell
/// on every edge, and neither row nor section separators are drawn, since the
/// chrome already divides the sections.
public struct InsetGroupedListStyle: ListStyle, Sendable {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics,
  /// `"ListStyle.insetGrouped"`.
  public var snapshotLabel: String {
    "ListStyle.insetGrouped"
  }

  /// Resolves the rounded per-section presentation for every render state.
  ///
  /// - Parameter configuration: The list's render state, which this style
  ///   ignores.
  /// - Returns: `ListStylePresentation.insetGrouped`.
  @MainActor
  public func resolvePresentation(
    for configuration: ListStyleConfiguration
  ) -> ListStylePresentation {
    .insetGrouped
  }
}

extension AutomaticListStyle: ReuseTransparentStyle {}
extension PlainListStyle: ReuseTransparentStyle {}
extension InsetGroupedListStyle: ReuseTransparentStyle {}
