public import SwiftTUICore

/// Which portal primitive a sheet's resolved presentation composes.
///
/// This is a within-family composition choice, not a surface-kind
/// discriminator: both cases belong to the sheet family and select between
/// two portal primitives of it.
public enum SheetSurfaceContainer: Equatable, Sendable {
  /// The centered, bordered surface a sheet renders by default.
  case standard
  /// A flat, edge-to-edge strip flush against the window's top edge, with a
  /// soft divider beneath it instead of a border.
  case dropdown
}

/// Resolved sheet chrome.
///
/// The field set here is the shared portal chrome vocabulary the remaining
/// presentation families reuse additively; `container` is the sheet
/// family's own composition choice.
public struct SheetSurfaceStylePresentation: Sendable, Equatable {
  public var container: SheetSurfaceContainer
  public var backdropOpacity: Double
  public var headerTone: TerminalTone
  public var minimumWidth: Int
  public var maximumWidth: Int?
  public var scrollMinimumHeight: Int
  public var scrollIdealHeight: Int
  public var scrollMaximumHeight: Int
  public var borderStroke: StrokeStyle

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
    self.container = container
    self.backdropOpacity = backdropOpacity
    self.headerTone = headerTone
    self.minimumWidth = minimumWidth
    self.maximumWidth = maximumWidth
    self.scrollMinimumHeight = scrollMinimumHeight
    self.scrollIdealHeight = scrollIdealHeight
    self.scrollMaximumHeight = scrollMaximumHeight
    self.borderStroke = borderStroke
  }
}

/// The state a sheet style resolves against.
///
/// `defaultPresentation` is the declaring modifier's own baseline, so a
/// style transforms the declaration's constants rather than restating
/// them — the `ButtonStyle.resolvedProminence(base:)` pattern. `.automatic`
/// returns it unchanged, which is what makes the automatic style reproduce
/// the current descriptor exactly.
public struct SheetStyleConfiguration: Sendable {
  public var defaultPresentation: SheetSurfaceStylePresentation
  public var terminalSize: CellSize
  public var controlProminence: ControlProminence
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
/// The portal coordinator keeps stacking, modal policy, focus scopes,
/// Escape, dismissal, source environments, and lifecycle; a style resolves
/// chrome only.
public protocol SheetStyle: Sendable {
  var snapshotLabel: String { get }

  @MainActor
  func resolvePresentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation
}

extension SheetStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

private protocol AnySheetStyleBox: Sendable {
  var snapshotLabel: String { get }

  @MainActor
  func presentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation
  func isEqualForReuse(to other: any AnySheetStyleBox) -> Bool
}

private struct ConcreteSheetStyleBox<S: SheetStyle>: AnySheetStyleBox {
  let style: S

  var snapshotLabel: String {
    style.snapshotLabel
  }

  @MainActor
  func presentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation {
    style.resolvePresentation(for: configuration)
  }

  func isEqualForReuse(to other: any AnySheetStyleBox) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return styleValuesAreEqualForReuse(style, other.style)
  }
}

/// A type-erased sheet style.
public struct AnySheetStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnySheetStyleBox

  public init<S: SheetStyle>(
    _ style: S
  ) {
    box = ConcreteSheetStyleBox(style: style)
  }

  /// A documented *fixed* alias of ``surface``.
  public static var automatic: Self {
    Self(SurfaceSheetStyle())
  }

  public static var surface: Self {
    Self(SurfaceSheetStyle())
  }

  public static var dropdown: Self {
    Self(DropdownSheetStyle())
  }

  public var description: String {
    box.snapshotLabel
  }

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
public struct SurfaceSheetStyle: SheetStyle, Sendable {
  public init() {}

  public var snapshotLabel: String { "SheetStyle.surface" }

  @MainActor
  public func resolvePresentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation {
    configuration.defaultPresentation
  }
}

/// Flat, edge-to-edge chrome flush against the window's top edge.
public struct DropdownSheetStyle: SheetStyle, Sendable {
  public init() {}

  public var snapshotLabel: String { "SheetStyle.dropdown" }

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
  public static var surface: SurfaceSheetStyle { .init() }
}

extension SheetStyle where Self == DropdownSheetStyle {
  public static var dropdown: DropdownSheetStyle { .init() }
}

extension SurfaceSheetStyle: ReuseTransparentStyle {}
extension DropdownSheetStyle: ReuseTransparentStyle {}

extension PromptPresentationDescriptor {
  /// The declaring modifier's own constants, expressed as a style baseline.
  package var sheetStyleBaseline: SheetSurfaceStylePresentation {
    SheetSurfaceStylePresentation(
      container: chrome == .dropdown ? .dropdown : .standard,
      backdropOpacity: backdropOpacity,
      headerTone: headerTone,
      minimumWidth: minWidth,
      maximumWidth: maxWidth,
      scrollMinimumHeight: scrollMinHeight,
      scrollIdealHeight: scrollIdealHeight,
      scrollMaximumHeight: scrollMaxHeight,
      borderStroke: borderStyle
    )
  }

  /// Folds a resolved sheet presentation back into the descriptor the
  /// portal coordinator consumes. Alignment follows the container, since a
  /// dropdown lands flush at the top edge — that is modifier-owned
  /// semantics rather than a style value.
  package func applyingSheetStyle(
    _ presentation: SheetSurfaceStylePresentation
  ) -> Self {
    var descriptor = self
    descriptor.chrome = presentation.container == .dropdown ? .dropdown : .surface
    descriptor.alignment = presentation.container == .dropdown ? .topLeading : .center
    descriptor.backdropOpacity = presentation.backdropOpacity
    descriptor.headerTone = presentation.headerTone
    descriptor.minWidth = presentation.minimumWidth
    descriptor.maxWidth = presentation.maximumWidth
    descriptor.scrollMinHeight = presentation.scrollMinimumHeight
    descriptor.scrollIdealHeight = presentation.scrollIdealHeight
    descriptor.scrollMaxHeight = presentation.scrollMaximumHeight
    descriptor.borderStyle = presentation.borderStroke
    return descriptor
  }
}

extension ResolveContext {
  /// Resolves the nearest sheet style against a declaration's baseline.
  @MainActor
  package func resolvedSheetDescriptor(
    baseline descriptor: PromptPresentationDescriptor
  ) -> PromptPresentationDescriptor {
    let resolved = environmentValues.sheetStyle.presentation(
      for: SheetStyleConfiguration(
        defaultPresentation: descriptor.sheetStyleBaseline,
        terminalSize: environmentValues.terminalSize,
        controlProminence: environmentValues.controlProminence,
        styleEnvironment: environmentValues.styleEnvironmentSnapshot
      )
    )
    return descriptor.applyingSheetStyle(resolved)
  }
}
