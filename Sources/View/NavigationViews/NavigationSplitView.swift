package import Core

/// Composes a sidebar, optional content pane, and detail pane using a
/// terminal-native split layout.
public struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View,
  ResolvableView
{
  private var sidebarView: Sidebar
  private var showsContent: Bool
  private var contentView: Content
  private var detailView: Detail

  public init(
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder detail: () -> Detail
  ) where Content == EmptyView {
    sidebarView = sidebar()
    showsContent = false
    contentView = EmptyView()
    detailView = detail()
  }

  public init(
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder content: () -> Content,
    @ViewBuilder detail: () -> Detail
  ) {
    sidebarView = sidebar()
    showsContent = true
    contentView = content()
    detailView = detail()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    composedView().resolveElements(in: context)
  }

  @ViewBuilder
  private func composedView() -> some View {
    HStack(alignment: .top, spacing: 0) {
      sidebarView
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clipped()
      Divider()

      if showsContent {
        contentView
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .clipped()
        Divider()
      }

      detailView
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
