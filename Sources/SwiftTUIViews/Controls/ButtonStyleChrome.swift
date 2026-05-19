package import SwiftTUICore

package enum BuiltInButtonStyleKind {
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
package func resolvedBuiltInButtonChrome(
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
