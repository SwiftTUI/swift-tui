import SwiftTUICore

/// Displays a title paired with an icon or glyph view.
public struct Label<Title: View, Icon: View>: PrimitiveView, IterativeResolvableView {
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

  package func makeResolveWork(
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    resolvedNode(in: context).map { [$0] }
  }
}

extension Label {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    let configuration = LabelStyleConfiguration(
      title: .init(authoringContext: authoringScope) { title.authoredAccessibilityLabel() },
      icon: .init(authoringContext: authoringScope) { icon },
      styleEnvironment: context.environmentValues.styleEnvironmentSnapshot
    )
    return context.environmentValues.labelStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("LabelBody"))
    ).map { child in
      return ResolvedNode(
        identity: context.identity,
        kind: .view("Label"),
        children: [child],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        semanticMetadata: SemanticMetadata().namingControl(with: title)
      )

    }
  }
}

/// Displays a leading label paired with trailing content or a value.
public struct LabeledContent<Label: View, Content: View>: PrimitiveView, IterativeResolvableView {
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

  package func makeResolveWork(
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    resolvedNode(in: context).map { [$0] }
  }
}

extension LabeledContent {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    let configuration = LabeledContentStyleConfiguration(
      label: .init(authoringContext: authoringScope) { label },
      content: .init(authoringContext: authoringScope) { content },
      styleEnvironment: context.environmentValues.styleEnvironmentSnapshot
    )
    return context.environmentValues.labeledContentStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("LabeledContentBody"))
    ).map { child in
      return ResolvedNode(
        identity: context.identity,
        kind: .view("LabeledContent"),
        children: [child],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )

    }
  }
}

/// Groups related controls into a compact row or stack.
public struct ControlGroup<Label: View, Content: View>: PrimitiveView, IterativeResolvableView {
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

  package func makeResolveWork(
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    var configuration = ControlGroupStyleConfiguration(
      label: showsLabel ? .init(authoringContext: authoringScope) { label } : nil,
      content: .init(authoringContext: authoringScope) { content },
      styleEnvironment: context.environmentValues.styleEnvironmentSnapshot)
    let owner = ViewNodeContext.current?.stateOwnerHandle
    if let owner {
      configuration.content.retention = CapturedSubviewRetention(
        owner: owner, identity: context.identity.child(.named("ControlGroupContent")),
        family: "ControlGroupStyle")
    }
    return context.environmentValues.controlGroupStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("ControlGroupBody"))
    ).map { child in
      var node = ResolvedNode(
        identity: context.identity, kind: .view("ControlGroup"), children: [child],
        environmentSnapshot: context.environment, transactionSnapshot: context.transaction)
      if let owner { node.preferenceValues[CapturedSubviewOwnersPreferenceKey.self].insert(owner) }
      return [node]

    }
  }
}

/// Frames related content with optional label chrome.
public struct GroupBox<Label: View, Content: View>: PrimitiveView, IterativeResolvableView {
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

  package func makeResolveWork(
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    let configuration = GroupBoxStyleConfiguration(
      label: showsLabel ? .init(authoringContext: authoringScope) { label } : nil,
      content: .init(authoringContext: authoringScope) { content },
      controlProminence: context.environmentValues.controlProminence,
      styleEnvironment: context.environmentValues.styleEnvironmentSnapshot
    )
    return context.environmentValues.groupBoxStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("GroupBoxBody"))
    ).map { child in
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
}
