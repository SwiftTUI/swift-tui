public import SwiftTUICore

/// The state a popover style resolves against.
///
/// `defaultPresentation` is the popover family's baseline, so a style
/// transforms it rather than restating it, and `.automatic` returns it
/// unchanged. The remaining members are read-only render state captured from
/// the declaring modifier's environment; nothing here is a binding or an
/// authored view, because the popover's content stays with the declaration.
public struct PopoverStyleConfiguration: Sendable {
  /// The chrome a popover declaration renders without a style: the defaults of
  /// ``AnchoredSurfaceStylePresentation`` with the rounded border stroke the
  /// popover family uses instead of the menu's half-block frame. Return it
  /// unchanged to keep the framework look, or copy and adjust it.
  public var defaultPresentation: AnchoredSurfaceStylePresentation
  /// The terminal's size in cells when the surface resolved, for capping the
  /// popover relative to the terminal rather than to a fixed width.
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

/// Defines the chrome an anchored popover renders.
///
/// A popover style is a presentation-value style:
/// ``PopoverStyle/resolvePresentation(for:)`` returns an
/// ``AnchoredSurfaceStylePresentation``, the same value type a menu's popup
/// resolves. The popover baseline differs from that type's own defaults in one
/// field: it keeps the rounded border stroke where the type defaults to the
/// menu's outset half-block frame. Transform
/// ``PopoverStyleConfiguration/defaultPresentation`` rather than building a
/// value from scratch, or the popover picks up menu chrome.
///
/// The portal coordinator keeps the anchor and its placement search, stacking,
/// focus scopes, Escape, dismissal, source environments, and lifecycle. A
/// popover always disables interaction with the content beneath it, and a style
/// cannot change that policy; the authored content belongs to the declaration.
///
/// The declaring modifier reads the style from the environment while the
/// popover is closed, so a change made then applies on the next opening, but it
/// calls and validates the style only when the surface presents. An invalid
/// value reports one `style.invalidPresentation` runtime issue and the baseline
/// renders for that resolve; a closed declaration reports nothing.
///
/// The only built-in, ``AnyPopoverStyle/automatic``, returns the baseline
/// unchanged. Apply one with `popoverStyle(_:)`; the nearest modifier wins for
/// every popover declaration in the subtree, including item popovers and
/// `popoverTip(...)`. Conform with a `Sendable` struct or enum.
///
/// ```swift
/// struct CappedPopoverStyle: PopoverStyle {
///   func resolvePresentation(
///     for configuration: PopoverStyleConfiguration
///   ) -> AnchoredSurfaceStylePresentation {
///     var presentation = configuration.defaultPresentation
///     presentation.maximumWidth = 40
///     presentation.maximumHeight = 6
///     return presentation
///   }
/// }
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol PopoverStyle: Sendable {
  /// The label reported in snapshots and diagnostics. Defaults to the reflected
  /// type name; the built-in pins `"PopoverStyle.automatic"`. It is diagnostic
  /// text, not identity.
  var snapshotLabel: String { get }

  /// Resolves the chrome the presented popover renders.
  ///
  /// Called on the main actor each time the presenting declaration resolves
  /// while the popover is presented, never while it is closed. Start from
  /// ``PopoverStyleConfiguration/defaultPresentation`` so fields the style does
  /// not touch keep the popover baseline, the rounded border included.
  ///
  /// - Parameter configuration: The popover baseline and render state.
  /// - Returns: The chrome for this resolve; an invalid value falls back to the
  ///   baseline after reporting.
  @MainActor
  func resolvePresentation(
    for configuration: PopoverStyleConfiguration
  ) -> AnchoredSurfaceStylePresentation
}

extension PopoverStyle {
  /// The reflected type name, used when a conformance does not pin a label.
  public var snapshotLabel: String { String(reflecting: Self.self) }
}

private protocol AnyPopoverStyleBox: AnyStyleBox {
  var snapshotLabel: String { get }
  @MainActor
  func presentation(for configuration: PopoverStyleConfiguration)
    -> AnchoredSurfaceStylePresentation
}

extension ConcreteStyleBox: AnyPopoverStyleBox where S: PopoverStyle {
  var snapshotLabel: String { style.snapshotLabel }

  @MainActor
  func presentation(for configuration: PopoverStyleConfiguration)
    -> AnchoredSurfaceStylePresentation
  {
    style.resolvePresentation(for: configuration)
  }

}

/// Type-erased storage for a popover style, the value the environment carries.
///
/// `popoverStyle(_:)` stores one of these for a subtree; a presenting popover
/// reads the nearest one. ``AnyPopoverStyle/automatic`` is the only built-in,
/// and ``AnyPopoverStyle/init(_:)`` wraps a custom conformance. The built-in
/// compares equal for retained reuse by type; a custom style compares by value
/// when it is `Equatable`.
public struct AnyPopoverStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyPopoverStyleBox

  /// Wraps `style` for storage in the environment.
  ///
  /// - Parameter style: The concrete ``PopoverStyle`` to erase.
  public init<S: PopoverStyle>(_ style: S) {
    box = ConcreteStyleBox(style: style)
  }

  /// The framework popover chrome: the popover baseline returned unchanged
  /// (``AutomaticPopoverStyle``).
  public static var automatic: Self { Self(AutomaticPopoverStyle()) }
  /// The wrapped style's `snapshotLabel`.
  public var description: String { box.snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
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

/// The popover chrome a declaration renders by default: the popover baseline,
/// returned unchanged.
///
/// The result is a surface sized to its content, painted with the theme's
/// surface background inside a rounded border in the theme's accent border
/// paint, with one cell of inset around the content and no height cap.
public struct AutomaticPopoverStyle: PopoverStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics, `"PopoverStyle.automatic"`.
  public var snapshotLabel: String { "PopoverStyle.automatic" }

  /// Returns ``PopoverStyleConfiguration/defaultPresentation`` unchanged.
  @MainActor
  public func resolvePresentation(
    for configuration: PopoverStyleConfiguration
  ) -> AnchoredSurfaceStylePresentation {
    configuration.defaultPresentation
  }
}

extension PopoverStyle where Self == AutomaticPopoverStyle {
  /// The popover baseline, unchanged; see ``AutomaticPopoverStyle``.
  public static var automatic: AutomaticPopoverStyle { .init() }
}

extension AutomaticPopoverStyle: ReuseTransparentStyle {}
