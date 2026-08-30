import SwiftTUICore

/// A typed scoped view wrapper that preserves the original authoring scope.
package struct ScopedBuilder<Output: View>: PrimitiveView, ResolvableView {
  // `var`, and read directly by `resolveElements`: the forwarded update pass
  // mutates this payload in place (plan 2026-08-30-001 §3.4). The initializer
  // used to capture `output` in a stored `resolveElementsClosure`, which would
  // have made a mutation here invisible to the resolve that consumes it.
  private var output: Output
  private let authoringContext: AuthoringContext?

  package init(
    scoped output: Output,
    authoringContext: AuthoringContext?
  ) {
    self.output = output
    self.authoringContext = authoringContext
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
    // A scoped builder with no captured scope resolves as a fresh authored
    // subtree at its destination, not inheriting whatever task-local authoring
    // context happened to be active in the parent wrapper.
    //
    // One route for resolvable and plain outputs alike: `resolveViewElements`
    // performs the resolvable dispatch, and its two branches are where the
    // capture-bind pass runs — a resolvable output forwarded here without its
    // own `resolveView` still binds its `@State` ownership before its
    // `resolveElements` evaluates.
    withAuthoringContext(authoringContext) {
      resolveViewElements(output, in: context)
    }
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
  package mutating func updateAdditionalDynamicProperties(
    in context: AdditionalDynamicPropertyUpdateContext
  ) -> DynamicPropertyUpdateResult {
    // `nil` is an explicit fresh-destination capture. It must not inherit an
    // enclosing builder's ambient capture when transparent builders nest.
    let scope = authoringContext ?? context.destinationAuthoringContext
    return withAuthoringContext(scope) {
      runForwardedDynamicPropertyUpdates(on: &output, in: context)
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
