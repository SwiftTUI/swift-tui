@_spi(Testing) package import SwiftTUICore
import SwiftTUIViews

package enum AnimationPropertyValueApplication {
  /// Extracts the ``AnimatableSlot`` from a property-scoped key.
  ///
  /// Traps when called on a non-property scope. Callers must filter to
  /// property-scoped animation kinds before asking for the slot.
  package static func propertySlot(for key: AnimationKey) -> AnimatableSlot {
    guard case .property(let slot) = key.scope else {
      preconditionFailure(
        "propertySlot(for:) called on non-property key scope=\(key.scope)"
      )
    }
    return slot
  }

  package static func applyInterpolatedValues(
    tree: ResolvedNode,
    interpolatedByNodeID: [ViewNodeID: [AnimatableSlot: AnyAnimatable]],
    interpolatedByIdentity: [Identity: [AnimatableSlot: AnyAnimatable]],
    appliedIdentities: inout Set<Identity>
  ) -> ResolvedNode {
    var node = tree
    // Entity-keyed values follow the node across an identity-changing move and
    // take precedence over any identity-keyed fallback for the same slot.
    var values = interpolatedByIdentity[node.identity]
    if let viewNodeID = node.viewNodeID,
      let byNodeID = interpolatedByNodeID[viewNodeID]
    {
      if values == nil {
        values = byNodeID
      } else {
        values?.merge(byNodeID) { _, entityScoped in entityScoped }
      }
    }
    if let values {
      for (slot, value) in values {
        applyValue(&node, slot: slot, value: value)
      }
      appliedIdentities.insert(node.identity)
    }
    // Recursively apply interpolated values to children; the shape is unchanged
    // so bypass derived-state recomputes.
    let interpolatedChildren = node.children.map { child in
      applyInterpolatedValues(
        tree: child,
        interpolatedByNodeID: interpolatedByNodeID,
        interpolatedByIdentity: interpolatedByIdentity,
        appliedIdentities: &appliedIdentities
      )
    }
    node.setChildrenPreservingDerivedState(interpolatedChildren)
    return node
  }

  package static func interpolate(
    from: AnyAnimatable,
    to: AnyAnimatable,
    progress: Double
  ) -> AnyAnimatable {
    // Snap to target on type mismatch. The controller should never produce a
    // slot animation where types differ, but `AnyAnimatable` uses nil for a
    // failed interpolation and snapping is the existing defensive behavior.
    from.interpolated(to: to, progress: progress) ?? to
  }

  private static func applyValue(
    _ node: inout ResolvedNode,
    slot: AnimatableSlot,
    value: AnyAnimatable
  ) {
    switch slot {
    case .opacity:
      guard let opacity = value.unwrap(as: Double.self) else { return }
      var drawMetadata = node.drawMetadata
      drawMetadata.baseStyle.explicitOpacity = opacity
      node.drawMetadata = drawMetadata

    case .foregroundShapeStyle:
      guard let style = unwrapShapeStyle(value) else { return }
      var drawMetadata = node.drawMetadata
      drawMetadata.baseStyle.foregroundStyle = style
      node.drawMetadata = drawMetadata

    case .backgroundShapeStyle:
      guard let style = unwrapShapeStyle(value) else { return }
      var drawMetadata = node.drawMetadata
      drawMetadata.baseStyle.backgroundStyle = style
      node.drawMetadata = drawMetadata

    case .borderShapeStyle:
      guard let style = unwrapShapeStyle(value) else { return }
      var drawMetadata = node.drawMetadata
      drawMetadata.borderShapeStyle = style
      node.drawMetadata = drawMetadata

    case .borderBlendPhase:
      guard let phase = value.unwrap(as: Double.self) else { return }
      if case .border(
        let set,
        let placement,
        let foreground,
        let background,
        let blend,
        _,
        let sides
      ) = node.layoutBehavior {
        node.setLayoutBehaviorPreservingDerivedState(
          .border(
            set,
            placement: placement,
            foreground: foreground,
            background: background,
            blend: blend,
            blendPhase: phase,
            sides: sides
          )
        )
      }

    case .padding:
      guard let insets = value.unwrap(as: EdgeInsets.self) else { return }
      if case .padding = node.layoutBehavior {
        node.setLayoutBehaviorPreservingDerivedState(.padding(insets))
      }

    case .offset:
      guard let pair = value.unwrap(as: AnimatablePair<Int, Int>.self)
      else { return }
      if case .offset = node.layoutBehavior {
        node.setLayoutBehaviorPreservingDerivedState(
          .offset(x: pair.first, y: pair.second)
        )
      }

    case .position:
      guard let pair = value.unwrap(as: AnimatablePair<Int, Int>.self)
      else { return }
      if case .position = node.layoutBehavior {
        node.setLayoutBehaviorPreservingDerivedState(
          .position(x: pair.first, y: pair.second)
        )
      }

    case .frameWidth:
      guard let width = value.unwrap(as: Int.self) else { return }
      applyFrameWidth(width, to: &node)

    case .frameHeight:
      guard let height = value.unwrap(as: Int.self) else { return }
      applyFrameHeight(height, to: &node)

    case .shapeFillStyle:
      guard let style = unwrapShapeStyle(value) else { return }
      guard case .shape(let shapePayload) = node.drawPayload,
        case .fill(_, let mode) = shapePayload.operation
      else {
        return
      }
      node.drawPayload = .shape(
        ShapePayload(
          geometry: shapePayload.geometry,
          insetAmount: shapePayload.insetAmount,
          operation: .fill(style: style, mode: mode)
        )
      )

    case .shapeStrokeStyle:
      guard let style = unwrapShapeStyle(value) else { return }
      guard case .shape(let shapePayload) = node.drawPayload,
        case .stroke(_, let strokeStyle, let strokeBorder, let backgroundStyle) =
          shapePayload.operation
      else {
        return
      }
      node.drawPayload = .shape(
        ShapePayload(
          geometry: shapePayload.geometry,
          insetAmount: shapePayload.insetAmount,
          operation: .stroke(
            style: style,
            strokeStyle: strokeStyle,
            strokeBorder: strokeBorder,
            backgroundStyle: backgroundStyle
          )
        )
      )
    }
  }

  private static func unwrapShapeStyle(_ value: AnyAnimatable) -> AnyShapeStyle? {
    if let color = value.unwrap(as: Color.self) {
      return .color(color)
    }
    if let linear = value.unwrap(as: LinearGradient.self) {
      return .linearGradient(linear)
    }
    if let radial = value.unwrap(as: RadialGradient.self) {
      return .radialGradient(radial)
    }
    if let tile = value.unwrap(as: TileStyle.self) {
      return .tileStyle(tile)
    }
    return nil
  }

  private static func applyFrameWidth(_ width: Int, to node: inout ResolvedNode) {
    switch node.layoutBehavior {
    case .frame(_, let height, let alignment):
      node.setLayoutBehaviorPreservingDerivedState(
        .frame(width: width, height: height, alignment: alignment)
      )
    case .flexibleFrame(
      let minWidth, let idealWidth, let maxWidth,
      let minHeight, let idealHeight, let maxHeight,
      let alignment):
      let (newMax, newIdeal, newMin) = replaceFirstFinite(
        width: width,
        dimensions: (maxWidth, idealWidth, minWidth)
      )
      node.setLayoutBehaviorPreservingDerivedState(
        .flexibleFrame(
          minWidth: newMin,
          idealWidth: newIdeal,
          maxWidth: newMax,
          minHeight: minHeight,
          idealHeight: idealHeight,
          maxHeight: maxHeight,
          alignment: alignment
        ))
    default:
      break
    }
  }

  private static func applyFrameHeight(_ height: Int, to node: inout ResolvedNode) {
    switch node.layoutBehavior {
    case .frame(let width, _, let alignment):
      node.setLayoutBehaviorPreservingDerivedState(
        .frame(width: width, height: height, alignment: alignment)
      )
    case .flexibleFrame(
      let minWidth, let idealWidth, let maxWidth,
      let minHeight, let idealHeight, let maxHeight,
      let alignment):
      let (newMax, newIdeal, newMin) = replaceFirstFinite(
        width: height,
        dimensions: (maxHeight, idealHeight, minHeight)
      )
      node.setLayoutBehaviorPreservingDerivedState(
        .flexibleFrame(
          minWidth: minWidth,
          idealWidth: idealWidth,
          maxWidth: maxWidth,
          minHeight: newMin,
          idealHeight: newIdeal,
          maxHeight: newMax,
          alignment: alignment
        ))
    default:
      break
    }
  }

  /// Replaces the first `.finite(_)` dimension, searched in max, ideal, then
  /// min order, leaving the other dimensions untouched.
  private static func replaceFirstFinite(
    width value: Int,
    dimensions: (max: ProposedDimension?, ideal: ProposedDimension?, min: ProposedDimension?)
  ) -> (max: ProposedDimension?, ideal: ProposedDimension?, min: ProposedDimension?) {
    if case .finite = dimensions.max {
      return (.finite(value), dimensions.ideal, dimensions.min)
    }
    if case .finite = dimensions.ideal {
      return (dimensions.max, .finite(value), dimensions.min)
    }
    if case .finite = dimensions.min {
      return (dimensions.max, dimensions.ideal, .finite(value))
    }
    return dimensions
  }
}
