import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@Observable
private final class MarshalModel {
  var count = 0
}

/// F162 — off-main `@Observable` writes marshal instead of trapping.
///
/// `withObservationTracking`'s `onChange` fires on whatever executor mutates
/// the observed property. The bridge previously routed it through a
/// release-checked MainActor precondition, so a background-task model write
/// crashed the process; SwiftUI permits such writes. The marshal appends the
/// change to a thread-safe box and wakes the scheduler (whose
/// `requestInvalidation` is `ThreadSafeInvalidating`); the MainActor
/// bookkeeping drains at the next frame head.
@MainActor
@Suite("Observation off-main marshal")
struct ObservationOffMainMarshalTests {
  @Test("a background-task model write marshals an invalidation instead of trapping")
  func offMainWriteMarshalsInvalidation() async {
    let bridge = ObservationBridge()
    let scheduler = FrameScheduler()
    bridge.attachInvalidator(scheduler)
    let identity = Identity(components: ["observed-model"])
    let model = MarshalModel()
    _ = bridge.track(identity: identity) { model.count }

    await Task.detached {
      model.count += 1
    }.value

    #expect(scheduler.pendingInvalidatedIdentities.contains(identity))
  }

  @Test("a main-actor write still requests its invalidation synchronously")
  func mainActorWriteInvalidatesSynchronously() {
    let bridge = ObservationBridge()
    let scheduler = FrameScheduler()
    bridge.attachInvalidator(scheduler)
    let identity = Identity(components: ["main-observed-model"])
    let model = MarshalModel()
    _ = bridge.track(identity: identity) { model.count }

    model.count += 1

    // The wake lands within the write itself (the enqueue runs
    // synchronously on the mutating executor), so same-frame main-actor
    // ordering is unchanged: the scheduler has the identity before the
    // write statement returns.
    #expect(scheduler.pendingInvalidatedIdentities.contains(identity))
  }

  @Test("drained changes apply MainActor bookkeeping in append order")
  func drainAppliesBookkeeping() {
    let bridge = ObservationBridge()
    let scheduler = FrameScheduler()
    bridge.attachInvalidator(scheduler)
    let identity = Identity(components: ["drained-model"])
    let model = MarshalModel()
    _ = bridge.track(identity: identity) { model.count }

    model.count += 1
    // Draining must be idempotent and must not trap with pending entries
    // from the write above.
    bridge.drainPendingChanges()
    bridge.drainPendingChanges()
    #expect(scheduler.pendingInvalidatedIdentities.contains(identity))
  }

  // MARK: Draft-window fires (the amd64 lean-lane deafness class)

  // A registration armed during a draft carries the draft's pass, which is
  // newer than anything published until the frame commits. A model write in
  // that window fires (and consumes) the one-shot; dropping the fire outright
  // permanently deafens observation for the identity — no invalidation, no
  // next frame, no re-arm (the amd64 stack-lean cadence stall: frame latency
  // ≥ writer cadence puts every next write inside the window).

  @Test("a write landing in the draft window survives to invalidate at publish")
  func draftWindowWritePromotesOnPublish() {
    let bridge = ObservationBridge()
    let scheduler = FrameScheduler()
    bridge.attachInvalidator(scheduler)
    let identity = Identity(components: ["draft-window-model"])
    let model = MarshalModel()
    // Prior frame's published registration, consumed by the write that would
    // schedule the next frame (the steady-tick shape).
    _ = bridge.track(identity: identity) { model.count }
    model.count += 1
    scheduler.reset()

    // Next frame's head: the draft records the re-arm, then the head
    // suspends for its async tail (the window).
    let draft = bridge.makeDraft(attaching: nil)
    _ = bridge.track(identity: identity) { model.count }
    draft.suspendRecording()

    // The window write: fires the draft-pass one-shot. It must be HELD, not
    // dropped — but also not invalidate yet (an aborted draft must be able
    // to suppress it, the F162 load-bearing behavior).
    model.count += 1
    #expect(!scheduler.pendingInvalidatedIdentities.contains(identity))

    draft.resumeRecording()
    draft.commit()
    // Publish promotes the held write: the invalidation survives, so the
    // next frame re-resolves and re-arms tracking.
    #expect(scheduler.pendingInvalidatedIdentities.contains(identity))
  }

  @Test("a discarded draft still suppresses its window fires")
  func discardedDraftSuppressesWindowFires() {
    let bridge = ObservationBridge()
    let scheduler = FrameScheduler()
    bridge.attachInvalidator(scheduler)
    let identity = Identity(components: ["draft-discard-model"])
    let model = MarshalModel()
    _ = bridge.track(identity: identity) { model.count }
    model.count += 1
    scheduler.reset()

    let draft = bridge.makeDraft(attaching: nil)
    _ = bridge.track(identity: identity) { model.count }
    draft.suspendRecording()
    model.count += 1

    draft.discard()
    // Aborted-draft suppression is load-bearing (F162): the never-published
    // registration's fire produces no wake and no invalidation — the
    // aborted intent's replay re-resolves and re-arms independently.
    #expect(!scheduler.pendingInvalidatedIdentities.contains(identity))
  }

  @Test("a first-ever registration's window write also survives to publish")
  func firstRegistrationWindowWritePromotesOnPublish() {
    // The bootstrap shape: no published record exists yet for the identity,
    // so the fire-time filter has no entry to compare against. It must hold
    // the change for the draft's publish, not drop it.
    let bridge = ObservationBridge()
    let scheduler = FrameScheduler()
    bridge.attachInvalidator(scheduler)
    let identity = Identity(components: ["draft-bootstrap-model"])
    let model = MarshalModel()

    let draft = bridge.makeDraft(attaching: nil)
    _ = bridge.track(identity: identity) { model.count }
    draft.suspendRecording()
    model.count += 1
    #expect(!scheduler.pendingInvalidatedIdentities.contains(identity))

    draft.resumeRecording()
    draft.commit()
    #expect(scheduler.pendingInvalidatedIdentities.contains(identity))
  }
}
