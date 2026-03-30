public import Core

@MainActor
package protocol ViewNode {
  func resolve(in context: ResolveContext) -> ResolvedNode
}

/// A declarative unit of terminal UI content.
///
/// Implement `body` the same way you would in SwiftUI: compose smaller views,
/// modifiers, and property wrappers rather than constructing render nodes
/// directly.
@preconcurrency @MainActor
public protocol View {
  associatedtype Body: View = Never

  @ViewBuilder @MainActor @preconcurrency
  var body: Body { get }
}

extension Never: View {
  /// Primitive views use `Never` as their body type.
  public typealias Body = Never

  public var body: Never {
    fatalError("Never.body is unreachable.")
  }
}

@MainActor
package protocol ResolvableView {
  func resolveElements(in context: ResolveContext) -> [ResolvedNode]
}

@MainActor
package protocol BuilderCompositeView {
  var builderChildren: [AnyView] { get }
}

/// The builder artifact produced when a ``ViewBuilder`` contains multiple child
/// expressions in sequence.
public struct TupleView<Content>: View, ResolvableView, BuilderCompositeView {
  package let value: Content
  package let builderChildren: [AnyView]

  package init(
    _ value: Content,
    children: [AnyView]
  ) {
    self.value = value
    self.builderChildren = children
  }

  public var body: Never {
    fatalError("TupleView is a builder composition artifact.")
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveDeclaredChildren(
      builderChildren,
      in: context,
      kindName: "Group"
    )
  }
}

/// The builder artifact produced by conditional branches inside a
/// ``ViewBuilder``.
public struct ConditionalContent<TrueContent: View, FalseContent: View>: View,
  ResolvableView, BuilderCompositeView
{
  /// The currently active conditional branch.
  public enum Storage {
    case trueContent(TrueContent)
    case falseContent(FalseContent)
  }

  package let storage: Storage
  package let collapsesImplicitEmptyFalseBranch: Bool

  package init(
    storage: Storage,
    collapsesImplicitEmptyFalseBranch: Bool
  ) {
    self.storage = storage
    self.collapsesImplicitEmptyFalseBranch = collapsesImplicitEmptyFalseBranch
  }

  public var body: Never {
    fatalError("ConditionalContent is a builder composition artifact.")
  }

  package var builderChildren: [AnyView] {
    switch storage {
    case .trueContent(let content):
      return declaredBuilderChildren(from: content)
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return []
      }
      return declaredBuilderChildren(from: content)
    }
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch storage {
    case .trueContent(let content):
      return resolveViewElements(content, in: context)
    case .falseContent(let content):
      return resolveViewElements(content, in: context)
    }
  }
}

/// The builder artifact produced by array-like view composition such as
/// `ForEach` expansion or `buildArray` support.
public struct VariadicView<Content: View>: View, ResolvableView, BuilderCompositeView {
  package let content: [Content]
  package let builderChildren: [AnyView]

  package init(
    _ content: [Content],
    children: [AnyView]
  ) {
    self.content = content
    self.builderChildren = children
  }

  public var body: Never {
    fatalError("VariadicView is a builder composition artifact.")
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveDeclaredChildren(
      builderChildren,
      in: context,
      kindName: "Group"
    )
  }
}

@resultBuilder
/// Builds strongly typed trees of terminal views.
///
/// `ViewBuilder` mirrors SwiftUI's builder shape closely so authored APIs can
/// stay body-driven and declarative.
@MainActor
public enum ViewBuilder {
  public static func buildBlock() -> EmptyView {
    EmptyView()
  }

  public static func buildExpression<V: View>(_ expression: V) -> V {
    expression
  }

  public static func buildExpression(_ expression: ()) -> EmptyView {
    EmptyView()
  }

  public static func buildPartialBlock<Content: View>(
    first content: Content
  ) -> Content {
    content
  }

  public static func buildPartialBlock<Accumulated: View, Next: View>(
    accumulated: Accumulated,
    next: Next
  ) -> TupleView<(Accumulated, Next)> {
    TupleView(
      (accumulated, next),
      children: declaredBuilderChildren(from: accumulated)
        + declaredBuilderChildren(from: next)
    )
  }

  public static func buildOptional<Content: View>(
    _ component: Content?
  ) -> ConditionalContent<Content, EmptyView> {
    if let component {
      return ConditionalContent(
        storage: .trueContent(component),
        collapsesImplicitEmptyFalseBranch: true
      )
    }
    return ConditionalContent(
      storage: .falseContent(EmptyView()),
      collapsesImplicitEmptyFalseBranch: true
    )
  }

  public static func buildEither<TrueContent: View, FalseContent: View>(
    first component: TrueContent
  ) -> ConditionalContent<TrueContent, FalseContent> {
    ConditionalContent(
      storage: .trueContent(component),
      collapsesImplicitEmptyFalseBranch: false
    )
  }

  public static func buildEither<TrueContent: View, FalseContent: View>(
    second component: FalseContent
  ) -> ConditionalContent<TrueContent, FalseContent> {
    ConditionalContent(
      storage: .falseContent(component),
      collapsesImplicitEmptyFalseBranch: false
    )
  }

  public static func buildArray<Content: View>(
    _ components: [Content]
  ) -> VariadicView<Content> {
    VariadicView(
      components,
      children: components.flatMap { declaredBuilderChildren(from: $0) }
    )
  }

