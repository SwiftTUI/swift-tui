@_spi(Testing) package import SwiftTUICore
import SwiftTUIViews

/// Identifies a logical animatable slot on a ``ResolvedNode``.  Each
/// slot maps to a specific writeback destination in ``applyValue``.
///
/// Compound slots (``foregroundShapeStyle``, ``backgroundShapeStyle``,
/// ``borderShapeStyle``, ``shapeFillStyle``, ``shapeStrokeStyle``) carry
/// heterogeneous animatable values — the slot identifies the
/// destination but the wrapped ``AnyAnimatable`` determines the concrete
/// type (Color, LinearGradient, RadialGradient, TileStyle).
///
/// **Where is the slot stored on `ResolvedNode`?** Two separate paths
/// reach the rasterizer:
///
/// - **`.foregroundShapeStyle` / `.backgroundShapeStyle` /
///   `.borderShapeStyle`** — style set by a `.foregroundStyle(_:)` /
///   `.background(_:)` / `.border(_:)` modifier.  Stored on
///   `node.drawMetadata.baseStyle.foregroundStyle` (and friends), or
///   inherited through the environment.  Leaf views like `Text` and
///   `TextFigure` resolve these at paint time.
/// - **`.shapeFillStyle` / `.shapeStrokeStyle`** — style set by a
///   `Shape.fill(_:)` / `Shape.stroke(_:)` / `Shape.strokeBorder(_:)`
///   modifier.  Stored *inside* `node.drawPayload` as
///   `.shape(ShapePayload(operation: .fill(style:mode:)))` (or
///   `.stroke(...)`).  The rasterizer reads this directly and never
///   consults `baseStyle.foregroundStyle` when the shape operation
///   carries a non-nil style.
///
/// These are two independent storage locations for what SwiftUI
/// conceptually treats as "the fill of a shape", and animations
/// targeting one must NOT be confused for the other.  A
/// `Rectangle().fill(LinearGradient(...))` writes to `.shapeFillStyle`;
/// a `Rectangle().foregroundStyle(LinearGradient(...))` writes to
/// `.foregroundShapeStyle`.  Both extract and apply paths here are
/// slot-specific so the two writeback destinations stay separate.
package enum AnimatableSlot: Hashable, Sendable {
  case opacity
  case foregroundShapeStyle
  case backgroundShapeStyle
  case borderShapeStyle
  case borderBlendPhase
  case padding
  case offset
  case position
  case frameWidth
  case frameHeight
  case shapeFillStyle
  case shapeStrokeStyle
}

/// Keyed identifier for a single active animation.  Carries the view
/// ``Identity`` plus a ``Scope`` discriminator that selects between
/// the per-property slot path, the placed-level insertion offset
/// path, and the placed-level matched-geometry path.  Every (identity,
/// scope) pairing can be in flight independently.
package struct AnimationKey: Hashable, Sendable {
  /// Discriminates the per-key payload that lives on ``ActiveAnimation``
  /// and selects which apply path consumes it.
  package enum Scope: Hashable, Sendable {
    /// A property animation against a specific ``AnimatableSlot``.
    case property(AnimatableSlot)
    /// A transition-driven insertion offset animation (placed level).
    case insertionOffset
    /// A matched-geometry translation animation (placed level).
    case matchedGeometry
  }

  package var identity: Identity
  package var scope: Scope

  package init(identity: Identity, scope: Scope) {
    self.identity = identity
    self.scope = scope
  }

  /// Convenience initializer for the property scope, preserving the
  /// pre-Phase-4 call shape `AnimationKey(identity:slot:)` at every
  /// historic call site.
  package init(identity: Identity, slot: AnimatableSlot) {
    self.identity = identity
    self.scope = .property(slot)
  }
}
