import SwiftTUICore

// Pure composition over public style values. No primitive identity or handler
// crosses this helper; the owning control keeps activation and semantics.
struct BoundControlStyleRow<Content: View>: View {
  let chrome: ControlChrome
  let focusActive: Bool
  let isHighlighted: Bool
  var reservesRail = true
  @ViewBuilder var content: Content

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      if focusActive {
        Text("▌").foregroundStyle(chrome.borderStyle)
      } else if reservesRail {
        Text(" ").foregroundStyle(.background)
      }
      content
    }
    .foregroundStyle(chrome.foregroundStyle)
    .background {
      if isHighlighted { Rectangle().fill(chrome.backgroundStyle) }
    }
    .opacity(chrome.opacity)
  }
}
