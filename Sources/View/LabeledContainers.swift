package import Core

/// Displays a title paired with an icon or glyph view.
public struct Label: View, ResolvableView {
  private var titleViews: [AnyView]
  private var iconViews: [AnyView]

  public init<Title: View, Icon: View>(
    @ViewBuilder title: () -> Title,
    @ViewBuilder icon: () -> Icon
  ) {
    titleViews = parallelBuilderChildren(from: title())
    iconViews = parallelBuilderChildren(from: icon())
  }

  public init<S: StringProtocol, Icon: View>(
    _ title: S,
    @ViewBuilder icon: () -> Icon
  ) {
    titleViews = [AnyView(Text(String(title)))]
    iconViews = parallelBuilderChildren(from: icon())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    AnyView(
      HStack(alignment: .center, spacing: 1) {
        combinedView(from: iconViews, kindName: "LabelIcon")
        combinedView(from: titleViews, kindName: "LabelTitle")
      }
    ).resolveElements(in: context)
  }
}

/// Displays a leading label paired with trailing content or a value.
public struct LabeledContent: View, ResolvableView {
  private var labelViews: [AnyView]
  private var contentViews: [AnyView]

  public init<Content: View, Label: View>(
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    labelViews = parallelBuilderChildren(from: label())
    contentViews = parallelBuilderChildren(from: content())
  }

  public init<S: StringProtocol, Content: View>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) {
    labelViews = [AnyView(Text(String(title)))]
    contentViews = parallelBuilderChildren(from: content())
  }

  public init<S1: StringProtocol, S2: StringProtocol>(
    _ title: S1,
    value: S2
  ) {
    labelViews = [AnyView(Text(String(title)))]
    contentViews = [AnyView(Text(String(value)))]
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    AnyView(
      HStack(alignment: .firstTextBaseline, spacing: 1) {
        combinedView(from: labelViews, kindName: "LabeledContentLabel")
          .foregroundStyle(.muted)
        Spacer()
        combinedView(from: contentViews, kindName: "LabeledContentValue")
      }
    ).resolveElements(in: context)
  }
}

/// Groups related controls into a compact row or stack.
public struct ControlGroup: View, ResolvableView {
  private var labelViews: [AnyView]
  private var contentViews: [AnyView]

  public init<Content: View>(
    @ViewBuilder content: () -> Content
  ) {
    labelViews = []
    contentViews = parallelBuilderChildren(from: content())
  }

  public init<S: StringProtocol, Content: View>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) {
    labelViews = [AnyView(Text(String(title)))]
    contentViews = parallelBuilderChildren(from: content())
  }

  public init<Content: View, Label: View>(
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    labelViews = parallelBuilderChildren(from: label())
    contentViews = parallelBuilderChildren(from: content())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    composedView().resolveElements(in: context)
  }

  private func composedView() -> AnyView {
    AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty {
          composedLabel()
        }
        HStack(spacing: 2) {
          ForEach(contentViews.indices, id: \.self) { index in
            contentViews[index]
          }
        }
      }
    )
  }

  private func composedLabel() -> AnyView {
    AnyView(
      combinedView(from: labelViews, kindName: "ControlGroupLabel")
        .foregroundStyle(.muted)
    )
  }
}

/// Frames related content with optional label chrome.
public struct GroupBox: View, ResolvableView {
  private var labelViews: [AnyView]
  private var contentViews: [AnyView]

  public init<Content: View>(
    @ViewBuilder content: () -> Content
  ) {
    labelViews = []
    contentViews = parallelBuilderChildren(from: content())
  }

  public init<S: StringProtocol, Content: View>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) {
    labelViews = [AnyView(Text(String(title)))]
    contentViews = parallelBuilderChildren(from: content())
  }

  public init<Content: View, Label: View>(
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    labelViews = parallelBuilderChildren(from: label())
    contentViews = parallelBuilderChildren(from: content())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    composedView().resolveElements(in: context)
  }

  private func composedView() -> AnyView {
    AnyView(
      EnvironmentReader(\.terminalAppearance) { appearance in
        EnvironmentReader(\.controlProminence) { prominence in
          let chrome = appearance.groupBoxChrome(prominence: prominence)
          let content = groupBoxContent()
            .padding(.init(all: 1))
            .background {
              RoundedRectangle(cornerRadius: 1).parallelInteriorFill(chrome.backgroundStyle)
            }
            .overlay {
              RoundedRectangle(cornerRadius: 1).parallelStrokeBorder(chrome.borderStyle)
            }
            .foregroundStyle(chrome.foregroundStyle)

          VStack(alignment: .leading, spacing: 0) {
            if !labelViews.isEmpty {
              groupBoxLabel()
            }
            content
          }
          .layoutMetadata(
            .init(
              minimumHeight: (labelViews.isEmpty ? 0 : 1) + 3
            )
          )
        }
      }
    )
  }

  private func groupBoxContent() -> AnyView {
    switch contentViews.count {
    case 0:
      return AnyView(EmptyView())
    case 1:
      return contentViews[0]
    default:
      return AnyView(
        VStack(alignment: .leading, spacing: 0) {
          ForEach(contentViews.indices, id: \.self) { index in
            contentViews[index]
          }
        }
      )
    }
  }

  private func groupBoxLabel() -> AnyView {
    AnyView(
      combinedView(from: labelViews, kindName: "GroupBoxLabel")
        .foregroundStyle(.muted)
    )
  }
}
