public import SwiftTUICore

/// An extensible list style.
///
/// A list style resolves a `ListStylePresentation` — container chrome,
/// insets, and separator visibility — from the list's render state. Table
/// treatments are a separate family; see `TableStyle`.
public protocol ListStyle: Sendable {
  var snapshotLabel: String { get }

  @MainActor
  func resolvePresentation(
    for configuration: ListStyleConfiguration
  ) -> ListStylePresentation
}

extension ListStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// The render state a list style may consult.
///
/// List chrome is focus- and enabled-sensitive; built-in styles currently
/// resolve the same presentation for every state, and the state is supplied
/// so custom styles can do better without a second resolution path.
public struct ListStyleConfiguration: Sendable {
  public var isSelectable: Bool
  public var isEnabled: Bool
  public var isFocused: Bool
  public var showsFocusEffect: Bool
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

private protocol AnyListStyleBox: Sendable {
  var snapshotLabel: String { get }
  var debugDescription: String { get }

  @MainActor
  func presentation(for configuration: ListStyleConfiguration) -> ListStylePresentation
  func isEqualForReuse(to other: any AnyListStyleBox) -> Bool
}

private struct ConcreteListStyleBox<S: ListStyle>: AnyListStyleBox {
  let style: S

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

  func isEqualForReuse(to other: any AnyListStyleBox) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return styleValuesAreEqualForReuse(style, other.style)
  }
}

/// A type-erased list style.
public struct AnyListStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyListStyleBox

  public init<S: ListStyle>(
    _ style: S
  ) {
    box = ConcreteListStyleBox(style: style)
  }

  public static var automatic: Self {
    Self(AutomaticListStyle())
  }

  public static var plain: Self {
    Self(PlainListStyle())
  }

  public static var insetGrouped: Self {
    Self(InsetGroupedListStyle())
  }

  public var description: String {
    box.snapshotLabel
  }

  public var debugDescription: String {
    box.debugDescription
  }

  @MainActor
  package func presentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    box.presentation(for: configuration)
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

/// The default list style that resolves to grouped chrome.
public struct AutomaticListStyle: ListStyle, Sendable {
  public init() {}

  public var snapshotLabel: String {
    "ListStyle.automatic"
  }

  @MainActor
  public func resolvePresentation(
    for configuration: ListStyleConfiguration
  ) -> ListStylePresentation {
    .insetGrouped
  }
}

/// A separator-driven list style with no outer chrome.
public struct PlainListStyle: ListStyle, Sendable {
  public init() {}

  public var snapshotLabel: String {
    "ListStyle.plain"
  }

  @MainActor
  public func resolvePresentation(
    for configuration: ListStyleConfiguration
  ) -> ListStylePresentation {
    .plain
  }
}

/// A grouped list style with rounded section chrome.
public struct InsetGroupedListStyle: ListStyle, Sendable {
  public init() {}

  public var snapshotLabel: String {
    "ListStyle.insetGrouped"
  }

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
