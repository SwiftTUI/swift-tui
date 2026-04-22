package import Core

/// Declares a single tab inside a `TabView`.
public struct Tab<SelectionValue: Hashable & Sendable, Content: View>: View {
  private let label: TabItemLabel
  private let selectionValue: SelectionValue
  private let content: Content

  public init<S: StringProtocol>(
    _ title: S,
    detail: String? = nil,
    badge: String? = nil,
    value: SelectionValue,
    @ViewBuilder content: () -> Content
  ) {
    label = TabItemLabel(
      String(title),
      detail: detail,
      badge: badge
    )
    selectionValue = value
    self.content = content()
  }

  public var body: some View {
    content
      .semanticMetadata(
        .init(tabItemLabel: label)
      )
      .tag(selectionValue)
  }
}

extension Tab: TabDeclarationView {
  package var tabDeclarationMetadata: PeekedTabChildMetadata {
    PeekedTabChildMetadata(
      label: label,
      tag: SelectionTag(value: selectionValue)
    )
  }

  package func resolveTabDeclarationContent(
    in context: ResolveContext
  ) -> ResolvedNode {
    let lowered =
      content
      .semanticMetadata(
        .init(tabItemLabel: label)
      )
      .tag(selectionValue)
    return lowered.resolve(in: context)
  }
}
