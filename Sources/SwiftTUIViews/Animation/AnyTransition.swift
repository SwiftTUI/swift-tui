public import SwiftTUICore

/// A scale effect carried by one phase of a transition.
package struct TransitionScaleEffect: Sendable, Equatable {
  package var scale: Double
  package var anchor: UnitPoint

  package init(scale: Double, anchor: UnitPoint) {
    self.scale = scale
    self.anchor = anchor
  }
}

/// The set of property and geometry effects a transition can apply during a
/// single phase.
package struct TransitionModifiers: Sendable, Equatable {
  package var opacity: Double?
  package var offsetX: Int?
  package var offsetY: Int?
  package var moveEdges: [Edge]
  package var moveEdge: Edge? {
    moveEdges.count == 1 ? moveEdges[0] : nil
  }
  package var scale: TransitionScaleEffect?

  package init(
    opacity: Double? = nil,
    offsetX: Int? = nil,
    offsetY: Int? = nil,
    moveEdge: Edge? = nil,
    scale: TransitionScaleEffect? = nil
  ) {
    self.opacity = opacity
    self.offsetX = offsetX
    self.offsetY = offsetY
    self.moveEdges = moveEdge.map { [$0] } ?? []
    self.scale = scale
  }

  package static let identity = TransitionModifiers()

  package var hasOffsetEffect: Bool {
    offsetX != nil || offsetY != nil || !moveEdges.isEmpty
  }

  /// Resolves an edge-relative `move` into a concrete cell delta.
  ///
  /// - Parameter edgeBasis: the box the edge is measured against. SwiftUI
  ///   moves the view "towards the specified edge *of the view*", so this is
  ///   the moving view's own placed size wherever the caller has it. Passing
  ///   the render surface instead makes a small view start a whole screen
  ///   away, which reads as a pop rather than a slide once anything clips it
  ///   (and, inside a narrow container, is invisible until the final frames).
  ///   The surface remains the documented fallback for the pre-layout
  ///   resolved-level removal path, where the view has no placed rect yet.
  ///   `nil` drops the edge component entirely.
  package func resolvedOffset(edgeBasis: CellSize?) -> (x: Int, y: Int) {
    var x = offsetX ?? 0
    var y = offsetY ?? 0

    for moveEdge in edgeBasis == nil ? [] : moveEdges {
      guard let edgeBasis else { continue }
      switch moveEdge {
      case .top:
        y -= edgeBasis.height
      case .bottom:
        y += edgeBasis.height
      case .leading:
        x -= edgeBasis.width
      case .trailing:
        x += edgeBasis.width
      }
    }

    return (x, y)
  }

  package func resolvingEdgeOffset(edgeBasis: CellSize?) -> TransitionModifiers {
    guard hasOffsetEffect else { return self }
    let offset = resolvedOffset(edgeBasis: edgeBasis)
    return TransitionModifiers(
      opacity: opacity,
      offsetX: offset.x,
      offsetY: offset.y,
      scale: scale
    )
  }

  /// Composes opacity and translations. Retain every edge-relative term
  /// until placement provides the size, including repeated and opposite edges.
  package func merging(_ other: TransitionModifiers) -> TransitionModifiers {
    var result = TransitionModifiers(
      opacity: opacity == nil && other.opacity == nil
        ? nil
        : (opacity ?? 1) * (other.opacity ?? 1),
      offsetX: offsetX == nil && other.offsetX == nil
        ? nil
        : (offsetX ?? 0) + (other.offsetX ?? 0),
      offsetY: offsetY == nil && other.offsetY == nil
        ? nil
        : (offsetY ?? 0) + (other.offsetY ?? 0),
      scale: other.scale ?? scale
    )
    result.moveEdges = moveEdges + other.moveEdges
    return result
  }

  /// Whether these effects move or resize the view. Opacity alone does not.
  /// This is the effect channel's contribution to
  /// ``TransitionProperties/hasMotion``.
  package var hasMotion: Bool {
    hasOffsetEffect || scale != nil
  }

  /// The values the same channels hold in the identity phase: opacity 1,
  /// zero offsets, no edge displacement and scale 1. A channel that is absent
  /// stays absent.
  package var identityCounterpart: TransitionModifiers {
    TransitionModifiers(
      opacity: opacity.map { _ in 1 },
      offsetX: offsetX.map { _ in 0 },
      offsetY: offsetY.map { _ in 0 },
      scale: scale.map { TransitionScaleEffect(scale: 1, anchor: $0.anchor) }
    )
  }

}

