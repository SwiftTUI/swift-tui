package import Core

extension Menu {
  func menuBody(
    isExpanded: Bool,
    isFocused: Bool,
    isPressed: Bool,
    chrome: ControlChrome
  ) -> AnyView {
    let triggerRow = AnyView(
      HStack(alignment: .center, spacing: 1) {
        combinedView(from: labelViews, kindName: "MenuLabel")
        Spacer()
        Text(isExpanded ? "▴" : "▾")
      }
      .foregroundStyle(chrome.foregroundStyle)
      .drawMetadata(.init(opacity: chrome.opacity))
    )

    let highlightedTrigger =
      if isFocused || isPressed {
        AnyView(
          triggerRow.background {
            Rectangle().fill(chrome.backgroundStyle)
          }
        )
      } else {
        triggerRow
      }

    return AnyView(
      VStack(alignment: .leading, spacing: 0) {
        highlightedTrigger

        if isExpanded {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<contentViews.count) { index in
              MenuNonFocusableContent(content: contentViews[index])
            }
          }
          .padding(.init(top: 0, leading: 2, bottom: 0, trailing: 0))
        }
      }
      .foregroundStyle(chrome.foregroundStyle)
      .drawMetadata(.init(opacity: chrome.opacity))
    )
  }
}

private struct MenuNonFocusableContent<Content: View>: View, ResolvableView {
  var content: Content

  func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    content.resolveElements(in: context).map(disablingFocus)
  }

  private func disablingFocus(
    _ node: ResolvedNode
  ) -> ResolvedNode {
    var disabled = node
    disabled.semanticMetadata = disabled.semanticMetadata.merging(.init(isFocusable: false))
    disabled.children = disabled.children.map(disablingFocus)
    return disabled
  }
}
