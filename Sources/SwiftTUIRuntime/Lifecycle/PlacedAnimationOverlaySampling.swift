@_spi(Testing) package import SwiftTUICore
package import SwiftTUIViews

package enum PlacedAnimationOverlaySampling {
  /// - Parameter adoption: the tree's co-present pairs, when the caller's
  ///   capture already walked the tree; `nil` walks it here.
  package static func sample(
    removingNodes: [ViewNodeID: RemovalEntry],
    activeAnimations: [AnimationKey: ActiveAnimation],
    registeredAnimations: [AnimationBox: Animation],
    tree: PlacedNode,
    timestamp: MonotonicInstant,
    surfaceSize: CellSize?,
    adoption: [MatchedGeometryAdoptionPair]? = nil
  ) -> PlacedAnimationOverlaySamplingResult {
    let effectiveSurfaceSize = surfaceSize ?? tree.bounds.size
    let removalResult = sampleRemovalOverlays(
      removingNodes: removingNodes,
      registeredAnimations: registeredAnimations,
      tree: tree,
      timestamp: timestamp,
      surfaceSize: effectiveSurfaceSize
    )
    let insertionResult = sampleInsertionOffsets(
      activeAnimations: activeAnimations,
      registeredAnimations: registeredAnimations,
      tree: tree,
      timestamp: timestamp,
      surfaceSize: effectiveSurfaceSize
    )
    let insertionScaleResult = sampleInsertionScales(
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
    for (key, state) in insertionScaleResult.customStates {
      activeCustomStates[key] = state
    }

    // Adoption follows a source that is itself in flight: a source with a
    // live matched or insertion offset is drawn away from its baseline rect
    // this frame, and its adoptee should sit on the drawn rect.
    let adoptionOffsets = sampleAdoption(
      tree: tree,
      pairs: adoption,
      liveOffsets: insertionResult.offsets + matchedResult.offsets,
      liveScales: insertionScaleResult.scales
    )

    return PlacedAnimationOverlaySamplingResult(
      snapshot: PlacedAnimationOverlaySnapshot(
        removalOverlays: removalResult.overlays,
        insertionOffsets: insertionResult.offsets,
        insertionScales: insertionScaleResult.scales,
        matchedGeometryOffsets: matchedResult.offsets,
        adoptionOffsets: adoptionOffsets
      ),
      removalCustomStates: removalResult.customStates,
      activeAnimationCustomStates: activeCustomStates,
      completedAnimationKeys: insertionResult.completedKeys + insertionScaleResult.completedKeys
        + matchedResult.completedKeys,
      completedRemovalNodeIDs: removalResult.completedNodeIDs
    )
  }

  /// The time-free adoption channel: each co-present non-source moves onto
  /// its source's rect (`MatchedGeometryAdoption`). Pure in its inputs, so
  /// the controller's capture can run the same pairing without a clock.
  package static func sampleAdoption(
    tree: PlacedNode,
    pairs: [MatchedGeometryAdoptionPair]? = nil,
    liveOffsets: [PlacedAnimationOverlayOffset] = [],
    liveScales: [PlacedAnimationOverlayScale] = []
  ) -> [PlacedAnimationOverlayOffset] {
    let pairs = pairs ?? MatchedGeometryAdoption.pairs(in: tree)
    guard !pairs.isEmpty else { return [] }
    var overrides: [Identity: CellRect] = [:]
    if !liveOffsets.isEmpty || !liveScales.isEmpty {
      for pair in pairs {
        var rect = pair.sourceBounds
        var changed = false
        for offset in liveOffsets where offset.identity == pair.source {
          rect = CellRect(
            origin: CellPoint(x: rect.origin.x + offset.dx, y: rect.origin.y + offset.dy),
            size: offset.size ?? rect.size
          )
          changed = true
        }
        for scale in liveScales where scale.identity == pair.source {
          rect = scaledTransitionRect(rect, scale: scale.scale, anchor: scale.anchor)
          changed = true
        }
        if changed {
          overrides[pair.source] = rect
        }
      }
    }
    return MatchedGeometryAdoption.offsets(for: pairs, sourceRectOverrides: overrides)
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

  private struct ScaleSamplingResult {
    var scales: [PlacedAnimationOverlayScale] = []
    var customStates: [AnimationKey: AnimationState] = [:]
    var completedKeys: [AnimationKey] = []
  }

  private static func sampleRemovalOverlays(
    removingNodes: [ViewNodeID: RemovalEntry],
    registeredAnimations: [AnimationBox: Animation],
    tree: PlacedNode,
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

      // The departing view leaves across its OWN edge, so the frozen overlay's
      // size is the basis — not the surface, which would fling a small view a
      // whole screen away in the time it should take to clear its own frame.
      let modifiers = AnimationTransitionOverlay.interpolatedRemovalModifiers(
        from: entry.startOpacity,
        to: entry.transition.removalModifiers(),
        progress: progress,
        edgeBasis: placedSnapshot.bounds.size
      )
      let matchedGeometryOffset = entry.matchedTravel.flatMap { travel in
        matchedRemovalOffset(
          travel: travel,
          overlay: placedSnapshot,
          tree: tree,
          progress: progress
        )
      }
      result.overlays.append(
        .init(
          parentIdentity: parentId,
          childIndex: entry.childIndex,
          snapshot: placedSnapshot,
          modifiers: modifiers,
          matchedGeometryOffset: matchedGeometryOffset
        )
      )
    }

    return result
  }

  /// The departing matched node's placed delta at `progress`: its frozen
  /// rect inside the exit overlay interpolates toward the live counterpart's
  /// current rect under the same anchor-space rule as the live side
  /// (`interpolatedMatchedRect`), so the two instances coincide while their
  /// transitions cross-fade. The delta is relative to the frozen rect, where
  /// the overlay already sits; the live side's delta is relative to its
  /// destination. `nil` when either rect is missing — the overlay then fades
  /// in place.
  private static func matchedRemovalOffset(
    travel: MatchedRemovalTravel,
    overlay: PlacedNode,
    tree: PlacedNode,
    progress: Double
  ) -> PlacedAnimationOverlayOffset? {
    guard
      let fromBounds = AnimationTreeQueries.findBounds(
        in: overlay,
        identity: travel.matchedIdentity
      ),
      let toBounds = AnimationTreeQueries.findBounds(
        in: tree,
        identity: travel.destinationIdentity
      )
    else {
      return nil
    }
    let rect = interpolatedMatchedRect(
      from: fromBounds,
      to: toBounds,
      properties: travel.properties,
      anchor: travel.anchor,
      progress: progress
    )
    return .init(
      identity: travel.matchedIdentity,
      dx: rect.origin.x - fromBounds.origin.x,
      dy: rect.origin.y - fromBounds.origin.y,
      size: travel.properties.contains(.size) ? rect.size : nil
    )
  }

  /// - Parameter surfaceSize: the fallback edge basis for an identity with no
  ///   placed rect in `tree` (it resolved away, or the insertion is being
  ///   sampled against a tree that does not contain it). The node's own placed
  ///   size is preferred — see ``TransitionModifiers/resolvedOffset(edgeBasis:)``.
  private static func sampleInsertionOffsets(
    activeAnimations: [AnimationKey: ActiveAnimation],
    registeredAnimations: [AnimationBox: Animation],
    tree: PlacedNode,
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

      // The arriving view crosses its OWN edge: it starts one view width (or
      // height) outside the slot it is about to occupy and slides into it.
      let edgeBasis =
        AnimationTreeQueries.findBounds(in: tree, identity: key.identity)?.size
        ?? surfaceSize
      let start = from.resolvedOffset(edgeBasis: edgeBasis)
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

  private static func sampleInsertionScales(
    activeAnimations: [AnimationKey: ActiveAnimation],
    registeredAnimations: [AnimationBox: Animation],
    timestamp: MonotonicInstant
  ) -> ScaleSamplingResult {
    var result = ScaleSamplingResult()

    for (key, entry) in activeAnimations {
      guard key.scope == .insertionScale else { continue }
      guard case .insertionScale(let from) = entry.kind else { continue }
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

      result.scales.append(
        .init(
          identity: key.identity,
          scale: from.scale + (1.0 - from.scale) * progress,
          anchor: from.anchor
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