/// The animation a transition carries for one direction.
package enum TransitionAnimationOverride: Sendable, Equatable {
  /// The transition has no animation of its own; the transaction decides.
  case inherit
  /// The transition's own animation replaces the transaction's. `nil` snaps.
  /// Indirect, so the common inheriting transition stays one word wide.
  indirect case explicit(Animation?)

  /// The override of a combination: the first part that carries its own
  /// animation decides for the whole combination.
  package func orInheriting(_ other: TransitionAnimationOverride) -> TransitionAnimationOverride {
    self == .inherit ? other : self
  }
}

/// A type-erased transition wrapper.
///
/// Compose the built-in opacity, offset, and scale effects with
/// ``combined(with:)`` and ``asymmetric(insertion:removal:)``, or erase a
/// ``Transition`` with ``init(_:)``.
///
/// A value has two channels. The effect channel is the opacity, offset, move
/// and scale values the built-in transitions declare. The body channel is the
/// body of a custom ``Transition``. A combination can carry both.
public struct AnyTransition: Sendable {
  package let insertionModifiers: @Sendable () -> TransitionModifiers
  package let removalModifiers: @Sendable () -> TransitionModifiers
  /// The body channel: the erased bodies of the custom ``Transition`` values
  /// in this transition, or `nil` when it has effects only.
  package let bodyBox: (any TransitionBodyBox)?
  /// The transition's own animation for insertion.
  package let insertionAnimation: TransitionAnimationOverride
  /// The transition's own animation for removal.
  package let removalAnimation: TransitionAnimationOverride
  /// Reports ``TransitionProperties/hasMotion`` for the whole transition. A
  /// closure, because a custom transition's `properties` are main-actor
  /// isolated while this value is built from any isolation.
  package let motion: @MainActor @Sendable () -> Bool

  /// An effects-only transition with no animation of its own. Its motion is
  /// read from the effect values.
  package init(
    insertion: @escaping @Sendable () -> TransitionModifiers,
    removal: @escaping @Sendable () -> TransitionModifiers
  ) {
    self.init(
      insertion: insertion,
      removal: removal,
      bodyBox: nil,
      insertionAnimation: .inherit,
      removalAnimation: .inherit,
      motion: { insertion().hasMotion || removal().hasMotion }
    )
  }

  package init(
    insertion: @escaping @Sendable () -> TransitionModifiers,
    removal: @escaping @Sendable () -> TransitionModifiers,
    bodyBox: (any TransitionBodyBox)?,
    insertionAnimation: TransitionAnimationOverride,
    removalAnimation: TransitionAnimationOverride,
    motion: @escaping @MainActor @Sendable () -> Bool
  ) {
    insertionModifiers = insertion
    removalModifiers = removal
    self.bodyBox = bodyBox
    self.insertionAnimation = insertionAnimation
    self.removalAnimation = removalAnimation
    self.motion = motion
  }

  /// Whether this transition moves or resizes the view, as
  /// ``TransitionProperties/hasMotion`` reports it.
  @MainActor
  package var hasMotion: Bool {
    motion()
  }

  /// The effect values the effect channel shows in `phase`. The identity
  /// phase holds the identity value of every channel either direction uses.
  package func effectModifiers(for phase: TransitionPhase) -> TransitionModifiers {
    switch phase {
    case .willAppear:
      insertionModifiers()
    case .didDisappear:
      removalModifiers()
    case .identity:
      insertionModifiers().identityCounterpart
        .merging(removalModifiers().identityCounterpart)
    }
  }

  // MARK: - Built-ins

