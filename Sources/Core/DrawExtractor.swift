/// Lowers placed nodes into draw commands.
public struct DrawExtractor {
  public init() {}

  /// Extracts a draw tree from a placed tree.
  public func extract(from placed: borrowing PlacedNode) -> DrawNode {
    extractIteratively(from: placed)
  }
}

private struct BorderMask {
  var bounds: Rect
  var geometry: ShapeGeometry
  var insetAmount: Int
  var strokeWidth: Int
}

private enum ExtractionStep {
  case descend(
    node: PlacedNode,
    inheritedBorderMask: BorderMask?,
    isInBackgroundSubtree: Bool
  )
  case assemble(
    node: PlacedNode,
    inheritedBorderMask: BorderMask?,
    isInBackgroundSubtree: Bool,
    children: [PlacedNode]
  )
}

extension DrawExtractor {
  private func extractIteratively(
    from root: PlacedNode
  ) -> DrawNode {
    var steps: [ExtractionStep] = [
      .descend(
        node: root,
        inheritedBorderMask: nil,
        isInBackgroundSubtree: false
      )
    ]
    steps.reserveCapacity(root.subtreeNodeCount * 2)

    var builtNodes: [DrawNode] = []
    builtNodes.reserveCapacity(root.subtreeNodeCount)

    while let step = steps.popLast() {
      switch step {
      case .descend(let node, let inheritedBorderMask, let isInBackgroundSubtree):
        let children = Array(node.children)
        let overlayBorderMask = overlayBorderMask(
          kind: node.kind,
          children: children
        )

        steps.append(
          .assemble(
            node: node,
            inheritedBorderMask: inheritedBorderMask,
            isInBackgroundSubtree: isInBackgroundSubtree,
            children: children
          )
        )

        for index in children.indices.reversed() {
          steps.append(
            .descend(
              node: children[index],
              inheritedBorderMask: inheritedBorderMaskForChild(
                forChildAt: index,
                kind: node.kind,
                inheritedBorderMask: inheritedBorderMask,
                overlayBorderMask: overlayBorderMask
              ),
              isInBackgroundSubtree: isInBackgroundSubtreeForChild(
                forChildAt: index,
                kind: node.kind,
                inheritedValue: isInBackgroundSubtree
              )
            )
          )
        }
      case .assemble(
        let node,
        let inheritedBorderMask,
        let isInBackgroundSubtree,
        let children
      ):
        let childCount = children.count
        let childNodes: [DrawNode] =
          if childCount == 0 {
            []
          } else {
            Array(builtNodes.suffix(childCount))
          }
        if childCount > 0 {
          builtNodes.removeLast(childCount)
        }

        builtNodes.append(
          makeDrawNode(
            from: node,
            children: children,
            childNodes: childNodes,
            inheritedBorderMask: inheritedBorderMask,
            isInBackgroundSubtree: isInBackgroundSubtree
          )
        )
      }
    }

    return builtNodes.removeLast()
  }

  private func makeDrawNode(
    from placed: borrowing PlacedNode,
    children: [PlacedNode],
    childNodes: [DrawNode],
    inheritedBorderMask: BorderMask?,
    isInBackgroundSubtree: Bool
  ) -> DrawNode {
    let identity = placed.identity
    let environmentSnapshot = placed.environmentSnapshot
    let bounds = placed.bounds
    let layoutMetadata = placed.layoutMetadata
    let drawMetadata = placed.drawMetadata
    let drawPayload = placed.drawPayload
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
          insetAmount: maskedBackgroundFill.insetAmount,
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
    case .textFigure(let payload):
      commands.append(
        .preformattedText(
          bounds: bounds,
          lines: TextFigureSupport.render(payload, boundsWidth: bounds.size.width).lines,
          style: textStyle(from: drawMetadata)
        )
      )
    case .richText(let payload):
      commands.append(
        .richText(
          bounds: bounds,
          payload: payload,
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
            insetAmount: payload.insetAmount,
            style: style ?? drawMetadata.foregroundStyle ?? .semantic(.foreground),
            mode: mode
          )
        )
      case .stroke(let style, let strokeStyle, let strokeBorder, let backgroundStyle):
        commands.append(
          .stroke(
            bounds: bounds,
            geometry: payload.geometry,
            insetAmount: payload.insetAmount,
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
          strokeStyle: strokeStyle ?? drawMetadata.borderStrokeStyle ?? .init(),
          stackAxis: drawMetadata.ruleStackAxis
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
          insetAmount: 0,
          style: borderShapeStyle,
          strokeStyle: drawMetadata.borderStrokeStyle ?? .init(),
          strokeBorder: true,
          backgroundStyle: nil
        )
      )
    }

