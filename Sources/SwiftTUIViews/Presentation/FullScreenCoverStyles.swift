public import SwiftTUICore

/// The declaration's baseline and environment for full-screen cover surfaces.
public struct FullScreenCoverStyleConfiguration: Sendable {
  public var defaultPresentation: FullScreenSurfaceStylePresentation
  public var terminalSize: CellSize
  public var controlProminence: ControlProminence
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs a style fixture without presenting a live surface.
  @_spi(StyleFixtures)
  public init(
    defaultPresentation: FullScreenSurfaceStylePresentation,
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

/// Resolves the appearance of full-screen cover surfaces.
///
/// The originating declaration retains placement, focus, modal policy,
/// dismissal, lifecycle, and action behavior.
public protocol FullScreenCoverStyle: Sendable {
  var snapshotLabel: String { get }

  @MainActor
  func resolvePresentation(
    for configuration: FullScreenCoverStyleConfiguration
  ) -> FullScreenSurfaceStylePresentation
}

extension FullScreenCoverStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }
}

private protocol AnyFullScreenCoverStyleBox: Sendable {
  var snapshotLabel: String { get }
  @MainActor
  func presentation(for configuration: FullScreenCoverStyleConfiguration)
    -> FullScreenSurfaceStylePresentation
  func isEqualForReuse(to other: any AnyFullScreenCoverStyleBox) -> Bool
}

private struct ConcreteFullScreenCoverStyleBox<S: FullScreenCoverStyle>: AnyFullScreenCoverStyleBox
{
  let style: S
  var snapshotLabel: String { style.snapshotLabel }

  @MainActor
  func presentation(for configuration: FullScreenCoverStyleConfiguration)
    -> FullScreenSurfaceStylePresentation
  {
    style.resolvePresentation(for: configuration)
  }

  func isEqualForReuse(to other: any AnyFullScreenCoverStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }
}

/// An erased full-screen cover style with typed reuse comparison.
public struct AnyFullScreenCoverStyle: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  private let box: any AnyFullScreenCoverStyleBox

  public init<S: FullScreenCoverStyle>(_ style: S) {
    box = ConcreteFullScreenCoverStyleBox(style: style)
  }

  public static var automatic: Self { Self(AutomaticFullScreenCoverStyle()) }
  public var description: String { box.snapshotLabel }
  public var debugDescription: String { description }

  @MainActor
  package func presentation(for configuration: FullScreenCoverStyleConfiguration)
    -> FullScreenSurfaceStylePresentation
  {
    box.presentation(for: configuration)
  }
}

extension AnyFullScreenCoverStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// Preserves the originating declaration's surface appearance.
public struct AutomaticFullScreenCoverStyle: FullScreenCoverStyle {
  public init() {}
  public var snapshotLabel: String { "FullScreenCoverStyle.automatic" }

  @MainActor
  public func resolvePresentation(
    for configuration: FullScreenCoverStyleConfiguration
  ) -> FullScreenSurfaceStylePresentation {
    configuration.defaultPresentation
  }
}

extension FullScreenCoverStyle where Self == AutomaticFullScreenCoverStyle {
  public static var automatic: AutomaticFullScreenCoverStyle { .init() }
}

extension AutomaticFullScreenCoverStyle: ReuseTransparentStyle {}
