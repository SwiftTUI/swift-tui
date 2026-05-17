import Foundation
import Testing

@testable import SwiftTUICore

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

@MainActor
@Suite
struct Phase0FoundationTests {
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
