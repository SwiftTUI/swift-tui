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
        // Nothing to composite (no frozen placed snapshot or no surviving
        // parent) — and neither can ever appear later, so complete the
        // removal now. A skipped entry would strand `removingNodes` and keep
        // the frame pump armed for the rest of the session.
        result.completedNodeIDs.append(viewNodeID)
        continue
      }

      guard let box = entry.animationBox,
        let animation = registeredAnimations[box]
      else {
        // No animation to drive (no `withAnimation` intent, or the box's
        // registration is gone): the exit is instantaneous — complete the
        // removal on this sample instead of skipping it forever.
        result.completedNodeIDs.append(viewNodeID)
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
      guard case .matchedGeometry(let fromBounds, let properties, let anchor) = entry.kind else {
        continue
      }
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

      let rect = interpolatedMatchedRect(
        from: fromBounds,
        to: toBounds,
        properties: properties,
        anchor: anchor,
        progress: progress
      )
      result.offsets.append(
        .init(
          identity: key.identity,
          dx: rect.origin.x - toBounds.origin.x,
          dy: rect.origin.y - toBounds.origin.y,
          size: properties.contains(.size) ? rect.size : nil
        )
      )
    }

    return result
  }

  /// The rect a matched node renders at for `progress`, in anchor space:
  /// the anchor point tracks from the source's to the destination's when
  /// `.position` is requested, the size interpolates when `.size` is, and
  /// the origin follows from the two. Position and size round separately,
  /// like the earlier translation-only `dx`/`dy`.
  package static func interpolatedMatchedRect(
    from: CellRect,
    to: CellRect,
    properties: MatchedGeometryProperties,
    anchor: UnitPoint,
    progress: Double
  ) -> CellRect {
    func anchorPoint(_ rect: CellRect) -> (x: Double, y: Double) {
      (
        Double(rect.origin.x) + anchor.x * Double(rect.size.width),
        Double(rect.origin.y) + anchor.y * Double(rect.size.height)
      )
    }
    let fromAnchor = anchorPoint(from)
    let toAnchor = anchorPoint(to)
    let tracksPosition = properties.contains(.position)
    let tracksSize = properties.contains(.size)

    let anchorX =
      tracksPosition ? fromAnchor.x + (toAnchor.x - fromAnchor.x) * progress : toAnchor.x
    let anchorY =
      tracksPosition ? fromAnchor.y + (toAnchor.y - fromAnchor.y) * progress : toAnchor.y
    let width =
      tracksSize
      ? Double(from.size.width) + Double(to.size.width - from.size.width) * progress
      : Double(to.size.width)
    let height =
      tracksSize
      ? Double(from.size.height) + Double(to.size.height - from.size.height) * progress
      : Double(to.size.height)

    let roundedWidth = Int(width.rounded())
    let roundedHeight = Int(height.rounded())
    return CellRect(
      origin: CellPoint(
        x: Int((anchorX - anchor.x * Double(roundedWidth)).rounded()),
        y: Int((anchorY - anchor.y * Double(roundedHeight)).rounded())
      ),
      size: CellSize(width: max(roundedWidth, 0), height: max(roundedHeight, 0))
    )
  }
}
