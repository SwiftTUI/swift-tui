public import SwiftTUICore

/// Defines the visual body and interaction prominence for a button.
public protocol ButtonStyle: Sendable {
  associatedtype Body: View

  var snapshotLabel: String { get }

  @MainActor
  func resolvedProminence(
    base: ControlProminence
  ) -> ControlProminence

  @ViewBuilder @MainActor
  func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> Body
}

extension ButtonStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }

  @MainActor
  public func resolvedProminence(
    base: ControlProminence
  ) -> ControlProminence {
    base
  }
}

public struct ButtonStyleConfiguration: Sendable {
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(
        authoringContext: authoringContext,
        content: content
      )
    }

    public var body: some View {
      CapturedSubviewView(payload: payload)
    }
  }

  public var label: Label
  public var role: ButtonRole?
  public var isEnabled: Bool
  public var isFocused: Bool
  public var showsFocusEffect: Bool
  public var isPressed: Bool
  public var controlProminence: ControlProminence
  public var buttonBorderShape: ButtonBorderShape
  public var styleEnvironment: StyleEnvironmentSnapshot

  public var focusActive: Bool {
    isFocused && showsFocusEffect
  }

  package init(
    label: Label,
    role: ButtonRole?,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    isPressed: Bool,
    controlProminence: ControlProminence,
    buttonBorderShape: ButtonBorderShape,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.role = role
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.isPressed = isPressed
    self.controlProminence = controlProminence
    self.buttonBorderShape = buttonBorderShape
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a concrete button style.
public struct AnyButtonStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyButtonStyleBox

  public init<S: ButtonStyle>(
    _ style: S
  ) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyButtonStyleBox(style: style)
  }

  public var description: String {
    snapshotLabel
  }

  public var debugDescription: String {
    snapshotLabel
  }

  public static var automatic: Self {
    Self(AutomaticButtonStyle())
  }

  public static var plain: Self {
    Self(PlainButtonStyle())
  }

  public static var bordered: Self {
    Self(BorderedButtonStyle())
  }

  public static var borderedProminent: Self {
    Self(BorderedProminentButtonStyle())
  }

  public static var link: Self {
    Self(LinkButtonStyle())
  }

  @MainActor
  package func resolvedProminence(
    base: ControlProminence
  ) -> ControlProminence {
    box.resolvedProminence(base: base)
  }

  @MainActor
  package func resolveBody(
    configuration: ButtonStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(
      configuration: configuration,
      in: context
    )
  }
}

extension AnyButtonStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The environment-driven default button style.
public struct AutomaticButtonStyle: Sendable, ButtonStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyButtonStyle.automatic"
  }

  @MainActor
  public func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> some View {
    ButtonChromeStyleBody(
      label: configuration.label,
      chrome: resolvedBuiltInButtonChrome(
        kind: .automatic,
        configuration: configuration
      ),
      controlProminence: configuration.controlProminence,
      buttonBorderShape: configuration.buttonBorderShape,
      usesDenseBorderlessChrome: true,
      verticalPadding: 0,
      needsMinimumHeight: false,
      focusActive: configuration.focusActive
    )
  }
}

/// A minimal button style without surrounding border chrome.
public struct PlainButtonStyle: Sendable, ButtonStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyButtonStyle.plain"
  }

  @MainActor
  public func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> some View {
    ButtonPlainStyleBody(
      label: configuration.label,
      chrome: resolvedBuiltInButtonChrome(
        kind: .plain,
        configuration: configuration
      ),
      focusActive: configuration.focusActive
    )
  }
}

/// A bordered button style that reserves terminal-cell chrome around the label.
public struct BorderedButtonStyle: Sendable, ButtonStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyButtonStyle.bordered"
  }

  @MainActor
  public func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> some View {
    ButtonChromeStyleBody(
      label: configuration.label,
      chrome: resolvedBuiltInButtonChrome(
        kind: .bordered,
        configuration: configuration
      ),
      controlProminence: configuration.controlProminence,
      buttonBorderShape: configuration.buttonBorderShape,
      usesDenseBorderlessChrome: false,
      verticalPadding: 1,
      needsMinimumHeight: true,
      focusActive: configuration.focusActive
    )
  }
}

/// A bordered button style with increased control prominence.
public struct BorderedProminentButtonStyle: Sendable, ButtonStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyButtonStyle.borderedProminent"
  }

  @MainActor
  public func resolvedProminence(
    base _: ControlProminence
  ) -> ControlProminence {
    .increased
  }

  @MainActor
  public func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> some View {
    ButtonChromeStyleBody(
      label: configuration.label,
      chrome: resolvedBuiltInButtonChrome(
        kind: .borderedProminent,
        configuration: configuration
      ),
      controlProminence: configuration.controlProminence,
      buttonBorderShape: configuration.buttonBorderShape,
      usesDenseBorderlessChrome: true,
      verticalPadding: 0,
      needsMinimumHeight: false,
      focusActive: configuration.focusActive
    )
  }
}

/// A link-shaped button style for navigation or external-link actions.
public struct LinkButtonStyle: Sendable, ButtonStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyButtonStyle.link"
  }

  @MainActor
  public func makeBody(
    configuration: ButtonStyleConfiguration
  ) -> some View {
    ButtonLinkStyleBody(
      label: configuration.label,
      chrome: resolvedBuiltInButtonChrome(
        kind: .link,
        configuration: configuration
      ),
      focusActive: configuration.focusActive
    )
  }
}

private protocol AnyButtonStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyButtonStyleBox) -> Bool

  @MainActor
  func resolvedProminence(
    base: ControlProminence
  ) -> ControlProminence

  @MainActor
  func resolveBody(
    configuration: ButtonStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode
}

private struct ConcreteAnyButtonStyleBox<S: ButtonStyle>: AnyButtonStyleBox {
  let style: S

  func isEqualForReuse(to other: any AnyButtonStyleBox) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    if style is AutomaticButtonStyle
      || style is PlainButtonStyle
      || style is BorderedButtonStyle
      || style is BorderedProminentButtonStyle
      || style is LinkButtonStyle
    {
      return true
    }
    return typedValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func resolvedProminence(
    base: ControlProminence
  ) -> ControlProminence {
    style.resolvedProminence(base: base)
  }

  @MainActor
  func resolveBody(
    configuration: ButtonStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    // The style body must resolve through its own view node: a value-only
    // style child forces the graph to mint a hollow, never-evaluated
    // placeholder whose chrome interiors outlive their anchors when a host
    // generation departs (the F04 teardown-coherence residual). The interior
    // must keep the ENCLOSING control's authoring scope, rebased onto the
    // style-body node — a fresh scope re-roots registration owners onto the
    // re-mintable style-body island, where input-driven @State writes degrade
    // to detached seed boxes: no dirt, no invalidation, stale retained reuse.
    resolveView(
      style.makeBody(configuration: configuration),
      in: context,
      authoringContextOverride: currentAuthoringContext()
    )
  }
}
