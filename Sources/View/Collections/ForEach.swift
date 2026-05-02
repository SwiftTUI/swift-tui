package import Core

/// Generates repeated content from a random-access collection.
public struct ForEach<Data, ID, Content>: View, ResolvableView
where Data: RandomAccessCollection, ID: Hashable, Content: View {
  public var data: Data
  public var id: KeyPath<Data.Element, ID>
  package let content: @MainActor (Data.Element) -> Content
  private let authoringScope: AuthoringContext?

  public init(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    @ViewBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) {
    self.data = data
    self.id = id
    self.content = content
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var resolved: [ResolvedNode] = []
    let dynamicPropertyScope = currentAuthoringContext() ?? authoringScope
    for element in data {
      let elementContext = context.replacingIdentity(
        with: context.identity.explicitID(element[keyPath: id])
      )
      // Diverge structural identity per iteration so identity-deriving
      // modifiers such as `.panel()` (which reads
      // `scope.structuralIdentity`) see distinct positions for each
      // element, while `viewIdentity` keeps pointing at the outer
      // authoring view — this preserves invalidation routing and
      // `@State` ownership for any closures that captured the scope
      // (Button/Menu/Link/Picker/Stepper/TabView/value controls).
      let perIterationScope = dynamicPropertyScope.map { scope in
        AuthoringContext(
          viewIdentity: scope.viewIdentity,
          structuralIdentity: elementContext.identity,
          focusedValues: scope.focusedValues,
          viewNode: scope.viewNode,
          ordinalTracker: scope.ordinalTracker
        )
      }
      let view = withAuthoringContext(perIterationScope) {
        elementContext.trackingObservableAccess {
          content(element)
        }
      }
      let elementNode = withAuthoringContext(perIterationScope) {
        resolveView(view, in: elementContext)
      }
      if elementNode.identity == elementContext.identity,
        elementNode.kind == .view("EmptyView")
      {
        continue
      }
      if elementNode.identity == elementContext.identity,
        elementNode.kind == .view("Group")
      {
        resolved.append(contentsOf: elementNode.children)
      } else {
        resolved.append(elementNode)
      }
    }
    return resolved
  }
}

extension ForEach: DeclaredChildrenView {
  package func appendDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    let childContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    resolved.append(contentsOf: resolveElements(in: childContext))
  }

  package func appendErasedDeclaredChildren(
    into children: inout [AnyView]
  ) {
    for element in data {
      let view = withAuthoringContext(authoringScope) {
        content(element)
      }
      appendErasedDeclaredBuilderChildren(
        from: view,
        into: &children
      )
    }
  }

  package func appendDeferredDeclaredChildren(
    into children: inout [DeferredViewPayload]
  ) {
    for element in data {
      let view = withAuthoringContext(authoringScope) {
        content(element)
      }
      appendDeferredDeclaredBuilderChildren(
        from: view,
        into: &children
      )
    }
  }

  package func appendPortalDeclaredChildren(
    into children: inout [PortalContentPayload]
  ) {
    for element in data {
      let view = withAuthoringContext(authoringScope) {
        content(element)
      }
      appendPortalDeclaredBuilderChildren(
        from: view,
        into: &children
      )
    }
  }

  package func enumerateDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    visitor: (
      _ child: Any,
      _ childContext: ResolveContext,
      _ resolveOne: @escaping @MainActor () -> ResolvedNode
    ) -> Void
  ) {
    let childContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    let dynamicPropertyScope = currentAuthoringContext() ?? authoringScope

    for element in data {
      let elementContext = childContext.replacingIdentity(
        with: childContext.identity.explicitID(element[keyPath: id])
      )
      let perIterationScope = dynamicPropertyScope.map { scope in
        AuthoringContext(
          viewIdentity: scope.viewIdentity,
          structuralIdentity: elementContext.identity,
          focusedValues: scope.focusedValues,
          viewNode: scope.viewNode,
          ordinalTracker: scope.ordinalTracker
        )
      }
      let view = withAuthoringContext(perIterationScope) {
        elementContext.trackingObservableAccess {
          content(element)
        }
      }

      visitor(view, elementContext) {
        withAuthoringContext(perIterationScope) {
          resolveView(view, in: elementContext)
        }
      }
    }
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
