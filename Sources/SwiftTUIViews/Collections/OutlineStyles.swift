public import SwiftTUICore

/// An extensible outline style for hierarchical connectors and indent guides.
///
/// ASCII substitution is deliberately not an outline style: capability-driven
/// glyph degradation is rasterizer fallback behavior.
public protocol OutlineStyle: Sendable {
  var snapshotLabel: String { get }

  @MainActor
  func resolvePresentation(
    for configuration: OutlineStyleConfiguration
  ) -> OutlineStylePresentation
}

extension OutlineStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// The render state an outline style may consult.
///
/// Outline connector choice currently needs only the style environment.
public struct OutlineStyleConfiguration: Sendable {
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// The framework's construction path, exposed to test targets through
  /// `@_spi(StyleFixtures)` so a style resolves against a fixture without a
  /// live render (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.styleEnvironment = styleEnvironment
  }
}

private protocol AnyOutlineStyleBox: Sendable {
  var snapshotLabel: String { get }
  var debugDescription: String { get }

  @MainActor
  func presentation(for configuration: OutlineStyleConfiguration) -> OutlineStylePresentation
  func isEqualForReuse(to other: any AnyOutlineStyleBox) -> Bool
}

private struct ConcreteOutlineStyleBox<S: OutlineStyle>: AnyOutlineStyleBox {
  let style: S

  var snapshotLabel: String {
    style.snapshotLabel
  }

  var debugDescription: String {
    String(reflecting: style)
  }

  @MainActor
  func presentation(for configuration: OutlineStyleConfiguration) -> OutlineStylePresentation {
    var presentation = style.resolvePresentation(for: configuration)
    presentation.snapshotLabel = style.snapshotLabel
    return presentation
  }

  func isEqualForReuse(to other: any AnyOutlineStyleBox) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return styleValuesAreEqualForReuse(style, other.style)
  }
}

/// A type-erased outline style.
public struct AnyOutlineStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyOutlineStyleBox

  public init<S: OutlineStyle>(
    _ style: S
  ) {
    box = ConcreteOutlineStyleBox(style: style)
  }

  public static var automatic: Self {
    Self(AutomaticOutlineStyle())
  }

  public static var rounded: Self {
    Self(RoundedOutlineStyle())
  }

  public static var plain: Self {
    Self(PlainOutlineStyle())
  }

  public var description: String {
    box.snapshotLabel
  }

  public var debugDescription: String {
    box.debugDescription
  }

  @MainActor
  package func presentation(
    for configuration: OutlineStyleConfiguration
  ) -> OutlineStylePresentation {
    box.presentation(for: configuration)
  }
}

extension AnyOutlineStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The default outline style that resolves to rounded connectors.
public struct AutomaticOutlineStyle: OutlineStyle, Sendable {
  public init() {}

  public var snapshotLabel: String {
    "OutlineStyle.automatic"
  }

  @MainActor
  public func resolvePresentation(
    for configuration: OutlineStyleConfiguration
  ) -> OutlineStylePresentation {
    .rounded
  }
}

/// An outline style with rounded leaf connectors.
public struct RoundedOutlineStyle: OutlineStyle, Sendable {
  public init() {}

  public var snapshotLabel: String {
    "OutlineStyle.rounded"
  }

  @MainActor
  public func resolvePresentation(
    for configuration: OutlineStyleConfiguration
  ) -> OutlineStylePresentation {
    .rounded
  }
}

/// An outline style that uses box-drawing connectors throughout.
public struct PlainOutlineStyle: OutlineStyle, Sendable {
  public init() {}

  public var snapshotLabel: String {
    "OutlineStyle.plain"
  }

  @MainActor
  public func resolvePresentation(
    for configuration: OutlineStyleConfiguration
  ) -> OutlineStylePresentation {
    .plain
  }
}

extension AutomaticOutlineStyle: ReuseTransparentStyle {}
extension RoundedOutlineStyle: ReuseTransparentStyle {}
extension PlainOutlineStyle: ReuseTransparentStyle {}
