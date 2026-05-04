public import SwiftTUICore

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
    package let payload: DeferredViewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = DeferredViewPayload(
        authoringContext: authoringContext,
        content: content
      )
    }

    public var body: some View {
      DeferredPayloadView(payload: payload)
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
    normalizeResolvedElements(
      resolveViewElements(
        style.makeBody(configuration: configuration),
        in: context
      ),
      in: context
    )
  }
}

private enum BuiltInButtonStyleKind {
  case automatic
  case plain
  case bordered
  case borderedProminent
  case link
}

@MainActor
package func resolvedLinkButtonChrome(
  styleEnvironment: StyleEnvironmentSnapshot,
  isEnabled: Bool,
  isFocused: Bool,
  showsFocusEffect: Bool,
  isPressed: Bool,
  role: ButtonRole? = nil
) -> ControlChrome {
  resolvedBuiltInButtonChrome(
    kind: .link,
    styleEnvironment: styleEnvironment,
    isEnabled: isEnabled,
    isFocused: isFocused,
    showsFocusEffect: showsFocusEffect,
    isPressed: isPressed,
    controlProminence: .standard,
    role: role
  )
}

@MainActor
private func resolvedBuiltInButtonChrome(
  kind: BuiltInButtonStyleKind,
  configuration: ButtonStyleConfiguration
) -> ControlChrome {
  resolvedBuiltInButtonChrome(
    kind: kind,
    styleEnvironment: configuration.styleEnvironment,
    isEnabled: configuration.isEnabled,
    isFocused: configuration.isFocused,
    showsFocusEffect: configuration.showsFocusEffect,
    isPressed: configuration.isPressed,
    controlProminence: configuration.controlProminence,
    role: configuration.role
  )
}

@MainActor
private func resolvedBuiltInButtonChrome(
  kind: BuiltInButtonStyleKind,
  styleEnvironment: StyleEnvironmentSnapshot,
  isEnabled: Bool,
  isFocused: Bool,
  showsFocusEffect: Bool,
  isPressed: Bool,
  controlProminence: ControlProminence,
  role: ButtonRole?
) -> ControlChrome {
  switch kind {
  case .plain:
    return resolvedPlainButtonChrome(
      styleEnvironment: styleEnvironment,
      isEnabled: isEnabled,
      role: role
    )
  case .link:
    return resolvedLinkChrome(
      styleEnvironment: styleEnvironment,
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed,
      role: role
    )
  case .bordered:
    return styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed,
      isSelected: false,
      prominence: .standard,
      role: role
    )
  case .automatic, .borderedProminent:
    return styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed,
      isSelected: false,
      prominence: .increased,
      role: role
    )
  }
}

@MainActor
private func resolvedPlainButtonChrome(
  styleEnvironment: StyleEnvironmentSnapshot,
  isEnabled: Bool,
  role: ButtonRole?
) -> ControlChrome {
  guard isEnabled else {
    let background = styleEnvironment.themeStyle(for: .background)
    return .init(
      foregroundStyle: styleEnvironment.themeStyle(for: .placeholder),
      contentBackgroundStyle: background,
      borderForegroundStyle: background,
      opacity: 0.6
    )
  }

  let background = styleEnvironment.themeStyle(for: .background)
  return .init(
    foregroundStyle: plainForegroundStyle(
      styleEnvironment: styleEnvironment,
      role: role
    ),
    contentBackgroundStyle: background,
    borderForegroundStyle: background
  )
}

@MainActor
private func resolvedLinkChrome(
  styleEnvironment: StyleEnvironmentSnapshot,
  isEnabled: Bool,
  isFocused: Bool,
  isPressed: Bool,
  role: ButtonRole?
) -> ControlChrome {
  guard isEnabled else {
    let background = styleEnvironment.themeStyle(for: .background)
    return .init(
      foregroundStyle: styleEnvironment.themeStyle(for: .placeholder),
      contentBackgroundStyle: background,
      borderForegroundStyle: background,
      opacity: 0.6
    )
  }

  let tone = chromeTone(for: role)
  let background =
    if isFocused || isPressed {
      AnyShapeStyle(.terminalRow(tone, isSelected: true))
    } else {
      styleEnvironment.themeStyle(for: .background)
    }

  return .init(
    foregroundStyle: linkForegroundStyle(
      styleEnvironment: styleEnvironment,
      role: role
    ),
    contentBackgroundStyle: background,
    borderForegroundStyle: styleEnvironment.themeStyle(for: .background)
  )
}

@MainActor
private func plainForegroundStyle(
  styleEnvironment: StyleEnvironmentSnapshot,
  role: ButtonRole?
) -> AnyShapeStyle {
  switch role {
  case .destructive:
    styleEnvironment.themeStyle(for: .danger)
  case .cancel, .close:
    styleEnvironment.themeStyle(for: .muted)
  case .confirm:
    styleEnvironment.resolvedStyle(for: .tint)
  case nil:
    styleEnvironment.resolvedStyle(for: .foreground)
  }
}

@MainActor
private func linkForegroundStyle(
  styleEnvironment: StyleEnvironmentSnapshot,
  role: ButtonRole?
) -> AnyShapeStyle {
  switch role {
  case .destructive:
    styleEnvironment.themeStyle(for: .danger)
  case .cancel, .close:
    styleEnvironment.themeStyle(for: .muted)
  case .confirm:
    styleEnvironment.resolvedStyle(for: .tint)
  case nil:
    styleEnvironment.themeStyle(for: .link)
  }
}

