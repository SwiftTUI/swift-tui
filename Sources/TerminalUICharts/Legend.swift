import Core
import View

// AnyView policy: retain heterogeneous child storage here for authored label
// content.
/// A compact legend that pairs labels with semantic tones.
public struct Legend: View, ResolvableView {
  public var items: [LegendItem]
  public var itemSpacing: Int
  private var labelViews: [AnyView]

  public init(
    items: [LegendItem],
    itemSpacing: Int = 2
  ) {
    self.items = items
    self.itemSpacing = itemSpacing
    labelViews = []
  }

  public init<S: StringProtocol>(
    _ title: S,
    items: [LegendItem],
    itemSpacing: Int = 2
  ) {
    self.items = items
    self.itemSpacing = itemSpacing
    labelViews = [AnyView(Text(String(title)))]
  }

  public init<Label: View>(
    items: [LegendItem],
    itemSpacing: Int = 2,
    @ViewBuilder label: () -> Label
  ) {
    self.items = items
    self.itemSpacing = itemSpacing
    labelViews = declaredBuilderChildren(from: label())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty {
          combinedView(from: labelViews, kindName: "LegendLabel")
            .foregroundStyle(.terminalBorder(.accent))
        }
        HStack(alignment: .center, spacing: itemSpacing) {
          ForEach(items.indices, id: \.self) { index in
            legendItemView(items[index])
          }
        }
      }
    ).resolveElements(in: context)
  }
}
