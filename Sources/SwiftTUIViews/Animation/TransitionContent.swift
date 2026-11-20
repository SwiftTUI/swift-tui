import SwiftTUICore

// The content carrier a transition body places, and the erased bodies an
// `AnyTransition` stores.
//
// A body is never erased into `AnyView`. Its content is a
// `TransitionContentSource`: `@MainActor` closures over the view the
// transition was applied to, the way `ViewModifierContent` carries a
// modifier's content. A `TransitionBodyBox` is the `Sendable` form of one or
// more bodies; it resolves in any phase, in any `ResolveContext`, around any
// source, which is what lets the engine evaluate a phase that is not on
// screen around a stand-in for the live content
// (`TransitionBodyRegistration`).

/// The erased content a transition body places.
@MainActor
package struct TransitionContentSource {
  /// Resolves the content as one node in the given context.
  package let resolveWork: @MainActor (ResolveContext) -> ResolveWork<ResolvedNode>

  package init(
    resolveWork: @escaping @MainActor (ResolveContext) -> ResolveWork<ResolvedNode>
  ) {
    self.resolveWork = resolveWork
  }

  /// The live content of a modifier: the view the transition was applied to.
  package init<Base: View>(_ inputs: ModifierContentInputs<Base>) {
    resolveWork = { context in
      inputs.resolveWork(in: context)
    }
  }
}

/// The stand-in for the view a ``Transition`` is applied to.
///
/// ``Transition/body(content:phase:)`` receives a value of this type as
/// `content`. Place it in the result as you would place any view. Authors
/// write `Content`, the alias the protocol declares.
///
/// Each placement resolves to one boundary around the view, so a modifier
/// the body applies to `content` (an opacity, a clip shape, a draw effect)
/// stays separate from the modifiers of the view itself. A body that places
/// `content` more than once mounts the view once for each placement, with
/// separate state and lifecycle. In the body a removal draws, each placement
/// shows the view as it was last drawn.
public struct TransitionContent<T: Transition>: PrimitiveView, IterativeResolvableView {
  private let source: TransitionContentSource

  package init(source: TransitionContentSource) {
    self.source = source
  }

  /// The carrier is a primitive view. It has no body to evaluate.
  public var body: Never {
    fatalError("Transition.Content is an opaque transition-content carrier.")
  }

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    // One boundary node at the placement's identity, with the content as its
    // single child. The node has the default intrinsic layout and no draw or
    // semantic data of its own, so it passes layout, drawing and semantics
    // through. A modifier that stamps its content lands on the boundary.
    //
    // The type discriminator names the transition whose body placed this
    // boundary. It is how a host tells its own boundaries from those of
    // another transition inside its body or its content.
    let contentContext = context.child(component: .named("content"))
    return source.resolveWork(contentContext).map { contentNode in
      [
        ResolvedNode(
          identity: context.identity,
          kind: .view(.transitionContent),
          typeDiscriminator: Self.boundaryType,
          children: [contentNode],
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction
        )
      ]
    }
  }

  /// The type discriminator of the boundary nodes this carrier emits.
  nonisolated static var boundaryType: ObjectIdentifier {
    ObjectIdentifier(Self.self)
  }
}

/// Evaluates one transition body as a view body, so it runs under the same
/// authoring context, observation tracking and body-evaluation funnel as any
/// composite view.
struct TransitionBodyHost<T: Transition>: View {
  let transition: T
  let content: TransitionContentSource
  let phase: TransitionPhase

  var body: T.Body {
    transition.body(content: TransitionContent(source: content), phase: phase)
  }
}

/// The erased body channel of an ``AnyTransition``.
package protocol TransitionBodyBox: Sendable {
  /// Resolves the body for `phase` around `content` in `context`.
  ///
  /// The three inputs are independent. The live path passes the identity
  /// phase, the registering modifier's context and the live content. A caller
  /// may pass another phase, another context, and a source that resolves a
  /// stand-in instead of the live content.
  @MainActor
  func resolveElementsWork(
    content: TransitionContentSource,
    phase: TransitionPhase,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]>

  /// The type discriminators of the boundary nodes on the way from a root
  /// of this body to its content, outermost first: one for each custom
  /// transition in the box. The last one is the boundary whose child is the
  /// content.
  var boundaryTypes: [ObjectIdentifier] { get }

  /// The names of the custom transition types in the box, for diagnostics.
  var transitionTypeNames: [String] { get }

  /// What the host recorded when it registered this body with the animation
  /// engine, or `nil` for a body no host has registered.
  var hostRegistration: TransitionBodyRegistration? { get }
}

extension TransitionBodyBox {
  package var hostRegistration: TransitionBodyRegistration? { nil }
}

/// The body of one custom transition value.
struct ConcreteTransitionBodyBox<T: Transition>: TransitionBodyBox {
  let transition: T

  var boundaryTypes: [ObjectIdentifier] { [TransitionContent<T>.boundaryType] }
  var transitionTypeNames: [String] { ["\(T.self)"] }

  @MainActor
  func resolveElementsWork(
    content: TransitionContentSource,
    phase: TransitionPhase,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    resolveViewElementsWork(
      TransitionBodyHost(transition: transition, content: content, phase: phase),
      in: context
    )
  }
}

/// A body that is active in one phase only and shows its identity phase in
/// the others: one side of an asymmetric transition.
struct PhaseLimitedTransitionBodyBox: TransitionBodyBox {
  let base: any TransitionBodyBox
  let activePhase: TransitionPhase

  var boundaryTypes: [ObjectIdentifier] { base.boundaryTypes }
  var transitionTypeNames: [String] { base.transitionTypeNames }

  @MainActor
  func resolveElementsWork(
    content: TransitionContentSource,
    phase: TransitionPhase,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    base.resolveElementsWork(
      content: content,
      phase: phase == activePhase ? phase : .identity,
      in: context
    )
  }
}

/// Two bodies, the outer one wrapping the inner one.
struct NestedTransitionBodyBox: TransitionBodyBox {
  let inner: any TransitionBodyBox
  let outer: any TransitionBodyBox

  var boundaryTypes: [ObjectIdentifier] { outer.boundaryTypes + inner.boundaryTypes }
  var transitionTypeNames: [String] { outer.transitionTypeNames + inner.transitionTypeNames }

  @MainActor
  func resolveElementsWork(
    content: TransitionContentSource,
    phase: TransitionPhase,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    let inner = inner
    let innerContent = TransitionContentSource { innerContext in
      resolveViewWork(
        ErasedTransitionBody(box: inner, content: content, phase: phase),
        in: innerContext
      )
    }
    return outer.resolveElementsWork(content: innerContent, phase: phase, in: context)
  }
}

/// Composes the body channels of two transitions. `nil` is the absent body.
func nestedTransitionBodyBox(
  inner: (any TransitionBodyBox)?,
  outer: (any TransitionBodyBox)?
) -> (any TransitionBodyBox)? {
  switch (inner, outer) {
  case (nil, nil):
    nil
  case (let inner?, nil):
    inner
  case (nil, let outer?):
    outer
  case (let inner?, let outer?):
    NestedTransitionBodyBox(inner: inner, outer: outer)
  }
}

/// An erased body as the content of the body that wraps it.
private struct ErasedTransitionBody: PrimitiveView, IterativeResolvableView {
  let box: any TransitionBodyBox
  let content: TransitionContentSource
  let phase: TransitionPhase

  func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    box.resolveElementsWork(content: content, phase: phase, in: context)
  }
}