private func chromeTone(
  for role: ButtonRole?
) -> TerminalTone {
  switch role {
  case .destructive:
    .danger
  case .cancel, .close:
    .neutral
  case .confirm, nil:
    .accent
  }
}

package struct ButtonPlainStyleBody<Label: View>: View {
  let label: Label
  let chrome: ControlChrome
  let focusActive: Bool
  let reservesRailGutter: Bool

  package init(
    label: Label,
    chrome: ControlChrome,
    focusActive: Bool,
    reservesRailGutter: Bool = true
  ) {
    self.label = label
    self.chrome = chrome
    self.focusActive = focusActive
    self.reservesRailGutter = reservesRailGutter
  }

  @MainActor
  package var body: some View {
    // The focus rail is the leading cell of an HStack with the rail
    // gutter permanently reserved (`reservesRailSpaceWhenHidden`). Two
    // requirements ride together on this choice:
    //
    //  1. Stable bounds across focus transitions. If the rail were a
    //     sibling that appeared only on focus, the button's bounds
    //     would grow by one cell the moment focus arrived, shifting
    //     layout out from under a pressed pointer and making
    //     mouseDown-followed-by-mouseUp miss the armed route so the
    //     action never dispatches. Reserving the gutter even when the
    //     rail is hidden keeps the row width constant.
    //
    //  2. No content overdraw. The previous implementation painted
    //     the rail glyph as a leading-aligned overlay, which collided
    //     with column 0 of the label — wiping the entire icon for a
    //     single-cell label and erasing the first character of any
    //     wider label (e.g. "File" → "ile"). An HStack sibling cannot
    //     overlap the label by construction.
    //
    // The bordered/automatic chrome wrapper opts out of the gutter
    // (`reservesRailGutter: false`) because that wrapper signals focus
    // via a heavy border drawn inside its own horizontal padding; a
    // second leading gutter would just widen every bordered button
    // for no visual gain.
    controlFocusRow(
      showsRail: focusActive,
      railStyle: chrome.borderStyle,
      isHighlighted: focusActive,
      backgroundStyle: chrome.backgroundStyle,
      reservesRailSpaceWhenHidden: reservesRailGutter,
      spacing: 0
    ) {
      label
    }
    .foregroundStyle(chrome.foregroundStyle)
    .drawMetadata(.init(opacity: chrome.opacity))
  }
}

package struct ButtonLinkStyleBody<Label: View>: View {
  let label: Label
  let chrome: ControlChrome
  let focusActive: Bool

  @MainActor
  package var body: some View {
    ButtonPlainStyleBody(
      label: label.underline(),
      chrome: chrome,
      focusActive: focusActive
    )
    .background {
      Rectangle().fill(chrome.backgroundStyle)
    }
  }
}

package struct ButtonChromeStyleBody<Label: View>: View {
  let label: Label
  let chrome: ControlChrome
  let controlProminence: ControlProminence
  let buttonBorderShape: ButtonBorderShape
  let usesDenseBorderlessChrome: Bool
  let verticalPadding: Int
  let needsMinimumHeight: Bool
  let focusActive: Bool

  @MainActor
  package var body: some View {
    let styledLabel =
      ButtonPlainStyleBody(
        label: label,
        chrome: chrome,
        focusActive: false,
        reservesRailGutter: false
      )
      .padding(
        .init(
          horizontal: 1,
          vertical: verticalPadding
        )
      )
      .background {
        ButtonStyleChromeBackground(
          chrome: chrome,
          usesDenseBorderlessChrome: usesDenseBorderlessChrome,
          prominence: controlProminence,
          borderShape: buttonBorderShape
        )
      }
      .overlay {
        if !usesDenseBorderlessChrome {
          ButtonStyleChromeBorder(
            chrome: chrome,
            prominence: controlProminence,
            borderShape: buttonBorderShape,
            focusActive: focusActive
          )
        }
      }

    if needsMinimumHeight {
      styledLabel.layoutMetadata(.init(minimumHeight: 3))
    } else {
      styledLabel
    }
  }
}

private struct ButtonStyleChromeBackground: View {
  let chrome: ControlChrome
  let usesDenseBorderlessChrome: Bool
  let prominence: ControlProminence
  let borderShape: ButtonBorderShape

  @ViewBuilder
  var body: some View {
    switch (borderShape, prominence) {
    case (.roundedRectangle, _), (.automatic, .increased):
      if usesDenseBorderlessChrome {
        RoundedRectangle(cornerRadius: 1).fill(chrome.backgroundStyle)
      } else {
        RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(chrome.backgroundStyle)
      }
    default:
      if usesDenseBorderlessChrome {
        Rectangle().fill(chrome.backgroundStyle)
      } else {
        Rectangle().inset(by: 1).fill(chrome.backgroundStyle)
      }
    }
  }
}

private struct ButtonStyleChromeBorder: View {
  let chrome: ControlChrome
  let prominence: ControlProminence
  let borderShape: ButtonBorderShape
  let focusActive: Bool

  @ViewBuilder
  var body: some View {
    let strokeStyle: StrokeStyle = focusActive ? .heavy : .init()
    switch (borderShape, prominence) {
    case (.roundedRectangle, _), (.automatic, .increased):
      RoundedRectangle(cornerRadius: 1).strokeBorder(
        chrome.borderStyle,
        style: strokeStyle,
        background: chrome.borderBackgroundStyle
      )
    default:
      Rectangle().strokeBorder(
        chrome.borderStyle,
        style: strokeStyle,
        background: chrome.borderBackgroundStyle
      )
    }
  }
}
