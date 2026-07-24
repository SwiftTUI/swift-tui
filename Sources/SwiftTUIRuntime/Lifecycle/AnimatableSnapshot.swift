@_spi(Testing) package import SwiftTUICore
import SwiftTUIViews

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
    case .meshGradient(let gradient):
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
