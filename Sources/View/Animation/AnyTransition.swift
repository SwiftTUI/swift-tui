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
/// are wrapped via ``AnyTransition/init(_:)``.
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

  @MainActor
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

  /// Walks a custom ``Transition/body`` output tree and aggregates
  /// opacity/offset effects into a single `TransitionModifiers`
  /// value.
  ///
  /// Preferred traversal order:
  /// - future generic modifier-chain traversal via
  ///   ``TransitionEffectProbeTraversable``
  /// - `Mirror` reflection for arbitrary authored wrapper views that
  ///   cannot yet expose a structured traversal hook
  ///
  /// Effects from modifiers the runtime does not yet understand are
  /// silently ignored; the `TransitionModifiers` type documents the
  /// current palette (opacity + offset).
  @MainActor
  private static func extractModifiers<V: View>(from view: V) -> TransitionModifiers {
    var result = TransitionModifiers.identity
    walk(view: view, into: &result)
    return result
  }

  @MainActor
  fileprivate static func walk(view: Any, into result: inout TransitionModifiers) {
    if let traversable = view as? any TransitionEffectProbeTraversable {
      traversable.collectTransitionEffects(into: &result)
      return
    }

    // Otherwise use Mirror reflection to descend into any wrapper
    // that exposes a conventional child field.  View builders,
    // generic wrappers, and user-authored compositions all fall
    // into this path.
    let mirror = Mirror(reflecting: view)
    for child in mirror.children {
      guard let label = child.label else { continue }
      if label == "content" || label == "base" || label == "body"
        || label == "children" || label == "wrapped" || label == "value"
      {
        if let children = child.value as? [Any] {
          for entry in children { walk(view: entry, into: &result) }
        } else {
          walk(view: child.value, into: &result)
        }
      }
    }
  }
}

/// Modifier-side transition semantic hook.
///
/// Built-in modifiers should report transition effects here instead of
/// attaching semantics to concrete wrapper views.
@MainActor
package protocol TransitionEffectProvidingModifier: ViewModifier {
  func contributeTransitionEffects(into modifiers: inout TransitionModifiers)
}

/// Structured traversal hook for authored transition bodies.
@MainActor
package protocol TransitionEffectProbeTraversable {
  func collectTransitionEffects(into modifiers: inout TransitionModifiers)
}

extension ModifiedContent: TransitionEffectProbeTraversable
where Content: View, Modifier: ViewModifier {
  package func collectTransitionEffects(into modifiers: inout TransitionModifiers) {
    if let provider = modifier as? any TransitionEffectProvidingModifier {
      provider.contributeTransitionEffects(into: &modifiers)
    }
    AnyTransition.walk(view: content, into: &modifiers)
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
