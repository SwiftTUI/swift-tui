import Foundation
import Testing

@testable import Core

private final class InteractionInstallerSpy {
  private(set) var installedRegions: [InteractionRegion] = []

  func installInteractionRegions(_ regions: [InteractionRegion]) {
    installedRegions = regions
  }
}

private final class LifecycleStagerSpy {
  private(set) var stagedEntries: [LifecycleCommitEntry] = []
  private(set) var transaction: TransactionSnapshot?

  func stageLifecycleEntries(
    _ entries: [LifecycleCommitEntry],
    transaction: TransactionSnapshot
  ) {
    stagedEntries = entries
    self.transaction = transaction
  }
}

private final class HandlerInstallerSpy {
  private(set) var installations: [HandlerInstallation] = []

  func installHandlers(_ installations: [HandlerInstallation]) {
    self.installations = installations
  }
}

private struct CommitBoundaryHarness {
  let interactionInstaller: InteractionInstallerSpy
  let lifecycleStager: LifecycleStagerSpy
  let handlerInstaller: HandlerInstallerSpy

  func stage(_ plan: CommitPlan) {
    interactionInstaller.installInteractionRegions(plan.semanticSnapshot.interactionRegions)
    lifecycleStager.stageLifecycleEntries(plan.lifecycle, transaction: plan.transaction)
    handlerInstaller.installHandlers(plan.handlerInstallations)
  }
}

private func sampleResolvedNode(
  identity: Identity = testIdentity("Root"),
  context: FrameContext = .init(),
  intrinsicSize: CellSize = .init(width: 12, height: 4)
) -> ResolvedNode {
  ResolvedNode(
    identity: identity,
    kind: .root,
    environmentSnapshot: context.environment,
    transactionSnapshot: context.transaction,
    intrinsicSize: intrinsicSize
  )
}

private func sampleMeasuredNode(
  identity: Identity = testIdentity("Root"),
  size: CellSize = .init(width: 12, height: 4)
) -> MeasuredNode {
  MeasuredNode(
    identity: identity,
    proposal: .init(width: size.width, height: size.height),
    measuredSize: size
  )
}

private func samplePlacedNode(
  identity: Identity = testIdentity("Root"),
  width: Int = 12,
  height: Int = 4
) -> PlacedNode {
  PlacedNode(
    identity: identity,
    bounds: .init(
      origin: .zero,
      size: .init(width: width, height: height)
    ),
    semanticRole: .container
  )
}

@MainActor
@Suite
struct Phase0FoundationTests {
  @Test("renderer executes the fresh-core phase order strictly")
  func rendererExecutesPhasesInOrder() {
    var phases: [Phase] = []
    let identity = testIdentity("Root")
    let context = FrameContext(
      environment: .init(debugSignature: "env"),
      transaction: .init(debugSignature: "txn"),
      invalidatedIdentities: [identity]
    )

    let renderer = Renderer<String>(
      resolvePhase: { root, context in
        phases.append(.resolve)
        #expect(root == "root")
        #expect(context.invalidatedIdentities == [identity])
        return sampleResolvedNode(identity: identity, context: context)
      },
      measurePhase: { resolved, _ in
        phases.append(.measure)
        #expect(resolved.identity == identity)
        return sampleMeasuredNode(identity: resolved.identity)
      },
      placePhase: { measured, _ in
        phases.append(.place)
        #expect(measured.identity == identity)
        return samplePlacedNode(identity: measured.identity)
      },
      semanticsPhase: { placed, _ in
        phases.append(.semantics)
        #expect(placed.identity == identity)
        return SemanticSnapshot()
      },
      drawPhase: { placed, _ in
        phases.append(.draw)
        #expect(placed.bounds.size == .init(width: 12, height: 4))
        return DrawNode(identity: placed.identity, bounds: placed.bounds)
      },
      rasterPhase: { draw, _ in
        phases.append(.raster)
        #expect(draw.identity == identity)
        return RasterSurface(size: .init(width: 12, height: 4), lines: ["ok"])
      },
      commitPhase: { resolved, measured, placed, semantics, draw, raster, context in
        phases.append(.commit)
        #expect(resolved.identity == identity)
        #expect(measured.identity == identity)
        #expect(placed.identity == identity)
        #expect(semantics.interactionRegions.isEmpty)
        #expect(draw.identity == identity)
        #expect(raster.lines == ["ok", "", "", ""])
        return CommitPlan(transaction: context.transaction)
      }
    )

    let artifacts = renderer.renderFrame(root: "root", context: context)

    #expect(phases == Phase.allCases)
    #expect(artifacts.resolvedTree.identity == identity)
    #expect(artifacts.placedTree.bounds.size == .init(width: 12, height: 4))
    #expect(artifacts.commitPlan.transaction.debugSignature == "txn")
    #expect(artifacts.diagnostics.proposal == .init(width: 12, height: 4))
    #expect(artifacts.diagnostics.resolvedNodeCount == 1)
    #expect(artifacts.diagnostics.measuredNodeCount == 1)
    #expect(artifacts.diagnostics.placedNodeCount == 1)
    #expect(artifacts.diagnostics.drawNodeCount == 1)
    #expect(artifacts.diagnostics.invalidatedIdentities == [identity])
    #expect(artifacts.diagnostics.measurementCache == nil)
  }

