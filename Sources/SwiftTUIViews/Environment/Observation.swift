import Observation
import SwiftTUICore
import Synchronization

private struct PendingObservationChange: Sendable {
  var identity: Identity
  var pass: UInt64
}

private struct WeakSendableInvalidator: Sendable {
  weak var value: (any ThreadSafeInvalidating)?
}

/// All callback-visible registration state shares one lock. A fire racing
/// publication either joins the draft's held changes or the published queue;
/// it cannot append to a draft after its promotion has already drained.
private struct ObservationMailbox {
  struct Draft {
    var records: [Identity: ObservationPassRecord] = [:]
    var heldChanges: [Identity: PendingObservationChange] = [:]
  }

  var published: [Identity: ObservationPassRecord] = [:]
  var drafts: [UInt64: Draft] = [:]
  var pendingChanges: [Identity: PendingObservationChange] = [:]

  mutating func enqueue(identity: Identity, pass: UInt64) -> Bool {
    let change = PendingObservationChange(identity: identity, pass: pass)
    if published[identity]?.pass == pass {
      pendingChanges[identity] = change
      return true
    }
    if drafts[pass]?.records[identity]?.pass == pass {
      drafts[pass]?.heldChanges[identity] = change
    }
    // Unknown tokens belong to superseded, discarded, or pruned registrations.
    return false
  }
}

@MainActor
package final class ObservationBridge: Equatable {
  private var currentPass: UInt64 = 0
  // Pass identities are lifetime currency, not checkpoint state. Never rewind
  // when a speculative frame is discarded or a checkpoint is restored.
  private var nextPass: UInt64 = 0
  private nonisolated let mailbox = Mutex(ObservationMailbox())
  private weak var invalidator: (any Invalidating)?
  private weak var viewGraph: ViewGraph?
  private weak var activeDraft: ObservationBridgeDraft?
  private nonisolated let wakeInvalidator = Mutex<WeakSendableInvalidator>(.init())

  package init() {}

  nonisolated package static func == (lhs: ObservationBridge, rhs: ObservationBridge) -> Bool {
    lhs === rhs
  }

  package func attachInvalidator(_ invalidator: (any Invalidating)?) {
    self.invalidator = invalidator
    wakeInvalidator.withLock { $0.value = invalidator as? any ThreadSafeInvalidating }
  }

  package func attachViewGraph(_ viewGraph: ViewGraph?) {
    self.viewGraph = viewGraph
  }

  private func issuePass() -> UInt64 {
    precondition(nextPass < .max, "Observation pass identity exhausted")
    nextPass += 1
    return nextPass
  }

  package func beginTrackingPass() {
    currentPass = issuePass()
  }

  package func makeDraft(attaching viewGraph: ViewGraph?) -> ObservationBridgeDraft {
    drainPendingChanges()
    precondition(activeDraft == nil)
    let pass = issuePass()
    mailbox.withLock { $0.drafts[pass] = .init() }
    let draft = ObservationBridgeDraft(bridge: self, viewGraph: viewGraph, pass: pass)
    activeDraft = draft
    return draft
  }

  package func track<T>(identity: Identity, _ apply: () -> T) -> T {
    let draft = activeDraft
    let pass = draft?.pass ?? currentPass
    let record = ObservationPassRecord(
      viewNodeID: ViewNodeContext.current?.viewNodeID,
      pass: pass
    )
    if draft != nil {
      mailbox.withLock { mailbox in
        precondition(mailbox.drafts[pass] != nil)
        mailbox.drafts[pass]?.records[identity] = record
      }
    } else {
      mailbox.withLock { $0.published[identity] = record }
    }

    // Collapsed custom bodies can record several dependency sets at the same
    // identity. Every read in this pass remains live until a newer pass replaces
    // it; per-call replacement would silently drop enclosing bodies' reads.
    return withObservationTracking {
      apply()
    } onChange: { [weak self] in
      self?.enqueueChange(identity: identity, pass: pass)
    }
  }

  // Observation invokes this on the mutating executor. Only the synchronized
  // mailbox and a thread-safe invalidator are touched until the main-actor drain.
  private nonisolated func enqueueChange(
    identity: Identity,
    pass: UInt64
  ) {
    let shouldWake = mailbox.withLock {
      $0.enqueue(identity: identity, pass: pass)
    }
    if shouldWake {
      wakeInvalidator.withLock { $0.value }?.requestInvalidation(of: [identity])
    }
  }

  /// Marks the graph at frame head, discarding fires already absorbed by a
  /// newer evaluation and coalescing all remaining fires for each identity.
  package func drainPendingChanges() {
    let identities = mailbox.withLock { mailbox -> [Identity] in
      let identities = mailbox.pendingChanges.values.compactMap { change in
        mailbox.published[change.identity]?.pass == change.pass
          ? change.identity : nil
      }
      mailbox.pendingChanges.removeAll(keepingCapacity: true)
      return identities
    }
    for identity in identities {
      viewGraph?.queueDirtyForObservationChange(observedBy: identity)
    }
  }

  package func prune(keeping identities: Set<Identity>) {
    prune(keepingIdentities: identities, liveNodeIDs: nil)
  }

  package func prune(keeping liveNodeIDs: Set<ViewNodeID>) {
    prune(keepingIdentities: nil, liveNodeIDs: liveNodeIDs)
  }

  private func prune(keepingIdentities identities: Set<Identity>?, liveNodeIDs: Set<ViewNodeID>?) {
    mailbox.withLock { mailbox in
      var stale: [Identity] = []
      for (identity, record) in mailbox.published {
        let isLive: Bool
        if let liveNodeIDs {
          isLive = record.viewNodeID.map { liveNodeIDs.contains($0) } ?? false
        } else {
          isLive = identities?.contains(identity) ?? false
        }
        if !isLive { stale.append(identity) }
      }
      for identity in stale {
        mailbox.published.removeValue(forKey: identity)
        mailbox.pendingChanges.removeValue(forKey: identity)
      }
    }
  }

  fileprivate func finishRecording(_ draft: ObservationBridgeDraft) {
    if activeDraft === draft { activeDraft = nil }
  }

  fileprivate func resumeRecording(_ draft: ObservationBridgeDraft) {
    precondition(activeDraft == nil || activeDraft === draft)
    activeDraft = draft
  }

  fileprivate func publish(_ draft: ObservationBridgeDraft) {
    finishRecording(draft)
    currentPass = draft.pass
    viewGraph = draft.viewGraph
    let promoted = mailbox.withLock { mailbox -> Set<Identity> in
      guard let pendingDraft = mailbox.drafts.removeValue(forKey: draft.pass) else {
        preconditionFailure("Cannot publish a retired observation draft")
      }
      for (identity, record) in pendingDraft.records {
        mailbox.published[identity] = record
      }
      var promoted: Set<Identity> = []
      for (identity, change) in pendingDraft.heldChanges
      where mailbox.published[identity]?.pass == change.pass {
        mailbox.pendingChanges[identity] = change
        promoted.insert(identity)
      }
      return promoted
    }
    if !promoted.isEmpty { invalidator?.requestInvalidation(of: promoted) }
  }

  fileprivate nonisolated func discardDraftWindowChanges(forPass pass: UInt64) {
    _ = mailbox.withLock { $0.drafts.removeValue(forKey: pass) }
  }
}

