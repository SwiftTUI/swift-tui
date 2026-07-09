extension LayoutEngine {
  package func placeIterative(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext?
  ) -> PlacedNode {
    var work: [PlacementWorkItem] = [
      .place(
        resolved,
        measured: measured,
        bounds: bounds,
        viewportContext: viewportContext
      )
    ]
    var results: [PlacedNode] = []
    var localMetrics = LayoutWorkMetrics()

    while let item = work.popLast() {
      localMetrics.placementWorkStackSteps += 1

      switch item {
      case .place(let node, let measured, let bounds, let viewportContext):
        schedulePlacement(
          of: node,
          measured: measured,
          in: bounds,
          viewportContext: viewportContext,
          passContext: passContext,
          localMetrics: &localMetrics,
          work: &work,
          results: &results
        )
      case .finish(let node, let measured, let bounds, let childCount):
        let children = popPlacements(from: &results, count: childCount)
        results.append(
          placedNode(
            from: node,
            bounds: bounds,
            measured: measured,
            children: children
          )
        )
      }
    }

    precondition(results.count == 1, "placement work stack left \(results.count) roots")
    passContext?.updateWorkMetrics {
      $0.placementWorkStackSteps += localMetrics.placementWorkStackSteps
      $0.placedNodesComputed += localMetrics.placedNodesComputed
      $0.placedNodesReused += localMetrics.placedNodesReused
    }
    return results[0]
  }

  private func schedulePlacement(
    of node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext?,
    localMetrics: inout LayoutWorkMetrics,
    work: inout [PlacementWorkItem],
    results: inout [PlacedNode]
  ) {
    if let retained = retainedPlacement(
      for: node,
      measured: measured,
      bounds: bounds,
      viewportContext: viewportContext,
      retainedLayout: passContext?.retainedLayout
    ) {
      localMetrics.placedNodesReused += retained.placed.subtreeNodeCount
      if let fragment = retained.placedFrameFragment {
        passContext?.recordPlacedFrameFragment(fragment)
      } else {
        passContext?.recordPlacedFrames(in: retained.placed)
      }
      results.append(retained.placed)
      return
    }

    localMetrics.placedNodesComputed += 1

    passContext?.recordPlacedFrame(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      bounds: bounds,
      namedCoordinateSpaceName: node.semanticMetadata.namedCoordinateSpaceName
    )

    let hasChildren =
      if node.layoutRealizedContent != nil {
        true
      } else if let source = node.indexedChildSource {
        source.count > 0
      } else {
        !node.children.isEmpty
      }

    guard hasChildren else {
      results.append(
        placedNode(
          from: node,
          bounds: bounds,
          measured: measured,
          children: []
        )
      )
      return
    }

    if case .custom(let token) = node.layoutBehavior {
      guard let handle = token as? CustomLayoutHandle else {
        preconditionFailure("LayoutBehavior.custom must carry a CustomLayoutHandle")
      }
      guard
        passContext?.enterCustomLayoutCompatibilityBoundary(
          identity: node.identity,
          debugName: handle.debugName,
          phase: .placement
        ) ?? true
      else {
        results.append(
          placedNode(
            from: node,
            bounds: bounds,
            measured: measured,
            children: []
          )
        )
        return
      }
      defer {
        passContext?.exitCustomLayoutCompatibilityBoundary()
      }

      let children = handle.placeSubviews(
        engine: self,
        node: node,
        measured: measured,
        in: bounds,
        passContext: passContext
      )
      results.append(
        placedNode(
          from: node,
          bounds: bounds,
          measured: measured,
          children: children
        )
      )
      return
    }

    let requests = placementRequests(
      for: node,
      measured: measured,
      in: bounds,
      viewportContext: viewportContext,
      passContext: passContext
    )

    work.append(
      .finish(
        node,
        measured: measured,
        bounds: bounds,
        childCount: requests.count
      )
    )
    let childViewportContext = passContext?.scrollViewportContext
    for request in requests.reversed() {
      work.append(
        .place(
          request.resolved,
          measured: request.measured,
          bounds: request.bounds,
          viewportContext: childViewportContext
        )
      )
    }
  }
}
