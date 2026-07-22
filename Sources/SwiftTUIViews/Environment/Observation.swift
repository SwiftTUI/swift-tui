import Observation
package import SwiftTUICore
import Synchronization

/// One marshaled observation change: the payload `onChange` records from
/// whatever executor mutated the observed property (F162).
private struct PendingObservationChange: Sendable {
  var identity: Identity
  var pass: UInt64
}

/// Weak, thread-safety-narrowed handle to the attached invalidator so an
/// off-main `onChange` can wake a sleeping run loop immediately. The
/// production `FrameScheduler` opts into ``ThreadSafeInvalidating``; a
/// main-actor-only test invalidator simply has no off-main wake (its
/// changes still drain at the next frame head).
private struct WeakSendableInvalidator: Sendable {
  weak var value: (any ThreadSafeInvalidating)?
}

@MainActor
package final class ObservationBridge: Equatable {
  private var currentPass: UInt64 = 0
  /// The published pass registrations, lock-held (not MainActor state) so
  /// the fire-time staleness filter in `enqueueChange` can run on whatever
  /// executor mutated the observed property (F162). Written on the main
  /// actor only (track/publish/prune); read under the lock at fire time.
  private nonisolated let passRecords = Mutex<[Identity: ObservationPassRecord]>([:])
  private weak var invalidator: (any Invalidating)?
  private weak var viewGraph: ViewGraph?
  private weak var activeDraft: ObservationBridgeDraft?
  /// Held fires from registrations armed by a still-unpublished draft (their
  /// pass is newer than anything published — the frame's async tail is in
  /// flight). Promoted to real invalidations when their draft publishes,
  /// suppressed when it discards. Losing these outright deafens the identity
  /// permanently: the fire consumed the one-shot, so without the promoted
  /// invalidation no frame ever re-arms tracking (the amd64 stack-lean
  /// cadence stall — frame latency ≥ writer cadence puts every next write
  /// inside the window).
  private nonisolated let draftWindowChanges = Mutex<[PendingObservationChange]>([])

  /// Off-main change marshaling (F162): `onChange` appends here from any
  /// executor; the MainActor bookkeeping (pass-staleness filter + dirty
  /// queueing) drains at the next frame head via ``drainPendingChanges()``.
  private nonisolated let pendingChanges = Mutex<[PendingObservationChange]>([])
  private nonisolated let wakeInvalidator = Mutex<WeakSendableInvalidator>(.init())

  package init() {}

  nonisolated package static func == (
    lhs: ObservationBridge,
    rhs: ObservationBridge
  ) -> Bool {
    lhs === rhs
  }

  package func attachInvalidator(
    _ invalidator: (any Invalidating)?
  ) {
    self.invalidator = invalidator
    wakeInvalidator.withLock { box in
      box.value = invalidator as? any ThreadSafeInvalidating
    }
  }

  package func attachViewGraph(
    _ viewGraph: ViewGraph?
  ) {
    self.viewGraph = viewGraph
  }

  package func beginTrackingPass() {
    currentPass &+= 1
  }

  package func makeDraft(
    attaching viewGraph: ViewGraph?
  ) -> ObservationBridgeDraft {
    drainPendingChanges()
    precondition(activeDraft == nil)
    let draft = ObservationBridgeDraft(
      bridge: self,
      viewGraph: viewGraph,
      pass: currentPass &+ 1
    )
    activeDraft = draft
    return draft
  }

  package func track<T>(
    identity: Identity,
    _ apply: () -> T
  ) -> T {
    let viewNodeID = ViewNodeContext.current?.viewNodeID
    let pass: UInt64
    if let activeDraft {
      pass = activeDraft.recordObserved(identity, viewNodeID: viewNodeID)
    } else {
      pass = currentPass
      passRecords.withLock { records in
        records[identity] = .init(viewNodeID: viewNodeID, pass: pass)
      }
    }

    return withObservationTracking {
      apply()
    } onChange: {
      // `onChange` fires synchronously on whatever executor mutates the
      // observed property — not necessarily the main actor. This previously
      // trapped off-main (release-checked); SwiftUI permits background-task
      // model writes, so marshal instead (F162): the staleness filter and
      // the scheduler wake run at fire time from any executor (the pass
      // records are lock-held and `requestInvalidation` is thread-safe on
      // `ThreadSafeInvalidating` conformers); only the graph dirty queueing
      // is MainActor-bound, and it drains at the next frame head — the next
      // consumer of dirty marks either way, so ordering with same-frame
      // main-actor writes is unchanged.
      self.enqueueChange(identity: identity, pass: pass)
    }
  }

  private nonisolated func enqueueChange(
    identity: Identity,
    pass: UInt64
  ) {
    // The stale-callback filter runs at FIRE time, exactly like the old
    // synchronous path — but it must discriminate by pass ORDER, not bare
    // equality. An OLDER-than-published pass is a superseded registration
    // (re-rendered, or an aborted lineage): no wake, no invalidation — pass
    // suppression is what keeps aborted drafts and repeated re-renders from
    // looping the scheduler. A NEWER-than-published pass (or an identity
    // with no published record yet) is a registration armed by a draft
    // still in flight: the fire consumed the one-shot, so the change must
    // be HELD for the draft's commit/discard decision — dropping it here
    // deafens the identity permanently once the draft publishes.
    enum FireDisposition {
      case current
      case draftWindow
      case superseded
    }
    let disposition = passRecords.withLock { records -> FireDisposition in
      guard let published = records[identity]?.pass else {
        return .draftWindow
      }
      if pass == published {
        return .current
      }
      return pass > published ? .draftWindow : .superseded
    }
    switch disposition {
    case .superseded:
      return
    case .draftWindow:
      draftWindowChanges.withLock { pen in
        pen.append(.init(identity: identity, pass: pass))
      }
    case .current:
      pendingChanges.withLock { pending in
        pending.append(.init(identity: identity, pass: pass))
      }
      wakeInvalidator.withLock { $0.value }?.requestInvalidation(of: [identity])
    }
  }

  /// Applies marshaled changes' MainActor bookkeeping — the graph dirty
  /// queueing. The invalidation request and the staleness filter already ran
  /// at fire time; the filter re-runs here because a resolve between fire
  /// and drain may have advanced the registration (the change is then
  /// already absorbed by that re-resolve). Runs at the frame head, before a
  /// new tracking draft begins.
  package func drainPendingChanges() {
    let changes = pendingChanges.withLock { pending -> [PendingObservationChange] in
      let drained = pending
      pending.removeAll(keepingCapacity: true)
      return drained
    }
    for change in changes {
      let isCurrent = passRecords.withLock { $0[change.identity]?.pass == change.pass }
      if isCurrent {
        viewGraph?.queueDirtyForObservationChange(observedBy: change.identity)
      }
    }
  }

  package func prune(keeping identities: Set<Identity>) {
    prune(keepingIdentities: identities, liveNodeIDs: nil)
  }

  package func prune(keeping liveNodeIDs: Set<ViewNodeID>) {
    prune(keepingIdentities: nil, liveNodeIDs: liveNodeIDs)
  }

  private func prune(
    keepingIdentities identities: Set<Identity>?,
    liveNodeIDs: Set<ViewNodeID>?
  ) {
    passRecords.withLock { records in
      guard !records.isEmpty else {
        return
      }

      let staleIdentities = records.filter { identity, record in
        if let liveNodeIDs {
          guard let viewNodeID = record.viewNodeID else {
            return true
          }
          return !liveNodeIDs.contains(viewNodeID)
        }
        if let identities {
          return !identities.contains(identity)
        }
        return true
      }.map(\.key)
      for identity in staleIdentities {
        records.removeValue(forKey: identity)
      }
    }
  }

  fileprivate func finishRecording(
    _ draft: ObservationBridgeDraft
  ) {
    if activeDraft === draft {
      activeDraft = nil
    }
  }

  fileprivate func resumeRecording(
    _ draft: ObservationBridgeDraft
  ) {
    precondition(activeDraft == nil || activeDraft === draft)
    activeDraft = draft
  }

  fileprivate func publish(
    _ draft: ObservationBridgeDraft
  ) {
    finishRecording(draft)
    currentPass = draft.pass
    passRecords.withLock { records in
      for (identity, record) in draft.observedPasses {
        records[identity] = record
      }
    }
    viewGraph = draft.viewGraph
    promoteDraftWindowChanges(publishedPass: draft.pass)
  }

  /// Held window fires whose draft just published become real invalidations:
  /// the write raced the frame's async tail, its one-shot is consumed, and
  /// only this promotion re-arms the identity (the next frame's resolve
  /// re-tracks). Entries older than the published pass can never match a
  /// future draft (passes only advance at publish) and are dropped; newer
  /// entries belong to drafts still in flight and stay held.
  private func promoteDraftWindowChanges(publishedPass: UInt64) {
    let promoted = draftWindowChanges.withLock { pen -> [PendingObservationChange] in
      let matching = pen.filter { $0.pass == publishedPass }
      pen.removeAll { $0.pass <= publishedPass }
      return matching
    }
    guard !promoted.isEmpty else {
      return
    }
    pendingChanges.withLock { pending in
      pending.append(contentsOf: promoted)
    }
    invalidator?.requestInvalidation(of: Set(promoted.map(\.identity)))
  }

  /// Discard-side twin of ``promoteDraftWindowChanges(publishedPass:)``: an
  /// aborted draft's held window fires must produce no wake and no
  /// invalidation (the load-bearing F162 suppression) — the aborted intent's
  /// replay re-resolves and re-arms tracking independently.
  fileprivate nonisolated func discardDraftWindowChanges(forPass pass: UInt64) {
    draftWindowChanges.withLock { pen in
      pen.removeAll { $0.pass == pass }
    }
  }
}

