import SwiftTUIViews

struct TaggedMenuStyle: MenuStyle, Equatable {
  let tag: String
  func makeBody(configuration: MenuStyleConfiguration) -> some View {
    configuration.portal(presentation: .init()) {
      configuration.trigger { Text(tag) }
    }
  }
}

struct TaggedControlGroupStyle: ControlGroupStyle, Equatable {
  let tag: String
  func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    VStack {
      Text(tag)
      configuration.content
    }
  }
}

// This file is also typechecked as an external consumer: no SPI or package APIs.
struct ConsumerAutomaticMenuStyle: MenuStyle {
  func makeBody(configuration: MenuStyleConfiguration) -> some View {
    ConsumerAutomaticMenuBody(configuration: configuration)
  }
}

private struct ConsumerAutomaticMenuBody: View {
  let configuration: MenuStyleConfiguration
  var body: some View {
    configuration.portal(presentation: .init()) {
      configuration.trigger {
        let chrome = configuration.styleEnvironment.controlChrome(
          isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
          isPressed: configuration.isPressed)
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 1) {
            if configuration.focusActive {
              Text("▌").foregroundStyle(chrome.borderStyle)
            } else {
              Text(" ").foregroundStyle(.background)
            }
            configuration.label
            Spacer()
            Text(configuration.isPresented ? "▴" : "▾")
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
    }
  }
}

struct ConsumerHorizontalControlGroupStyle: ControlGroupStyle {
  func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    ConsumerHorizontalControlGroupBody(configuration: configuration)
  }
}
private struct ConsumerHorizontalControlGroupBody: View {
  let configuration: ControlGroupStyleConfiguration
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label { label.foregroundStyle(.separator) }
      HStack(spacing: 1) { configuration.content }
    }
  }
}

struct ConsumerVerticalControlGroupStyle: ControlGroupStyle {
  func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    ConsumerVerticalControlGroupBody(configuration: configuration)
  }
}
private struct ConsumerVerticalControlGroupBody: View {
  let configuration: ControlGroupStyleConfiguration
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label { label.foregroundStyle(.separator) }
      VStack(alignment: .leading, spacing: 1) { configuration.content }
    }
  }
}

struct ConsumerCompactMenuControlGroupStyle: ControlGroupStyle {
  func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    ConsumerCompactMenuControlGroupBody(configuration: configuration)
  }
}
private struct ConsumerCompactMenuControlGroupBody: View {
  let configuration: ControlGroupStyleConfiguration
  var body: some View {
    Menu {
      if let label = configuration.label { label } else { Text("Controls") }
    } content: {
      configuration.content
    }
  }
}
