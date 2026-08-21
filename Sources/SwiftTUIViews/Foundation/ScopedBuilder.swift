import SwiftTUICore

/// A typed scoped view wrapper that preserves the original authoring scope.
package struct ScopedBuilder<Output: View>: PrimitiveView, ResolvableView {
  private let output: Output
  private let authoringContext: AuthoringContext?
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
    self.authoringContext = authoringContext

    // One route for resolvable and plain outputs alike:
    // `resolveViewElements` performs the identical resolvable dispatch this
    // closure used to special-case, and its two branches are where the
    // capture-bind pass runs — a resolvable output forwarded here without
    // its own `resolveView` still binds its `@State` ownership before its
    // `resolveElements` evaluates.
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

extension ScopedBuilder: AdditionalDynamicPropertyUpdating {
  package func ownsDynamicPropertyTraversal(ofStoredFieldAt index: Int) -> Bool {
    index == 0  // `output`
  }

  /// `ScopedBuilder` is transparent to its authored output: its resolve
  /// closure intentionally lowers that value without passing through another
  /// graph identity. Forward the pre-reuse update/certification for the same
  /// reason, under the scope that the closure will install for body access.
  package func updateAdditionalDynamicProperties(
    in context: AdditionalDynamicPropertyUpdateContext
  ) -> DynamicPropertyUpdateResult {
    // `nil` is an explicit fresh-destination capture. It must not inherit an
    // enclosing builder's ambient capture when transparent builders nest.
    let scope = authoringContext ?? context.destinationAuthoringContext
    return withAuthoringContext(scope) {
      runForwardedDynamicPropertyUpdates(on: output, in: context)
    }
  }

  package func hasAdditionalDynamicPropertyUpdateSurface() -> Bool {
    hasDynamicPropertyUpdateSurface(output)
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
