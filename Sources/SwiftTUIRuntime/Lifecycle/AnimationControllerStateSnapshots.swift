@_spi(Testing) package import SwiftTUICore

extension AnimationController {
  /// An opaque snapshot of the controller's mutable state.  Carries the four
  /// clustered sub-structs plus the standalone animation/removal/tick fields.
  /// ``AnimationController/makeCheckpoint()`` and ``restore(_:)`` move each
  /// member with one whole-value assignment, so the memberwise structs carry
  /// the checkpoint totality contract instead of a hand-listed field copy.
  package struct Checkpoint {
    package var previousFrame: PreviousFrameState
    package var transitions: TransitionRegistry
    package var batchCompletion: BatchCompletionState
    package var frameHead: FrameHeadTransactionState
    package var completionLedger: CompletionLedger
    package var activeAnimations: [AnimationKey: ActiveAnimation]
    package var removingNodes: [ViewNodeID: RemovalEntry]
    package var lastTickResult: AnimationTickResult
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
