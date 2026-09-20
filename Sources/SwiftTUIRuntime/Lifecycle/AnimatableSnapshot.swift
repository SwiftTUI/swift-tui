@_spi(Testing) import SwiftTUICore
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

    if let tint = extractAnimatableShapeStyle(from: node.environmentSnapshot.style.tintStyle) {
      snapshot[.tintShapeStyle] = tint
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
      if case .path(let path, _) = shapePayload.geometry {
        snapshot[.shapePath] = AnyAnimatable(path.path)
      }
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

    // A dashed stroke animates its phase, which is how a marching-ants border
    // moves. A solid stroke has no slot: its phase draws nothing, and a static
    // zero would create a phantom diff on a stroke that later gains a dash.
    if let stroke = Self.dashedStroke(of: node) {
      snapshot[.strokeDashPhase] = AnyAnimatable(stroke.dashPhase)
    }

    // A trimmed stroke animates its interval, which is how an outline draws
    // itself on. An untrimmed stroke has no slot, for the reason a solid stroke
    // has no dash-phase slot.
    if let trim = Self.strokeStyle(of: node)?.trim {
      snapshot[.shapeTrim] = AnyAnimatable(AnimatablePair(trim.from, trim.to))
    }

    // A `Text` that resolved with a content transition: the at-rest roll
    // value carries the string so a string change starts a roll. Nodes
    // without the stamp (the default `.identity`) have no slot and cut.
    if case .text(let content) = node.drawPayload,
      let transition = node.drawMetadata.contentTransition
    {
      snapshot[.textRoll] = AnyAnimatable(
        TextRollValue(text: content, transition: transition)
      )
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
    case .border(_, _, let foreground, _, let blend, let blendPhase, _):
      // Only populate the phase slot when a ``BorderBlend`` is attached.
      // `.border` layouts without a blend have nothing to animate here —
      // the static zero default would otherwise create a phantom
      // "identity → 0" diff on any border that ever transitioned from
      // a blend to a plain foreground.
      if blend != nil {
        snapshot[.borderBlendPhase] = AnyAnimatable(blendPhase)
      } else if let foreground,
        foreground.top == foreground.right, foreground.top == foreground.bottom,
        foreground.top == foreground.left,
        let paint = Self.extractAnimatableShapeStyle(from: foreground.top)
      {
        // A border painted with one style animates that paint, as a shape
        // stroke does. It is how a conic gradient's angle chases round a
        // border. A border with a different paint on each side does not
        // animate, because a slot holds one value.
        snapshot[.borderForegroundStyle] = paint
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

  /// The stroke style a node draws with, from whichever of the three places
  /// carries it: a border keeps its join and dash in the draw metadata, and a
  /// shape stroke and a rule keep theirs in the draw payload.
  package static func strokeStyle(of node: ResolvedNode) -> StrokeStyle? {
    if case .border = node.layoutBehavior {
      return node.drawMetadata.layoutBorderStroke
    }
    if case .shape(let payload) = node.drawPayload,
      case .stroke(_, let strokeStyle, _, _) = payload.operation
    {
      return strokeStyle
    }
    if case .rule(let strokeStyle) = node.drawPayload {
      return strokeStyle
    }
    return nil
  }

  /// Writes a stroke style back to the place ``strokeStyle(of:)`` read it from.
  /// None of the three is layout state, so a dash phase or a trim that changes
  /// every tick cannot invalidate layout.
  package static func setStrokeStyle(_ stroke: StrokeStyle, on node: inout ResolvedNode) {
    if case .border = node.layoutBehavior {
      var drawMetadata = node.drawMetadata
      drawMetadata.layoutBorderStroke = stroke
      node.drawMetadata = drawMetadata
    } else if case .shape(let payload) = node.drawPayload,
      case .stroke(let style, _, let strokeBorder, let backgroundStyle) = payload.operation
    {
      node.drawPayload = .shape(
        ShapePayload(
          geometry: payload.geometry,
          insetAmount: payload.insetAmount,
          operation: .stroke(
            style: style,
            strokeStyle: stroke,
            strokeBorder: strokeBorder,
            backgroundStyle: backgroundStyle
          )
        )
      )
    } else if case .rule = node.drawPayload {
      node.drawPayload = .rule(stroke)
    }
  }

  /// The stroke style a node dashes with, or `nil` for a solid stroke.
  package static func dashedStroke(of node: ResolvedNode) -> StrokeStyle? {
    guard let stroke = strokeStyle(of: node), !stroke.effectiveDash.isEmpty else {
      return nil
    }
    return stroke
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
    case .angularGradient(let gradient):
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
