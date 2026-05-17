@_spi(Testing) package import SwiftTUICore
package import SwiftTUIViews

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

/// Snapshot of every tracked animatable slot's value for one view
/// ``Identity`` after a resolve pass.  Stored per-identity in
/// ``AnimationController/previousSnapshots`` and diffed against the
/// next frame's snapshot to detect changes.
package struct AnimatableSnapshot: Sendable {
  package var values: [AnimatableSlot: AnyAnimatable]

  package init(values: [AnimatableSlot: AnyAnimatable] = [:]) {
    self.values = values
  }

  package subscript(slot: AnimatableSlot) -> AnyAnimatable? {
    get { values[slot] }
    set { values[slot] = newValue }
  }

  /// Extracts every animatable slot from the given resolved node.
  /// Slots whose source value is missing or not-Animatable are
  /// simply absent from the result dictionary.
  package static func extract(from node: ResolvedNode) -> AnimatableSnapshot {
    var snapshot = AnimatableSnapshot()

    // Opacity (Double)
    if let opacity = node.drawMetadata.baseStyle.explicitOpacity {
      snapshot[.opacity] = AnyAnimatable(opacity)
    }

    // Foreground/background/border shape styles.  `.foregroundStyle(color)`
    // on a generic view writes to the environment rather than to the
    // node's own draw metadata; leaf views such as `TextFigure` pick it
    // up from the environment at rasterize time.  Prefer the node's
    // local draw metadata and fall back to the environment snapshot so
    // environment-carried styles are still animated.  Note this is a
    // coalesce — an untracked local style (e.g. `.semantic`) still
    // falls through to the environment, matching the pre-Phase-3
    // extractColor behaviour.
    if let fg = extractAnimatableShapeStyle(
      from: node.drawMetadata.baseStyle.foregroundStyle
    )
      ?? extractAnimatableShapeStyle(
        from: node.environmentSnapshot.style.foregroundStyle
      )
    {
      snapshot[.foregroundShapeStyle] = fg
    }

    if let bg = extractAnimatableShapeStyle(
      from: node.drawMetadata.baseStyle.backgroundStyle
    ) {
      snapshot[.backgroundShapeStyle] = bg
    }

    if let border = extractAnimatableShapeStyle(
      from: node.drawMetadata.borderShapeStyle
    ) {
      snapshot[.borderShapeStyle] = border
    }

    // Shape draw payloads.  `Rectangle().fill(LinearGradient(...))` and
    // friends write their style into ``DrawPayload/shape(_:)``'s
    // ``ShapePayload/operation``, NOT into `baseStyle.foregroundStyle`.
    // Extract those styles into dedicated slots so Shape.fill / .stroke
    // animations flow through the same interpolation pipeline as the
    // `.foregroundStyle(_:)` modifier path.  A nil operation style
    // means the shape inherits from `baseStyle.foregroundStyle` at
    // paint time — in that case the .foregroundShapeStyle extraction
    // above already covers it.
    if case .shape(let shapePayload) = node.drawPayload {
      switch shapePayload.operation {
      case .fill(let style, _):
        if let fill = extractAnimatableShapeStyle(from: style) {
          snapshot[.shapeFillStyle] = fill
        }
      case .stroke(let style, _, _, _):
        if let stroke = extractAnimatableShapeStyle(from: style) {
          snapshot[.shapeStrokeStyle] = stroke
        }
      }
    }

    // Layout-derived slots.
    switch node.layoutBehavior {
    case .padding(let insets):
      snapshot[.padding] = AnyAnimatable(insets)
    case .offset(let x, let y):
      snapshot[.offset] = AnyAnimatable(AnimatablePair(x, y))
    case .position(let x, let y):
      snapshot[.position] = AnyAnimatable(AnimatablePair(x, y))
    case .frame(let width, let height, _):
      if let width { snapshot[.frameWidth] = AnyAnimatable(width) }
      if let height { snapshot[.frameHeight] = AnyAnimatable(height) }
    case .border(_, _, _, _, let blend, let blendPhase, _):
      // Only populate the phase slot when a ``BorderBlend`` is attached.
      // `.border` layouts without a blend have nothing to animate here —
      // the static zero default would otherwise create a phantom
      // "identity → 0" diff on any border that ever transitioned from
      // a blend to a plain foreground.
      if blend != nil {
        snapshot[.borderBlendPhase] = AnyAnimatable(blendPhase)
      }
    case .flexibleFrame(
      let minWidth, let idealWidth, let maxWidth,
      let minHeight, let idealHeight, let maxHeight,
      _):
      // Pick a representative finite dimension for each axis: prefer
      // max, then ideal, then min.  Most user-authored animation targets
      // either `.frame(maxWidth: X)` (stretching with a cap) or a
      // single fixed `.frame(width: X)` — the latter already takes the
      // `.frame` branch above.  Apply will update the same dimension
      // this extract selected, keeping the other dimensions untouched.
      if let w = firstFiniteValue(of: [maxWidth, idealWidth, minWidth]) {
        snapshot[.frameWidth] = AnyAnimatable(w)
      }
      if let h = firstFiniteValue(of: [maxHeight, idealHeight, minHeight]) {
        snapshot[.frameHeight] = AnyAnimatable(h)
      }
    default:
      break
    }

    return snapshot
  }

  /// Back-compat shim: a lot of pre-Phase-3 tests assert on
  /// `snapshot.foregroundColor` directly.  Expose a computed accessor
  /// that unwraps the ``.foregroundShapeStyle`` slot when it happens to
  /// carry a plain `Color`, so the assertion set doesn't have to move
  /// wholesale to the new subscript form.
  package var foregroundColor: Color? {
    self[.foregroundShapeStyle]?.unwrap(as: Color.self)
  }

  package var backgroundColor: Color? {
    self[.backgroundShapeStyle]?.unwrap(as: Color.self)
  }

  package var borderColor: Color? {
    self[.borderShapeStyle]?.unwrap(as: Color.self)
  }

  package var opacity: Double? {
    self[.opacity]?.unwrap(as: Double.self)
  }

  package var frameWidth: Int? {
    self[.frameWidth]?.unwrap(as: Int.self)
  }

  package var frameHeight: Int? {
    self[.frameHeight]?.unwrap(as: Int.self)
  }

  /// Unwraps an ``AnyShapeStyle`` to a concrete animatable value
  /// the controller can interpolate.  Returns `nil` for shape
  /// styles that can't be reduced to a single animatable
  /// conformance (semantic tokens, terminal chrome, etc.).
  private static func extractAnimatableShapeStyle(
    from style: AnyShapeStyle?
  ) -> AnyAnimatable? {
    guard let style else { return nil }
    switch style {
    case .color(let color):
      return AnyAnimatable(color)
    case .linearGradient(let gradient):
      return AnyAnimatable(gradient)
    case .radialGradient(let gradient):
      return AnyAnimatable(gradient)
    case .tileStyle(let tile):
      return AnyAnimatable(tile)
    case .opacity(let inner, _):
      return extractAnimatableShapeStyle(from: inner)
    case .terminalChrome, .semantic:
      return nil
    }
  }

  private static func firstFiniteValue(of dimensions: [ProposedDimension?]) -> Int? {
    for dimension in dimensions {
      if case .finite(let value) = dimension {
        return value
      }
    }
    return nil
  }
}

