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
