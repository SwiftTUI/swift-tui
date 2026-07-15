import Foundation
import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("Proposal -003 teardown reachability")
struct TeardownReachabilityBaselineTests {
  @Test("manual hosted-subtree anchor API has no production invocations")
  func manualHostedSubtreeAnchorAPIHasNoProductionInvocations() throws {
    let repositoryRoot = try SourceParsingTestSupport.repositoryRoot()
    let sourcesRoot = repositoryRoot.appendingPathComponent("Sources")
    let enumerator = try #require(
      FileManager.default.enumerator(
        at: sourcesRoot,
        includingPropertiesForKeys: nil
      )
    )
    var invocationCountsByPath: [String: Int] = [:]

    for case let sourceURL as URL in enumerator where sourceURL.pathExtension == "swift" {
      let source = try String(contentsOf: sourceURL, encoding: .utf8)
      let rawCount =
        source.components(
          separatedBy: "recordDetachedHostedSubtree("
        ).count - 1
      let declarationCount = source.components(separatedBy: .newlines).count { line in
        line.contains("func recordDetachedHostedSubtree(")
      }
      let invocationCount = rawCount - declarationCount
      guard invocationCount > 0 else {
        continue
      }
      let relativePath = String(
        sourceURL.path.dropFirst(repositoryRoot.path.count + 1)
      )
      invocationCountsByPath[relativePath] = invocationCount
    }

