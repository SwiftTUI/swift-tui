import SwiftTUICore

// Shared composition only; handlers, routes, and typed arithmetic remain with
// the owning value control and its public configuration wrappers.
struct ValueControlStyleRow<Content: View>: View {
  let chrome: ControlChrome
  let focusActive: Bool
  let isHighlighted: Bool
  var reservesRail = true
  @ViewBuilder var content: Content

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      if focusActive && reservesRail {
        Text("▌").foregroundStyle(chrome.borderStyle)
      } else if reservesRail {
        Text(" ").foregroundStyle(.background)
      }
      content
    }
    .background {
      if isHighlighted { Rectangle().fill(chrome.backgroundStyle) }
    }
    .opacity(chrome.opacity)
  }
}
