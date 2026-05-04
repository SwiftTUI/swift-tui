package import SwiftTUICore

/// Displays a title paired with an icon or glyph view.
public struct Label<Title: View, Icon: View>: View, ResolvableView {
  private var title: Title
  private var icon: Icon

  public init(
    @ViewBuilder title: () -> Title,
    @ViewBuilder icon: () -> Icon
  ) {
    self.title = title()
    self.icon = icon()
  }

  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder icon: () -> Icon
  ) where Title == Text {
    self.title = Text(String(title))
    self.icon = icon()
  }

  public init<S: StringProtocol>(
    _ title: S,
    image: Image
  ) where Title == Text, Icon == Image {
    self.title = Text(String(title))
    icon = image
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension Label {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    HStack(alignment: .center, spacing: 1) {
      icon
      title
    }
    .resolve(in: context)
  }
}

/// Displays a leading label paired with trailing content or a value.
public struct LabeledContent<Label: View, Content: View>: View, ResolvableView {
  private var label: Label
  private var content: Content

  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    self.label = label()
    self.content = content()
  }

  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) where Label == Text {
    label = Text(String(title))
    self.content = content()
  }

  public init<S1: StringProtocol, S2: StringProtocol>(
    _ title: S1,
    value: S2
  ) where Label == Text, Content == Text {
    label = Text(String(title))
    content = Text(String(value))
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension LabeledContent {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    HStack(alignment: .firstTextBaseline, spacing: 1) {
      label
        .foregroundStyle(.separator)
      Spacer()
      content
    }
    .resolve(in: context)
  }
}

/// Groups related controls into a compact row or stack.
public struct ControlGroup<Label: View, Content: View>: View, ResolvableView {
  private var showsLabel: Bool
  private var label: Label
  private var content: Content

  public init(
    @ViewBuilder content: () -> Content
  ) where Label == EmptyView {
    showsLabel = false
    label = EmptyView()
    self.content = content()
  }

  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) where Label == Text {
    showsLabel = true
    label = Text(String(title))
    self.content = content()
  }

  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    showsLabel = true
    self.label = label()
    self.content = content()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    composedView().resolveElements(in: context)
  }

  @ViewBuilder
  private func composedView() -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if showsLabel {
        label.foregroundStyle(.separator)
      }
      HStack(spacing: 1) {
        content
      }
    }
  }
}

/// Frames related content with optional label chrome.
public struct GroupBox<Label: View, Content: View>: View, ResolvableView {
  private var showsLabel: Bool
  private var label: Label
  private var content: Content

  public init(
    @ViewBuilder content: () -> Content
  ) where Label == EmptyView {
    showsLabel = false
    label = EmptyView()
    self.content = content()
  }

  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) where Label == Text {
    showsLabel = true
    label = Text(String(title))
    self.content = content()
  }

  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    showsLabel = true
    self.label = label()
    self.content = content()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    composedView().resolveElements(in: context)
  }

  @ViewBuilder
  private func composedView() -> some View {
    EnvironmentReader(\.styleEnvironmentSnapshot) { styleEnvironment in
      EnvironmentReader(\.controlProminence) { prominence in
        let chrome = styleEnvironment.groupBoxChrome(prominence: prominence)
        VStack(alignment: .leading, spacing: 0) {
          if showsLabel {
            label.foregroundStyle(.separator)
          }
          groupBoxContent()
            .padding(.init(horizontal: 1, vertical: 1))
            .overlay {
              RoundedRectangle(cornerRadius: 1).strokeBorder(chrome.borderStyle)
            }
            .foregroundStyle(chrome.foregroundStyle)
        }
        .layoutMetadata(
          .init(
            minimumHeight: (showsLabel ? 1 : 0) + 3
          )
        )
      }
    }
  }

  @ViewBuilder
  private func groupBoxContent() -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content
    }
  }
}
