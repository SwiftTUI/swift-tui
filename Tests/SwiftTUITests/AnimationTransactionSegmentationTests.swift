import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Per-batch animation transaction segmentation")
struct AnimationTransactionSegmentationTests {
  @Test("disjoint segments start property animations with their own transactions")
  func disjointSegmentsKeepTheirOwnAnimationBoxesAndBatches() throws {
    let controller = AnimationController()
    let firstAnimation = Animation.linear(duration: .milliseconds(100))
    let secondAnimation = Animation.easeIn(duration: .milliseconds(250))
    let firstBatchID = AnimationBatchID(16_101)
    let secondBatchID = AnimationBatchID(16_102)
    let rootIdentity = testIdentity("segmented-root")
    let firstIdentity = testIdentity("segmented-root", "first")
    let secondIdentity = testIdentity("segmented-root", "second")

    let baseline = tree(
      rootIdentity: rootIdentity,
      firstIdentity: firstIdentity,
      firstOpacity: 1,
      secondIdentity: secondIdentity,
      secondOpacity: 1
    )
    let target = tree(
      rootIdentity: rootIdentity,
      firstIdentity: firstIdentity,
      firstOpacity: 0,
      secondIdentity: secondIdentity,
      secondOpacity: 0
    )
    let timestamp = MonotonicInstant.now()
    controller.processResolvedTree(baseline, transaction: .init(), timestamp: timestamp)

    let plan = FrameAnimationTransactionPlan(
      base: .init(),
      segments: [
        segment(
          identity: firstIdentity,
          animation: firstAnimation,
          batchID: firstBatchID
        ),
        segment(
          identity: secondIdentity,
          animation: secondAnimation,
          batchID: secondBatchID
        ),
      ]
    )
    #expect(!controller.canSkipResolvedTreeProcessing(transactionPlan: plan))

    controller.processResolvedTree(target, transactionPlan: plan, timestamp: timestamp)

    let state = controller.debugStateSnapshot()
    #expect(
      state.activeAnimationBoxesByKey[
        AnimationKey(identity: firstIdentity, slot: .opacity)
      ] == firstAnimation.animationBox
    )
    #expect(
      state.activeAnimationBoxesByKey[
        AnimationKey(identity: secondIdentity, slot: .opacity)
      ] == secondAnimation.animationBox
    )
    #expect(state.batchRefCounts[firstBatchID] == 1)
    #expect(state.batchRefCounts[secondBatchID] == 1)
  }

  @Test("each stranded segment batch receives its own delayed drain")
  func strandedSegmentBatchesKeepSeparateCompletionDrains() throws {
    let controller = AnimationController()
    let firstAnimation = Animation.linear(duration: .milliseconds(100))
    let secondAnimation = Animation.linear(duration: .milliseconds(250))
    let firstBatchID = AnimationBatchID(16_103)
    let secondBatchID = AnimationBatchID(16_104)
    let rootIdentity = testIdentity("stranded-root")
    let firstIdentity = testIdentity("stranded-root", "first")
    let secondIdentity = testIdentity("stranded-root", "second")
    let unchanged = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [
        ResolvedNode(identity: firstIdentity, kind: .view("First")),
        ResolvedNode(identity: secondIdentity, kind: .view("Second")),
      ]
    )
    let timestamp = MonotonicInstant.now()
    controller.processResolvedTree(unchanged, transaction: .init(), timestamp: timestamp)
    controller.registerCompletion(batchID: firstBatchID) {}
    controller.registerCompletion(batchID: secondBatchID) {}

    controller.processResolvedTree(
      unchanged,
      transactionPlan: FrameAnimationTransactionPlan(
        base: .init(),
        segments: [
          segment(
            identity: firstIdentity,
            animation: firstAnimation,
            batchID: firstBatchID
          ),
          segment(
            identity: secondIdentity,
            animation: secondAnimation,
            batchID: secondBatchID
          ),
        ]
      ),
      timestamp: timestamp
    )

    let drains = controller.debugStateSnapshot().pendingEmptyBatchCompletions
    #expect(drains[firstBatchID] == timestamp.advanced(by: .milliseconds(100)))
    #expect(drains[secondBatchID] == timestamp.advanced(by: .milliseconds(250)))
  }

  @Test("insertion transition selects the transaction claimed by the inserted identity")
  func insertionTransitionUsesIdentitySpecificAnimation() {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(300))
    let batchID = AnimationBatchID(16_105)
    let rootIdentity = testIdentity("insertion-root")
    let insertedIdentity = testIdentity("insertion-root", "inserted")
    let insertedNodeID = ViewNodeID(rawValue: 16_105)
    let baseline = ResolvedNode(identity: rootIdentity, kind: .view("Root"))
    let timestamp = MonotonicInstant.now()
    controller.processResolvedTree(baseline, transaction: .init(), timestamp: timestamp)

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: insertedIdentity,
      viewNodeID: insertedNodeID,
      transition: AnyTransition.slide
    )
    controller.finishTransitionCollection()
    let target = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [
        ResolvedNode(
          viewNodeID: insertedNodeID,
          identity: insertedIdentity,
          kind: .view("Inserted")
        )
      ]
    )

    controller.processResolvedTree(
      target,
      transactionPlan: FrameAnimationTransactionPlan(
        base: .init(),
        segments: [
          segment(identity: insertedIdentity, animation: animation, batchID: batchID)
        ]
      ),
      timestamp: timestamp
    )

    let state = controller.debugStateSnapshot()
    #expect(
      state.activeAnimationBoxesByKey[
        AnimationKey(identity: insertedIdentity, scope: .insertionOffset)
      ] == animation.animationBox
    )
    #expect(state.batchRefCounts[batchID] == 1)
  }

  @Test("rebased removal selects its structural parent's transaction")
  func rebasedRemovalUsesStructuralParentAnimation() {
    let controller = AnimationController()
    let animation = Animation.easeOut(duration: .milliseconds(300))
    let batchID = AnimationBatchID(16_106)
    let rootIdentity = testIdentity("removal-root")
    let removedIdentity = testIdentity("authored-absolute-removed-id")
    let removedNodeID = ViewNodeID(rawValue: 16_106)
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: removedIdentity,
      viewNodeID: removedNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()
    let baseline = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [
        ResolvedNode(
          viewNodeID: removedNodeID,
          identity: removedIdentity,
          kind: .view("Removed")
        )
      ]
    )
    let timestamp = MonotonicInstant.now()
    controller.processResolvedTree(baseline, transaction: .init(), timestamp: timestamp)

    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    let target = ResolvedNode(identity: rootIdentity, kind: .view("Root"))
    controller.processResolvedTree(
      target,
      transactionPlan: FrameAnimationTransactionPlan(
        base: .init(),
        segments: [
          segment(identity: rootIdentity, animation: animation, batchID: batchID)
        ]
      ),
      timestamp: timestamp
    )

    #expect(
      controller.debugStateSnapshot().removalAnimationBoxesByNodeID[removedNodeID]
        == animation.animationBox
    )
  }

  @Test("matched geometry selects the destination identity's transaction")
  func matchedGeometryUsesIdentitySpecificAnimation() {
    let controller = AnimationController()
    let animation = Animation.easeInOut(duration: .milliseconds(300))
    let batchID = AnimationBatchID(16_107)
    let rootIdentity = testIdentity("matched-root")
    let sourceIdentity = testIdentity("matched-root", "source")
    let destinationIdentity = testIdentity("matched-root", "destination")
    let key = MatchedGeometryKey(id: "segmented-match")
    let baseline = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [matchedNode(identity: sourceIdentity, key: key)]
    )
    let timestamp = MonotonicInstant.now()
    controller.processResolvedTree(baseline, transaction: .init(), timestamp: timestamp)
    controller.capturePlacedTree(
      PlacedNode(
        identity: rootIdentity,
        bounds: CellRect(origin: .zero, size: CellSize(width: 40, height: 4)),
        children: [
          PlacedNode(
            identity: sourceIdentity,
            bounds: CellRect(origin: .zero, size: CellSize(width: 5, height: 1)),
            matchedGeometry: MatchedGeometryConfig(key: key)
          )
        ]
      )
    )
    let target = ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [matchedNode(identity: destinationIdentity, key: key)]
    )

    controller.processResolvedTree(
      target,
      transactionPlan: FrameAnimationTransactionPlan(
        base: .init(),
        segments: [
          segment(identity: destinationIdentity, animation: animation, batchID: batchID)
        ]
      ),
      timestamp: timestamp
    )

    let state = controller.debugStateSnapshot()
    #expect(
      state.activeAnimationBoxesByKey[
        AnimationKey(identity: destinationIdentity, scope: .matchedGeometry)
      ] == animation.animationBox
    )
    #expect(state.batchRefCounts[batchID] == 1)
  }

  @Test("two same-turn withAnimation scopes retain distinct curves end to end")
  func sameTurnWithAnimationScopesKeepDistinctCurves() throws {
    let firstAnimation = Animation.linear(duration: .seconds(100))
    let secondAnimation = Animation.easeIn(duration: .seconds(100))
    let rootIdentity = testIdentity("same-turn-segment-root")
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: SegmentedAnimationTestSurface(),
      terminalInputReader: SegmentedAnimationTestInputReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      viewBuilder: ScopedMapper { _ in
        SameTurnAnimationProbe(
          firstAnimation: firstAnimation,
          secondAnimation: secondAnimation
        )
      }
    )
    let controller = runLoop.renderer.internalAnimationController

    try withAnimationSinks(controller) {
      scheduler.requestInvalidation(of: [rootIdentity])
      var renderedFrames = 0
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    }

    let boxes = Set(controller.debugStateSnapshot().activeAnimationBoxesByKey.values)
    #expect(boxes.contains(firstAnimation.animationBox))
    #expect(boxes.contains(secondAnimation.animationBox))
  }

  private func segment(
    identity: Identity,
    animation: Animation,
    batchID: AnimationBatchID
  ) -> AnimationInvalidationSegment {
    AnimationInvalidationSegment(
      identities: [identity],
      animationRequest: .animate(animation.animationBox),
      animationBatchID: batchID
    )
  }

  private func tree(
    rootIdentity: Identity,
    firstIdentity: Identity,
    firstOpacity: Double,
    secondIdentity: Identity,
    secondOpacity: Double
  ) -> ResolvedNode {
    ResolvedNode(
      identity: rootIdentity,
      kind: .view("Root"),
      children: [
        leaf(identity: firstIdentity, name: "First", opacity: firstOpacity),
        leaf(identity: secondIdentity, name: "Second", opacity: secondOpacity),
      ]
    )
  }

  private func leaf(
    identity: Identity,
    name: String,
    opacity: Double
  ) -> ResolvedNode {
    var metadata = DrawMetadata()
    metadata.baseStyle.explicitOpacity = opacity
    return ResolvedNode(
      identity: identity,
      kind: .view(name),
      drawMetadata: metadata
    )
  }

  private func matchedNode(
    identity: Identity,
    key: MatchedGeometryKey
  ) -> ResolvedNode {
    var node = ResolvedNode(identity: identity, kind: .view("Matched"))
    node.matchedGeometry = MatchedGeometryConfig(key: key)
    return node
  }
}

private struct SameTurnAnimationProbe: View {
  var firstAnimation: Animation
  var secondAnimation: Animation

  var body: some View {
    HStack {
      SameTurnAnimationLeaf(label: "First", animation: firstAnimation)
      SameTurnAnimationLeaf(label: "Second", animation: secondAnimation)
    }
  }
}

private struct SameTurnAnimationLeaf: View {
  var label: String
  var animation: Animation
  @State private var opacity = 1.0

  var body: some View {
    Text(label)
      .opacity(opacity)
      .onAppear {
        withAnimation(animation) {
          opacity = 0.25
        }
      }
  }
}

private final class SegmentedAnimationTestInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class SegmentedAnimationTestSurface: PresentationSurface {
  let surfaceSize = CellSize(width: 40, height: 4)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}

  @discardableResult
  func present(_: RasterSurface) throws -> TerminalPresentationMetrics {
    TerminalPresentationMetrics()
  }
}
