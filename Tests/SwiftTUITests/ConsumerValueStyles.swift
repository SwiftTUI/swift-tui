import SwiftTUIViews

// Typechecked independently of this package; no SPI or package-only APIs.
struct ConsumerSliderStyle: SliderStyle {
  var prefix = ""
  var omitsRoutes = false
  var duplicates = false

  func makeBody(configuration: SliderStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if !prefix.isEmpty { Text(prefix) }
      configuration.label
      if omitsRoutes {
        Text("========")
      } else {
        configuration.track { Text("========") }
        if duplicates { configuration.track { Text("duplicate track") } }
      }
      configuration.valueLabel
    }
  }
}

struct ConsumerStepperStyle: StepperStyle {
  var prefix = ""
  var omitsRoutes = false
  var duplicates = false

  func makeBody(configuration: StepperStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if !prefix.isEmpty { Text(prefix) }
      configuration.label
      HStack(spacing: 1) {
        if omitsRoutes {
          Text("Less")
        } else {
          configuration.decrement { Text("Less") }
        }
        configuration.valueLabel
        if omitsRoutes {
          Text("More")
        } else {
          configuration.increment { Text("More") }
        }
      }
      if duplicates {
        configuration.decrement { Text("duplicate less") }
        configuration.increment { Text("duplicate more") }
      }
    }
  }
}

struct ConsumerAutomaticSliderStyle: SliderStyle {
  func makeBody(configuration: SliderStyleConfiguration) -> some View {
    let active = configuration.focusActive || configuration.isPressed
    let row = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let control = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let width = max(1, configuration.trackCellCount)
    let fraction =
      configuration.fractionCompleted.isFinite
      ? min(max(configuration.fractionCompleted, 0), 1) : 0
    let position = min(width - 1, max(0, Int((fraction * Double(width - 1)).rounded())))
    ConsumerValueStyleRow(chrome: row, focused: configuration.focusActive, active: active) {
      configuration.label.foregroundStyle(.terminalBorder(.accent))
      HStack(alignment: .center, spacing: 1) {
        configuration.track {
          Text(
            String(repeating: "━", count: position) + "●"
              + String(repeating: "─", count: width - position - 1)
          )
          .foregroundStyle(active ? control.borderStyle : AnyShapeStyle(.separator))
        }
        configuration.valueLabel.foregroundStyle(
          active ? control.foregroundStyle : row.foregroundStyle)
      }
      .opacity(control.opacity)
      .background { if active { Rectangle().fill(control.backgroundStyle) } }
    }
  }
}

struct ConsumerAutomaticStepperStyle: StepperStyle {
  func makeBody(configuration: StepperStyleConfiguration) -> some View {
    let active = configuration.focusActive || configuration.isPressed
    let row = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let control = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    let accent = active ? control.borderStyle : AnyShapeStyle(.separator)
    ConsumerValueStyleRow(chrome: row, focused: configuration.focusActive, active: active) {
      configuration.label.foregroundStyle(.terminalBorder(.accent))
      HStack(alignment: .center, spacing: 1) {
        configuration.decrement {
          Text(configuration.canDecrement ? "◀" : "◁")
            .foregroundStyle(configuration.canDecrement ? accent : AnyShapeStyle(.placeholder))
        }
        configuration.valueLabel.foregroundStyle(
          active ? control.foregroundStyle : row.foregroundStyle)
        configuration.increment {
          Text(configuration.canIncrement ? "▶" : "▷")
            .foregroundStyle(configuration.canIncrement ? accent : AnyShapeStyle(.placeholder))
        }
      }
      .opacity(control.opacity)
      .background { if active { Rectangle().fill(control.backgroundStyle) } }
    }
  }
}

private struct ConsumerValueStyleRow<Content: View>: View {
  let chrome: ControlChrome
  let focused: Bool
  let active: Bool
  @ViewBuilder var content: Content

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      Text(focused ? "▌" : " ").foregroundStyle(
        focused ? chrome.borderStyle : AnyShapeStyle(.background))
      content
    }
    .background { if active { Rectangle().fill(chrome.backgroundStyle) } }
    .opacity(chrome.opacity)
  }
}
