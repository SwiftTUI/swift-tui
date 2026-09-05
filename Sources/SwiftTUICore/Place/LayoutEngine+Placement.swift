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

    var node = PlacedNode(
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
    node.lazyChildScrollEstimates = lazyChildScrollEstimates(
      for: resolved,
      bounds: bounds,
      measured: measured,
      placedChildren: children
    )
    node.lazyStackAllocationSnapshot = measured.containerAllocationSnapshot?.lazyStack
    node.hostedCollectionTableColumnWidths =
      measured.containerAllocationSnapshot?
      .hostedCollection?.tableColumnWidths
    node.scrollViewportRect = scrollViewportRect(for: resolved, bounds: bounds)
    if let appearance = resolved.drawMetadata.scrollIndicatorAppearance,
      let content = children.first
    {
      // Publish the same content extent and viewport used by scroll layout.
      // Including the outer inset or indicator track in the viewport would
      // make wheel, key, and pointer clamping stop before the final cells.
      node.contentBounds = content.contentBounds
      let innerBounds = appearance.insetBounds(bounds)
      let insets = resolvedScrollIndicatorInsets(
        viewportRect: innerBounds, contentBounds: content.contentBounds,
        axes: resolved.drawMetadata.scrollIndicatorAxes ?? [],
        reservesSpace: appearance.reservesSpace)
      node.scrollViewportRect = .init(
        origin: innerBounds.origin,
        size: .init(
          width: max(0, innerBounds.size.width - insets.trailing),
          height: max(0, innerBounds.size.height - insets.bottom)))
    }
    if case .list(let payload) = resolved.drawPayload,
      resolved.semanticMetadata.hostedCollectionContainer?.kind == .list
    {
      node.hostedListVisibleLayout = hostedListVisibleLayout(
        for: resolved,
        measured: measured,
        payload: payload,
        in: bounds
      )
    }
    if case .table(let payload) = resolved.drawPayload,
      resolved.semanticMetadata.hostedCollectionContainer?.kind == .table
    {
      node.hostedTableVisibleLayout = hostedTableVisibleLayout(
        measured: measured,
        payload: payload,
        in: bounds
      )
    }
    return node
  }

  /// The rect scroll routing should treat as a collection's viewport: the rows
  /// it actually draws, not its full bounds. See
  /// ``PlacedNode/scrollViewportRect``.
  private func scrollViewportRect(
    for resolved: ResolvedNode,
    bounds: CellRect
  ) -> CellRect? {
    switch resolved.drawPayload {
    case .list(let payload):
      return payload.style.viewportBackedListContentBounds(for: payload, in: bounds)
    case .table(let payload):
      return DrawExtractor().viewportBackedTableContentBounds(for: payload, in: bounds)
    default:
      return nil
    }
  }

  /// Estimated frames for a lazy container's never-placed children. A
  /// `scrollTo` aimed at an out-of-window lazy row has no placed frame, but
  /// the allocation snapshot already computed the exact offset placement
  /// would assign — publish it so the scroll command can target it and let
  /// materialization catch up once the viewport arrives.
  private func lazyChildScrollEstimates(
    for resolved: ResolvedNode,
    bounds: CellRect,
    measured: MeasuredNode,
    placedChildren: [PlacedNode]
  ) -> [LazyChildScrollEstimate]? {
    guard
      case .lazyStack = resolved.layoutBehavior,
      let snapshot = measured.containerAllocationSnapshot?.lazyStack,
      snapshot.childIdentities.count == snapshot.childMainOffsets.count,
      snapshot.childIdentities.count > placedChildren.count
    else {
      return nil
    }

    let placedIdentities = Set(placedChildren.map(\.identity))
    let crossLength = max(0, snapshot.crossLeading + snapshot.crossTrailing)
    var estimates: [LazyChildScrollEstimate] = []
    estimates.reserveCapacity(snapshot.childIdentities.count - placedChildren.count)
    for (index, identity) in snapshot.childIdentities.enumerated()
    where !placedIdentities.contains(identity) {
      let rect: CellRect =
        switch snapshot.axis {
        case .vertical:
          CellRect(
            origin: CellPoint(
              x: bounds.origin.x,
              y: bounds.origin.y + snapshot.childMainOffsets[index]
            ),
            size: CellSize(width: crossLength, height: snapshot.childMainLengths[index])
          )
        case .horizontal:
          CellRect(
            origin: CellPoint(
              x: bounds.origin.x + snapshot.childMainOffsets[index],
              y: bounds.origin.y
            ),
            size: CellSize(width: snapshot.childMainLengths[index], height: crossLength)
          )
        }
      estimates.append(LazyChildScrollEstimate(identity: identity, rect: rect))
    }
    return estimates.isEmpty ? nil : estimates
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

  /// Translates a placed subtree by `delta`.
  ///
  /// Iterative post-order rebuild: reached from the frame tail through
  /// `retainedPlacement`'s viewport-translation leg, over deep scroll content,
  /// on the worker's small Dispatch stack. Each frame translates its own node's
  /// geometry immediately and keeps the untranslated children as placeholders;
  /// completed children are written back into the parent frame's value-typed
  /// `children[index]` one at a time, so the tree is rebuilt bottom-up without
  /// call-stack frames.
  package func translatedPlacement(
    _ node: PlacedNode,
    by delta: CellPoint
  ) -> PlacedNode {
    struct Frame {
      var node: PlacedNode
      var nextChildIndex: Int
    }

    var stack: [Frame] = [Frame(node: translatedNodeItself(node, by: delta), nextChildIndex: 0)]
    while true {
      let index = stack.count - 1
      if stack[index].nextChildIndex < stack[index].node.children.count {
        let child = stack[index].node.children[stack[index].nextChildIndex]
        stack.append(Frame(node: translatedNodeItself(child, by: delta), nextChildIndex: 0))
        continue
      }

      let finished = stack.removeLast().node
      guard let parentIndex = stack.indices.last else {
        return finished
      }
      stack[parentIndex].node.children[stack[parentIndex].nextChildIndex] = finished
      stack[parentIndex].nextChildIndex += 1
    }
  }

  /// Translates one node's own geometry, leaving `children` untouched for the
  /// caller to replace as each is rebuilt.
  private func translatedNodeItself(
    _ node: PlacedNode,
    by delta: CellPoint
  ) -> PlacedNode {
    let translatedBounds = translated(node.bounds, by: delta)
    let translatedChildren = node.children

    var translatedNode = PlacedNode(
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
    translatedNode.lazyChildScrollEstimates = node.lazyChildScrollEstimates.map { estimates in
      estimates.map { estimate in
        LazyChildScrollEstimate(
          identity: estimate.identity,
          rect: translated(estimate.rect, by: delta)
        )
      }
    }
    translatedNode.hostedCollectionTableColumnWidths = node.hostedCollectionTableColumnWidths
    return translatedNode
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