  public static func buildLimitedAvailability<Content: View>(
    _ component: Content
  ) -> AnyView {
    scopedAnyView {
      component
    }
  }
}

/// A type-erased terminal view.
///
/// Use `AnyView` when a call site must store heterogeneous view values while
/// still participating in the normal authored `View` surface. Prefer typed
/// `@ViewBuilder` composition and generic `Content: View` storage when those
/// are practical.
public struct AnyView: View, ResolvableView {
  private let resolveElementsClosure: @MainActor (ResolveContext) -> [ResolvedNode]

  private static func resolveWithAuthoringScope(
    _ authoringScope: DynamicPropertyScope?,
    _ apply: @escaping @MainActor (ResolveContext) -> [ResolvedNode]
  ) -> @MainActor (ResolveContext) -> [ResolvedNode] {
    guard let authoringScope else {
      return apply
    }

    return { context in
      withDynamicPropertyScope(authoringScope) {
        apply(context)
      }
    }
  }

  package init<V: View & ResolvableView>(resolving view: V) {
    resolveElementsClosure = { context in
      view.resolveElements(in: context)
    }
  }

  package init<V: View>(
    scoped view: V,
    authoringScope: DynamicPropertyScope?
  ) {
    let erased: Any = view
    if let resolvable = erased as? any ResolvableView {
      resolveElementsClosure = Self.resolveWithAuthoringScope(authoringScope) { context in
        resolvable.resolveElements(in: context)
      }
      return
    }

    resolveElementsClosure = Self.resolveWithAuthoringScope(authoringScope) { context in
      resolveViewElements(view, in: context)
    }
  }

  /// Erases the concrete type of `view`.
  ///
  /// Prefer `scopedAnyView(...)` when authored content will be stored for later
  /// evaluation, because that helper also restores the original
  /// dynamic-property scope.
  public init<V: View>(_ view: V) {
    let erased: Any = view
    if let resolvable = erased as? any ResolvableView {
      resolveElementsClosure = { context in
        resolvable.resolveElements(in: context)
      }
      return
    }

    resolveElementsClosure = { context in
      resolveViewElements(view, in: context)
    }
  }

  package init(erasing view: some ViewNode) {
    resolveElementsClosure = { context in
      [view.resolve(in: context)]
    }
  }

  public var body: Never {
    fatalError("AnyView is a type-erased view.")
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveElementsClosure(context)
  }
}

extension AnyView: ViewNode {
  package func resolve(in context: ResolveContext) -> ResolvedNode {
    resolveView(self, in: context)
  }
}

/// Resolves authored views into resolved render trees.
///
/// This is the lowest public entry point for inspecting the authored view tree
/// before layout, semantics, draw extraction, and rasterization occur.
public struct Resolver {
  public init() {}

  /// Resolves `root` in the supplied context.
  @MainActor
  public func resolve<V: View>(
    _ root: V,
    in context: ResolveContext = .init()
  ) -> ResolvedNode {
    resolveView(root, in: context)
  }
}

@MainActor
package func declaredBuilderChildren<V: View>(
  from view: V
) -> [AnyView] {
  let erased: Any = view
  if let composite = erased as? any BuilderCompositeView {
    return composite.builderChildren
  }
  return [scopedAnyView { view }]
}

@MainActor
package func declaredBuilderChildren<V: View & BuilderCompositeView>(
  from view: V
) -> [AnyView] {
  view.builderChildren
}

@MainActor
package func scopedAnyView<V: View>(
  authoringScope: DynamicPropertyScope? = currentDynamicPropertyScope(),
  _ build: () -> V
) -> AnyView {
  // AnyView policy: use this helper instead of plain AnyView(...) when stored
  // authored content must preserve its original dynamic-property scope.
  withDynamicPropertyScope(authoringScope) {
    AnyView(
      scoped: build(),
      authoringScope: authoringScope
    )
  }
}

@MainActor
package func resolveViewElements<V: View>(
  _ view: V,
  in context: ResolveContext
) -> [ResolvedNode] {
  let erased: Any = view
  if let resolvable = erased as? any ResolvableView {
    return resolvable.resolveElements(in: context)
  }
  return view.resolveBody(in: context) {
    view.body
  }
}

@MainActor
package func resolveViewElements<V: View & ResolvableView>(
  _ view: V,
  in context: ResolveContext
) -> [ResolvedNode] {
  view.resolveElements(in: context)
}

@MainActor
package func normalizeResolvedElements(
  _ resolvedElements: [ResolvedNode],
  in context: ResolveContext
) -> ResolvedNode {
  switch resolvedElements.count {
  case 0:
    return ResolvedNode(
      identity: context.identity,
      kind: .view("EmptyView"),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      intrinsicSize: .zero
    )
  case 1:
    return resolvedElements[0]
  default:
    return ResolvedNode(
      identity: context.identity,
      kind: .view("Group"),
      children: resolvedElements,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction
    )
  }
}

@MainActor
package func resolveView<V: View>(
  _ view: V,
  in context: ResolveContext
) -> ResolvedNode {
  if let reused = context.reusedResolvedSubtreeIfAvailable() {
    return reused
  }
  context.recordResolvedComputation()
  return normalizeResolvedElements(
    resolveViewElements(view, in: context),
    in: context
  )
}