@MainActor
package final class ObservationBridgeDraft {
  private let bridge: ObservationBridge
  fileprivate weak var viewGraph: ViewGraph?
  fileprivate let pass: UInt64
  private var didCommit = false
  private var didDiscard = false

  fileprivate init(bridge: ObservationBridge, viewGraph: ViewGraph?, pass: UInt64) {
    self.bridge = bridge
    self.viewGraph = viewGraph
    self.pass = pass
  }

  deinit {
    bridge.discardDraftWindowChanges(forPass: pass)
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
      observedPasses: mailbox.withLock { $0.published },
      invalidator: invalidator,
      viewGraph: viewGraph
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    // Restore retires draft mailbox state. Reject an active recorder here,
    // before mutation, instead of failing later when its owner tries to commit.
    precondition(
      activeDraft == nil, "Cannot restore observation checkpoint while recording a draft")
    currentPass = checkpoint.currentPass
    nextPass = max(nextPass, currentPass)
    mailbox.withLock { mailbox in
      mailbox.published = checkpoint.observedPasses
      mailbox.drafts.removeAll()
      mailbox.pendingChanges = mailbox.pendingChanges.filter { identity, change in
        mailbox.published[identity]?.pass == change.pass
      }
    }
    activeDraft = nil
    attachInvalidator(checkpoint.invalidator)
    viewGraph = checkpoint.viewGraph
  }
}

package struct ObservationPassRecord: Equatable, Sendable {
  package var viewNodeID: ViewNodeID?
  package var pass: UInt64

  package init(viewNodeID: ViewNodeID?, pass: UInt64) {
    self.viewNodeID = viewNodeID
    self.pass = pass
  }
}
