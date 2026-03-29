/// Lowers placed nodes into draw commands.
public struct DrawExtractor {
  public init() {}

  /// Extracts a draw tree from a placed tree.
  public func extract(from placed: borrowing PlacedNode) -> DrawNode {
    extract(
      from: placed,
      inheritedBorderMask: nil,
      isInBackgroundSubtree: false
    )
  }
}

private struct BorderMask {
  var bounds: Rect
  var geometry: ShapeGeometry
  var strokeWidth: Int
}

extension DrawExtractor {
  private func extract(
    from placed: borrowing PlacedNode,
    inheritedBorderMask: BorderMask?,
    isInBackgroundSubtree: Bool
  ) -> DrawNode {
    let identity = placed.identity
    let environmentSnapshot = placed.environmentSnapshot
    let bounds = placed.bounds
    let children: [PlacedNode] = Array(placed.children)
    let layoutMetadata = placed.layoutMetadata
    let drawMetadata = placed.drawMetadata
    let drawPayload = placed.drawPayload

    let overlayBorderMask = overlayBorderMask(
      kind: placed.kind,
      children: children
    )
    var childNodes: [DrawNode] = []
    childNodes.reserveCapacity(children.count)
    for index in children.indices {
      childNodes.append(
        extract(
          from: children[index],
          inheritedBorderMask: inheritedBorderMaskForChild(
            forChildAt: index,
            kind: placed.kind,
            inheritedBorderMask: inheritedBorderMask,
            overlayBorderMask: overlayBorderMask
          ),
          isInBackgroundSubtree: isInBackgroundSubtreeForChild(
            forChildAt: index,
            kind: placed.kind,
            inheritedValue: isInBackgroundSubtree
          )
        )
      )
    }
    var commands: [DrawCommand] = []
    let drawsRule: Bool

    switch drawPayload {
    case .rule:
      drawsRule = true
    default:
      drawsRule = false
    }

    if let backgroundStyle = drawMetadata.backgroundStyle {
      let defaultFillMode: ShapeFillMode =
        if let borderStrokeStyle = drawMetadata.borderStrokeStyle,
          drawMetadata.borderShapeStyle != nil,
          !drawsRule
        {
          .interior(strokeWidth: borderStrokeStyle.lineWidth)
        } else if drawMetadata.borderShapeStyle != nil, !drawsRule {
          .interior(strokeWidth: 1)
        } else {
          .full
        }
      let maskedBackgroundFill = maskedBackgroundFillCommand(
        bounds: bounds,
        style: backgroundStyle,
        defaultMode: defaultFillMode,
        inheritedBorderMask: inheritedBorderMask
      )
      commands.append(
        .fill(
          bounds: maskedBackgroundFill.bounds,
          geometry: maskedBackgroundFill.geometry,
          style: maskedBackgroundFill.style,
          mode: maskedBackgroundFill.mode
        )
      )
    }

    switch drawPayload {
    case .none:
      break
    case .text(let content):
      commands.append(
        .text(
          bounds: bounds,
          content: content,
          style: textStyle(from: drawMetadata),
          lineLimit: layoutMetadata.lineLimit,
          truncationMode: layoutMetadata.textTruncationMode ?? .tail,
          wrappingStrategy: layoutMetadata.textWrappingStrategy ?? .wordBoundary
        )
      )
    case .image(let payload):
      commands.append(
        .image(
          bounds: bounds,
          identity: identity,
          payload: payload
        )
      )
    case .list(let payload):
      commands.append(contentsOf: listCommands(for: payload, in: bounds))
    case .table(let payload):
      commands.append(contentsOf: tableCommands(for: payload, in: bounds))
    case .shape(let payload):
      switch payload.operation {
      case .fill(let style, let mode):
        commands.append(
          .fill(
            bounds: bounds,
            geometry: payload.geometry,
            style: style ?? drawMetadata.foregroundStyle ?? .semantic(.foreground),
            mode: mode
          )
        )
      case .stroke(let style, let strokeStyle, let strokeBorder, let backgroundStyle):
        commands.append(
          .stroke(
            bounds: bounds,
            geometry: payload.geometry,
            style: style
              ?? drawMetadata.borderShapeStyle
              ?? drawMetadata.foregroundStyle
              ?? .semantic(strokeBorder ? .separator : .foreground),
            strokeStyle: strokeStyle,
            strokeBorder: strokeBorder,
            backgroundStyle: backgroundStyle
          )
        )
      }
    case .rule(let strokeStyle):
      commands.append(
        .rule(
          bounds: bounds,
          style: drawMetadata.borderShapeStyle
            ?? drawMetadata.foregroundStyle
            ?? .semantic(.separator),
          strokeStyle: strokeStyle ?? drawMetadata.borderStrokeStyle ?? .init()
        )
      )
    }

    commands.append(
      contentsOf: scrollIndicatorCommands(
        bounds: bounds,
        drawMetadata: drawMetadata,
        children: children
      )
    )

    if let borderShapeStyle = drawMetadata.borderShapeStyle, !drawsRule {
      commands.append(
        .stroke(
          bounds: bounds,
          geometry: .rectangle,
          style: borderShapeStyle,
          strokeStyle: drawMetadata.borderStrokeStyle ?? .init(),
          strokeBorder: true,
          backgroundStyle: nil
        )
      )
    }

    return DrawNode(
      identity: identity,
      environmentSnapshot: environmentSnapshot,
      bounds: bounds,
      clipBounds: drawMetadata.clipsToBounds ? bounds : nil,
      metadata: drawMetadata,
      commands: maskedBackgroundCommands(
        commands,
        in: bounds,
        inheritedBorderMask: inheritedBorderMask,
        isInBackgroundSubtree: isInBackgroundSubtree
      ),
      children: childNodes
    )
  }

