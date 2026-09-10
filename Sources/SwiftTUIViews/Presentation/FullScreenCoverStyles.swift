public import SwiftTUICore

/// The state a full-screen cover style resolves against.
///
/// `defaultPresentation` is the declaring modifier's own baseline, so a style
/// transforms the declaration's constants rather than restating them, and
/// `.automatic` returns it unchanged. The remaining members are read-only
/// render state captured from the declaring modifier's environment; nothing
/// here is a binding or an authored view, because the cover's content stays
/// with the declaration.
public struct FullScreenCoverStyleConfiguration: Sendable {
  /// The chrome the `fullScreenCover(...)` declaration renders without a
  /// style: the defaults of ``FullScreenSurfaceStylePresentation``, which are
  /// no insets and the theme's surface background. Return it unchanged to keep
  /// the framework look, or copy and adjust it.
  public var defaultPresentation: FullScreenSurfaceStylePresentation
  /// The terminal's size in cells when the surface resolved, which for a cover
  /// is also the surface's own size before insets.
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

/// Defines the chrome a full-screen cover renders.
///
/// A cover style is a presentation-value style:
/// ``FullScreenCoverStyle/resolvePresentation(for:)`` returns a
/// ``FullScreenSurfaceStylePresentation`` rather than a view body. A cover
/// always fills the terminal and draws no framework header, close button, or
/// border, so the value it resolves carries only content insets and a
/// background paint: there is no other chrome for a style to change.
///
/// The portal coordinator keeps stacking, modal policy, focus scopes, Escape,
/// dismissal, source environments, and lifecycle. The authored content, and any
/// chrome drawn inside it, belongs to the declaration.
///
/// The declaring modifier reads the style from the environment while the cover
/// is closed, so a change made then applies on the next opening, but it calls
/// and validates the style only when the surface presents. A negative or
/// unrepresentable inset reports one `style.invalidPresentation` runtime issue
/// and the baseline renders for that resolve; a closed declaration reports
/// nothing.
///
/// The only built-in, ``AnyFullScreenCoverStyle/automatic``, returns the
/// baseline unchanged. Apply one with `fullScreenCoverStyle(_:)`; the nearest
/// modifier wins. Conform with a `Sendable` struct or enum.
///
/// ```swift
/// struct FramedCoverStyle: FullScreenCoverStyle {
///   func resolvePresentation(
///     for configuration: FullScreenCoverStyleConfiguration
///   ) -> FullScreenSurfaceStylePresentation {
///     var presentation = configuration.defaultPresentation
///     presentation.contentInsets = .init(all: 2)
///     return presentation
///   }
/// }
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol FullScreenCoverStyle: Sendable {
  /// The label reported in snapshots and diagnostics. Defaults to the reflected
  /// type name; the built-in pins `"FullScreenCoverStyle.automatic"`. It is
  /// diagnostic text, not identity.
  var snapshotLabel: String { get }

  /// Resolves the insets and background the presented cover renders.
  ///
  /// Called on the main actor each time the presenting declaration resolves
  /// while the cover is presented, never while it is closed. Start from
  /// ``FullScreenCoverStyleConfiguration/defaultPresentation`` so fields the
  /// style does not touch keep the declaration's constants.
  ///
  /// - Parameter configuration: The declaration's baseline and render state.
  /// - Returns: The chrome for this resolve; an invalid value falls back to the
  ///   baseline after reporting.
  @MainActor
  func resolvePresentation(
    for configuration: FullScreenCoverStyleConfiguration
  ) -> FullScreenSurfaceStylePresentation
}

extension FullScreenCoverStyle {
  /// The reflected type name, used when a conformance does not pin a label.
  public var snapshotLabel: String { String(reflecting: Self.self) }
}

private protocol AnyFullScreenCoverStyleBox: AnyStyleBox {
  var snapshotLabel: String { get }
  @MainActor
  func presentation(for configuration: FullScreenCoverStyleConfiguration)
    -> FullScreenSurfaceStylePresentation
}

extension ConcreteStyleBox: AnyFullScreenCoverStyleBox where S: FullScreenCoverStyle {
  var snapshotLabel: String { style.snapshotLabel }

  @MainActor
  func presentation(for configuration: FullScreenCoverStyleConfiguration)
    -> FullScreenSurfaceStylePresentation
  {
    style.resolvePresentation(for: configuration)
  }

}

/// Type-erased storage for a full-screen cover style, the value the environment
/// carries.
///
/// `fullScreenCoverStyle(_:)` stores one of these for a subtree; a presenting
/// cover reads the nearest one. ``AnyFullScreenCoverStyle/automatic`` is the
/// only built-in, and ``AnyFullScreenCoverStyle/init(_:)`` wraps a custom
/// conformance. The built-in compares equal for retained reuse by type; a
/// custom style compares by value when it is `Equatable`.
public struct AnyFullScreenCoverStyle: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  private let box: any AnyFullScreenCoverStyleBox

  /// Wraps `style` for storage in the environment.
  ///
  /// - Parameter style: The concrete ``FullScreenCoverStyle`` to erase.
  public init<S: FullScreenCoverStyle>(_ style: S) {
    box = ConcreteStyleBox(style: style)
  }

  /// The framework cover chrome: the declaration's own baseline returned
  /// unchanged (``AutomaticFullScreenCoverStyle``).
  public static var automatic: Self { Self(AutomaticFullScreenCoverStyle()) }
  /// The wrapped style's `snapshotLabel`.
  public var description: String { box.snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
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

/// The cover chrome a declaration renders by default: the modifier's own
/// baseline, returned unchanged.
///
/// With the framework baseline the result is a surface filling the terminal,
/// painted with the theme's surface background and with no insets, so the
/// authored content starts at the terminal's own edges.
public struct AutomaticFullScreenCoverStyle: FullScreenCoverStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics,
  /// `"FullScreenCoverStyle.automatic"`.
  public var snapshotLabel: String { "FullScreenCoverStyle.automatic" }

  /// Returns ``FullScreenCoverStyleConfiguration/defaultPresentation``
  /// unchanged.
  @MainActor
  public func resolvePresentation(
    for configuration: FullScreenCoverStyleConfiguration
  ) -> FullScreenSurfaceStylePresentation {
    configuration.defaultPresentation
  }
}

extension FullScreenCoverStyle where Self == AutomaticFullScreenCoverStyle {
  /// The declaration's own baseline, unchanged; see
  /// ``AutomaticFullScreenCoverStyle``.
  public static var automatic: AutomaticFullScreenCoverStyle { .init() }
}

extension AutomaticFullScreenCoverStyle: ReuseTransparentStyle {}
