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

  /// Cumulative counts of committed appear/disappear/change handler IDs whose
  /// lookup failed at commit time (F163). Mirrors ``taskStartSkipCount``: the
  /// commit plan only carries handler IDs the graph decided must fire, so
  /// every miss is a committed lifecycle callback that silently never ran —
  /// the same publication-loss class the task path instruments. Read by tests
  /// as zero-oracles. Every skip is counted and reported; if a benign class
  /// ever surfaces (the taskCancel departed-node analog), carve it out with
  /// the calibration evidence, don't stop reporting the rest.
  package private(set) var appearHandlerSkipCount = 0
  package private(set) var disappearHandlerSkipCount = 0
  package private(set) var changeHandlerSkipCount = 0

  /// Cumulative count of committed change handlers dispatched from the
  /// retained handler store because the current registry had no entry.
  /// The known producer: a re-minted node that adopts a reused resolved
  /// artifact never re-runs registration capture, so scoped publication
  /// removes the departed owner's registration without a replacement while
  /// the committed tree still names the handler (gallery fuzzer find,
  /// 2026-07-17: sheet-presentation content). The retained closure is the
  /// last-registered one — identical unless the body re-evaluated, which
  /// would have re-registered. A deep fix at the reuse-adoption seam should
  /// drive this counter back to zero.
  package private(set) var changeHandlerSnapshotFallbackCount = 0

  // `assertsOnTaskStartSkip` defaults OFF. The one live skip the first armed
  // run found (TermUIPerf's synthetic-text-shimmer `…/Group[1]#task[id:1]`,
  // "no task registration at commit") is root-caused and fixed: the `.task`
  // registration was recorded on an absorbed shadowed interior mint that
  // `pruneAbsorbedShadowedNodes` reclaimed before the registration
  // publication, so the committed plan's start found no registration —
  // reclaim now re-homes the interior's registrations and descriptor slots
  // to the absorber (see `ViewGraph.pruneAbsorbedShadowedNodes` and
  // `TimelineTaskStartSkipRuntimeTests`). The flag stays observability-first
  // (counter + `lifecycle.taskStartSkipped` runtime issue) because a skip in
  // a user app is better reported than crashed; flip it per-coordinator to
  // assert in a focused investigation.
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
    var disappearedIdentities: [Identity] = []
    for entry in plan.lifecycle {
      if case .disappear = entry.operation {
        disappearedIdentities.append(entry.identity)
      }
      apply(
        entry,
        currentLifecycleRegistry: currentLifecycleRegistry,
        currentTaskRegistry: currentTaskRegistry,
        skipIssues: &skipIssues
      )
    }

    // Retained handler store, not a one-frame snapshot: a re-minted node
    // that adopts a reused resolved artifact never re-runs registration
    // capture, so publication can drop a registration frames before the
    // committed tree stops naming its handler (gallery fuzzer find,
    // 2026-07-17: sheet-presentation content). Retention is bounded by the
    // framework's own departure signal — a subtree's handlers are pruned
    // once its disappear dispatches — and re-registrations replace their
    // retained entries. Prune before absorbing so a same-frame remount's
    // fresh registrations survive their identity's disappear.
    previousLifecycleHandlers.prune(under: disappearedIdentities)
    previousLifecycleHandlers.absorbNewer(currentLifecycleRegistry.snapshot())
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
        guard let handler = currentLifecycleRegistry.appearHandler(for: handlerID) else {
          recordHandlerSkip(.appear, entry: entry, handlerID: handlerID, into: &skipIssues)
          continue
        }
        handler()
      }
    case .disappear(let handlerIDs):
      for handlerID in handlerIDs {
        guard let handler = previousLifecycleHandlers.disappearHandlers[handlerID] else {
          recordHandlerSkip(.disappear, entry: entry, handlerID: handlerID, into: &skipIssues)
          continue
        }
        handler()
      }
    case .change(let handlerIDs):
      for handlerID in handlerIDs {
        if let handler = currentLifecycleRegistry.changeHandler(for: handlerID) {
          handler()
          continue
        }
        // Mirror the disappear path's previous-snapshot dispatch: content
        // that did not re-register this frame still owes its committed
        // callback (see changeHandlerSnapshotFallbackCount).
        if let handler = previousLifecycleHandlers.changeHandlers[handlerID] {
          changeHandlerSnapshotFallbackCount += 1
          handler()
          continue
        }
        recordHandlerSkip(.change, entry: entry, handlerID: handlerID, into: &skipIssues)
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

  private enum LifecycleHandlerSkipKind: String {
    case appear
    case disappear
    case change
  }

  private func recordHandlerSkip(
    _ kind: LifecycleHandlerSkipKind,
    entry: LifecycleCommitEntry,
    handlerID: String,
    into skipIssues: inout [RuntimeIssue]
  ) {
    switch kind {
    case .appear:
      appearHandlerSkipCount += 1
    case .disappear:
      disappearHandlerSkipCount += 1
    case .change:
      changeHandlerSkipCount += 1
    }
    let issue = RuntimeIssue(
      severity: .warning,
      code: "lifecycle.\(kind.rawValue)HandlerSkipped",
      message:
        "committed \(kind.rawValue) handler '\(handlerID)' never fired: "
        + "no registered handler at commit",
      identity: entry.identity,
      source: "LifecycleCoordinator"
    )
    skipIssues.append(issue)
    SoundnessProbeConfiguration.recordLifecycleHandlerSkip(
      "\(kind.rawValue) handler '\(handlerID)' missing at commit for \(entry.identity)"
    )
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
