import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

/// F43: committed lifecycle work must not be droppable in silence.
///
/// `LifecycleCoordinator.apply` bails when a `.taskStart`'s registration or
/// view-node lookup fails at commit time. A committed plan only carries
/// `.taskStart` for work the graph decided must run, so a skipped start is a
/// `.task` that silently never ran — the failure mode that cost the
/// entity-rebind investigation a full instrumented session
/// (docs/plans/2026-07-01-002). These tests pin the observability contract:
/// suspicious skips are counted and surfaced as runtime issues; departed-node
/// cancels stay benign and unreported.
@MainActor
@Suite("Lifecycle commit skip observability")
struct LifecycleCoordinatorSkipTests {
  @Test("a .taskStart with no matching registration is counted and reported")
  func taskStartWithoutRegistrationIsCountedAndReported() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: false)
    let descriptor = TaskDescriptor(id: "orphaned-start", priority: .medium)
    let plan = CommitPlan(
      lifecycle: [
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: testIdentity("Root", "missing"),
          operation: .taskStart(descriptor)
        )
      ]
    )

    let issues = coordinator.applyCommittedFrame(
      plan: plan,
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: LocalTaskRegistry()
    )

    #expect(coordinator.taskStartSkipCount == 1)
    #expect(coordinator.activeTaskCount == 0)
    #expect(issues.count == 1)
    #expect(issues.first?.code == "lifecycle.taskStartSkipped")
    #expect(issues.first?.severity == .warning)
    #expect(issues.first?.identity == testIdentity("Root", "missing"))
    #expect(issues.first?.message.contains("task registration") == true)
  }

  @Test("a .taskStart with no view node is counted and reported")
  func taskStartWithoutViewNodeIsCountedAndReported() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: false)
    let identity = testIdentity("Root", "task-holder")
    let descriptor = TaskDescriptor(id: "unrouted-start", priority: .medium)
    let taskRegistry = LocalTaskRegistry()
    taskRegistry.register(
      identity: identity,
      registration: TaskRegistration(descriptor: descriptor) {}
    )
    let plan = CommitPlan(
      lifecycle: [
        .init(identity: identity, operation: .taskStart(descriptor))
      ]
    )

    let issues = coordinator.applyCommittedFrame(
      plan: plan,
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: taskRegistry
    )

    #expect(coordinator.taskStartSkipCount == 1)
    #expect(coordinator.activeTaskCount == 0)
    #expect(issues.count == 1)
    #expect(issues.first?.message.contains("view node") == true)
  }

  @Test("a departed-node .taskCancel is a benign skip: counted, never reported")
  func departedNodeTaskCancelIsBenign() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: false)
    let plan = CommitPlan(
      lifecycle: [
        .init(
          identity: testIdentity("Root", "departed"),
          operation: .taskCancel(TaskDescriptor(id: "departed-cancel", priority: .medium))
        )
      ]
    )

    let issues = coordinator.applyCommittedFrame(
      plan: plan,
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: LocalTaskRegistry()
    )

    #expect(coordinator.taskCancelSkipCount == 1)
    #expect(coordinator.taskStartSkipCount == 0)
    #expect(issues.isEmpty)
  }

  /// The carried-stale `.taskStart` class (gallery fuzzer, 2026-07-18,
  /// final-mixed cases 292/302/559): a carry-forward merge dispatches an
  /// earlier frame's start after the site's `.task(id:)` value moved on.
  /// The registry (correctly) holds only the replacement descriptor, so the
  /// stale start must be dropped as superseded — not started, not
  /// skip-warned.
  @Test("a carried start cancelled later in the same plan is superseded, not skipped")
  func carriedStartWithLaterCancelIsSuperseded() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: true)
    let identity = testIdentity("Root", "tab-payload")
    let stale = TaskDescriptor(id: "\(identity)#task[id:1]", priority: .medium)
    let replacement = TaskDescriptor(id: "\(identity)#task[id:2]", priority: .medium)
    let taskRegistry = LocalTaskRegistry()
    taskRegistry.register(
      identity: identity,
      registration: TaskRegistration(descriptor: replacement) {}
    )
    // The 559 shape: carried start prepended, current frame's diff cancels
    // the stale descriptor and starts its replacement.
    let plan = CommitPlan(
      lifecycle: [
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: identity,
          operation: .taskStart(stale)
        ),
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: identity,
          operation: .taskCancel(stale)
        ),
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: identity,
          operation: .taskStart(replacement)
        ),
      ]
    )

    let issues = coordinator.applyCommittedFrame(
      plan: plan,
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: taskRegistry
    )

    #expect(issues.isEmpty)
    #expect(coordinator.taskStartSkipCount == 0)
    #expect(coordinator.taskStartSupersededCount == 1)
    #expect(coordinator.activeTaskCount == 1)
    #expect(coordinator.activeTaskDescriptors[identity]?.map(\.id) == [replacement.id])
  }

  @Test("a cancelled-and-gone carried start is superseded even when its cancel came first")
  func carriedStartReplacedBySameSiteStartIsSuperseded() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: true)
    let identity = testIdentity("Root", "tab-payload")
    let stale = TaskDescriptor(id: "\(identity)#task[id:1]", priority: .medium)
    let replacement = TaskDescriptor(id: "\(identity)#task[id:2]", priority: .medium)
    let taskRegistry = LocalTaskRegistry()
    taskRegistry.register(
      identity: identity,
      registration: TaskRegistration(descriptor: replacement) {}
    )
    // The 302 shape: the pairing cancel landed in an EARLIER plan section
    // (cancel-first order), re-mints duplicated the carried stale start
    // under fresh viewNodeIDs, and the registry has re-registered under the
    // replacement descriptor — the cancelled-and-gone starts must drop.
    let plan = CommitPlan(
      lifecycle: [
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: identity,
          operation: .taskCancel(stale)
        ),
        .init(
          viewNodeID: ViewNodeID(rawValue: 2),
          identity: identity,
          operation: .taskStart(stale)
        ),
        .init(
          viewNodeID: ViewNodeID(rawValue: 3),
          identity: identity,
          operation: .taskStart(stale)
        ),
        .init(
          viewNodeID: ViewNodeID(rawValue: 3),
          identity: identity,
          operation: .taskStart(replacement)
        ),
      ]
    )

    let issues = coordinator.applyCommittedFrame(
      plan: plan,
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: taskRegistry
    )

    #expect(issues.isEmpty)
    #expect(coordinator.taskStartSkipCount == 0)
    #expect(coordinator.taskStartSupersededCount == 2)
    #expect(coordinator.activeTaskCount == 1)
    #expect(coordinator.activeTaskDescriptors[identity]?.map(\.id) == [replacement.id])
  }

  @Test("a restart pair (cancel then start of the same descriptor) still dispatches")
  func restartPairStillDispatches() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: true)
    let identity = testIdentity("Root", "restarting")
    let descriptor = TaskDescriptor(id: "\(identity)#task[id:1]", priority: .medium)
    let taskRegistry = LocalTaskRegistry()
    taskRegistry.register(
      identity: identity,
      registration: TaskRegistration(descriptor: descriptor) {}
    )
    let plan = CommitPlan(
      lifecycle: [
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: identity,
          operation: .taskCancel(descriptor)
        ),
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: identity,
          operation: .taskStart(descriptor)
        ),
      ]
    )

    let issues = coordinator.applyCommittedFrame(
      plan: plan,
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: taskRegistry
    )

    #expect(issues.isEmpty)
    #expect(coordinator.taskStartSupersededCount == 0)
    #expect(coordinator.activeTaskCount == 1)
  }

  @Test("distinct task sites on one identity never supersede each other")
  func distinctSitesOnOneIdentityDoNotSupersede() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: true)
    let identity = testIdentity("Root", "multi-task")
    // One descriptor per distinct authored site, covering the ID grammar's
    // forms (`ViewLifecycleModifiers`' minting): bare ordinal 0, labeled
    // ordinal 0, bare ordinal 1, labeled ordinal 2. No cancels ride the
    // plan and every registration exists, so supersession must not touch
    // any of them (the multi-`.task` contract — stacked modifiers on one
    // identity can even share an ordinal across chain-level owner nodes).
    let descriptors = [
      TaskDescriptor(id: "\(identity)#task", priority: .medium),
      TaskDescriptor(id: "\(identity)#task[id:7]", priority: .medium),
      TaskDescriptor(id: "\(identity)#task[1]", priority: .medium),
      TaskDescriptor(id: "\(identity)#task[2:id:9]", priority: .medium),
    ]
    let taskRegistry = LocalTaskRegistry()
    for descriptor in descriptors {
      taskRegistry.register(
        identity: identity,
        registration: TaskRegistration(descriptor: descriptor) {}
      )
    }
    let plan = CommitPlan(
      lifecycle: descriptors.map { descriptor in
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: identity,
          operation: .taskStart(descriptor)
        )
      }
    )

    let issues = coordinator.applyCommittedFrame(
      plan: plan,
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: taskRegistry
    )

    #expect(issues.isEmpty)
    #expect(coordinator.taskStartSupersededCount == 0)
    #expect(coordinator.activeTaskCount == 4)
  }

  @Test("an .appear handler missing from the current registry is counted and reported")
  func appearHandlerMissingIsCountedAndReported() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: false)
    let plan = CommitPlan(
      lifecycle: [
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: testIdentity("Root", "appearing"),
          operation: .appear(handlerIDs: ["missing-appear"])
        )
      ]
    )

    let issues = coordinator.applyCommittedFrame(
      plan: plan,
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: LocalTaskRegistry()
    )

    #expect(coordinator.appearHandlerSkipCount == 1)
    #expect(issues.count == 1)
    #expect(issues.first?.code == "lifecycle.appearHandlerSkipped")
    #expect(issues.first?.severity == .warning)
    #expect(issues.first?.identity == testIdentity("Root", "appearing"))
  }

  @Test("a .disappear handler missing from the previous snapshot is counted and reported")
  func disappearHandlerMissingIsCountedAndReported() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: false)
    let plan = CommitPlan(
      lifecycle: [
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: testIdentity("Root", "departing"),
          operation: .disappear(handlerIDs: ["missing-disappear"])
        )
      ]
    )

    let issues = coordinator.applyCommittedFrame(
      plan: plan,
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: LocalTaskRegistry()
    )

    #expect(coordinator.disappearHandlerSkipCount == 1)
    #expect(issues.count == 1)
    #expect(issues.first?.code == "lifecycle.disappearHandlerSkipped")
  }

  @Test("an .onChange handler missing from the current registry is counted and reported")
  func changeHandlerMissingIsCountedAndReported() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: false)
    let plan = CommitPlan(
      lifecycle: [
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: testIdentity("Root", "changing"),
          operation: .change(handlerIDs: ["missing-change"])
        )
      ]
    )

    let issues = coordinator.applyCommittedFrame(
      plan: plan,
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: LocalTaskRegistry()
    )

    #expect(coordinator.changeHandlerSkipCount == 1)
    #expect(issues.count == 1)
    #expect(issues.first?.code == "lifecycle.changeHandlerSkipped")
  }

  @Test(
    "an .onChange handler absent from the current registry dispatches from the previous snapshot")
  func changeHandlerFallsBackToPreviousSnapshot() {
    // Gallery fuzzer find (2026-07-17, presentation-lab): a re-minted node
    // adopting a reused resolved artifact never re-runs registration
    // capture, so scoped publication removes the departed owner's change
    // registration while the committed tree still names the handler. The
    // committed callback must dispatch from the previous commit's snapshot
    // (the disappear path's long-standing contract), not silently skip.
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: false)
    let identity = testIdentity("Root", "reused")
    var changeFired = 0

    let firstRegistry = LocalLifecycleRegistry()
    let changeID = firstRegistry.registerChange(identity: identity, ordinal: 0) {
      changeFired += 1
    }
    _ = coordinator.applyCommittedFrame(
      plan: CommitPlan(
        lifecycle: [
          .init(
            viewNodeID: ViewNodeID(rawValue: 1),
            identity: identity,
            operation: .change(handlerIDs: [changeID])
          )
        ]
      ),
      currentLifecycleRegistry: firstRegistry,
      currentTaskRegistry: LocalTaskRegistry()
    )
    #expect(changeFired == 1)

    // Frame 2: the current registry lost the registration (scoped
    // publication removed the departed owner; nothing re-registered), but
    // the committed plan still fires the handler.
    let issues = coordinator.applyCommittedFrame(
      plan: CommitPlan(
        lifecycle: [
          .init(
            viewNodeID: ViewNodeID(rawValue: 2),
            identity: identity,
            operation: .change(handlerIDs: [changeID])
          )
        ]
      ),
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: LocalTaskRegistry()
    )

    #expect(changeFired == 2, "the committed change handler must fire from the snapshot")
    #expect(coordinator.changeHandlerSnapshotFallbackCount == 1)
    #expect(coordinator.changeHandlerSkipCount == 0)
    #expect(issues.isEmpty)

    // The retention must span multi-frame gaps: publication can drop the
    // registration frames before the committed tree stops naming it, with
    // intervening commits that carry no lifecycle entries at all.
    _ = coordinator.applyCommittedFrame(
      plan: CommitPlan(lifecycle: []),
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: LocalTaskRegistry()
    )
    let lateIssues = coordinator.applyCommittedFrame(
      plan: CommitPlan(
        lifecycle: [
          .init(
            viewNodeID: ViewNodeID(rawValue: 3),
            identity: identity,
            operation: .change(handlerIDs: [changeID])
          )
        ]
      ),
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: LocalTaskRegistry()
    )
    #expect(changeFired == 3, "retention must survive commits that republish nothing")
    #expect(lateIssues.isEmpty)
  }

  @Test("a departed subtree's retained change handler is pruned at its disappear")
  func retainedChangeHandlerPrunedOnDisappear() {
    // The retained store is bounded by the framework's departure signal: once
    // a subtree's disappear dispatches, a later (stale) plan naming its
    // change handler must skip-and-report, not fire a departed closure.
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: false)
    let identity = testIdentity("Root", "departing")
    var changeFired = 0

    let firstRegistry = LocalLifecycleRegistry()
    let changeID = firstRegistry.registerChange(identity: identity, ordinal: 0) {
      changeFired += 1
    }
    _ = coordinator.applyCommittedFrame(
      plan: CommitPlan(lifecycle: []),
      currentLifecycleRegistry: firstRegistry,
      currentTaskRegistry: LocalTaskRegistry()
    )

    _ = coordinator.applyCommittedFrame(
      plan: CommitPlan(
        lifecycle: [
          .init(
            viewNodeID: ViewNodeID(rawValue: 1),
            identity: identity,
            operation: .disappear(handlerIDs: [])
          )
        ]
      ),
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: LocalTaskRegistry()
    )

    let issues = coordinator.applyCommittedFrame(
      plan: CommitPlan(
        lifecycle: [
          .init(
            viewNodeID: ViewNodeID(rawValue: 2),
            identity: identity,
            operation: .change(handlerIDs: [changeID])
          )
        ]
      ),
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: LocalTaskRegistry()
    )

    #expect(changeFired == 0, "a pruned handler must not fire after its subtree departed")
    #expect(coordinator.changeHandlerSkipCount == 1)
    #expect(issues.count == 1)
  }

  @Test("a commit-time absorbed registration dispatches after a later publication removes it")
  func commitTimeAbsorbedRegistrationDispatchesAfterRemoval() {
    // Gallery fuzzer find (2026-07-17 §5 residual, presentation-lab sheet
    // `onChange`): a focus-sync convergence re-render (or an elided commit)
    // publishes a frame's registrations and folds its unapplied commit plan
    // into the lifecycle carry-forward — `applyCommittedFrame` never runs
    // for that frame, so apply-time absorption alone never witnesses the
    // registration. When the next pass's scoped publication removes it (the
    // owner's record was reset by a re-evaluation that did not re-trigger),
    // the carried-forward committed callback found it in NO store. The run
    // loop now absorbs every committed publication into the retained store
    // at acquisition time; this pins the coordinator-side contract.
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: false)
    let identity = testIdentity("Root", "sheet", "Group")
    var changeFired = 0

    let registry = LocalLifecycleRegistry()
    let changeID = registry.registerChange(identity: identity, ordinal: 0) {
      changeFired += 1
    }
    // Commit-time absorb: the publishing frame never reaches
    // `applyCommittedFrame`.
    coordinator.absorbPublishedRegistrations(registry.snapshot())

    // A later pass's scoped publication removes the registration with
    // nothing to restore.
    registry.removeSubtrees(rootedAt: [testIdentity("Root", "sheet")])

    // The carried-forward plan finally dispatches.
    let issues = coordinator.applyCommittedFrame(
      plan: CommitPlan(
        lifecycle: [
          .init(
            viewNodeID: ViewNodeID(rawValue: 1),
            identity: identity,
            operation: .change(handlerIDs: [changeID])
          )
        ]
      ),
      currentLifecycleRegistry: registry,
      currentTaskRegistry: LocalTaskRegistry()
    )

    #expect(changeFired == 1, "the committed change handler must fire from the retained store")
    #expect(coordinator.changeHandlerSnapshotFallbackCount == 1)
    #expect(coordinator.changeHandlerSkipCount == 0)
    #expect(issues.isEmpty)
  }

  @Test("healthy appear, disappear, and change handlers fire and report nothing")
  func healthyHandlersFireAndReportNothing() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: false)
    let identity = testIdentity("Root", "member")
    var appearFired = 0
    var disappearFired = 0
    var changeFired = 0

    // Frame 1: appear + change fire from the current registry; the same
    // registry's disappear handler is snapshotted for the next frame.
    let firstRegistry = LocalLifecycleRegistry()
    let appearID = firstRegistry.registerAppear(identity: identity, ordinal: 0) {
      appearFired += 1
    }
    let changeID = firstRegistry.registerChange(identity: identity, ordinal: 0) {
      changeFired += 1
    }
    let disappearID = firstRegistry.registerDisappear(identity: identity, ordinal: 0) {
      disappearFired += 1
    }
    let firstIssues = coordinator.applyCommittedFrame(
      plan: CommitPlan(
        lifecycle: [
          .init(
            viewNodeID: ViewNodeID(rawValue: 1),
            identity: identity,
            operation: .appear(handlerIDs: [appearID])
          ),
          .init(
            viewNodeID: ViewNodeID(rawValue: 1),
            identity: identity,
            operation: .change(handlerIDs: [changeID])
          ),
        ]
      ),
      currentLifecycleRegistry: firstRegistry,
      currentTaskRegistry: LocalTaskRegistry()
    )

    // Frame 2: the node departed; its disappear handler resolves through the
    // previous frame's snapshot.
    let secondIssues = coordinator.applyCommittedFrame(
      plan: CommitPlan(
        lifecycle: [
          .init(
            viewNodeID: ViewNodeID(rawValue: 1),
            identity: identity,
            operation: .disappear(handlerIDs: [disappearID])
          )
        ]
      ),
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: LocalTaskRegistry()
    )

    #expect(appearFired == 1)
    #expect(changeFired == 1)
    #expect(disappearFired == 1)
    #expect(firstIssues.isEmpty)
    #expect(secondIssues.isEmpty)
    #expect(coordinator.appearHandlerSkipCount == 0)
    #expect(coordinator.disappearHandlerSkipCount == 0)
    #expect(coordinator.changeHandlerSkipCount == 0)
  }

  @Test("a .taskStart whose lookups succeed runs the task and reports nothing")
  func healthyTaskStartReportsNothing() {
    let coordinator = LifecycleCoordinator(assertsOnTaskStartSkip: false)
    let identity = testIdentity("Root", "task-holder")
    let descriptor = TaskDescriptor(id: "healthy-start", priority: .medium)
    let taskRegistry = LocalTaskRegistry()
    taskRegistry.register(
      identity: identity,
      registration: TaskRegistration(descriptor: descriptor) {
        // Parks cancellation-responsively, without timers (the test-sync
        // ratchet forbids new sleeps), so the started task stays observable
        // via activeTaskCount until shutdown() cancels it.
        while !Task.isCancelled {
          await Task.yield()
        }
      }
    )
    let plan = CommitPlan(
      lifecycle: [
        .init(
          viewNodeID: ViewNodeID(rawValue: 1),
          identity: identity,
          operation: .taskStart(descriptor)
        )
      ]
    )

    let issues = coordinator.applyCommittedFrame(
      plan: plan,
      currentLifecycleRegistry: LocalLifecycleRegistry(),
      currentTaskRegistry: taskRegistry
    )

    #expect(coordinator.taskStartSkipCount == 0)
    #expect(coordinator.taskCancelSkipCount == 0)
    #expect(coordinator.activeTaskCount == 1)
    #expect(issues.isEmpty)
    coordinator.shutdown()
  }
}
