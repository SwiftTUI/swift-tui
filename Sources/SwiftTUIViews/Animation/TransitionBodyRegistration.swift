import SwiftTUICore

// What a host registers for a transition with a body, and the scratch scope
// that evaluates a phase of that body which is not on screen.
//
// The live view graph only ever holds the identity phase of a body. The
// animation engine needs the other two phases as plain resolved trees: the
// values of `.willAppear` are where an insertion starts, and the values of
// `.didDisappear` are where a removal ends. `TransitionBodyRegistration`
// carries what is needed to produce such a tree later, after the frame that
// registered it has resolved: the body, and a copy of the host's resolve
// context that has no view graph and no registry.
//
// A registration travels inside the `AnyTransition` the host registers, as a
// body box that wraps the body. Every map the animation controller keeps
// transitions in therefore carries it, and so does a removal entry.

/// The body channel of a transition as its host last resolved it.
package struct TransitionBodyRegistration: Sendable {
  /// The body.
  package let box: any TransitionBodyBox
  /// The context the host resolved the identity phase under, without a view
  /// graph, registries or frame inputs. See
  /// ``ResolveContext/detachedForTransitionPhase()``.
  package let context: ResolveContext
  /// The identities of the boundary nodes whose child is the content, in the
  /// tree the host emitted, in tree order. A body that places `content` twice
  /// has two. The content of each is at its `content` child identity.
  package let boundaryIdentities: [Identity]

  package init(
    box: any TransitionBodyBox,
    context: ResolveContext,
    boundaryIdentities: [Identity]
  ) {
    self.box = box
    self.context = context
    self.boundaryIdentities = boundaryIdentities
  }

  /// The identity the body resolves at: the identity of the view the
  /// transition is attached to.
  package var identity: Identity { context.identity }

  /// The custom transition types of the body, for diagnostics.
  package var transitionTypeDescription: String {
    box.transitionTypeNames.joined(separator: " + ")
  }

  /// Evaluates the body in `phase` around a stand-in for the content and
  /// returns the resolved tree.
  ///
  /// The tree has the identities the live tree has for the same structure,
  /// because it resolves under the host's own identity and structural path.
  /// Each placement of `content` resolves to one leaf at the content's
  /// identity, of kind `transitionContentStandIn`, with the intrinsic size
  /// `contentSize` returns for that identity.
  ///
  /// Nothing here reaches live state. The context has no view graph, so no
  /// node is created, no state slot is read or written, no evaluator is
  /// installed and nothing is committed; a `@State` in a view the body adds
  /// reads its initial value. The context has no registry, so lifecycle
  /// handlers, tasks, gestures, focus bindings, key handlers and preference
  /// observers register nowhere. The task-local animation sinks are unbound
  /// for the duration, so a `.transition` or an `.animation(_:value:)` inside
  /// the body registers nothing with the animation controller. The ambient
  /// view node and authoring context are cleared, so a dynamic property
  /// cannot find the node of whatever was evaluating when this was called.
  @MainActor
  package func resolve(
    phase: TransitionPhase,
    contentSize: @escaping @MainActor (Identity) -> CellSize = { _ in .zero }
  ) -> TransitionPhaseTree {
    let recorder = TransitionStandInRecorder()
    let standIn = TransitionContentSource { contentContext in
      recorder.identities.append(contentContext.identity)
      return .value(
        ResolvedNode(
          identity: contentContext.identity,
          kind: .view(.transitionContentStandIn),
          environmentSnapshot: contentContext.environment,
          transactionSnapshot: contentContext.transaction,
          intrinsicSize: contentSize(contentContext.identity)
        )
      )
    }
    let box = box
    let context = context
    let roots = TransitionRegistrationStorage.$currentTaskSink.withValue(nil) {
      AnimationRegistrationStorage.$currentTaskSink.withValue(nil) {
        AnimationCompletionStorage.$currentTaskSink.withValue(nil) {
          ViewNodeContext.withCurrentValue(nil) {
            withAuthoringContext(nil) {
              box.resolveElementsWork(content: standIn, phase: phase, in: context).run()
            }
          }
        }
      }
    }
    return TransitionPhaseTree(roots: roots, contentIdentities: recorder.identities)
  }
}

/// A transition body evaluated in one phase around stand-ins for the content.
package struct TransitionPhaseTree: Sendable {
  /// The roots of the body, as the host would emit them for the phase.
  package var roots: [ResolvedNode]
  /// The identity of each content stand-in, in the order the body resolved
  /// them.
  package var contentIdentities: [Identity]

  package init(roots: [ResolvedNode], contentIdentities: [Identity]) {
    self.roots = roots
    self.contentIdentities = contentIdentities
  }
}

