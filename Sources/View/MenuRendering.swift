import Core

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

    let expandedContent = AnyView(
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<contentViews.count) { index in
          MenuNonFocusableContent(content: contentViews[index])
        }
      }
      .padding(.init(horizontal: 1, vertical: 1))
      .background {
        RoundedRectangle(cornerRadius: 1).chromeFill(chrome.backgroundStyle)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
          chrome.borderStyle,
          backgroundStyle: chrome.borderBackgroundStyle
        )
      }
    )

    return AnyView(
      VStack(alignment: .leading, spacing: 0) {
        highlightedTrigger

        if isExpanded {
          expandedContent
            .padding(.init(top: 0, leading: 1, bottom: 0, trailing: 0))
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
