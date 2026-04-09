public import Core

/// The set of property effects a transition can apply during a single
/// phase.
///
/// **Known limitation:** only opacity and offset are currently wired
/// into the renderer.  Custom transitions that use other modifiers
/// in their `body` will have those effects silently ignored until the
/// effect palette is expanded.
package struct TransitionModifiers: Sendable, Equatable {
  package var opacity: Double?
  package var offsetX: Int?
  package var offsetY: Int?

  package init(
    opacity: Double? = nil,
    offsetX: Int? = nil,
    offsetY: Int? = nil
  ) {
    self.opacity = opacity
    self.offsetX = offsetX
    self.offsetY = offsetY
  }

  package static let identity = TransitionModifiers()

  /// Merges `other` on top of `self`, with non-nil values from `other`
  /// taking precedence.
  package func merging(_ other: TransitionModifiers) -> TransitionModifiers {
    TransitionModifiers(
      opacity: other.opacity ?? opacity,
      offsetX: other.offsetX ?? offsetX,
      offsetY: other.offsetY ?? offsetY
    )
  }
}

/// A type-erased transition wrapper.
///
/// Built-in transitions (``opacity``, ``move(edge:)``, etc.) construct
/// `AnyTransition` values directly.  Custom ``Transition`` conformances
/// are wrapped via ``AnyTransition/init(_:)-<A: Transition>``.
public struct AnyTransition: Sendable {
  package let insertionModifiers: @Sendable () -> TransitionModifiers
  package let removalModifiers: @Sendable () -> TransitionModifiers

  package init(
    insertion: @escaping @Sendable () -> TransitionModifiers,
    removal: @escaping @Sendable () -> TransitionModifiers
  ) {
    insertionModifiers = insertion
    removalModifiers = removal
  }

  // MARK: - Built-ins

  /// No visual change — insertion/removal snap immediately.
  public static let identity = AnyTransition(
    insertion: { .identity },
    removal: { .identity }
  )

  /// Fades in and out via opacity.
  public static let opacity = AnyTransition(
    insertion: { TransitionModifiers(opacity: 0.0) },
    removal: { TransitionModifiers(opacity: 0.0) }
  )

  /// Slides from a specific edge on insertion and back to it on removal.
  public static func move(edge: Edge) -> AnyTransition {
    let (dx, dy) = moveOffset(for: edge)
    return AnyTransition(
      insertion: { TransitionModifiers(offsetX: dx, offsetY: dy) },
      removal: { TransitionModifiers(offsetX: dx, offsetY: dy) }
    )
  }

  /// Leading-in, trailing-out slide.
  public static let slide = AnyTransition.asymmetric(
    insertion: .move(edge: .leading),
    removal: .move(edge: .trailing)
  )

  /// Fixed offset shift.
  public static func offset(x: Int = 0, y: Int = 0) -> AnyTransition {
    AnyTransition(
      insertion: { TransitionModifiers(offsetX: x, offsetY: y) },
      removal: { TransitionModifiers(offsetX: x, offsetY: y) }
    )
  }

  /// Push: inserted content slides in from `edge`, removed content
  /// slides out the opposite side.
  public static func push(from edge: Edge) -> AnyTransition {
    let (dx, dy) = moveOffset(for: edge)
    let (oppositeDx, oppositeDy) = moveOffset(for: oppositeEdge(edge))
    return AnyTransition(
      insertion: { TransitionModifiers(offsetX: dx, offsetY: dy) },
      removal: { TransitionModifiers(offsetX: oppositeDx, offsetY: oppositeDy) }
    )
  }

  // MARK: - Combinators

  public func combined(with other: AnyTransition) -> AnyTransition {
    let selfInsertion = insertionModifiers
    let selfRemoval = removalModifiers
    let otherInsertion = other.insertionModifiers
    let otherRemoval = other.removalModifiers
    return AnyTransition(
      insertion: { selfInsertion().merging(otherInsertion()) },
      removal: { selfRemoval().merging(otherRemoval()) }
    )
  }

  public static func asymmetric(
    insertion: AnyTransition,
    removal: AnyTransition
  ) -> AnyTransition {
    let insertionGetter = insertion.insertionModifiers
    let removalGetter = removal.removalModifiers
    return AnyTransition(
      insertion: insertionGetter,
      removal: removalGetter
    )
  }

  // MARK: - Custom Transition support

  public init<T: Transition>(_ transition: T) {
    let insertionBody = transition.body(
      content: TransitionContent<T>(),
      phase: .willAppear
    )
    let removalBody = transition.body(
      content: TransitionContent<T>(),
      phase: .didDisappear
    )
    // Probe the authored body for opacity / offset effects.  More
    // sophisticated reflection can be added once the effect palette
    // expands beyond opacity + offset.
    let insertionModifiers = AnyTransition.extractModifiers(from: insertionBody)
    let removalModifiers = AnyTransition.extractModifiers(from: removalBody)
    self.insertionModifiers = { insertionModifiers }
    self.removalModifiers = { removalModifiers }
  }

  private static func extractModifiers<V: View>(from view: V) -> TransitionModifiers {
    // The initial slice does not walk arbitrary view trees to locate
    // opacity and offset modifiers.  Authored custom transitions that
    // rely on more than the built-in effect set should instead compose
    // `AnyTransition` directly using the built-in factories.
    //
    // This placeholder implementation returns identity modifiers and
    // leaves extension to a later pass that teaches the runtime how to
    // walk transition bodies.
    _ = view
    return .identity
  }
}

// MARK: - Helpers

private func moveOffset(for edge: Edge) -> (Int, Int) {
  switch edge {
  case .top: return (0, -10)
  case .bottom: return (0, 10)
  case .leading: return (-10, 0)
  case .trailing: return (10, 0)
  }
}

private func oppositeEdge(_ edge: Edge) -> Edge {
  switch edge {
  case .top: return .bottom
  case .bottom: return .top
  case .leading: return .trailing
  case .trailing: return .leading
  }
}
