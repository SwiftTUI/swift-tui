public import SwiftTUICore

// The concrete transition types and their erasure into `AnyTransition`.
//
// Every type here knows its own erased form (`ErasableTransition`). A
// built-in type erases to exactly the value of the matching `AnyTransition`
// static, so `.transition(OpacityTransition())` and `.transition(.opacity)`
// take one engine path. A combination, an asymmetric pair and an animated
// wrapper erase their parts recursively. A type without an erased form is a
// custom transition and becomes a body box.

/// A transition that knows its own type-erased form.
package protocol ErasableTransition {
  var erasedTransition: AnyTransition { get }
}

extension AnyTransition {
  /// Creates a type-erased transition from `transition`.
  ///
  /// A built-in transition type becomes the matching ``AnyTransition`` value,
  /// for example ``OpacityTransition`` becomes ``opacity``. A combination, an
  /// ``AsymmetricTransition`` and a transition with an attached animation are
  /// erased part by part. Any other type is kept as a custom body.
  public init<T: Transition>(_ transition: T) {
    if let erasable = transition as? any ErasableTransition {
      self = erasable.erasedTransition
    } else {
      self.init(
        insertion: { .identity },
        removal: { .identity },
        bodyBox: ConcreteTransitionBodyBox(transition: transition),
        insertionAnimation: .inherit,
        removalAnimation: .inherit,
        motion: { T.properties.hasMotion }
      )
    }
  }

  /// A transition that applies `active` while the view appears or disappears
  /// and `identity` while it is present.
  ///
  /// The modifier type must be `Sendable`. A modifier that declares its
  /// conformance in its primary declaration already is.
  public static func modifier<E: ViewModifier & Sendable>(
    active: E,
    identity: E
  ) -> AnyTransition {
    AnyTransition(ModifierTransition(active: active, identity: identity))
  }

  /// Attaches an animation to this transition.
  ///
  /// The animation replaces the animation of the transaction for this
  /// transition, on insertion and on removal. It also plays when the state
  /// change has no animation. Pass `nil` to make the transition snap.
  /// `withAnimation(nil)` and reduced motion still disable the transition.
  ///
  /// If the transition already carries its own animation, that animation
  /// stays in effect.
  public func animation(_ animation: Animation?) -> AnyTransition {
    AnyTransition(
      insertion: insertionModifiers,
      removal: removalModifiers,
      bodyBox: bodyBox,
      insertionAnimation: insertionAnimation.orInheriting(.explicit(animation)),
      removalAnimation: removalAnimation.orInheriting(.explicit(animation)),
      motion: motion
    )
  }
}

// MARK: - The effect primitive

/// Applies the effect values of one transition phase to its content.
///
/// The body of every built-in transition is its content with this modifier.
/// It carries the same `TransitionModifiers` value the effect channel of the
/// erased transition holds for the phase.
///
/// A body is made of nodes, so it can render the effects that have a node
/// form. Opacity is the ordinary opacity modifier. A fixed offset is the
/// ordinary offset layout behaviour, present in every phase (at zero in the
/// identity phase), so it renders exactly and animates as a slot. An
/// edge-relative move and a scale act on placed bounds: the distance of a move
/// is the placed size of the view, and a scale crops the placed rectangle.
/// Neither has a node form. Resolved with such a value, the modifier reports a
/// runtime issue and renders the content without that effect. The engine
/// plays those two through the effect channel of an erased transition, which
/// is what `combined(with:)` builds.
package struct TransitionPhaseEffectModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  /// The effect values for the phase. The identity phase carries the
  /// identity value of each channel the transition uses.
  package var modifiers: TransitionModifiers
  /// The name of the built-in transition type, for diagnostics.
  package var transitionTypeName: String

  package init(modifiers: TransitionModifiers, transitionTypeName: String = "") {
    self.modifiers = modifiers
    self.transitionTypeName = transitionTypeName
  }

  /// Whether the values include an effect a body cannot render: a move
  /// relative to an edge, or a scale other than one.
  package var hasPlacedOnlyEffect: Bool {
    !modifiers.moveEdges.isEmpty || modifiers.scale.map { $0.scale != 1 } == true
  }

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    if hasPlacedOnlyEffect {
      reportPlacedOnlyEffect(in: context)
    }
    let hasOffset = modifiers.offsetX != nil || modifiers.offsetY != nil
    guard hasOffset else {
      guard let opacity = modifiers.opacity else {
        return content.resolveWork(in: context).map { [$0] }
      }
      // Opacity is the ordinary opacity modifier, in every phase.
      return DrawMetadataModifier(metadata: DrawMetadata(opacity: opacity))
        .makeResolveWork(content: content, in: context)
    }
    // A fixed offset is the ordinary offset modifier, in every phase.
    let offset = OffsetModifier(x: modifiers.offsetX ?? 0, y: modifiers.offsetY ?? 0)
      .makeResolveWork(content: content, in: context)
    guard let opacity = modifiers.opacity else {
      return offset
    }
    return offset.map { nodes in
      nodes.map { node in
        var node = node
        node.drawMetadata = node.drawMetadata.merging(DrawMetadata(opacity: opacity))
        node.recordOpacityAnimationScope(context.transaction)
        return node
      }
    }
  }

  /// Reports the move or scale this modifier cannot render. During a live
  /// resolve the issue rides the frame the graph is resolving. A phase that
  /// is evaluated outside the graph has no frame of its own, so the issue
  /// goes to the queue the next frame tail drains.
  @MainActor
  private func reportPlacedOnlyEffect(in context: ResolveContext) {
    let effect = modifiers.moveEdges.isEmpty ? "a scale" : "a move relative to an edge"
    let name = transitionTypeName.isEmpty ? "A built-in transition" : transitionTypeName
    let issue = RuntimeIssue(
      severity: .warning,
      code: .Transition.unsupportedBuiltInBody,
      message:
        "\(name) was applied inside a transition body in a phase where it has \(effect). "
        + "A transition body cannot render \(effect), so the content is shown without it. "
        + "Combine the transitions instead, for example "
        + "MyTransition().combined(with: .move(edge: .leading)), which plays the built-in "
        + "effect beside the body.",
      identity: context.identity,
      source: "Transition.apply(content:phase:)"
    )
    if let viewGraph = context.viewGraph {
      viewGraph.recordFrameRuntimeIssue(issue)
    } else {
      ImperativeRuntimeIssueQueue.record(issue)
    }
  }
}

