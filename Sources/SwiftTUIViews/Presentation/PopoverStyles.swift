public import SwiftTUICore

/// The declaration's baseline and environment for anchored popover surfaces.
public struct PopoverStyleConfiguration: Sendable {
  public var defaultPresentation: AnchoredSurfaceStylePresentation
  public var terminalSize: CellSize
  public var controlProminence: ControlProminence
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Constructs a style fixture without presenting a live surface.
  @_spi(StyleFixtures)
  public init(
    defaultPresentation: AnchoredSurfaceStylePresentation,
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

/// Resolves the appearance of anchored popover surfaces.
///
/// The originating declaration retains placement, focus, modal policy,
/// dismissal, lifecycle, and action behavior.
public protocol PopoverStyle: Sendable {
  var snapshotLabel: String { get }

  @MainActor
  func resolvePresentation(
    for configuration: PopoverStyleConfiguration
  ) -> AnchoredSurfaceStylePresentation
}

extension PopoverStyle {
  public var snapshotLabel: String { String(reflecting: Self.self) }
}

private protocol AnyPopoverStyleBox: Sendable {
  var snapshotLabel: String { get }
  @MainActor
  func presentation(for configuration: PopoverStyleConfiguration)
    -> AnchoredSurfaceStylePresentation
  func isEqualForReuse(to other: any AnyPopoverStyleBox) -> Bool
}

private struct ConcretePopoverStyleBox<S: PopoverStyle>: AnyPopoverStyleBox {
  let style: S
  var snapshotLabel: String { style.snapshotLabel }

  @MainActor
  func presentation(for configuration: PopoverStyleConfiguration)
    -> AnchoredSurfaceStylePresentation
  {
    style.resolvePresentation(for: configuration)
  }

  func isEqualForReuse(to other: any AnyPopoverStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }
}

/// An erased popover style with typed reuse comparison.
public struct AnyPopoverStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyPopoverStyleBox

  public init<S: PopoverStyle>(_ style: S) {
    box = ConcretePopoverStyleBox(style: style)
  }

  public static var automatic: Self { Self(AutomaticPopoverStyle()) }
  public var description: String { box.snapshotLabel }
  public var debugDescription: String { description }

  @MainActor
  package func presentation(for configuration: PopoverStyleConfiguration)
    -> AnchoredSurfaceStylePresentation
  {
    box.presentation(for: configuration)
  }
}

extension AnyPopoverStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// Preserves the originating declaration's surface appearance.
public struct AutomaticPopoverStyle: PopoverStyle {
  public init() {}
  public var snapshotLabel: String { "PopoverStyle.automatic" }

  @MainActor
  public func resolvePresentation(
    for configuration: PopoverStyleConfiguration
  ) -> AnchoredSurfaceStylePresentation {
    configuration.defaultPresentation
  }
}

extension PopoverStyle where Self == AutomaticPopoverStyle {
  public static var automatic: AutomaticPopoverStyle { .init() }
}

extension AutomaticPopoverStyle: ReuseTransparentStyle {}

extension ResolveContext {
  @MainActor
  package func resolvedPopoverPresentation() -> AnchoredSurfaceStylePresentation {
    // Popovers keep their rounded stroke; Menu's shared value has its own baseline.
    let baseline = AnchoredSurfaceStylePresentation(borderStroke: StrokeStyle())
    let style = environmentValues.popoverStyle
    let resolved = style.presentation(
      for: .init(
        defaultPresentation: baseline, terminalSize: environmentValues.terminalSize,
        controlProminence: environmentValues.controlProminence,
        styleEnvironment: environmentValues.styleEnvironmentSnapshot))
    return StyleMisuse.validatedPresentation(
      resolved, problems: resolved.validationProblems, family: "PopoverStyle",
      styleLabel: style.description, identity: identity,
      report: ImperativeRuntimeIssueQueue.record, fallback: { baseline })
  }
}
