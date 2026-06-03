@_spi(Testing) package import SwiftTUICore
package import SwiftTUIViews

/// The product of one placed-overlay sampling pass.
///
/// `PlacedAnimationOverlaySampling` (in `PlacedAnimationOverlaySampling.swift`)
/// returns this value; the animation controller then writes the sampled custom
/// states back and releases the keys reported as completed. Splitting the
/// result type out keeps the sampling file focused on the algorithm.
package struct PlacedAnimationOverlaySamplingResult: Sendable {
  package var snapshot: PlacedAnimationOverlaySnapshot
  package var removalCustomStates: [ViewNodeID: AnimationState]
  package var activeAnimationCustomStates: [AnimationKey: AnimationState]
  package var completedAnimationKeys: [AnimationKey]

  package init(
    snapshot: PlacedAnimationOverlaySnapshot,
    removalCustomStates: [ViewNodeID: AnimationState] = [:],
    activeAnimationCustomStates: [AnimationKey: AnimationState] = [:],
    completedAnimationKeys: [AnimationKey] = []
  ) {
    self.snapshot = snapshot
    self.removalCustomStates = removalCustomStates
    self.activeAnimationCustomStates = activeAnimationCustomStates
    self.completedAnimationKeys = completedAnimationKeys
  }
}
