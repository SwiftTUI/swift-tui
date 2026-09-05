public import SwiftTUICore

/// The declaration's baseline and environment for alert and confirmation-dialog surfaces.
public struct PromptStyleConfiguration: Sendable {
  /// Whether message slots were declared. Opaque view bodies count as present.
  public var hasMessage: Bool
  /// Whether action slots were declared. Empty builders do not count.
  public var hasActions: Bool
  public var defaultPresentation: PromptSurfaceStylePresentation
  public var terminalSize: CellSize
  public var controlProminence: ControlProminence
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs a style fixture without presenting a live surface.
  @_spi(StyleFixtures)
  public init(
    hasMessage: Bool,
    hasActions: Bool,
    defaultPresentation: PromptSurfaceStylePresentation,
    terminalSize: CellSize,
    controlProminence: ControlProminence,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.hasMessage = hasMessage
    self.hasActions = hasActions
    self.defaultPresentation = defaultPresentation
    self.terminalSize = terminalSize
    self.controlProminence = controlProminence
    self.styleEnvironment = styleEnvironment
  }
}

/// Resolves the appearance of alert and confirmation-dialog surfaces.
///
/// The originating declaration retains placement, focus, modal policy,
/// dismissal, lifecycle, and action behavior.
public protocol PromptStyle: Sendable {
  var snapshotLabel: String { get }

  @MainActor
  func resolvePresentation(
    for configuration: PromptStyleConfiguration
  ) -> PromptSurfaceStylePresentation
}

extension PromptStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }
}

private protocol AnyPromptStyleBox: Sendable {
  var snapshotLabel: String { get }
  @MainActor
  func presentation(for configuration: PromptStyleConfiguration) -> PromptSurfaceStylePresentation
  func isEqualForReuse(to other: any AnyPromptStyleBox) -> Bool
}

private struct ConcretePromptStyleBox<S: PromptStyle>: AnyPromptStyleBox {
  let style: S
  var snapshotLabel: String { style.snapshotLabel }

  @MainActor
  func presentation(for configuration: PromptStyleConfiguration) -> PromptSurfaceStylePresentation {
    style.resolvePresentation(for: configuration)
  }

  func isEqualForReuse(to other: any AnyPromptStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }
}

/// An erased prompt style with typed reuse comparison.
public struct AnyPromptStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyPromptStyleBox

  public init<S: PromptStyle>(_ style: S) {
    box = ConcretePromptStyleBox(style: style)
  }

  public static var automatic: Self { Self(AutomaticPromptStyle()) }
  public var description: String { box.snapshotLabel }
  public var debugDescription: String { description }

  @MainActor
  package func presentation(for configuration: PromptStyleConfiguration)
    -> PromptSurfaceStylePresentation
  {
    box.presentation(for: configuration)
  }
}

extension AnyPromptStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// Preserves the originating declaration's surface appearance.
public struct AutomaticPromptStyle: PromptStyle {
  public init() {}
  public var snapshotLabel: String { "PromptStyle.automatic" }

  @MainActor
  public func resolvePresentation(
    for configuration: PromptStyleConfiguration
  ) -> PromptSurfaceStylePresentation {
    configuration.defaultPresentation
  }
}

extension PromptStyle where Self == AutomaticPromptStyle {
  public static var automatic: AutomaticPromptStyle { .init() }
}

extension AutomaticPromptStyle: ReuseTransparentStyle {}