extension Transition where Self: ErasableTransition {
  /// The body of a built-in transition: the content with the effect values
  /// its erased form holds for `phase`.
  @MainActor
  func effectBody(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(
      TransitionPhaseEffectModifier(
        modifiers: erasedTransition.effectModifiers(for: phase),
        transitionTypeName: "\(Self.self)"
      )
    )
  }
}

// MARK: - Built-in transition types

/// A transition that fades the view in and out.
nonisolated public struct OpacityTransition: Transition, ErasableTransition {
  /// Creates an opacity transition.
  public init() {}

  /// The content with this transition's effect for `phase`.
  @MainActor
  public func body(content: Content, phase: TransitionPhase) -> some View {
    effectBody(content: content, phase: phase)
  }

  /// An opacity transition has no motion.
  public static let properties = TransitionProperties(hasMotion: false)

  package var erasedTransition: AnyTransition { .opacity }
}

/// A transition that changes nothing: the view appears and disappears at
/// once.
nonisolated public struct IdentityTransition: Transition, ErasableTransition {
  /// Creates an identity transition.
  public init() {}

  /// The content, unchanged in every phase.
  @MainActor
  public func body(content: Content, phase: TransitionPhase) -> Content {
    content
  }

  /// An identity transition has no motion.
  public static let properties = TransitionProperties(hasMotion: false)

  package var erasedTransition: AnyTransition { .identity }
}

/// A transition that moves the view in from an edge and back out to it.
///
/// The distance is the size of the view itself along the edge's axis. The
/// move acts on the placed frame of the view, so it cannot be part of another
/// transition's body: combine it with that transition instead of applying it
/// with ``Transition/apply(content:phase:)``.
nonisolated public struct MoveTransition: Transition, ErasableTransition {
  /// The edge the view moves from and to.
  public var edge: Edge

  /// Creates a transition that moves the view from and to `edge`.
  public init(edge: Edge) {
    self.edge = edge
  }

  /// The content with this transition's effect for `phase`.
  @MainActor
  public func body(content: Content, phase: TransitionPhase) -> some View {
    effectBody(content: content, phase: phase)
  }

  package var erasedTransition: AnyTransition { .move(edge: edge) }
}

/// A transition that shifts the view by a fixed number of cells.
///
/// Applied inside another transition's body with
/// ``Transition/apply(content:phase:)``, the shift is an ordinary offset: it
/// renders in every phase and animates.
nonisolated public struct OffsetTransition: Transition, ErasableTransition {
  /// The shift in cells: `width` columns and `height` rows.
  public var offset: CellSize

  /// Creates a transition that shifts the view by `offset` cells.
  public init(_ offset: CellSize) {
    self.offset = offset
  }

  /// The content with this transition's effect for `phase`.
  @MainActor
  public func body(content: Content, phase: TransitionPhase) -> some View {
    effectBody(content: content, phase: phase)
  }

  package var erasedTransition: AnyTransition {
    .offset(x: offset.width, y: offset.height)
  }
}

/// A transition that fades and moves the view in from an edge, and fades and
/// moves it out toward the opposite edge.
///
/// The move acts on the placed frame of the view, so only the fade can be
/// part of another transition's body. Combine the push with that transition
/// instead of applying it with ``Transition/apply(content:phase:)``.
nonisolated public struct PushTransition: Transition, ErasableTransition {
  /// The edge the view enters from.
  public var edge: Edge

  /// Creates a transition that pushes the view in from `edge`.
  public init(edge: Edge) {
    self.edge = edge
  }

  /// The content with this transition's effect for `phase`.
  @MainActor
  public func body(content: Content, phase: TransitionPhase) -> some View {
    effectBody(content: content, phase: phase)
  }

  package var erasedTransition: AnyTransition { .push(from: edge) }
}

