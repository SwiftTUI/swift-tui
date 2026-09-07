import SwiftTUICore

// Pure composition over public style values, shared by the built-in bodies of
// the bound-control, value-control, and menu families. No primitive identity
// or handler crosses this helper; the owning control keeps activation and
// semantics.
struct ControlStyleRow<Content: View>: View {
  let chrome: ControlChrome
  let focusActive: Bool
  let isHighlighted: Bool
  /// Keeps one leading cell for the focus rail while unfocused, so gaining
  /// focus never shifts the content. `false` draws no rail at all — the
  /// compact treatments — rather than a rail that appears on focus.
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
    .foregroundStyle(chrome.foregroundStyle)
    .background {
      if isHighlighted { Rectangle().fill(chrome.backgroundStyle) }
    }
    .opacity(chrome.opacity)
  }
}
