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
  package var moveEdge: Edge?
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
    self.moveEdge = moveEdge
    self.scale = scale
  }

  package static let identity = TransitionModifiers()

  package var hasOffsetEffect: Bool {
    offsetX != nil || offsetY != nil || moveEdge != nil
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

    if let moveEdge, let edgeBasis {
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

  /// Merges `other` on top of `self`, with non-nil values from `other`
  /// taking precedence.
  package func merging(_ other: TransitionModifiers) -> TransitionModifiers {
    TransitionModifiers(
      opacity: other.opacity ?? opacity,
      offsetX: other.offsetX ?? offsetX,
      offsetY: other.offsetY ?? offsetY,
      moveEdge: other.moveEdge ?? moveEdge,
      scale: other.scale ?? scale
    )
  }
}

/// A type-erased transition wrapper.
///
/// Compose the built-in opacity, offset, and scale effects with
/// ``combined(with:)`` and ``asymmetric(insertion:removal:)``.
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

  /// Push: inserted content slides in from `edge`, removed content
  /// slides out the opposite side.
  public static func push(from edge: Edge) -> AnyTransition {
    return AnyTransition(
      insertion: { TransitionModifiers(moveEdge: edge) },
      removal: { TransitionModifiers(moveEdge: oppositeEdge(edge)) }
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

}

private func oppositeEdge(_ edge: Edge) -> Edge {
  switch edge {
  case .top: return .bottom
  case .bottom: return .top
  case .leading: return .trailing
  case .trailing: return .leading
  }
}