/// Collects the identities at which a scratch resolve placed its stand-ins.
@MainActor
private final class TransitionStandInRecorder {
  var identities: [Identity] = []
}

/// A body together with its host's registration.
struct RegisteredTransitionBodyBox: TransitionBodyBox {
  let registration: TransitionBodyRegistration

  var boundaryTypes: [ObjectIdentifier] { registration.box.boundaryTypes }
  var transitionTypeNames: [String] { registration.box.transitionTypeNames }
  var hostRegistration: TransitionBodyRegistration? { registration }

  @MainActor
  func resolveElementsWork(
    content: TransitionContentSource,
    phase: TransitionPhase,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    registration.box.resolveElementsWork(content: content, phase: phase, in: context)
  }
}

extension AnyTransition {
  /// The registration the host attached to the body channel, or `nil` for a
  /// transition without a body and for one no host has registered.
  package var bodyRegistration: TransitionBodyRegistration? {
    bodyBox?.hostRegistration
  }

  /// This transition with its body channel registered for `context`, the
  /// context the host resolved the identity phase under, and `nodes`, the
  /// trees that resolve emitted. A transition without a body is returned
  /// unchanged.
  package func registeringBody(
    in context: ResolveContext,
    emitting nodes: [ResolvedNode]
  ) -> AnyTransition {
    guard let bodyBox else { return self }
    // Never wrap a registration in a registration.
    let box = bodyBox.hostRegistration?.box ?? bodyBox
    let registration = TransitionBodyRegistration(
      box: box,
      context: context.detachedForTransitionPhase(),
      boundaryIdentities: transitionContentBoundaryIdentities(
        in: nodes, boundaryTypes: box.boundaryTypes)
    )
    return AnyTransition(
      insertion: insertionModifiers,
      removal: removalModifiers,
      bodyBox: RegisteredTransitionBodyBox(registration: registration),
      insertionAnimation: insertionAnimation,
      removalAnimation: removalAnimation,
      motion: motion
    )
  }
}

/// The identities of the boundary nodes in `nodes` whose child is the content
/// of a body with the given boundary types.
///
/// A body box places one boundary for each custom transition in it, nested
/// outermost first. Walking down from a root, the boundaries of the box are
/// met in that order, and the last one encloses the content. A boundary of
/// another type on the way belongs to a transition applied inside the body
/// (`apply(content:phase:)`) or to a view the body adds, and is passed over.
/// The walk stops at each content boundary, so it never enters the content.
func transitionContentBoundaryIdentities(
  in nodes: [ResolvedNode],
  boundaryTypes: [ObjectIdentifier]
) -> [Identity] {
  guard !boundaryTypes.isEmpty else { return [] }
  var identities: [Identity] = []
  func visit(_ node: ResolvedNode, expecting index: Int) {
    var index = index
    if node.kind == .view(.transitionContent), node.typeDiscriminator == boundaryTypes[index] {
      index += 1
      if index == boundaryTypes.count {
        identities.append(node.identity)
        return
      }
    }
    for child in node.children {
      visit(child, expecting: index)
    }
  }
  for node in nodes {
    visit(node, expecting: 0)
  }
  return identities
}

extension ResolveContext {
  /// This context for evaluating a transition body outside the live graph.
  ///
  /// The copy resolves at the same identity and structural path, under the
  /// same environment values and environment snapshot, with a plain
  /// transaction that requests no animation. It has no view graph, no
  /// runtime registry, no invalidation proxy, no observation bridge, no
  /// frame inputs and no deadline hook, so resolving under it cannot touch
  /// live state. The image asset resolver stays: it is a lookup, and an
  /// image in a body must resolve to the same node in every phase.
  package func detachedForTransitionPhase() -> ResolveContext {
    var detached = self
    var registries = PropagatedRegistries()
    registries.imageAssetResolver = imageAssetResolver
    registries.authoredFocusPressOverrides = propagated.authoredFocusPressOverrides
    registries.gestureSuppressionScopes = gestureSuppressionScopes
    detached.propagated = registries
    detached.transaction = TransactionSnapshot(debugSignature: transaction.debugSignature)
    detached.invalidatedIdentities = []
    detached.forceRootEvaluation = false
    detached.entityHosting = false
    detached.valueAnimationOrdinalCursor = 0
    return detached
  }
}