    #expect(invocationCountsByPath.isEmpty)
  }

  @Test("inactive entity homes are not kept")
  func inactiveEntityHomesAreNotKept() {
    #expect(
      !entityHomeQualifiesForLifetime(
        EntityHomeLifetimeFacts(
          entityIsActive: false,
          routeOwnsNode: true,
          occurrence: 0,
          resolvedIdentityIndexOwnsNode: true
        )
      )
    )
  }

  @Test("primary entity homes require route and resolved-identity index ownership")
  func primaryEntityHomesRequireRouteAndResolvedIdentityIndexOwnership() {
    #expect(
      !entityHomeQualifiesForLifetime(
        EntityHomeLifetimeFacts(
          entityIsActive: true,
          routeOwnsNode: false,
          occurrence: 0,
          resolvedIdentityIndexOwnsNode: true
        )
      )
    )
    #expect(
      !entityHomeQualifiesForLifetime(
        EntityHomeLifetimeFacts(
          entityIsActive: true,
          routeOwnsNode: true,
          occurrence: 0,
          resolvedIdentityIndexOwnsNode: false
        )
      )
    )
    #expect(
      entityHomeQualifiesForLifetime(
        EntityHomeLifetimeFacts(
          entityIsActive: true,
          routeOwnsNode: true,
          occurrence: 0,
          resolvedIdentityIndexOwnsNode: true
        )
      )
    )
  }

  @Test("duplicate entity occurrences are exempt from index ownership")
  func duplicateEntityOccurrencesAreExemptFromIndexOwnership() {
    #expect(
      entityHomeQualifiesForLifetime(
        EntityHomeLifetimeFacts(
          entityIsActive: true,
          routeOwnsNode: true,
          occurrence: 1,
          resolvedIdentityIndexOwnsNode: false
        )
      )
    )
    #expect(
      !entityHomeQualifiesForLifetime(
        EntityHomeLifetimeFacts(
          entityIsActive: false,
          routeOwnsNode: true,
          occurrence: 1,
          resolvedIdentityIndexOwnsNode: false
        )
      )
    )
  }

  @Test("barrier trace distinguishes enqueued and consumed work")
  func barrierTraceDistinguishesEnqueuedAndConsumedWork() {
    let enqueuedNodeID = ViewNodeID(rawValue: 41)
    let consumedNodeID = ViewNodeID(rawValue: 42)
    let recorder = TeardownBarrierTraceRecorder(caller: .preview)
    recorder.record(
      stage: .staleDetachedHostedRoot,
      nodesBefore: [enqueuedNodeID, consumedNodeID],
      nodesAfter: [enqueuedNodeID],
      workBefore: TeardownWorkSnapshot(
        entityRoutedRemovalNodeIDs: [],
        absorbedShadowNodeIDs: [],
        departedNavigationSurfaceNodeIDs: [consumedNodeID]
      ),
      workAfter: TeardownWorkSnapshot(
        entityRoutedRemovalNodeIDs: [enqueuedNodeID],
        absorbedShadowNodeIDs: [],
        departedNavigationSurfaceNodeIDs: []
      )
    )

    let stage = recorder.trace.stages[0]
    #expect(stage.removedNodeIDs == [consumedNodeID])
    #expect(stage.enqueuedWork.entityRoutedRemovalNodeIDs == [enqueuedNodeID])
    #expect(
      stage.consumedWork.departedNavigationSurfaceNodeIDs == [consumedNodeID]
    )
    #expect(stage.endingWork.entityRoutedRemovalNodeIDs == [enqueuedNodeID])
  }

  @Test("preview and finalize expose the same reachability and barrier order")
  func previewAndFinalizeExposeTheSameReachabilityAndBarrierOrder() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let resolved = ResolvedNode(
      identity: rootIdentity,
      kind: .root,
      children: [ResolvedNode(identity: childIdentity, kind: .view("Child"))]
    )
    _ = graph.applySnapshot(resolved)

    let IDsByIdentity = graph.debugTotalStateSnapshot().nodeIDByIdentity
    let rootNodeID = try #require(IDsByIdentity[rootIdentity])
    let childNodeID = try #require(IDsByIdentity[childIdentity])
    let candidate = graph.snapshot(rootIdentity: rootIdentity)
    graph.beginFrame()
    graph.recordReusedSubtree(candidate, invalidator: nil)
    let checkpoint = graph.makeCheckpoint()

    let previewTrace = TeardownBarrierTraceRecorder(caller: .preview)
    _ = graph.previewLifecycleEventPlan(
      resolved: candidate,
      placed: nil,
      debugTeardownTrace: previewTrace
    )
    let previewReachability = try #require(
      graph.debugLifetimeReachabilitySnapshot()
    )
    #expect(previewReachability.storedNodeIDs == [rootNodeID, childNodeID])
    #expect(previewReachability.reachableNodeIDs == [rootNodeID, childNodeID])
    #expect(previewReachability.keepReasonsByNodeID[rootNodeID] == .root)
    #expect(
      previewReachability.keepReasonsByNodeID[childNodeID]
        == .parent(rootNodeID)
    )
    #expect(previewReachability.unreachableNodeIDs.isEmpty)
    #expect(graph.debugTeardownCoherenceViolation() == nil)
    graph.restoreCheckpoint(checkpoint)
    let finalizeTrace = TeardownBarrierTraceRecorder(caller: .finalize)
    _ = graph.finalizeFrame(
      rootIdentity: rootIdentity,
      resolved: candidate,
      placed: nil,
      debugTeardownTrace: finalizeTrace
    )
    let finalizeReachability = try #require(
      graph.debugLifetimeReachabilitySnapshot()
    )

    let expectedStageOrder = TeardownBarrierStage.allCases
    #expect(previewTrace.trace.stages.map(\.stage) == expectedStageOrder)
    #expect(finalizeTrace.trace.stages.map(\.stage) == expectedStageOrder)
    #expect(previewTrace.trace.endingWork.totalCount == 0)
    #expect(finalizeTrace.trace.endingWork.totalCount == 0)
    #expect(finalizeReachability == previewReachability)
    #expect(graph.debugTeardownCoherenceViolation() == nil)
  }

  @Test("preview teardown mutations roll back across the total graph checkpoint")
  func previewTeardownMutationsRollBackAcrossTheTotalGraphCheckpoint() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let orphanIdentity = testIdentity("Orphan")
    let resolved = ResolvedNode(identity: rootIdentity, kind: .root)
    _ = graph.applySnapshot(resolved)

    graph.beginFrame()
    let orphan = graph.beginEvaluation(identity: orphanIdentity, invalidator: nil)
    _ = graph.finishEvaluation(
      orphan,
      resolved: ResolvedNode(identity: orphanIdentity, kind: .view("Orphan")),
      accessedStateSlots: 0
    )

    let candidate = graph.snapshot(rootIdentity: rootIdentity)
    graph.beginFrame()
    graph.recordReusedSubtree(candidate, invalidator: nil)
    graph.debugEnqueueTeardownWork(
      .departedNavigationSurface,
      nodeID: orphan.viewNodeID
    )
    let beforePreview = graph.debugTotalStateSnapshot()
    let checkpoint = graph.makeCheckpoint()

    let previewTrace = TeardownBarrierTraceRecorder(caller: .preview)
    _ = graph.previewLifecycleEventPlan(
      resolved: candidate,
      placed: nil,
      debugTeardownTrace: previewTrace
    )
    #expect(graph.debugTotalStateSnapshot() != beforePreview)
    let previewDeparture = try #require(
      previewTrace.trace.stages.first { $0.stage == .departedNavigationSurface }
    )
    #expect(previewDeparture.removedNodeIDs == [orphan.viewNodeID])
    #expect(
      previewDeparture.consumedWork.departedNavigationSurfaceNodeIDs
        == [orphan.viewNodeID]
    )
    #expect(previewTrace.trace.endingWork.totalCount == 0)
    #expect(graph.debugTeardownCoherenceViolation() == nil)

    graph.restoreCheckpoint(checkpoint)
    #expect(graph.debugTotalStateSnapshot() == beforePreview)

    let finalizeTrace = TeardownBarrierTraceRecorder(caller: .finalize)
    _ = graph.finalizeFrame(
      rootIdentity: rootIdentity,
      resolved: candidate,
      placed: nil,
      debugTeardownTrace: finalizeTrace
    )
    let finalizeDeparture = try #require(
      finalizeTrace.trace.stages.first { $0.stage == .departedNavigationSurface }
    )
    #expect(finalizeDeparture.removedNodeIDs == previewDeparture.removedNodeIDs)
    #expect(finalizeDeparture.consumedWork == previewDeparture.consumedWork)
    #expect(finalizeTrace.trace.endingWork.totalCount == 0)
    #expect(graph.debugTeardownCoherenceViolation() == nil)
  }
}
