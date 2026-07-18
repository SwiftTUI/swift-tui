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

  /// Cumulative count of committed `.taskStart` entries dropped because the
  /// SAME merged plan also cancels the same identity + descriptor: a
  /// carried-forward frame's start (elided/convergence commits prepend an
  /// earlier frame's unapplied entries — `mergeLifecycleCarryForward`) whose
  /// `.task(id:)` value moved on before the plan dispatched, so the current
  /// frame's diff already cancels the stale descriptor and starts its
  /// replacement. Benign by design — the graph has adjudicated that task's
  /// tenure; see ``supersededTaskStartIndices(in:currentTaskRegistry:)``.
  package private(set) var taskStartSupersededCount = 0

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
    let supersededStarts = supersededTaskStartIndices(
      in: plan.lifecycle,
      currentTaskRegistry: currentTaskRegistry
    )
    for (index, entry) in plan.lifecycle.enumerated() {
      if case .disappear = entry.operation {
        disappearedIdentities.append(entry.identity)
      }
      if supersededStarts.contains(index) {
        taskStartSupersededCount += 1
        continue
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

  /// Absorbs a just-published live registry into the retained handler store
  /// at COMMIT time, for frames whose commit plan does not reach
  /// ``applyCommittedFrame`` with the publication still live: elided commits
  /// publish registration state but produce no frame artifacts at all, and a
  /// focus-sync convergence re-render commits its pass, folds the unapplied
  /// plan into the lifecycle carry-forward, and loops. Without this, a
  /// registration published by such a commit and removed by a later frame's
  /// scoped publication — its owner's record was legitimately reset by a
  /// re-evaluation that did not re-trigger — is in NO store by the time the
  /// carried-forward plan finally dispatches, and the committed callback is
  /// silently skipped (gallery fuzzer find, 2026-07-17 §5 residual: sheet
  /// `onChange` under convergence/elision pressure).
  func absorbPublishedRegistrations(
    _ snapshot: LifecycleHandlerSnapshot
  ) {
    previousLifecycleHandlers.absorbNewer(snapshot)
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

  /// Indices of committed `.taskStart` entries superseded within their own
  /// merged plan. Carried-forward plans (elided or convergence-looped
  /// commits prepend an earlier frame's unapplied entries —
  /// `mergeLifecycleCarryForward`; duplicates survive dedupe when re-mints
  /// change `viewNodeID`) can carry a start whose `.task(id:)` value moved
  /// on before the plan dispatched. Dispatching the stale start would run a
  /// superseded closure just to cancel it — or, once the registry has
  /// (correctly) re-registered under the new descriptor, skip-warn a task
  /// that is not lost but replaced (gallery fuzzer find, 2026-07-18:
  /// node-backed TabContent `.task(id:)` churn under carry-forward
  /// pressure — final-mixed cases 292/302/559). Two supersession legs, both
  /// keyed by identity + full descriptor:
  ///
  /// 1. **Cancel-later:** a start whose descriptor is cancelled LATER in
  ///    the plan — the current frame's diff cancelled the carried
  ///    descriptor. Restart pairs order cancel-then-start and dispatch
  ///    untouched.
  /// 2. **Cancelled-and-gone:** a start whose descriptor the same plan
  ///    cancels ANYWHERE and whose registration no longer exists — the
  ///    cancel proves the graph adjudicated that task's tenure, and the
  ///    registry's silence proves the site re-registered under a
  ///    replacement (or departed with its subtree). This covers carried
  ///    plans whose pairing cancel landed in an earlier section
  ///    (cancel-first orders). A genuine restart re-registers its
  ///    descriptor, so its registration is present and it dispatches.
  ///
  /// The pairing cancels still dispatch: an earlier genuine start of the
  /// same descriptor may be running.
  private func supersededTaskStartIndices(
    in entries: [LifecycleCommitEntry],
    currentTaskRegistry: LocalTaskRegistry
  ) -> Set<Int> {
    var lastCancelIndexByKey: [SupersededTaskKey: Int] = [:]
    for (index, entry) in entries.enumerated() {
      if case .taskCancel(let descriptor) = entry.operation {
        lastCancelIndexByKey[SupersededTaskKey(identity: entry.identity, descriptor: descriptor)] =
          index
      }
    }
    guard !lastCancelIndexByKey.isEmpty else {
      return []
    }
    var superseded: Set<Int> = []
    for (index, entry) in entries.enumerated() {
      guard case .taskStart(let descriptor) = entry.operation,
        let cancelIndex =
          lastCancelIndexByKey[SupersededTaskKey(identity: entry.identity, descriptor: descriptor)]
      else {
        continue
      }
      if cancelIndex > index {
        superseded.insert(index)
        continue
      }
      if currentTaskRegistry.registration(for: entry.identity, descriptor: descriptor) == nil {
        superseded.insert(index)
      }
    }
    return superseded
  }

  private struct SupersededTaskKey: Hashable {
    var identity: Identity
    var descriptorID: String
    var priority: TaskPriority

    init(identity: Identity, descriptor: TaskDescriptor) {
      self.identity = identity
      descriptorID = descriptor.id
      priority = descriptor.priority
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
