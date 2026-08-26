@_spi(Testing) import SwiftTUIPrimitives

/// Lowers placed nodes into draw commands.
package struct DrawExtractor: Sendable {
  package init() {}

  /// Extracts a draw tree from a placed tree.
  package func extract(from placed: borrowing PlacedNode) -> DrawNode {
    extractIteratively(from: placed, retained: nil)
  }

  package func extract(
    from placed: borrowing PlacedNode,
    retained input: RetainedDrawExtractionInput?
  ) -> DrawNode {
    if let input, input.proof == .wholeTreeIdentical {
      return input.previousDraw
    }
    return extractIteratively(from: placed, retained: input)
  }
}

private struct BorderMask {
  var bounds: CellRect
  var geometry: ShapeGeometry
  var insetAmount: Int
  var strokeWidth: Int
}

/// Placed-to-draw projection for one node.
///
/// The draw phase owns the command tree it emits, but it reads geometry,
/// clipping policy, layout text policy, draw metadata, environment style, and
/// payload snapshots from the current placed node. Grouping those reads keeps
/// the projection boundary explicit without changing `PlacedNode` storage.
private struct DrawPhaseProjection {
  var viewNodeID: ViewNodeID?
  var identity: Identity
  var environmentSnapshot: EnvironmentSnapshot
  var bounds: CellRect
  var layoutMetadata: LayoutMetadata
  var drawMetadata: DrawMetadata
  var drawEffects: DrawEffects
  var drawPayload: DrawPayload
  var layoutBehavior: LayoutBehavior
  var hostedCollectionContainer: HostedCollectionContainerMetadata?
  var hostedTableColumnWidths: [Int]?
  var hostedListVisibleLayout: ListVisibleLayout?
  var hostedTableVisibleLayout: TableVisibleLayout?
}

private enum ExtractionStep {
  case descend(
    node: PlacedNode,
    inheritedBorderMask: BorderMask?,
    isInBackgroundSubtree: Bool,
    inheritedOpacity: Double
  )
  case assemble(
    node: PlacedNode,
    inheritedBorderMask: BorderMask?,
    isInBackgroundSubtree: Bool,
    inheritedOpacity: Double,
    children: [PlacedNode]
  )
}