  @Test("no-op renderer produces an empty frame that can idle behind the scheduler")
  func noOpRendererProducesEmptyFrame() {
    let root = NoOpRoot(identity: testIdentity("NoOp"), intrinsicSize: .zero)
    let renderer = Renderer<NoOpRoot>.noOp()
    let artifacts = renderer.renderFrame(root: root)
    let scheduler = FrameScheduler()

    #expect(artifacts.resolvedTree.identity == root.identity)
    #expect(artifacts.measuredTree.measuredSize == .zero)
    #expect(artifacts.semanticSnapshot.interactionRegions.isEmpty)
    #expect(artifacts.drawTree.commands.isEmpty)
    #expect(artifacts.rasterSurface.lines.isEmpty)
    #expect(scheduler.hasPendingFrame(at: .zero) == false)
    #expect(scheduler.nextWakeInstant(after: .zero) == nil)
  }

  @Test("scheduler coalesces invalidations and preserves the earliest deadline")
  func schedulerCoalescesWakeCauses() throws {
    let scheduler = FrameScheduler()
    let now = MonotonicInstant(offset: .seconds(10_000))
    let deadline = now.advanced(by: .seconds(5))
    let laterDeadline = now.advanced(by: .seconds(20))
    let identity = testIdentity("Leaf")

    scheduler.requestInvalidation(of: [identity])
    scheduler.requestInput()
    scheduler.requestSignal(named: "SIGWINCH")
    scheduler.requestDeadline(laterDeadline)
    scheduler.requestDeadline(deadline)

    let immediateWake = try #require(scheduler.nextWakeInstant(after: now))
    #expect(immediateWake == now)

    let firstFrame = try #require(scheduler.consumeReadyFrame(at: now))
    #expect(firstFrame.causes.contains(.input))
    #expect(firstFrame.causes.contains(.invalidation))
    #expect(firstFrame.causes.contains(.signal))
    #expect(firstFrame.invalidatedIdentities == Set([identity]))
    #expect(firstFrame.signalNames == ["SIGWINCH"])
    #expect(firstFrame.triggeredDeadline == nil)
    #expect(firstFrame.nextDeadline == deadline)

    let nextWake = try #require(scheduler.nextWakeInstant(after: now))
    #expect(nextWake == deadline)

    let secondFrame = try #require(scheduler.consumeReadyFrame(at: deadline))
    #expect(secondFrame.causes == Set([.deadline]))
    #expect(secondFrame.triggeredDeadline == deadline)
    #expect(secondFrame.nextDeadline == nil)
    #expect(scheduler.hasPendingFrame(at: deadline) == false)
  }

  @Test("commit staging boundaries route semantics, lifecycle, and handlers explicitly")
  func commitStagingBoundariesRoutePlan() {
    let interactionInstaller = InteractionInstallerSpy()
    let lifecycleStager = LifecycleStagerSpy()
    let handlerInstaller = HandlerInstallerSpy()
    let harness = CommitBoundaryHarness(
      interactionInstaller: interactionInstaller,
      lifecycleStager: lifecycleStager,
      handlerInstaller: handlerInstaller
    )
    let identity = testIdentity("Button")
    let routeID = testRoute("Button")
    let plan = CommitPlan(
      transaction: .init(debugSignature: "txn"),
      semanticSnapshot: SemanticSnapshot(
        interactionRegions: [
          .init(
            identity: identity,
            rect: .init(
              origin: .init(x: 8, y: 3),
              size: .init(width: 6, height: 1)
            ),
            routeID: routeID
          )
        ]
      ),
      lifecycle: [
        .init(
          identity: identity,
          operation: .appear(handlerIDs: ["appear"])
        ),
        .init(
          identity: identity,
          operation: .taskStart(.init(id: "task", priority: .medium))
        ),
        .init(
          identity: identity,
          operation: .disappear(handlerIDs: ["disappear"])
        ),
      ],
      handlerInstallations: [
        .init(handlerID: routeID)
      ]
    )

    harness.stage(plan)

    #expect(interactionInstaller.installedRegions == plan.semanticSnapshot.interactionRegions)
    #expect(lifecycleStager.stagedEntries == plan.lifecycle)
    #expect(lifecycleStager.transaction == plan.transaction)
    #expect(handlerInstaller.installations == plan.handlerInstallations)
  }
}
