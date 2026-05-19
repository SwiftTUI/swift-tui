package import SwiftTUICore

/// Groups related collection content with optional header and footer content.
public struct Section<Content: View, Header: View, Footer: View>: PrimitiveView,
  ResolvableView
{
  private var showsHeader: Bool
  private var showsFooter: Bool
  private var header: Header
  private var footer: Footer
  private var content: Content

  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder header: () -> Header,
    @ViewBuilder footer: () -> Footer
  ) {
    showsHeader = true
    showsFooter = true
    self.header = header()
    self.footer = footer()
    self.content = content()
  }

  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder header: () -> Header
  ) where Footer == EmptyView {
    showsHeader = true
    showsFooter = false
    self.header = header()
    footer = EmptyView()
    self.content = content()
  }

  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) where Header == Text, Footer == EmptyView {
    showsHeader = true
    showsFooter = false
    header = Text(String(title))
    footer = EmptyView()
    self.content = content()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension Section {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    var children: [ResolvedNode] = []

    if showsHeader {
      children.append(
        sectionChild(
          in: context,
          component: .named("Header"),
          role: .header,
          view: header
        )
      )
    }

    children.append(
      sectionChild(
        in: context,
        component: .named("Content"),
        role: .content,
        view: content
      )
    )

    if showsFooter {
      children.append(
        sectionChild(
          in: context,
          component: .named("Footer"),
          role: .footer,
          view: footer
        )
      )
    }

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Section"),
      children: children,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: .init(
        sectionRole: .section,
        accessibilityRole: .section
      )
    )
  }

  private func sectionChild<ViewContent: View>(
    in context: ResolveContext,
    component: IdentityComponent,
    role: SectionRole,
    view: ViewContent
  ) -> ResolvedNode {
    let childContext = context.child(component: component)
    return ResolvedNode(
      identity: childContext.identity,
      kind: .view("Section\(component.rawValue)"),
      children: resolveDeclaredChildren(
        view,
        in: childContext.child(component: .named("Views")),
        kindName: "Section\(component.rawValue)"
      ),
      environmentSnapshot: childContext.environment,
      transactionSnapshot: childContext.transaction,
      semanticMetadata: .init(sectionRole: role)
    )
  }
}
