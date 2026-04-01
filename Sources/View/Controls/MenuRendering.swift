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
      if isFocused || isPressed {
        triggerRow(isExpanded: isExpanded, chrome: chrome)
          .background {
            Rectangle().fill(chrome.backgroundStyle)
          }
      } else {
        triggerRow(isExpanded: isExpanded, chrome: chrome)
      }

      if isExpanded {
        MenuExpandedContent(content: content)
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
          .padding(.init(top: 0, leading: 1, bottom: 0, trailing: 0))
      }
    }
    .foregroundStyle(chrome.foregroundStyle)
    .drawMetadata(.init(opacity: chrome.opacity))
  }

  @ViewBuilder
  private func triggerRow(
    isExpanded: Bool,
    chrome: ControlChrome
  ) -> some View {
    HStack(alignment: .center, spacing: 1) {
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