extension DrawExtractor {
  private func extractIteratively(
    from root: PlacedNode,
    retained input: RetainedDrawExtractionInput?
  ) -> DrawNode {
    var steps: [ExtractionStep] = [
      .descend(
        node: root,
        inheritedBorderMask: nil,
        isInBackgroundSubtree: false,
        inheritedOpacity: 1
      )
    ]
    steps.reserveCapacity(root.subtreeNodeCount * 2)

    var builtNodes: [DrawNode] = []
    builtNodes.reserveCapacity(root.subtreeNodeCount)

    while let step = steps.popLast() {
      switch step {
      case .descend(
        let node, let inheritedBorderMask, let isInBackgroundSubtree, let inheritedOpacity
      ):
        // The reuse proof already verified the inherited opacity at this
        // subtree root matches the previous frame's, so reusing under a
        // steady ancestor fade is sound (see `collectReusablePhaseSubtrees`).
        if inheritedBorderMask == nil,
          !isInBackgroundSubtree,
          input?.proof.canReuseSubtree(rootedAt: node.identity) == true,
          let previousDraw = input?.previousDrawNode(for: node)
        {
          builtNodes.append(previousDraw)
          continue
        }

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
            inheritedOpacity: inheritedOpacity,
            children: children
          )
        )

        // Children inherit the node's effective factor: the product of every
        // ancestor `.opacity` including this node's own.
        let childInheritedOpacity =
          inheritedOpacity * (node.drawMetadata.explicitOpacity ?? 1)
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
              ),
              inheritedOpacity: childInheritedOpacity
            )
          )
        }
      case .assemble(
        let node,
        let inheritedBorderMask,
        let isInBackgroundSubtree,
        let inheritedOpacity,
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
            isInBackgroundSubtree: isInBackgroundSubtree,
            inheritedOpacity: inheritedOpacity
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
    isInBackgroundSubtree: Bool,
    inheritedOpacity: Double
  ) -> DrawNode {
    let projection = drawPhaseProjection(from: placed)
    let identity = projection.identity
    let environmentSnapshot = projection.environmentSnapshot
    let bounds = projection.bounds
    let layoutMetadata = projection.layoutMetadata
    let drawMetadata = projection.drawMetadata
    let drawEffects = projection.drawEffects
    let drawPayload = projection.drawPayload
    // The multiplicative cascade: every command this node emits carries the
    // product of the ancestor chain's `.opacity` factors including its own.
    // An unfaded tree (`effectiveOpacity == 1`) emits byte-identical commands
    // to the uncascaded output. Text styles always carried the node's own
    // factor, so they take `effectiveOpacity` directly; shape styles carried
    // no factor at all (`.opacity` on a shape leaf was silently dropped) and
    // gain it through the multiplicative `AnyShapeStyle.opacity` wrap.
    let effectiveOpacity = inheritedOpacity * (drawMetadata.explicitOpacity ?? 1)
    func faded(_ style: AnyShapeStyle) -> AnyShapeStyle {
      effectiveOpacity == 1 ? style : style.opacity(effectiveOpacity)
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
        style: faded(backgroundStyle),
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
      if let roll = drawMetadata.textRoll, roll.isRolling, roll.text == content {
        // A content-transition roll in flight: the intermediate glyphs of
        // each column, per-column dimmed, as rich-text runs in the node's
        // own style. Same cells, same layout as the plain string.
        commands.append(
          .richText(
            bounds: bounds,
            payload: TextRollRendering.payload(
              for: roll,
              style: textStyle(from: drawMetadata, effectiveOpacity: effectiveOpacity)
            ),
            lineLimit: layoutMetadata.lineLimit,
            truncationMode: layoutMetadata.textTruncationMode ?? .tail,
            wrappingStrategy: layoutMetadata.textWrappingStrategy ?? .wordBoundary
          )
        )
      } else {
        commands.append(
          .text(
            bounds: bounds,
            content: content,
            style: textStyle(from: drawMetadata, effectiveOpacity: effectiveOpacity),
            lineLimit: layoutMetadata.lineLimit,
            truncationMode: layoutMetadata.textTruncationMode ?? .tail,
            wrappingStrategy: layoutMetadata.textWrappingStrategy ?? .wordBoundary
          )
        )
      }
    case .textFigure(let payload):
      let renderedFigure = TextFigureSupport.render(
        payload,
        boundsWidth: bounds.size.width,
        environment: environmentSnapshot.style
      )
      commands.append(
        .styledPreformattedText(
          bounds: bounds,
          lines: renderedFigure.styledLines,
          style: textStyle(from: drawMetadata, effectiveOpacity: effectiveOpacity)
        )
      )
    case .richText(let payload):
      commands.append(
        .richText(
          bounds: bounds,
          payload: fadedRichTextPayload(payload, effectiveOpacity: effectiveOpacity),
          lineLimit: layoutMetadata.lineLimit,
          truncationMode: layoutMetadata.textTruncationMode ?? .tail,
          wrappingStrategy: layoutMetadata.textWrappingStrategy ?? .wordBoundary
        )
      )
    case .image(let payload):
      var fadedPayload = payload
      fadedPayload.opacity *= effectiveOpacity
      commands.append(
        .image(
          bounds: bounds,
          identity: identity,
          payload: fadedPayload
        )
      )
    case .list(let payload):
      commands.append(
        contentsOf: listCommands(
          for: payload,
          in: bounds,
          hostsCommittedItems: projection.hostedCollectionContainer?.kind == .list,
          placedLayout: projection.hostedListVisibleLayout,
          effectiveOpacity: effectiveOpacity
        )
      )
    case .table(let payload):
      commands.append(
        contentsOf: tableCommands(
          for: payload,
          in: bounds,
          hostsCommittedItems: projection.hostedCollectionContainer?.kind == .table,
          columnWidths: projection.hostedTableColumnWidths,
          placedLayout: projection.hostedTableVisibleLayout,
          effectiveOpacity: effectiveOpacity
        )
      )
    case .shape(let payload):
      switch payload.operation {
      case .fill(let style, let mode):
        commands.append(
          .fill(
            bounds: bounds,
            geometry: payload.geometry,
            insetAmount: payload.insetAmount,
            style: faded(style ?? drawMetadata.foregroundStyle ?? .semantic(.foreground)),
            mode: mode
          )
        )
      case .stroke(let style, let strokeStyle, let strokeBorder, let backgroundStyle):
        commands.append(
          .stroke(
            bounds: bounds,
            geometry: payload.geometry,
            insetAmount: payload.insetAmount,
            style: faded(
              style
                ?? drawMetadata.borderShapeStyle
                ?? drawMetadata.foregroundStyle
                ?? .semantic(strokeBorder ? .separator : .foreground)
            ),
            strokeStyle: strokeStyle,
            strokeBorder: strokeBorder,
            backgroundStyle: fadedBorderBackground(
              backgroundStyle,
              effectiveOpacity: effectiveOpacity
            )
          )
        )
      }
    case .rule(let strokeStyle):
      commands.append(
        .rule(
          bounds: bounds,
          style: faded(
            drawMetadata.borderShapeStyle
              ?? drawMetadata.foregroundStyle
              ?? .semantic(.separator)
          ),
          strokeStyle: strokeStyle ?? drawMetadata.borderStrokeStyle ?? .init(),
          stackAxis: drawMetadata.leafStackAxis
        )
      )
    case .canvas(let payload):
      // The canvas default foreground fades; colors the drawing sets
      // explicitly cannot (they resolve inside the canvas context) — see the
      // divergence register.
      commands.append(
        .canvas(
          bounds: bounds,
          payload: payload,
          foregroundStyle: faded(drawMetadata.foregroundStyle ?? .semantic(.foreground))
        )
      )
    case .foreignSurface(let payload):
      commands.append(
        .foreignSurface(
          bounds: bounds,
          payload: payload
        )
      )
    }

    commands.append(
      contentsOf: scrollIndicatorCommands(
        bounds: bounds,
        drawMetadata: drawMetadata,
        children: children,
        effectiveOpacity: effectiveOpacity
      )
    )

    if let borderShapeStyle = drawMetadata.borderShapeStyle, !drawsRule {
      commands.append(
        .stroke(
          bounds: bounds,
          geometry: .rectangle,
          insetAmount: 0,
          style: faded(borderShapeStyle),
          strokeStyle: drawMetadata.borderStrokeStyle ?? .init(),
          strokeBorder: true,
          backgroundStyle: nil
        )
      )
    }

    // Inset-placement border commands must paint AFTER the child's own
    // content, because their edge glyphs overdraw the outermost rows and
    // columns of the child's frame.  Outset placements do
    // not overlap the child (outset grows the outer frame) and
    // can safely paint before children.  Route inset borders into
    // `postCommands` so the rasterizer's paint walk visits them after
    // the subtree has been fully drawn.
    var postCommands: [DrawCommand] = []
    if case .border(
      let set,
      let placement,
      let foreground,
      let background,
      let blend,
      let blendPhase,
      let sides
    ) = projection.layoutBehavior {
      // Default-styled (nil) foreground sides fall back to the theme
      // foreground at raster time; when fading, substitute that exact color
      // so the faded border matches the unfaded default hue. A nil
      // background side means "no background paint" and stays nil.
      let fadedForeground: BorderEdgeStyle?
      let fadedBlend: BorderBlend?
      if effectiveOpacity == 1 {
        fadedForeground = foreground
        fadedBlend = blend
      } else {
        let themeForeground = AnyShapeStyle.color(environmentSnapshot.style.theme.foreground)
        var edge = foreground ?? .init()
        edge.top = (edge.top ?? themeForeground).opacity(effectiveOpacity)
        edge.right = (edge.right ?? themeForeground).opacity(effectiveOpacity)
        edge.bottom = (edge.bottom ?? themeForeground).opacity(effectiveOpacity)
        edge.left = (edge.left ?? themeForeground).opacity(effectiveOpacity)
        fadedForeground = edge
        fadedBlend = blend.map { blend in
          var faded = blend
          faded.stops = faded.stops.map { stop in
            .init(color: stop.color.opacity(effectiveOpacity), location: stop.location)
          }
          return faded
        }
      }
      let borderCommand: DrawCommand = .border(
        bounds: bounds,
        set: set,
        foreground: fadedForeground,
        background: fadedBorderBackground(background, effectiveOpacity: effectiveOpacity),
        blend: fadedBlend,
        blendPhase: blendPhase,
        sides: sides
      )
      if placement == .inset {
        postCommands.append(borderCommand)
      } else {
        commands.append(borderCommand)
      }
    }

    return DrawNode(
      viewNodeID: projection.viewNodeID,
      identity: identity,
      environmentSnapshot: environmentSnapshot,
      bounds: bounds,
      clipBounds: drawMetadata.clipsToBounds ? bounds : nil,
      metadata: drawMetadata,
      drawEffects: drawEffects,
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

  private func drawPhaseProjection(
    from placed: borrowing PlacedNode
  ) -> DrawPhaseProjection {
    DrawPhaseProjection(
      viewNodeID: placed.viewNodeID,
      identity: placed.identity,
      environmentSnapshot: placed.environmentSnapshot,
      bounds: placed.bounds,
      layoutMetadata: placed.layoutMetadata,
      drawMetadata: placed.drawMetadata,
      drawEffects: placed.drawEffects,
      drawPayload: placed.drawPayload,
      layoutBehavior: placed.layoutBehavior,
      hostedCollectionContainer: placed.semanticMetadata.hostedCollectionContainer,
      hostedTableColumnWidths: placed.hostedCollectionTableColumnWidths,
      hostedListVisibleLayout: placed.hostedListVisibleLayout,
      hostedTableVisibleLayout: placed.hostedTableVisibleLayout
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
    // Draw-only projection for background/overlay masking. This is not a
    // retained-layout input; retained placement is keyed by the canonical placed
    // tree and refreshed resolved metadata before draw extraction reads it.
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
    bounds: CellRect,
    style: AnyShapeStyle,
    defaultMode: ShapeFillMode,
    inheritedBorderMask: BorderMask?
  ) -> (
    bounds: CellRect,
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
    in bounds: CellRect,
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
    in bounds: CellRect,
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
    case .foreignSurface:
      return command
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
  from metadata: DrawMetadata,
  effectiveOpacity: Double
) -> TextStyle {
  TextStyle(
    foregroundStyle: metadata.foregroundStyle,
    backgroundStyle: metadata.backgroundStyle,
    emphasis: metadata.emphasis,
    underlineStyle: metadata.underlineStyle,
    strikethroughStyle: metadata.strikethroughStyle,
    // The cascade product. With no faded ancestor this equals the node's own
    // `metadata.opacity`, keeping unfaded commands byte-identical.
    opacity: effectiveOpacity
  )
}

/// Multiplies the cascade factor into every rich-text run. Run styles carry
/// the authoring-time `Text`-value styling (their `opacity` never includes
/// node-level draw metadata), so the node's effective factor applies once.
private func fadedRichTextPayload(
  _ payload: RichTextPayload,
  effectiveOpacity: Double
) -> RichTextPayload {
  guard effectiveOpacity != 1 else {
    return payload
  }
  var faded = payload
  faded.runs = faded.runs.map { run in
    var run = run
    run.style.opacity = run.style.opacity * effectiveOpacity
    return run
  }
  return faded
}

/// Fades the non-nil sides of a border background. A nil side means "no
/// background paint" and must stay nil.
func fadedBorderBackground(
  _ style: BorderBackgroundStyle?,
  effectiveOpacity: Double
) -> BorderBackgroundStyle? {
  guard effectiveOpacity != 1, var faded = style else {
    return style
  }
  faded.top = faded.top?.opacity(effectiveOpacity)
  faded.right = faded.right?.opacity(effectiveOpacity)
  faded.bottom = faded.bottom?.opacity(effectiveOpacity)
  faded.left = faded.left?.opacity(effectiveOpacity)
  return faded
}
