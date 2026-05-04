import SwiftTUICore
import SwiftTUIViews

/// A compact legend that pairs labels with semantic tones.
public struct Legend<Label: View>: View, ResolvableView {
  public var items: [LegendItem]
  public var itemSpacing: Int
  private let label: Label

  public init(
    items: [LegendItem],
    itemSpacing: Int = 2,
    @ViewBuilder label: () -> Label
  ) {
    self.items = items
    self.itemSpacing = itemSpacing
    self.label = label()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: EmptyView())
          HStack(alignment: .center, spacing: itemSpacing) {
            ForEach(items.indices, id: \.self) { index in
              legendItemView(items[index])
            }
          }
        },
        in: context
      )
    ]
  }
}

extension Legend where Label == EmptyView {
  public init(
    items: [LegendItem],
    itemSpacing: Int = 2
  ) {
    self.init(
      items: items,
      itemSpacing: itemSpacing,
      label: { EmptyView() }
    )
  }
}

extension Legend where Label == Text {
  public init<S: StringProtocol>(
    _ title: S,
    items: [LegendItem],
    itemSpacing: Int = 2
  ) {
    self.init(
      items: items,
      itemSpacing: itemSpacing,
      label: { Text(String(title)) }
    )
  }
}
