package import Core

/// Generates repeated content from a random-access collection.
public struct ForEach<Data, ID, Content>: View, ResolvableView
where Data: RandomAccessCollection, ID: Hashable, Content: View {
  public var data: Data
  public var id: KeyPath<Data.Element, ID>
  package let content: @MainActor (Data.Element) -> Content

  public init(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    @ViewBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) {
    self.data = data
    self.id = id
    self.content = content
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var resolved: [ResolvedNode] = []
    for element in data {
      let elementContext = context.replacingIdentity(
        with: context.identity.explicitID(element[keyPath: id])
      )
      let view = elementContext.trackingObservableAccess {
        content(element)
      }
      resolved.append(contentsOf: view.resolveElements(in: elementContext))
    }
    return resolved
  }
}

extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
  public init(
    _ data: Data,
    @ViewBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) {
    self.init(data, id: \.id, content: content)
  }
}

extension ForEach where Data == Range<Int>, ID == Int {
  public init(
    _ data: Range<Int>,
    @ViewBuilder content: @escaping @MainActor (Int) -> Content
  ) {
    self.init(data, id: \.self, content: content)
  }
}