/// A transition that scales the view around an anchor.
///
/// The scale changes the rendered bounds and clips to them. It does not take
/// part in layout, so it cannot be part of another transition's body: combine
/// it with that transition instead of applying it with
/// ``Transition/apply(content:phase:)``.
nonisolated public struct ScaleTransition: Transition, ErasableTransition {
  /// The scale the view has when it is not present.
  public var scale: Double
  /// The point of the view that stays in place.
  public var anchor: UnitPoint

  /// Creates a transition that scales the view from and to `scale` around
  /// `anchor`.
  public init(_ scale: Double, anchor: UnitPoint = .center) {
    self.scale = scale
    self.anchor = anchor
  }

  /// The content with this transition's effect for `phase`.
  @MainActor
  public func body(content: Content, phase: TransitionPhase) -> some View {
    effectBody(content: content, phase: phase)
  }

  package var erasedTransition: AnyTransition {
    .scale(scale: scale, anchor: anchor)
  }
}

/// A transition that moves the view in from its leading edge and out toward
/// its trailing edge.
///
/// The move acts on the placed frame of the view, so it cannot be part of
/// another transition's body: combine it with that transition instead of
/// applying it with ``Transition/apply(content:phase:)``.
nonisolated public struct SlideTransition: Transition, ErasableTransition {
  /// Creates a slide transition.
  public init() {}

  /// The content with this transition's effect for `phase`.
  @MainActor
  public func body(content: Content, phase: TransitionPhase) -> some View {
    effectBody(content: content, phase: phase)
  }

  package var erasedTransition: AnyTransition { .slide }
}

/// A transition that uses one transition when the view appears and another
/// when it disappears.
///
/// The body nests both bodies. The insertion body is in its
/// ``TransitionPhase/willAppear`` phase only while the view appears, and the
/// removal body is in its ``TransitionPhase/didDisappear`` phase only while
/// the view disappears. Each is in its identity phase otherwise, so the view
/// structure is the same in every phase.
nonisolated public struct AsymmetricTransition<Insertion: Transition, Removal: Transition>:
  Transition, ErasableTransition
{
  /// The transition to use when the view appears.
  public var insertion: Insertion
  /// The transition to use when the view disappears.
  public var removal: Removal

  /// Creates a transition from an insertion and a removal transition.
  public init(insertion: Insertion, removal: Removal) {
    self.insertion = insertion
    self.removal = removal
  }

  /// The content inside the insertion body, inside the removal body.
  @MainActor
  public func body(content: Content, phase: TransitionPhase) -> some View {
    removal.apply(
      content: insertion.apply(
        content: content,
        phase: phase == .willAppear ? .willAppear : .identity
      ),
      phase: phase == .didDisappear ? .didDisappear : .identity
    )
  }

  /// The pair has motion when either part has motion.
  @MainActor
  public static var properties: TransitionProperties {
    TransitionProperties(
      hasMotion: Insertion.properties.hasMotion || Removal.properties.hasMotion
    )
  }

  package var erasedTransition: AnyTransition {
    .asymmetric(insertion: AnyTransition(insertion), removal: AnyTransition(removal))
  }
}

// MARK: - Wrappers behind `some Transition`

/// The result of ``Transition/combined(with:)``.
nonisolated struct CombinedTransition<First: Transition, Second: Transition>:
  Transition, ErasableTransition
{
  var first: First
  var second: Second

  @MainActor
  func body(content: Content, phase: TransitionPhase) -> some View {
    second.apply(content: first.apply(content: content, phase: phase), phase: phase)
  }

  @MainActor
  static var properties: TransitionProperties {
    TransitionProperties(
      hasMotion: First.properties.hasMotion || Second.properties.hasMotion
    )
  }

  var erasedTransition: AnyTransition {
    AnyTransition(first).combined(with: AnyTransition(second))
  }
}

/// The result of ``Transition/animation(_:)``.
nonisolated struct AnimatedTransition<Base: Transition>: Transition, ErasableTransition {
  var base: Base
  var animation: Animation?

  // The attached animation belongs to the erased form, where the animation
  // engine reads it. The body is the base body.
  @MainActor
  func body(content: Content, phase: TransitionPhase) -> some View {
    base.apply(content: content, phase: phase)
  }

  @MainActor
  static var properties: TransitionProperties {
    Base.properties
  }

  var erasedTransition: AnyTransition {
    AnyTransition(base).animation(animation)
  }
}

/// The transition behind ``AnyTransition/modifier(active:identity:)``.
nonisolated struct ModifierTransition<Modifier: ViewModifier & Sendable>: Transition {
  var active: Modifier
  var identity: Modifier

  @MainActor
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(phase.isIdentity ? identity : active)
  }
}
