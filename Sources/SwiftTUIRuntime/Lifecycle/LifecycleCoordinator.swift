import SwiftTUICore

@MainActor
package final class LifecycleCoordinator {
  private let taskRunner: TaskRunner
  private let assertsOnTaskStartSkip: Bool
  private(set) var previousLifecycleHandlers = LifecycleHandlerSnapshot()

  /// Cumulative count of committed `.taskStart` entries dropped because the
  /// registration or view-node lookup failed at commit time. The commit plan
  /// only carries `.taskStart` for work the graph decided must run, so every
  /// skip here is a `.task` that silently never started — the failure mode
  /// behind the entity-rebind bug (docs/plans/2026-07-01-002, "START-SKIP
  /// hasReg=false"). Read by tests as a zero-oracle.
  package private(set) var taskStartSkipCount = 0

  /// Cumulative count of committed `.taskCancel` entries dropped for lack of
  /// a view node. Benign by design: departed-identity cancels are keyed to
  /// nodes that already left the registries (see ``TaskLifecycleDiff``), so a
  /// cancel that finds nothing is the expected steady state under churn.
  package private(set) var taskCancelSkipCount = 0

  // `assertsOnTaskStartSkip` defaults OFF: the first armed run immediately
  // found a live skip — TermUIPerf's synthetic-text-shimmer scenario drops
  // the second `.task` (`…/Group[1]#task[id:1]`, "no task registration at
  // commit") on a Layout-hosted Group. Until that instance is root-caused,
  // the skip stays observable through the counter and the reported
  // `lifecycle.taskStartSkipped` runtime issue rather than a crash; flip the
  // flag per-coordinator to assert in a focused investigation.
  init(
    taskRunner: TaskRunner = .init(),
    assertsOnTaskStartSkip: Bool = false
  ) {
    self.taskRunner = taskRunner
    self.assertsOnTaskStartSkip = assertsOnTaskStartSkip
  }

  /// Creates a coordinator for tests that drive commit plans directly, with
  /// explicit control over the DEBUG start-skip assertion.
  package convenience init(assertsOnTaskStartSkip: Bool) {
    self.init(taskRunner: .init(), assertsOnTaskStartSkip: assertsOnTaskStartSkip)
  }

  /// Applies the committed lifecycle plan and returns one runtime issue per
  /// suspicious skip so the run loop can surface them through the host's
  /// ``RuntimeIssueSink``.
  @discardableResult
  func applyCommittedFrame(
    plan: CommitPlan,
    currentLifecycleRegistry: LocalLifecycleRegistry,
    currentTaskRegistry: LocalTaskRegistry
  ) -> [RuntimeIssue] {
    var skipIssues: [RuntimeIssue] = []
    for entry in plan.lifecycle {
      apply(
        entry,
        currentLifecycleRegistry: currentLifecycleRegistry,
        currentTaskRegistry: currentTaskRegistry,
        skipIssues: &skipIssues
      )
    }

    previousLifecycleHandlers = currentLifecycleRegistry.snapshot()
    return skipIssues
  }

  func shutdown() {
    taskRunner.cancelAll()
    previousLifecycleHandlers = .init()
  }

  package var activeTaskDescriptors: [Identity: [TaskDescriptor]] {
    taskRunner.activeTaskDescriptors
  }

  package var activeTaskCount: Int {
    taskRunner.activeTaskCount
  }

  private func apply(
    _ entry: LifecycleCommitEntry,
    currentLifecycleRegistry: LocalLifecycleRegistry,
    currentTaskRegistry: LocalTaskRegistry,
    skipIssues: inout [RuntimeIssue]
  ) {
    switch entry.operation {
    case .appear(let handlerIDs):
      for handlerID in handlerIDs {
        currentLifecycleRegistry.appearHandler(for: handlerID)?()
      }
    case .disappear(let handlerIDs):
      for handlerID in handlerIDs {
        previousLifecycleHandlers.disappearHandlers[handlerID]?()
      }
    case .change(let handlerIDs):
      for handlerID in handlerIDs {
        currentLifecycleRegistry.changeHandler(for: handlerID)?()
      }
    case .taskStart(let descriptor):
      let registration = currentTaskRegistry.registration(
        for: entry.identity,
        descriptor: descriptor
      )
      guard let registration, let viewNodeID = entry.viewNodeID else {
        recordTaskStartSkip(
          entry: entry,
          descriptor: descriptor,
          hasRegistration: registration != nil,
          into: &skipIssues
        )
        return
      }
      taskRunner.start(
        viewNodeID: viewNodeID,
        identity: entry.identity,
        registration: registration
      )
    case .taskCancel(let descriptor):
      guard let viewNodeID = entry.viewNodeID else {
        taskCancelSkipCount += 1
        return
      }
      taskRunner.cancel(viewNodeID: viewNodeID, matching: descriptor)
    }
  }

  private func recordTaskStartSkip(
    entry: LifecycleCommitEntry,
    descriptor: TaskDescriptor,
    hasRegistration: Bool,
    into skipIssues: inout [RuntimeIssue]
  ) {
    taskStartSkipCount += 1
    var missing: [String] = []
    if !hasRegistration {
      missing.append("task registration")
    }
    if entry.viewNodeID == nil {
      missing.append("view node")
    }
    let issue = RuntimeIssue(
      severity: .warning,
      code: "lifecycle.taskStartSkipped",
      message:
        "committed task '\(descriptor.id)' never started: "
        + "no \(missing.joined(separator: " or ")) at commit",
      identity: entry.identity,
      source: "LifecycleCoordinator"
    )
    skipIssues.append(issue)
    #if DEBUG
      if assertsOnTaskStartSkip {
        assertionFailure(issue.description)
      }
    #endif
  }
}