    // Inset-placement border commands must paint AFTER the child's own
    // content, because their edge glyphs overdraw the outermost rows and
    // columns of the child's frame.  Outset and decorative placements do
    // not overlap the child (outset grows the outer frame, decorative
    // draws on the outer frame which is outside the child's bounds) and
    // can safely paint before children.  Route inset borders into
    // `postCommands` so the rasterizer's paint walk visits them after
    // the subtree has been fully drawn.
    var postCommands: [DrawCommand] = []
    if case .border(
      let set,
      let foreground,
      let background,
      let blend,
      let blendPhase,
      let sides
    ) = placed.layoutBehavior {
      let borderCommand: DrawCommand = .border(
        bounds: bounds,
        set: set,
        foreground: foreground,
        background: background,
        blend: blend,
        blendPhase: blendPhase,
        sides: sides
      )
      if set.placement == .inset {
        postCommands.append(borderCommand)
      } else {
        commands.append(borderCommand)
      }
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
      postCommands: postCommands,
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
        insetAmount: payload.insetAmount,
        strokeWidth: max(1, strokeStyle.lineWidth)
      )
    }

    guard placed.drawMetadata.borderShapeStyle != nil else {
      return nil
    }

    return BorderMask(
      bounds: placed.bounds,
      geometry: .rectangle,
      insetAmount: 0,
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
    insetAmount: Int,
    style: AnyShapeStyle,
    mode: ShapeFillMode
  ) {
    guard let inheritedBorderMask,
      inheritedBorderMask.bounds == bounds
    else {
      return (bounds, .rectangle, 0, style, defaultMode)
    }

    let maskedFill = combinedMaskedFill(
      insetAmount: 0,
      mode: defaultMode,
      inheritedBorderMask: inheritedBorderMask
    )

    return (
      bounds,
      inheritedBorderMask.geometry,
      maskedFill.insetAmount,
      style,
      maskedFill.mode
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
    case .fill(let commandBounds, _, let insetAmount, let style, let mode)
    where commandBounds == inheritedBorderMask.bounds && commandBounds == bounds:
      let maskedFill = combinedMaskedFill(
        insetAmount: insetAmount,
        mode: mode,
        inheritedBorderMask: inheritedBorderMask
      )
      return .fill(
        bounds: commandBounds,
        geometry: inheritedBorderMask.geometry,
        insetAmount: maskedFill.insetAmount,
        style: style,
        mode: maskedFill.mode
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

  private func combinedMaskedFill(
    insetAmount: Int,
    mode: ShapeFillMode,
    inheritedBorderMask: BorderMask
  ) -> (insetAmount: Int, mode: ShapeFillMode) {
    let existingReservedWidth =
      switch mode {
      case .full:
        max(0, insetAmount)
      case .interior(let strokeWidth):
        max(0, insetAmount) + strokeWidth
      }
    let borderReservedWidth =
      max(0, inheritedBorderMask.insetAmount) + inheritedBorderMask.strokeWidth
    let finalReservedWidth = max(existingReservedWidth, borderReservedWidth)
    let finalInsetAmount = max(max(0, insetAmount), inheritedBorderMask.insetAmount)
    let additionalInset = max(0, finalReservedWidth - finalInsetAmount)
    let finalMode: ShapeFillMode =
      additionalInset == 0 ? .full : .interior(strokeWidth: additionalInset)
    return (
      insetAmount: finalInsetAmount,
      mode: finalMode
    )
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