/// Per-kind payload carried on ``ActiveAnimation``.  The case selects
/// how the animation is sampled and how its output is applied to the
/// resolved/placed tree.
package enum AnimationKind: Sendable {
  /// A property animation on a specific ``AnimatableSlot``.  The
  /// `from`/`to` values are interpolated and written back through
  /// ``AnimationController/applyValue``.
  case property(from: AnyAnimatable, to: AnyAnimatable)
  /// A transition-driven insertion offset animation applied at
  /// placed level (cannot route through the slot path because it
  /// operates on intrinsic-layout leaves).  The `from` tuple holds
  /// the starting (x, y) delta; the animation interpolates from
  /// `from` toward (0, 0).
  case insertionOffset(from: (x: Int, y: Int))
  /// A matched-geometry translation animation between two placed
  /// bounds.  At progress 0 the target identity renders at
  /// `fromBounds`; at progress 1 it renders at its natural new
  /// bounds (looked up in the current placed tree).
  case matchedGeometry(fromBounds: CellRect)
}

/// An animation currently in flight for one ``AnimationKey``.
package struct ActiveAnimation: Sendable {
  /// The per-kind payload.  Selects how this animation is sampled
  /// and applied to the tree.
  package var kind: AnimationKind
  package var animationBox: AnimationBox
  package var startTime: MonotonicInstant
  /// Per-key persistent state threaded into
  /// ``CustomAnimation/animate(value:time:context:)`` on each tick.
  /// Built-in bezier/spring curves ignore this; custom animations can
  /// use it to persist bookkeeping across frames.
  package var customState: AnimationState = .init()
  /// Batch identifier copied from ``TransactionSnapshot/animationBatchID``
  /// at enqueue time.  Used to look up a registered completion closure
  /// when every animation in the batch has drained.
  package var batchID: AnimationBatchID?
}

