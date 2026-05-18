@_spi(Testing) package import SwiftTUICore
package import SwiftTUIViews

package struct PlacedAnimationOverlaySamplingResult: Sendable {
  package var snapshot: PlacedAnimationOverlaySnapshot
  package var removalCustomStates: [Identity: AnimationState]
  package var activeAnimationCustomStates: [AnimationKey: AnimationState]
  package var completedAnimationKeys: [AnimationKey]

  package init(
    snapshot: PlacedAnimationOverlaySnapshot,
    removalCustomStates: [Identity: AnimationState] = [:],
    activeAnimationCustomStates: [AnimationKey: AnimationState] = [:],
    completedAnimationKeys: [AnimationKey] = []
  ) {
    self.snapshot = snapshot
    self.removalCustomStates = removalCustomStates
    self.activeAnimationCustomStates = activeAnimationCustomStates
    self.completedAnimationKeys = completedAnimationKeys
  }
}

package enum PlacedAnimationOverlaySampling {
  package static func sample(
    removingIdentities: [Identity: RemovalEntry],
    activeAnimations: [AnimationKey: ActiveAnimation],
    registeredAnimations: [AnimationBox: Animation],
    tree: PlacedNode,
    timestamp: MonotonicInstant
  ) -> PlacedAnimationOverlaySamplingResult {
    let removalResult = sampleRemovalOverlays(
      removingIdentities: removingIdentities,
      registeredAnimations: registeredAnimations,
      timestamp: timestamp
    )
    let insertionResult = sampleInsertionOffsets(
      activeAnimations: activeAnimations,
      registeredAnimations: registeredAnimations,
      timestamp: timestamp
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
      completedAnimationKeys: insertionResult.completedKeys + matchedResult.completedKeys
    )
  }

  private struct RemovalSamplingResult {
    var overlays: [PlacedRemovalOverlaySnapshot] = []
    var customStates: [Identity: AnimationState] = [:]
  }

  private struct OffsetSamplingResult {
    var offsets: [PlacedAnimationOverlayOffset] = []
    var customStates: [AnimationKey: AnimationState] = [:]
    var completedKeys: [AnimationKey] = []
  }

  private static func sampleRemovalOverlays(
    removingIdentities: [Identity: RemovalEntry],
    registeredAnimations: [AnimationBox: Animation],
    timestamp: MonotonicInstant
  ) -> RemovalSamplingResult {
    var result = RemovalSamplingResult()

    for (identity, entry) in removingIdentities {
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
      result.customStates[identity] = state

      guard let progress = evaluated else {
        continue
      }

      let modifiers = AnimationTransitionOverlay.interpolatedRemovalModifiers(
        from: entry.startOpacity,
        to: entry.transition.removalModifiers(),
        progress: progress
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
    timestamp: MonotonicInstant
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

      result.offsets.append(
        .init(
          identity: key.identity,
          dx: Int(Double(from.x) * (1.0 - progress)),
          dy: Int(Double(from.y) * (1.0 - progress))
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
