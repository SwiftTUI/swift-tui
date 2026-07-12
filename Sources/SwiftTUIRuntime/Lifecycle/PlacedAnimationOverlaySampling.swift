@_spi(Testing) package import SwiftTUICore
package import SwiftTUIViews

package enum PlacedAnimationOverlaySampling {
  package static func sample(
    removingNodes: [ViewNodeID: RemovalEntry],
    activeAnimations: [AnimationKey: ActiveAnimation],
    registeredAnimations: [AnimationBox: Animation],
    tree: PlacedNode,
    timestamp: MonotonicInstant,
    surfaceSize: CellSize?
  ) -> PlacedAnimationOverlaySamplingResult {
    let effectiveSurfaceSize = surfaceSize ?? tree.bounds.size
    let removalResult = sampleRemovalOverlays(
      removingNodes: removingNodes,
      registeredAnimations: registeredAnimations,
      timestamp: timestamp,
      surfaceSize: effectiveSurfaceSize
    )
    let insertionResult = sampleInsertionOffsets(
      activeAnimations: activeAnimations,
      registeredAnimations: registeredAnimations,
      timestamp: timestamp,
      surfaceSize: effectiveSurfaceSize
    )
    let matchedResult = sampleMatchedGeometryOffsets(
      activeAnimations: activeAnimations,
      registeredAnimations: registeredAnimations,
      tree: tree,
      timestamp: timestamp
    )

    var activeCustomStates = insertionResult.customStates
    for (key, state) in matchedResult.customStates {
      activeCustomStates[key] = state
    }

    return PlacedAnimationOverlaySamplingResult(
      snapshot: PlacedAnimationOverlaySnapshot(
        removalOverlays: removalResult.overlays,
        insertionOffsets: insertionResult.offsets,
        matchedGeometryOffsets: matchedResult.offsets
      ),
      removalCustomStates: removalResult.customStates,
      activeAnimationCustomStates: activeCustomStates,
      completedAnimationKeys: insertionResult.completedKeys + matchedResult.completedKeys,
      completedRemovalNodeIDs: removalResult.completedNodeIDs
    )
  }

  private struct RemovalSamplingResult {
    var overlays: [PlacedRemovalOverlaySnapshot] = []
    var customStates: [ViewNodeID: AnimationState] = [:]
    var completedNodeIDs: [ViewNodeID] = []
  }

  private struct OffsetSamplingResult {
    var offsets: [PlacedAnimationOverlayOffset] = []
    var customStates: [AnimationKey: AnimationState] = [:]
    var completedKeys: [AnimationKey] = []
  }

  private static func sampleRemovalOverlays(
    removingNodes: [ViewNodeID: RemovalEntry],
    registeredAnimations: [AnimationBox: Animation],
    timestamp: MonotonicInstant,
    surfaceSize: CellSize
  ) -> RemovalSamplingResult {
    var result = RemovalSamplingResult()

    for (viewNodeID, entry) in removingNodes {
      guard let placedSnapshot = entry.placedSnapshot,
        let parentId = entry.parentIdentity
      else {
        continue
      }

      guard let box = entry.animationBox,
        let animation = registeredAnimations[box]
      else {
        continue
      }

      let elapsed = entry.startTime.duration(to: timestamp)
      var state = entry.customState
      let evaluated = animation.evaluate(elapsed: elapsed, state: &state)
      result.customStates[viewNodeID] = state

      guard let progress = evaluated else {
        // The exit curve finished. The placed pass owns this removal's single
        // evaluation and completion (the resolved tick no longer evaluates or
        // purges placed removals — 016), so record the node for the controller
        // to purge from `removingNodes`.
        result.completedNodeIDs.append(viewNodeID)
        continue
      }

      let modifiers = AnimationTransitionOverlay.interpolatedRemovalModifiers(
        from: entry.startOpacity,
        to: entry.transition.removalModifiers(),
        progress: progress,
        surfaceSize: surfaceSize
      )
      result.overlays.append(
        .init(
          parentIdentity: parentId,
          childIndex: entry.childIndex,
          snapshot: placedSnapshot,
          modifiers: modifiers
        )
      )
    }

    return result
  }

  private static func sampleInsertionOffsets(
    activeAnimations: [AnimationKey: ActiveAnimation],
    registeredAnimations: [AnimationBox: Animation],
    timestamp: MonotonicInstant,
    surfaceSize: CellSize
  ) -> OffsetSamplingResult {
    var result = OffsetSamplingResult()

    for (key, entry) in activeAnimations {
      guard key.scope == .insertionOffset else { continue }
      guard case .insertionOffset(let from) = entry.kind else { continue }
      guard let animation = registeredAnimations[entry.animationBox] else {
        result.completedKeys.append(key)
        continue
      }

      let elapsed = entry.startTime.duration(to: timestamp)
      var state = entry.customState
      let evaluated = animation.evaluate(elapsed: elapsed, state: &state)
      result.customStates[key] = state

      guard let progress = evaluated else {
        result.completedKeys.append(key)
        continue
      }

      let start = from.resolvedOffset(surfaceSize: surfaceSize)
      result.offsets.append(
        .init(
          identity: key.identity,
          dx: Int(Double(start.x) * (1.0 - progress)),
          dy: Int(Double(start.y) * (1.0 - progress))
        )
      )
    }

    return result
  }

  private static func sampleMatchedGeometryOffsets(
    activeAnimations: [AnimationKey: ActiveAnimation],
    registeredAnimations: [AnimationBox: Animation],
    tree: PlacedNode,
    timestamp: MonotonicInstant
  ) -> OffsetSamplingResult {
    var result = OffsetSamplingResult()

    for (key, entry) in activeAnimations {
      guard key.scope == .matchedGeometry else { continue }
      guard case .matchedGeometry(let fromBounds) = entry.kind else { continue }
      guard let animation = registeredAnimations[entry.animationBox] else {
        result.completedKeys.append(key)
        continue
      }

      let elapsed = entry.startTime.duration(to: timestamp)
      var state = entry.customState
      let evaluated = animation.evaluate(elapsed: elapsed, state: &state)
      result.customStates[key] = state

      guard let progress = evaluated else {
        result.completedKeys.append(key)
        continue
      }

      guard
        let toBounds = AnimationTreeQueries.findBounds(
          in: tree,
          identity: key.identity
        )
      else {
        continue
      }

      let deltaX =
        Double(fromBounds.origin.x - toBounds.origin.x)
        * (1.0 - progress)
      let deltaY =
        Double(fromBounds.origin.y - toBounds.origin.y)
        * (1.0 - progress)

      result.offsets.append(
        .init(
          identity: key.identity,
          dx: Int(deltaX.rounded()),
          dy: Int(deltaY.rounded())
        )
      )
    }

    return result
  }
}
