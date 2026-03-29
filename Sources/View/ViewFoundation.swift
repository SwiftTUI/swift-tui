public import Core

package protocol ViewNode {
  func resolve(in context: ResolveContext) -> ResolvedNode
}

/// A declarative unit of terminal UI content.
///
/// Implement `body` the same way you would in SwiftUI: compose smaller views,
/// modifiers, and property wrappers rather than constructing render nodes
/// directly.
public protocol View {
  associatedtype Body: View = Never

  var body: Body { get }
}

extension Never: View {
  /// Primitive views use `Never` as their body type.
  public typealias Body = Never

  public var body: Never {
    fatalError("Never.body is unreachable.")
  }
}

package protocol ResolvableView {
  func resolveElements(in context: ResolveContext) -> [ResolvedNode]
}

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
      return parallelBuilderChildren(from: content)
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return []
      }
      return parallelBuilderChildren(from: content)
    }
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch storage {
    case .trueContent(let content):
      return parallelResolveElements(content, in: context)
    case .falseContent(let content):
      return parallelResolveElements(content, in: context)
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
      children: parallelBuilderChildren(from: accumulated)
        + parallelBuilderChildren(from: next)
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
      children: components.flatMap { parallelBuilderChildren(from: $0) }
    )
  }

  public static func buildLimitedAvailability<Content: View>(
    _ component: Content
  ) -> AnyView {
    AnyView(component)
  }
}

/// A type-erased terminal view.
///
/// Use `AnyView` when a call site must store heterogeneous view values while
/// still participating in the normal authored `View` surface.
public struct AnyView: View, ResolvableView {
  private let resolveElementsClosure: (ResolveContext) -> [ResolvedNode]

  package init<V: View & ResolvableView>(resolving view: V) {
    resolveElementsClosure = { context in
      view.resolveElements(in: context)
    }
  }

  /// Erases the concrete type of `view`.
  public init<V: View>(_ view: V) {
    let erased: Any = view
    if let resolvable = erased as? any ResolvableView {
      resolveElementsClosure = { context in
        resolvable.resolveElements(in: context)
      }
      return
    }

    resolveElementsClosure = { context in
      parallelResolveElements(view, in: context)
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
    parallelResolve(self, in: context)
  }
}

/// Resolves authored views into resolved render trees.
///
/// This is the lowest public entry point for inspecting the authored view tree
/// before layout, semantics, draw extraction, and rasterization occur.
public struct Resolver {
  public init() {}

  /// Resolves `root` in the supplied context.
  public func resolve<V: View>(
    _ root: V,
    in context: ResolveContext = .init()
  ) -> ResolvedNode {
    parallelResolve(root, in: context)
  }
}

package func parallelBuilderChildren<V: View>(
  from view: V
) -> [AnyView] {
  let erased: Any = view
  if let composite = erased as? any BuilderCompositeView {
    return composite.builderChildren
  }
  return [AnyView(view)]
}

package func parallelBuilderChildren<V: View & BuilderCompositeView>(
  from view: V
) -> [AnyView] {
  view.builderChildren
}

package func parallelResolveElements<V: View>(
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

package func parallelResolveElements<V: View & ResolvableView>(
  _ view: V,
  in context: ResolveContext
) -> [ResolvedNode] {
  view.resolveElements(in: context)
}

package func parallelNormalizeResolvedElements(
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

package func parallelResolve<V: View>(
  _ view: V,
  in context: ResolveContext
) -> ResolvedNode {
  if let reused = context.reusedResolvedSubtreeIfAvailable() {
    return reused
  }
  context.recordResolvedComputation()
  return parallelNormalizeResolvedElements(
    parallelResolveElements(view, in: context),
    in: context
  )
}
