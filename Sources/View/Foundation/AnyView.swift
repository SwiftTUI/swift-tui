package import Core

/// A type-erased terminal view.
///
/// Use `AnyView` when a call site must store heterogeneous view values while
/// still participating in the normal authored `View` surface. Prefer typed
/// `@ViewBuilder` composition and generic `Content: View` storage when those
/// are practical.
public struct AnyView: View, ResolvableView {
  private let resolveElementsClosure: @MainActor (ResolveContext) -> [ResolvedNode]

  private static func resolveWithAuthoringContext(
    _ authoringContext: AuthoringContext?,
    _ apply: @escaping @MainActor (ResolveContext) -> [ResolvedNode]
  ) -> @MainActor (ResolveContext) -> [ResolvedNode] {
    guard let authoringContext else {
      return apply
    }

    return { context in
      withAuthoringContext(authoringContext) {
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
    authoringContext: AuthoringContext?
  ) {
    let erased: Any = view
    if let resolvable = erased as? any ResolvableView {
      resolveElementsClosure = Self.resolveWithAuthoringContext(authoringContext) { context in
        resolvable.resolveElements(in: context)
      }
      return
    }

    resolveElementsClosure = Self.resolveWithAuthoringContext(authoringContext) { context in
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
