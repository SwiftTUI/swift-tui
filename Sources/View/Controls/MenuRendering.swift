import Core

extension Menu {
  @ViewBuilder
  func menuBody(
    isExpanded: Bool,
    isFocused: Bool,
    isPressed: Bool,
    chrome: ControlChrome
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      triggerRow(
        isExpanded: isExpanded,
        isFocused: isFocused,
        isPressed: isPressed,
        chrome: chrome
      )

      if isExpanded {
        MenuExpandedContent(content: content)
          .padding(.init(horizontal: 1, vertical: 1))
          .background {
            RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(chrome.backgroundStyle)
          }
          .overlay {
            RoundedRectangle(cornerRadius: 1).strokeBorder(
              chrome.borderStyle,
              style: isFocused ? .heavy : .init(),
              background: chrome.borderBackgroundStyle
            )
          }
          .padding(.init(top: 0, leading: 1, bottom: 0, trailing: 0))
      }
    }
    .foregroundStyle(chrome.foregroundStyle)
    .drawMetadata(.init(opacity: chrome.opacity))
  }

  @ViewBuilder
  private func triggerRow(
    isExpanded: Bool,
    isFocused: Bool,
    isPressed: Bool,
    chrome: ControlChrome
  ) -> some View {
    controlFocusRow(
      showsRail: isFocused,
      railStyle: chrome.borderStyle,
      isHighlighted: isFocused || isPressed,
      backgroundStyle: chrome.backgroundStyle,
      reservesRailSpaceWhenHidden: true
    ) {
      label
      Spacer()
      Text(isExpanded ? "▴" : "▾")
    }
    .foregroundStyle(chrome.foregroundStyle)
    .drawMetadata(.init(opacity: chrome.opacity))
  }
}

private struct MenuExpandedContent<Content: View>: View, ResolvableView {
  var content: Content

  func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    VStack(alignment: .leading, spacing: 0) {
      content
    }
    .resolveElements(in: context)
    .map(disablingFocus)
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
