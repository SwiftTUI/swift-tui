import SwiftTUIViews

// This file is also typechecked outside the package, without @testable or SPI.
struct ConsumerToggleStyle: ToggleStyle {
  var prefix = ""
  func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    HStack(alignment: .center, spacing: 1) {
      Text(configuration.focusActive ? "▌" : " ")
        .foregroundStyle(
          configuration.focusActive ? chrome.borderStyle : AnyShapeStyle(.background))
      Text(configuration.isMixed ? "◐" : configuration.isOn ? "◉" : "○")
        .foregroundStyle(configuration.isOn ? chrome.borderStyle : AnyShapeStyle(.separator))
      if !prefix.isEmpty { Text(prefix) }
      configuration.label
    }
    .foregroundStyle(chrome.foregroundStyle)
    .background {
      if configuration.focusActive || configuration.isPressed {
        Rectangle().fill(chrome.backgroundStyle)
      }
    }
    .opacity(chrome.opacity)
  }
}

struct ConsumerDisclosureGroupStyle: DisclosureGroupStyle {
  var prefix = ""
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    let chrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 1) {
        Text(configuration.focusActive ? "▌" : " ")
          .foregroundStyle(
            configuration.focusActive ? chrome.borderStyle : AnyShapeStyle(.background))
        Text(configuration.isExpanded ? "▾" : "▸")
          .foregroundStyle(
            configuration.isExpanded ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator))
        if !prefix.isEmpty { Text(prefix) }
        configuration.label
      }
      .foregroundStyle(chrome.foregroundStyle)
      .background {
        if configuration.focusActive || configuration.isPressed {
          Rectangle().fill(chrome.backgroundStyle)
        }
      }
      .opacity(chrome.opacity)
      if configuration.isExpanded {
        configuration.content.padding(.init(leading: 1))
      }
    }
  }
}

struct ConsumerTextEditorStyle: TextEditorStyle {
  var prefix = ""
  func makeBody(configuration: TextEditorStyleConfiguration) -> some View {
    let content = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: false)
    let focus = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive)
    VStack(alignment: .leading, spacing: 0) {
      if !prefix.isEmpty { Text(prefix) }
      configuration.editorContent
    }
    .padding(.init(horizontal: 1, vertical: 1))
    .background {
      RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(content.backgroundStyle)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 1).strokeBorder(
        focus.borderStyle, style: configuration.focusActive ? .heavy : .init())
    }
    .frame(minHeight: .finite(3), alignment: .topLeading)
  }
}

struct ConsumerProgressViewStyle: ProgressViewStyle {
  var prefix = ""
  func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if !prefix.isEmpty { Text(prefix) }
      HStack(alignment: .center, spacing: 1) {
        if let label = configuration.label { label.foregroundStyle(.terminalBorder(.accent)) }
        if let value = configuration.currentValueLabel {
          Spacer()
          value.foregroundStyle(.separator)
        }
      }
      if !configuration.accessibilityReduceMotion {
        let width = max(1, configuration.barWidth)
        let band = max(1, width / 3 + (width % 3 == 0 ? 0 : 1))
        let offset = Int(configuration.indeterminatePhase % UInt64(max(1, width - band + 1)))
        if let fraction = configuration.fractionCompleted {
          let value = fraction.isFinite ? min(max(fraction, 0), 1) : 0
          let filled = min(width, max(0, Int((value * Double(width)).rounded())))
          HStack(spacing: 0) {
            Text(String(repeating: "█", count: filled)).foregroundStyle(.tint)
            Text(String(repeating: "─", count: width - filled)).foregroundStyle(.separator)
          }
        } else {
          HStack(spacing: 0) {
            Text(String(repeating: "─", count: offset)).foregroundStyle(.separator)
            Text(String(repeating: "█", count: band)).foregroundStyle(.tint)
            Text(String(repeating: "─", count: width - offset - band)).foregroundStyle(.separator)
          }
        }
      }
    }
  }
}

struct PaddedConsumerEditorStyle: TextEditorStyle {
  func makeBody(configuration: TextEditorStyleConfiguration) -> some View {
    configuration.editorContent.padding(.init(horizontal: 2))
  }
}
