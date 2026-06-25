package import SwiftTUICore

/// A typed scoped view wrapper that preserves the original authoring scope.
package struct ScopedBuilder<Output: View>: PrimitiveView, ResolvableView {
  private let output: Output
  private let resolveElementsClosure: @MainActor (ResolveContext) -> [ResolvedNode]

  private static func resolveWithAuthoringContext(
    _ authoringContext: AuthoringContext?,
    _ apply: @escaping @MainActor (ResolveContext) -> [ResolvedNode]
  ) -> @MainActor (ResolveContext) -> [ResolvedNode] {
    return { context in
      // A scoped builder with no captured scope should resolve as a fresh
      // authored subtree at its destination, not inherit whatever task-local
      // authoring context happened to be active in the parent wrapper.
      withAuthoringContext(authoringContext) {
        apply(context)
      }
    }
  }

  package init(
    scoped output: Output,
    authoringContext: AuthoringContext?
  ) {
    self.output = output
    let erased: Any = output

    if let resolvable = erased as? any ResolvableView {
      resolveElementsClosure = Self.resolveWithAuthoringContext(authoringContext) { context in
        resolvable.resolveElements(in: context)
      }
      return
    }

    resolveElementsClosure = Self.resolveWithAuthoringContext(authoringContext) { context in
      resolveViewElements(output, in: context)
    }
  }

  package init(
    authoringContext: AuthoringContext? = currentAuthoringContext(),
    @ViewBuilder content: @escaping @MainActor () -> Output
  ) {
    let output = withAuthoringContext(authoringContext) {
      content()
    }
    self.init(
      scoped: output,
      authoringContext: authoringContext
    )
  }

  package func build() -> Output {
    output
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveElementsClosure(context)
  }

  package var body: Never {
    fatalError("ScopedBuilder is a typed scoped view wrapper.")
  }
}

/// A typed mapper that captures and restores authored view scope.
@MainActor
package struct ScopedMapper<Input, Output: View> {
  private let authoringContext: AuthoringContext?
  private let apply: @MainActor (Input) -> Output

  package init(
    authoringContext: AuthoringContext? = currentAuthoringContext(),
    apply: @escaping @MainActor (Input) -> Output
  ) {
    self.authoringContext = authoringContext
    self.apply = apply
  }

  package func callAsFunction(
    _ input: Input
  ) -> ScopedBuilder<Output> {
    ScopedBuilder(authoringContext: authoringContext) {
      apply(input)
    }
  }
}