@MainActor
package final class ObservationBridgeDraft {
  private let bridge: ObservationBridge
  fileprivate weak var viewGraph: ViewGraph?
  fileprivate let pass: UInt64
  fileprivate var observedPasses: [Identity: ObservationPassRecord] = [:]
  private var didCommit = false
  private var didDiscard = false

  fileprivate init(
    bridge: ObservationBridge,
    viewGraph: ViewGraph?,
    pass: UInt64
  ) {
    self.bridge = bridge
    self.viewGraph = viewGraph
    self.pass = pass
  }

  fileprivate func recordObserved(
    _ identity: Identity,
    viewNodeID: ViewNodeID?
  ) -> UInt64 {
    precondition(!didCommit && !didDiscard)
    observedPasses[identity] = .init(viewNodeID: viewNodeID, pass: pass)
    return pass
  }

  package func commit() {
    precondition(!didCommit && !didDiscard)
    bridge.publish(self)
    didCommit = true
  }

  package func suspendRecording() {
    precondition(!didCommit && !didDiscard)
    bridge.finishRecording(self)
  }

  package func resumeRecording() {
    precondition(!didCommit && !didDiscard)
    bridge.resumeRecording(self)
  }

  package func discard() {
    precondition(!didCommit && !didDiscard)
    bridge.discardDraftWindowChanges(forPass: pass)
    bridge.finishRecording(self)
    didDiscard = true
  }
}

extension ObservationBridge {
  package struct Checkpoint {
    package var currentPass: UInt64
    package var observedPasses: [Identity: ObservationPassRecord]
    package var invalidator: (any Invalidating)?
    package var viewGraph: ViewGraph?
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      currentPass: currentPass,
      observedPasses: passRecords.withLock { $0 },
      invalidator: invalidator,
      viewGraph: viewGraph
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    currentPass = checkpoint.currentPass
    passRecords.withLock { $0 = checkpoint.observedPasses }
    // Held window fires reference passes from the rolled-back lineage; pass
    // numbers can be re-minted after the restore, so stale holds must not
    // survive to falsely match a future draft's publish.
    draftWindowChanges.withLock { $0.removeAll() }
    invalidator = checkpoint.invalidator
    viewGraph = checkpoint.viewGraph
  }
}

package struct ObservationPassRecord: Equatable, Sendable {
  package var viewNodeID: ViewNodeID?
  package var pass: UInt64

  package init(
    viewNodeID: ViewNodeID?,
    pass: UInt64
  ) {
    self.viewNodeID = viewNodeID
    self.pass = pass
  }
}
