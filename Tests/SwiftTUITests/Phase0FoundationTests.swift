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
    // The later deadline must SURVIVE the earlier one firing (F41): the
    // single-slot min-coalescing this test used to codify silently discarded
    // it, which is how a long-press timer's wake was eaten by any nearer
    // animation/momentum tick.
    #expect(secondFrame.nextDeadline == laterDeadline)
    #expect(scheduler.hasPendingFrame(at: deadline) == false)

    let thirdFrame = try #require(scheduler.consumeReadyFrame(at: laterDeadline))
    #expect(thirdFrame.causes == Set([.deadline]))
    #expect(thirdFrame.triggeredDeadline == laterDeadline)
    #expect(thirdFrame.nextDeadline == nil)
  }

  @Test("deadlines coalesce as a set: firing the nearest retains the rest")
  func schedulerRetainsLaterDeadlinesAcrossConsumes() throws {
    // The long-press loss shape (F41): a gesture arms its wake once at
    // press + 500 ms; a nearer animation tick (33 ms) must not eat it.
    let scheduler = FrameScheduler()
    let now = MonotonicInstant(offset: .seconds(20_000))
    let longPressWake = now.advanced(by: .milliseconds(500))
    let animationTick = now.advanced(by: .milliseconds(33))

    scheduler.requestDeadline(longPressWake)
    scheduler.requestDeadline(animationTick)
    // Duplicate arms coalesce.
    scheduler.requestDeadline(animationTick)

    let tickFrame = try #require(
      scheduler.consumeReadyFrame(at: now.advanced(by: .milliseconds(40)))
    )
    #expect(tickFrame.triggeredDeadline == animationTick)
    #expect(tickFrame.nextDeadline == longPressWake)

    // The long-press wake still fires on its own timer.
    let pressFrame = try #require(scheduler.consumeReadyFrame(at: longPressWake))
    #expect(pressFrame.triggeredDeadline == longPressWake)
    #expect(pressFrame.nextDeadline == nil)
  }

  @Test("multiple overdue deadlines drain in one frame at the latest due instant")
  func schedulerDrainsAllOverdueDeadlinesInOneFrame() throws {
    let scheduler = FrameScheduler()
    let now = MonotonicInstant(offset: .seconds(30_000))
    let first = now.advanced(by: .milliseconds(10))
    let second = now.advanced(by: .milliseconds(20))
    let future = now.advanced(by: .seconds(5))

    scheduler.requestDeadline(second)
    scheduler.requestDeadline(first)
    scheduler.requestDeadline(future)

    let frame = try #require(scheduler.consumeReadyFrame(at: now.advanced(by: .seconds(1))))
    // Both overdue deadlines drain in this frame; the triggered instant is the
    // LATEST due one so every consumer whose deadline passed sees itself due.
    #expect(frame.triggeredDeadline == second)
    #expect(frame.nextDeadline == future)
    #expect(scheduler.hasPendingFrame(at: now.advanced(by: .seconds(1))) == false)
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
