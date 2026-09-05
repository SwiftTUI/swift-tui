import SwiftTUICore

/// Displays a title paired with an icon or glyph view.
public struct Label<Title: View, Icon: View>: PrimitiveView, ResolvableView {
  private var title: Title
  private var icon: Icon
  private let authoringScope: AuthoringContext?

  public init(
    @ViewBuilder title: () -> Title,
    @ViewBuilder icon: () -> Icon
  ) {
    authoringScope = currentAuthoringContext()
    self.title = title()
    self.icon = icon()
  }

  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder icon: () -> Icon
  ) where Title == Text {
    authoringScope = currentAuthoringContext()
    self.title = Text(String(title))
    self.icon = icon()
  }

  public init<S: StringProtocol>(
    _ title: S,
    image: Image
  ) where Title == Text, Icon == Image {
    authoringScope = currentAuthoringContext()
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
    let configuration = LabelStyleConfiguration(
      title: .init(authoringContext: authoringScope) { title },
      icon: .init(authoringContext: authoringScope) { icon },
      styleEnvironment: context.environmentValues.styleEnvironmentSnapshot
    )
    let child = context.environmentValues.labelStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("LabelBody")))
    return ResolvedNode(
      identity: context.identity,
      kind: .view("Label"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction
    )
  }
}

/// Displays a leading label paired with trailing content or a value.
public struct LabeledContent<Label: View, Content: View>: PrimitiveView, ResolvableView {
  private var label: Label
  private var content: Content
  private let authoringScope: AuthoringContext?

  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    authoringScope = currentAuthoringContext()
    self.label = label()
    self.content = content()
  }

  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) where Label == Text {
    authoringScope = currentAuthoringContext()
    label = Text(String(title))
    self.content = content()
  }

  public init<S1: StringProtocol, S2: StringProtocol>(
    _ title: S1,
    value: S2
  ) where Label == Text, Content == Text {
    authoringScope = currentAuthoringContext()
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
    let configuration = LabeledContentStyleConfiguration(
      label: .init(authoringContext: authoringScope) { label },
      content: .init(authoringContext: authoringScope) { content },
      styleEnvironment: context.environmentValues.styleEnvironmentSnapshot
    )
    let child = context.environmentValues.labeledContentStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("LabeledContentBody")))
    return ResolvedNode(
      identity: context.identity,
      kind: .view("LabeledContent"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction
    )
  }
}

/// Groups related controls into a compact row or stack.
public struct ControlGroup<Label: View, Content: View>: PrimitiveView, ResolvableView {
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
public struct GroupBox<Label: View, Content: View>: PrimitiveView, ResolvableView {
  private var showsLabel: Bool
  private var label: Label
  private var content: Content
  private let authoringScope: AuthoringContext?

  public init(
    @ViewBuilder content: () -> Content
  ) where Label == EmptyView {
    authoringScope = currentAuthoringContext()
    showsLabel = false
    label = EmptyView()
    self.content = content()
  }

  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) where Label == Text {
    authoringScope = currentAuthoringContext()
    showsLabel = true
    label = Text(String(title))
    self.content = content()
  }

  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    authoringScope = currentAuthoringContext()
    showsLabel = true
    self.label = label()
    self.content = content()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let configuration = GroupBoxStyleConfiguration(
      label: showsLabel ? .init(authoringContext: authoringScope) { label } : nil,
      content: .init(authoringContext: authoringScope) { content },
      controlProminence: context.environmentValues.controlProminence,
      styleEnvironment: context.environmentValues.styleEnvironmentSnapshot
    )
    let child = context.environmentValues.groupBoxStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("GroupBoxBody")))
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("GroupBox"),
        children: [child],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}
