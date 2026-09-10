public import SwiftTUICore

/// The state an alert or confirmation-dialog style resolves against.
///
/// `defaultPresentation` is the declaring modifier's own baseline, so a style
/// transforms the declaration's constants rather than restating them; the two
/// declarations do not share one baseline, and `.automatic` returns whichever
/// it is handed unchanged. `hasMessage` and `hasActions` report what the
/// declaration holds without exposing it: the title, the message, the action
/// buttons, the order they render in, and the surface's alignment all stay
/// with the declaration. The remaining members are read-only render state
/// captured from the declaring modifier's environment; nothing here is a
/// binding or an authored view.
public struct PromptStyleConfiguration: Sendable {
  /// Whether the declaration supplied message content, which lets a style give
  /// a prompt with prose a taller viewport than a bare one. Opaque view bodies
  /// count as present.
  public var hasMessage: Bool
  /// Whether the declaration supplied action content. Empty builders do not
  /// count, so a prompt whose actions are all conditioned away reports `false`.
  public var hasActions: Bool
  /// The chrome this declaration renders without a style. The two prompt
  /// declarations differ: an alert starts from the defaults of
  /// ``PromptSurfaceStylePresentation``, and a confirmation dialog starts from
  /// an accent header tone, a minimum width of 20 cells, no maximum width, and
  /// scroll heights of 3, 4, and 6 cells. Return it unchanged to keep the
  /// framework look, or copy and adjust it.
  public var defaultPresentation: PromptSurfaceStylePresentation
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

/// Defines the chrome an alert or a confirmation dialog renders.
///
/// A prompt style is a presentation-value style:
/// ``PromptStyle/resolvePresentation(for:)`` returns a
/// ``PromptSurfaceStylePresentation`` rather than a view body. One style serves
/// both surfaces, so the same conformance applies to every `alert(...)` and
/// every `confirmationDialog(...)` in the subtree; the
/// ``PromptStyleConfiguration`` hands it that declaration's own baseline plus
/// ``PromptStyleConfiguration/hasMessage``,
/// ``PromptStyleConfiguration/hasActions``, the terminal size, the control
/// prominence, and the style environment.
///
/// The portal coordinator keeps stacking, modal policy, focus scopes, Escape,
/// dismissal, source environments, and lifecycle. The surface's alignment (an
/// alert centers, a confirmation dialog sits at the bottom leading corner), its
/// accessibility role, the authored title, message, and actions, and the order
/// the actions render in belong to the declaration; a style resolves chrome
/// only.
///
/// The declaring modifier reads the style from the environment while the prompt
/// is closed, so a change made then applies on the next opening, but it calls
/// and validates the style only when the surface presents. An invalid value
/// reports one `style.invalidPresentation` runtime issue and the baseline
/// renders for that resolve; a closed declaration reports nothing.
///
/// The only built-in, ``AnyPromptStyle/automatic``, returns the baseline
/// unchanged. Apply one with `promptStyle(_:)`; the nearest modifier wins.
/// Conform with a `Sendable` struct or enum.
///
/// ```swift
/// struct CompactPromptStyle: PromptStyle {
///   func resolvePresentation(
///     for configuration: PromptStyleConfiguration
///   ) -> PromptSurfaceStylePresentation {
///     var presentation = configuration.defaultPresentation
///     presentation.maximumWidth = 32
///     presentation.scrollMinimumHeight = 1
///     presentation.scrollIdealHeight = configuration.hasMessage ? 4 : 1
///     return presentation
///   }
/// }
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol PromptStyle: Sendable {
  /// The label reported in snapshots and diagnostics. Defaults to the reflected
  /// type name; the built-in pins `"PromptStyle.automatic"`. It is diagnostic
  /// text, not identity.
  var snapshotLabel: String { get }

  /// Resolves the chrome the presented alert or confirmation dialog renders.
  ///
  /// Called on the main actor each time the presenting declaration resolves
  /// while the prompt is presented, never while it is closed. Start from
  /// ``PromptStyleConfiguration/defaultPresentation`` so fields the style does
  /// not touch keep the declaration's constants, which differ between the two
  /// surfaces.
  ///
  /// - Parameter configuration: The declaration's baseline, what it declared,
  ///   and the render state.
  /// - Returns: The chrome for this resolve; an invalid value falls back to the
  ///   baseline after reporting.
  @MainActor
  func resolvePresentation(
    for configuration: PromptStyleConfiguration
  ) -> PromptSurfaceStylePresentation
}

extension PromptStyle {
  /// The reflected type name, used when a conformance does not pin a label.
  public var snapshotLabel: String { String(reflecting: Self.self) }
}

private protocol AnyPromptStyleBox: AnyStyleBox {
  var snapshotLabel: String { get }
  @MainActor
  func presentation(for configuration: PromptStyleConfiguration) -> PromptSurfaceStylePresentation
}

extension ConcreteStyleBox: AnyPromptStyleBox where S: PromptStyle {
  var snapshotLabel: String { style.snapshotLabel }

  @MainActor
  func presentation(for configuration: PromptStyleConfiguration) -> PromptSurfaceStylePresentation {
    style.resolvePresentation(for: configuration)
  }

}

/// Type-erased storage for a prompt style, the value the environment carries.
///
/// `promptStyle(_:)` stores one of these for a subtree; a presenting alert or
/// confirmation dialog reads the nearest one. ``AnyPromptStyle/automatic`` is
/// the only built-in, and ``AnyPromptStyle/init(_:)`` wraps a custom
/// conformance. The built-in compares equal for retained reuse by type; a
/// custom style compares by value when it is `Equatable`.
public struct AnyPromptStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyPromptStyleBox

  /// Wraps `style` for storage in the environment.
  ///
  /// - Parameter style: The concrete ``PromptStyle`` to erase.
  public init<S: PromptStyle>(_ style: S) {
    box = ConcreteStyleBox(style: style)
  }

  /// The framework prompt chrome: the declaration's own baseline returned
  /// unchanged (``AutomaticPromptStyle``).
  public static var automatic: Self { Self(AutomaticPromptStyle()) }
  /// The wrapped style's `snapshotLabel`.
  public var description: String { box.snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
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

/// The prompt chrome a declaration renders by default: the modifier's own
/// baseline, returned unchanged.
///
/// An alert therefore renders centered on a neutral header tone, between 24 and
/// 48 cells wide, with a scrolling content viewport, one cell of inset, a
/// single-line border, and no backdrop dim; a confirmation dialog renders the
/// same chrome with its own narrower, accent-headed baseline at the bottom
/// leading corner. Both paints follow the theme.
public struct AutomaticPromptStyle: PromptStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics, `"PromptStyle.automatic"`.
  public var snapshotLabel: String { "PromptStyle.automatic" }

  /// Returns ``PromptStyleConfiguration/defaultPresentation`` unchanged.
  @MainActor
  public func resolvePresentation(
    for configuration: PromptStyleConfiguration
  ) -> PromptSurfaceStylePresentation {
    configuration.defaultPresentation
  }
}

extension PromptStyle where Self == AutomaticPromptStyle {
  /// The declaration's own baseline, unchanged; see ``AutomaticPromptStyle``.
  public static var automatic: AutomaticPromptStyle { .init() }
}

extension AutomaticPromptStyle: ReuseTransparentStyle {}
