@_spi(Testing) package import SwiftTUICore
package import SwiftTUIViews

extension AnimationController {
  package struct Checkpoint {
    package var previousSnapshots: [Identity: AnimatableSnapshot]
    package var previousTreeRoot: ResolvedNode?
    package var previousPlacedRoot: PlacedNode?
    package var previousMatchedGeometryBounds: [MatchedGeometryKey: CellRect]
    package var previousMatchedKeyIdentities: [MatchedGeometryKey: Identity]
    package var previousParentByIdentity: [Identity: Identity]
    package var previousChildIndexByIdentity: [Identity: Int]
    package var activeAnimations: [AnimationKey: ActiveAnimation]
    package var registeredAnimations: [AnimationBox: Animation]
    package var completionClosures: [AnimationBatchID: @Sendable () -> Void]
    package var batchRefCounts: [AnimationBatchID: Int]
    package var pendingEmptyBatchCompletions: [AnimationBatchID: MonotonicInstant]
    package var transitionsByNodeID: [ViewNodeID: AnyTransition]
    package var transitionIdentitiesByNodeID: [ViewNodeID: Identity]
    package var previousTransitionsByNodeID: [ViewNodeID: AnyTransition]
    package var previousTransitionIdentitiesByNodeID: [ViewNodeID: Identity]
    package var pendingTransitionsByNodeID: [ViewNodeID: AnyTransition]
    package var pendingTransitionIdentitiesByNodeID: [ViewNodeID: Identity]
    package var removingNodes: [ViewNodeID: RemovalEntry]
    package var previousIdentities: Set<Identity>
    package var lastTickResult: AnimationTickResult
    package var isFrameHeadTransactionActive: Bool
    package var deferredFrameHeadCompletions: [@Sendable () -> Void]
    package var lastFrameHeadCompletionCount: Int
  }

  package struct DebugStateSnapshot: Equatable {
    package var previousSnapshotIdentities: Set<Identity>
    package var previousTreeRoot: ResolvedNode?
    package var previousPlacedRoot: PlacedNode?
    package var previousMatchedGeometryBounds: [MatchedGeometryKey: CellRect]
    package var previousMatchedKeyIdentities: [MatchedGeometryKey: Identity]
    package var previousParentByIdentity: [Identity: Identity]
    package var previousChildIndexByIdentity: [Identity: Int]
    package var activeAnimationKeys: Set<AnimationKey>
    package var registeredAnimationCount: Int
    package var completionClosureBatchIDs: Set<AnimationBatchID>
    package var batchRefCounts: [AnimationBatchID: Int]
    package var pendingEmptyBatchCompletions: [AnimationBatchID: MonotonicInstant]
    package var transitionNodeIDs: Set<ViewNodeID>
    package var transitionIdentities: Set<Identity>
    package var previousTransitionNodeIDs: Set<ViewNodeID>
    package var previousTransitionIdentities: Set<Identity>
    package var pendingTransitionNodeIDs: Set<ViewNodeID>
    package var pendingTransitionIdentities: Set<Identity>
    package var removingNodeIDs: Set<ViewNodeID>
    package var removingIdentities: Set<Identity>
    package var previousIdentities: Set<Identity>
    package var lastTickHasPendingWork: Bool
    package var lastTickNextDeadline: MonotonicInstant?
    package var lastTickRedrawIdentities: Set<Identity>
    package var isFrameHeadTransactionActive: Bool
    package var deferredFrameHeadCompletionCount: Int
    package var lastFrameHeadCompletionCount: Int
  }
}