  private func overlayBorderMask(
    kind: NodeKind,
    children: [PlacedNode]
  ) -> BorderMask? {
    guard kind == .view("Overlay"),
      children.count == 2
    else {
      return nil
    }

    return borderMask(for: children[1])
  }

  private func inheritedBorderMaskForChild(
    forChildAt index: Int,
    kind: NodeKind,
    inheritedBorderMask: BorderMask?,
    overlayBorderMask: BorderMask?
  ) -> BorderMask? {
    if kind == .view("Overlay"), index == 0, let overlayBorderMask {
      return overlayBorderMask
    }
    return inheritedBorderMask
  }

  private func isInBackgroundSubtreeForChild(
    forChildAt index: Int,
    kind: NodeKind,
    inheritedValue: Bool
  ) -> Bool {
    guard kind == .view("Background") else {
      return inheritedValue
    }
    if index == 0 {
      return true
    }
    return inheritedValue
  }

  private func borderMask(
    for placed: borrowing PlacedNode
  ) -> BorderMask? {
    if case .shape(let payload) = placed.drawPayload,
      case .stroke(_, let strokeStyle, let strokeBorder, _) = payload.operation,
      strokeBorder
    {
      return BorderMask(
        bounds: placed.bounds,
        geometry: payload.geometry,
        strokeWidth: max(1, strokeStyle.lineWidth)
      )
    }

    guard placed.drawMetadata.borderShapeStyle != nil else {
      return nil
    }

    return BorderMask(
      bounds: placed.bounds,
      geometry: .rectangle,
      strokeWidth: max(1, placed.drawMetadata.borderStrokeStyle?.lineWidth ?? 1)
    )
  }

  private func maskedBackgroundFillCommand(
    bounds: Rect,
    style: AnyShapeStyle,
    defaultMode: ShapeFillMode,
    inheritedBorderMask: BorderMask?
  ) -> (
    bounds: Rect,
    geometry: ShapeGeometry,
    style: AnyShapeStyle,
    mode: ShapeFillMode
  ) {
    guard let inheritedBorderMask,
      inheritedBorderMask.bounds == bounds
    else {
      return (bounds, .rectangle, style, defaultMode)
    }

    let strokeWidth: Int =
      switch defaultMode {
      case .full:
        inheritedBorderMask.strokeWidth
      case .interior(let strokeWidth):
        max(strokeWidth, inheritedBorderMask.strokeWidth)
      }

    return (
      bounds,
      inheritedBorderMask.geometry,
      style,
      .interior(strokeWidth: strokeWidth)
    )
  }

  private func maskedBackgroundCommands(
    _ commands: [DrawCommand],
    in bounds: Rect,
    inheritedBorderMask: BorderMask?,
    isInBackgroundSubtree: Bool
  ) -> [DrawCommand] {
    guard isInBackgroundSubtree,
      let inheritedBorderMask
    else {
      return commands
    }

    return commands.map {
      maskedBackgroundCommand(
        $0,
        in: bounds,
        inheritedBorderMask: inheritedBorderMask
      )
    }
  }

  private func maskedBackgroundCommand(
    _ command: DrawCommand,
    in bounds: Rect,
    inheritedBorderMask: BorderMask
  ) -> DrawCommand {
    switch command {
    case .fill(let commandBounds, _, let style, let mode)
    where commandBounds == inheritedBorderMask.bounds && commandBounds == bounds:
      let strokeWidth: Int =
        switch mode {
        case .full:
          inheritedBorderMask.strokeWidth
        case .interior(let strokeWidth):
          max(strokeWidth, inheritedBorderMask.strokeWidth)
        }
      return .fill(
        bounds: commandBounds,
        geometry: inheritedBorderMask.geometry,
        style: style,
        mode: .interior(strokeWidth: strokeWidth)
      )
    case .group(let commandBounds, let children):
      return .group(
        bounds: commandBounds,
        children: children.map {
          maskedBackgroundCommand(
            $0,
            in: bounds,
            inheritedBorderMask: inheritedBorderMask
          )
        }
      )
    case .clip(let clipBounds, let child):
      return .clip(
        bounds: clipBounds,
        child: maskedBackgroundCommand(
          child,
          in: bounds,
          inheritedBorderMask: inheritedBorderMask
        )
      )
    default:
      return command
    }
  }
}

// Style precedence in the authoritative draw path:
// 1. Per-node draw metadata wins for directly-authored draw properties such as
//    foreground/background on a concrete node.
// 2. Environment overrides are consulted only when resolving semantic roles
//    like `.foreground` and `.tint`.
// 3. Theme semantic defaults provide the final fallback.
//
// This keeps author-authored node styling stronger than inherited environment
// state, while still allowing environment/theme-driven semantic roles to flow
// through the pipeline in a deterministic order.
private func textStyle(
  from metadata: DrawMetadata
) -> TextStyle {
  TextStyle(
    foregroundStyle: metadata.foregroundStyle,
    backgroundStyle: metadata.backgroundStyle,
    emphasis: metadata.emphasis,
    underlineStyle: metadata.underlineStyle,
    strikethroughStyle: metadata.strikethroughStyle,
    opacity: metadata.opacity
  )
}
