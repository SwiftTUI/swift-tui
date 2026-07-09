@_spi(Testing) import SwiftTUIPrimitives

extension LayoutEngine {
  package func placedNode(
    from resolved: ResolvedNode,
    bounds: CellRect,
    measured: MeasuredNode,
    children: [PlacedNode]
  ) -> PlacedNode {
    let contentBounds = resolvedContentBounds(
      for: resolved,
      bounds: bounds,
      measured: measured,
      children: children
    )

    return PlacedNode(
      viewNodeID: resolved.viewNodeID,
      identity: resolved.identity,
      resolvedMetadata: .init(
        resolved: resolved,
        semanticRole: semanticRole(for: resolved)
      ),
      bounds: bounds,
      contentBounds: contentBounds,
      children: children
    )
  }

  package func combinedContentBounds(
    parentBounds: CellRect,
    children: [PlacedNode]
  ) -> CellRect {
    children.reduce(parentBounds) { partial, child in
      union(partial, child.contentBounds)
    }
  }

  package func union(
    _ lhs: CellRect,
    _ rhs: CellRect
  ) -> CellRect {
    let minX = min(lhs.origin.x, rhs.origin.x)
    let minY = min(lhs.origin.y, rhs.origin.y)
    let maxX = max(lhs.origin.x + lhs.size.width, rhs.origin.x + rhs.size.width)
    let maxY = max(lhs.origin.y + lhs.size.height, rhs.origin.y + rhs.size.height)

    return CellRect(
      origin: .init(x: minX, y: minY),
      size: .init(width: maxX - minX, height: maxY - minY)
    )
  }

  package func resolvedContentBounds(
    for resolved: ResolvedNode,
    bounds: CellRect,
    measured: MeasuredNode,
    children: [PlacedNode]
  ) -> CellRect {
    let childContentBounds = combinedContentBounds(
      parentBounds: bounds,
      children: children
    )

    switch resolved.drawPayload {
    case .image:
      return childContentBounds
    case .list(let payload):
      return union(
        childContentBounds,
        CellRect(
          origin: bounds.origin,
          size: measuredListIdealSize(for: payload)
        )
      )
    case .table(let payload):
      return union(
        childContentBounds,
        CellRect(
          origin: bounds.origin,
          size: measuredTableIdealSize(for: payload)
        )
      )
    case .none:
      break
    default:
      break
    }

    switch resolved.layoutBehavior {
    case .offset(let x, let y):
      if let child = children.first {
        return translated(
          child.contentBounds,
          by: .init(x: -x, y: -y)
        )
      }
      return bounds
    case .position:
      // `.position` reserves the full proposed bounds for its
      // absolute placement area.  The content bounds are simply
      // the wrapper's bounds — the child sits somewhere inside
      // that area, but scroll views and parents should see the
      // entire reserved region.
      return bounds
    case .lazyStack(let axis, _, _, _):
      guard
        let snapshot = measured.containerAllocationSnapshot?.lazyStack,
        snapshot.contentMainLength > 0
      else {
        return union(childContentBounds, bounds)
      }

      let contentSize: CellSize =
        switch axis {
        case .vertical:
          .init(
            width: snapshot.crossLeading + snapshot.crossTrailing,
            height: snapshot.contentMainLength
          )
        case .horizontal:
          .init(
            width: snapshot.contentMainLength,
            height: snapshot.crossLeading + snapshot.crossTrailing
          )
        }
      let contentBounds = CellRect(origin: bounds.origin, size: contentSize)
      return union(childContentBounds, contentBounds)
    default:
      return childContentBounds
    }
  }

  package func semanticRole(for resolved: ResolvedNode) -> SemanticRole {
    if resolved.semanticMetadata.scrollRole != nil {
      return .scroll
    }
    if resolved.participatesInTopLevelFocus
      || resolved.semanticMetadata.participatesInPointerHitTesting
    {
      return .control
    }
    switch resolved.layoutBehavior {
    case .stack, .lazyStack, .overlay, .padding, .safeAreaIgnoring, .safeAreaInset, .border,
      .frame, .offset, .position, .flexibleFrame, .decoration, .viewThatFits, .custom:
      return .container
    case .intrinsic:
      return .generic
    }
  }

  package func translatedPlacement(
    _ node: PlacedNode,
    by delta: CellPoint
  ) -> PlacedNode {
    let translatedBounds = translated(node.bounds, by: delta)
    let translatedChildren = node.children.map { child in
      translatedPlacement(child, by: delta)
    }

    return PlacedNode(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      kind: node.kind,
      environmentSnapshot: node.environmentSnapshot,
      bounds: translatedBounds,
      contentBounds: translated(node.contentBounds, by: delta),
      clipBounds: node.clipBounds.map { translated($0, by: delta) },
      zIndex: node.zIndex,
      children: translatedChildren,
      semanticRole: node.semanticRole,
      layoutMetadata: node.layoutMetadata,
      drawMetadata: node.drawMetadata,
      drawEffects: node.drawEffects,
      surfaceComposition: node.surfaceComposition,
      semanticMetadata: node.semanticMetadata,
      lifecycleMetadata: node.lifecycleMetadata,
      drawPayload: node.drawPayload,
      layoutBehavior: node.layoutBehavior,
      isTransient: node.isTransient,
      matchedGeometry: node.matchedGeometry
    )
  }

  private func translated(
    _ rect: CellRect,
    by delta: CellPoint
  ) -> CellRect {
    CellRect(
      origin: .init(
        x: rect.origin.x + delta.x,
        y: rect.origin.y + delta.y
      ),
      size: rect.size
    )
  }
}
