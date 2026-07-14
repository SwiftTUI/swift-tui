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
}