  /// No visual change: insertion/removal snap immediately.
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
    return AnyTransition(
      insertion: { TransitionModifiers(moveEdge: edge) },
      removal: { TransitionModifiers(moveEdge: edge) }
    )
  }

  /// Leading-in, trailing-out slide.
  public static let slide = AnyTransition.asymmetric(
    insertion: .move(edge: .leading),
    removal: .move(edge: .trailing)
  )

  /// Scales from and to a nearly collapsed view around its center.
  ///
  /// SwiftUI uses a small nonzero factor instead of zero so the active
  /// transform remains nonsingular.
  public static let scale = AnyTransition(
    insertion: {
      TransitionModifiers(
        scale: TransitionScaleEffect(scale: 1e-5, anchor: .center)
      )
    },
    removal: {
      TransitionModifiers(
        scale: TransitionScaleEffect(scale: 1e-5, anchor: .center)
      )
    }
  )

  /// Scales from and to `scale` around `anchor` without changing layout.
  public static func scale(
    scale: Double,
    anchor: UnitPoint = .center
  ) -> AnyTransition {
    AnyTransition(
      insertion: {
        TransitionModifiers(
          scale: TransitionScaleEffect(scale: scale, anchor: anchor)
        )
      },
      removal: {
        TransitionModifiers(
          scale: TransitionScaleEffect(scale: scale, anchor: anchor)
        )
      }
    )
  }

  /// Fixed offset shift.
  public static func offset(x: Int = 0, y: Int = 0) -> AnyTransition {
    AnyTransition(
      insertion: { TransitionModifiers(offsetX: x, offsetY: y) },
      removal: { TransitionModifiers(offsetX: x, offsetY: y) }
    )
  }

  /// Push: inserted content fades and slides in from `edge`; removed
  /// content fades and slides out the opposite side.
  public static func push(from edge: Edge) -> AnyTransition {
    return AnyTransition(
      insertion: { TransitionModifiers(opacity: 0, moveEdge: edge) },
      removal: { TransitionModifiers(opacity: 0, moveEdge: oppositeEdge(edge)) }
    )
  }

  // MARK: - Combinators

  /// Combines this transition with another.
  ///
  /// Opacities multiply and offsets add. The scale of `other` replaces this
  /// transition's scale. The body of `other` wraps this transition's body.
  /// When more than one part carries its own animation, the first one decides
  /// for the whole combination.
  public func combined(with other: AnyTransition) -> AnyTransition {
    let selfInsertion = insertionModifiers
    let selfRemoval = removalModifiers
    let otherInsertion = other.insertionModifiers
    let otherRemoval = other.removalModifiers
    let selfMotion = motion
    let otherMotion = other.motion
    return AnyTransition(
      insertion: { selfInsertion().merging(otherInsertion()) },
      removal: { selfRemoval().merging(otherRemoval()) },
      bodyBox: nestedTransitionBodyBox(inner: bodyBox, outer: other.bodyBox),
      insertionAnimation: insertionAnimation.orInheriting(other.insertionAnimation),
      removalAnimation: removalAnimation.orInheriting(other.removalAnimation),
      motion: { selfMotion() || otherMotion() }
    )
  }

  /// Uses `insertion` when the view appears and `removal` when it disappears.
  public static func asymmetric(
    insertion: AnyTransition,
    removal: AnyTransition
  ) -> AnyTransition {
    let insertionGetter = insertion.insertionModifiers
    let removalGetter = removal.removalModifiers
    let insertionMotion = insertion.motion
    let removalMotion = removal.motion
    return AnyTransition(
      insertion: insertionGetter,
      removal: removalGetter,
      bodyBox: nestedTransitionBodyBox(
        inner: insertion.bodyBox.map {
          PhaseLimitedTransitionBodyBox(base: $0, activePhase: .willAppear)
        },
        outer: removal.bodyBox.map {
          PhaseLimitedTransitionBodyBox(base: $0, activePhase: .didDisappear)
        }
      ),
      insertionAnimation: insertion.insertionAnimation,
      removalAnimation: removal.removalAnimation,
      motion: { insertionMotion() || removalMotion() }
    )
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
