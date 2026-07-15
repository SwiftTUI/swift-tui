import Foundation
import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("Teardown barrier fixed point")
struct TeardownBarrierFixedPointTests {
  @Test("preview and finalize delegate teardown only to the shared barrier")
  func previewAndFinalizeUseOnlySharedBarrier() throws {
    let source = try SourceParsingTestSupport.sourceText(
      relativePath: "Sources/SwiftTUIGraph/Resolve/ViewGraph.swift"
    )

    #expect(source.components(separatedBy: "settleTeardownBarrier(").count - 1 == 4)
    #expect(source.components(separatedBy: "runTeardownStage(").count - 1 == 6)
    #expect(
      source.components(separatedBy: "prunePendingEntityRoutedRemovals(").count - 1 == 1
    )
    #expect(source.components(separatedBy: "pruneAbsorbedShadowedNodes(").count - 1 == 1)
  }

  @Test("resolve-scope scratch is consumed before the other teardown stages")
  func resolveScopeScratchIsFirstAndLeavesNoWork() throws {
    let (graph, root, orphan) = try graphWithOrphan()
    graph.debugEnqueueTeardownWork(
      .resolveScopeScratch,
      nodeID: orphan.viewNodeID
    )
    let trace = TeardownBarrierTraceRecorder(caller: .preview)

    let result = graph.debugSettleTeardownBarrier(
      resolved: root,
      trace: trace
    )

    #expect(result.didConverge)
    #expect(result.iterationCount == 2)
    #expect(graph.nodeForViewNodeID(orphan.viewNodeID) == nil)
    #expect(trace.trace.endingWork.totalCount == 0)
    assertStableStageOrder(trace.trace)
    let firstStage = try #require(trace.trace.stages.first)
    #expect(firstStage.stage == .resolveScopeScratch)
    #expect(firstStage.consumedWork.resolveScopeScratchNodeIDs == [orphan.viewNodeID])
  }

  @Test("entity work enqueued after its stage settles on the next outer iteration")
  func lateEntityWorkSettlesOnNextIteration() throws {
    let entity = EntityIdentity("late")
    let (graph, root, orphan) = try graphWithOrphan(entity: entity)
    let trace = TeardownBarrierTraceRecorder(caller: .preview)

    let result = graph.debugSettleTeardownBarrier(
      resolved: root,
      trace: trace
    ) { stage, iteration in
      if stage == .entityRoutedRemoval, iteration == 0 {
        graph.debugEnqueueTeardownWork(
          .entityRoutedRemoval,
          nodeID: orphan.viewNodeID
        )
      }
    }

    #expect(result.didConverge)
    #expect(result.iterationCount == 3)
    #expect(graph.nodeForViewNodeID(orphan.viewNodeID) == nil)
    #expect(trace.trace.endingWork.totalCount == 0)
    assertStableStageOrder(trace.trace)
    let consumingStage = try #require(
      trace.trace.stages.first {
        $0.iteration == 1 && $0.stage == .entityRoutedRemoval
      }
    )
    #expect(consumingStage.consumedWork.entityRoutedRemovalNodeIDs == [orphan.viewNodeID])
  }

  @Test("a re-enqueuing stage trips the no-progress convergence alarm")
  func reEnqueuingStageTripsNonConvergenceAlarm() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    _ = graph.applySnapshot(ResolvedNode(identity: rootIdentity, kind: .root))
    let root = graph.snapshot(rootIdentity: rootIdentity)
    graph.beginFrame()
    graph.recordReusedSubtree(root, invalidator: nil)
    let impossibleNodeID = ViewNodeID(rawValue: UInt64.max)
    let alarmBefore = SoundnessProbeConfiguration.barrierNonConvergenceCount

    let result = graph.debugSettleTeardownBarrier(resolved: root) { stage, _ in
      if stage == .departedNavigationSurface {
        graph.debugEnqueueTeardownWork(
          .departedNavigationSurface,
          nodeID: impossibleNodeID
        )
      }
    }

    #expect(!result.didConverge)
    #expect(result.iterationCount < result.iterationBound)
    #expect(SoundnessProbeConfiguration.barrierNonConvergenceCount == alarmBefore + 1)
  }

  private func graphWithOrphan(
    entity: EntityIdentity? = nil
  ) throws -> (ViewGraph, ResolvedNode, ViewNode) {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    _ = graph.applySnapshot(ResolvedNode(identity: rootIdentity, kind: .root))

    graph.beginFrame()
    let orphanIdentity = testIdentity("Orphan")
    let orphan = graph.beginEvaluation(
      identity: orphanIdentity,
      entityIdentity: entity,
      invalidator: nil
    )
    var orphanResolved = ResolvedNode(
      identity: orphanIdentity,
      kind: .view("Orphan")
    )
    if let entity {
      orphanResolved.attachingEntityIdentity(
        entity,
        at: orphanResolved.structuralPath
      )
    }
    _ = graph.finishEvaluation(
      orphan,
      resolved: orphanResolved,
      accessedStateSlots: 0
    )

    let root = graph.snapshot(rootIdentity: rootIdentity)
    graph.beginFrame()
    graph.recordReusedSubtree(root, invalidator: nil)
    return (graph, root, orphan)
  }

  private func assertStableStageOrder(
    _ trace: TeardownBarrierTrace,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let stagesByIteration = Dictionary(grouping: trace.stages, by: \.iteration)
    for iteration in stagesByIteration.keys.sorted() {
      #expect(
        stagesByIteration[iteration]?.map(\.stage) == TeardownBarrierStage.allCases,
        "iteration \(iteration)",
        sourceLocation: sourceLocation
      )
    }
  }
}