/// Result of a tick: tells the runtime whether more frames are needed
/// and when the next one should arrive.
///
/// Phase 4 split the previously overloaded ``hasActiveAnimations`` /
/// ``affectedIdentities`` fields:
///
/// - ``hasPendingWork`` is the scheduling signal — `true` whenever the
///   tick produced any work that needs another frame, including
///   identity-agnostic stranded-batch drains.
/// - ``redrawIdentities`` is the visibility signal — the set of view
///   identities whose rendered cells must be redrawn this frame.  May
///   be empty even when ``hasPendingWork`` is `true` (the drain case),
///   so the run loop must not gate the wake-up on this set being
///   non-empty.
package struct AnimationTickResult: Sendable {
  /// `true` when the tick produced pending work and the scheduler
  /// should wake up again before ``nextDeadline``.
  package var hasPendingWork: Bool
  /// The absolute time by which the scheduler must wake for the
  /// next tick.  `nil` when no wake-up is needed.
  package var nextDeadline: MonotonicInstant?
  /// Identities whose rendered cells need to be redrawn this frame.
  /// Used by the render pipeline's incremental presentation diff to
  /// decide which subtrees need re-rasterizing — NOT by the run loop
  /// to decide whether to schedule another tick.
  package var redrawIdentities: Set<Identity>

  package init(
    hasPendingWork: Bool = false,
    nextDeadline: MonotonicInstant? = nil,
    redrawIdentities: Set<Identity> = []
  ) {
    self.hasPendingWork = hasPendingWork
    self.nextDeadline = nextDeadline
    self.redrawIdentities = redrawIdentities
  }
}

/// Snapshot of a removed view retained for visual-only exit animation.
///
/// The snapshot holds the full subtree as it existed at the moment the
/// node was removed from the live resolved tree, along with the parent
/// identity and child-index needed to re-inject the subtree in roughly
/// the same visual position during the removal animation.
package struct RemovalEntry: Sendable {
  package var snapshot: ResolvedNode
  package var parentIdentity: Identity?
  package var childIndex: Int
  package var transition: AnyTransition
  package var animationBox: AnimationBox?
  package var startTime: MonotonicInstant
  /// Opacity at the moment the removal was snapped.  Normally `1.0`
  /// (the identity phase value), but when the view was still fading
  /// in via an interrupted insertion, the controller samples the
  /// mid-flight opacity and stores it here so the removal continues
  /// from the value currently on screen instead of snapping back
  /// to full opacity.
  package var startOpacity: Double = 1.0
  /// Frozen PlacedNode subtree captured from the previous frame's
  /// placed tree at the moment the removal was snapped.  When
  /// present, the controller injects this subtree into the placed
  /// tree after layout (draw-only overlay) instead of re-injecting
  /// at the resolved level.  When nil (no previous placed tree
  /// cached), the controller falls back to the resolved-level
  /// injection path — see ``applyInterpolations(to:at:)``.
  package var placedSnapshot: PlacedNode? = nil
  /// Per-key persistent state threaded into the removal animation's
  /// ``CustomAnimation/animate(value:time:context:)`` on each tick.
  /// Built-in bezier/spring curves ignore this; custom animations can
  /// use it to persist bookkeeping across the frames of an exit
  /// transition (e.g. a spring that accumulates velocity).
  package var customState: AnimationState = .init()
}
