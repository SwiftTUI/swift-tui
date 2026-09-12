import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@Observable
private final class RegistrationLifetimeModel {
  var count = 0
}

@MainActor
@Suite("Observation registration lifetime")
struct ObservationRegistrationLifetimeTests {
  @Test("checkpoint restore rejects an actively recording draft at the restore boundary")
  func restoreDuringActiveDraftTraps() async {
    await #expect(processExitsWith: .failure) {
      await MainActor.run {
        let bridge = ObservationBridge()
        let checkpoint = bridge.makeCheckpoint()
        let draft = bridge.makeDraft(attaching: nil)
        bridge.restoreCheckpoint(checkpoint)
        withExtendedLifetime(draft) {}
      }
    }
  }

  @Test("collapsed view bodies retain every same-identity observation dependency")
  func collapsedBodiesRetainEveryDependency() {
    let bridge = ObservationBridge()
    let scheduler = FrameScheduler()
    bridge.attachInvalidator(scheduler)
    let identity = Identity(components: ["composed-bodies"])
    let outerModel = RegistrationLifetimeModel()
    let innerModel = RegistrationLifetimeModel()
    var context = ResolveContext(identity: identity)
    context.observationBridge = bridge
    let draft = bridge.makeDraft(attaching: nil)
    _ = Resolver().resolve(
      RegistrationOuterBody(outer: outerModel, inner: innerModel), in: context
    )
    draft.commit()
    outerModel.count += 1
    #expect(scheduler.pendingInvalidatedIdentities == [identity])
    scheduler.reset()
    innerModel.count += 1
    #expect(scheduler.pendingInvalidatedIdentities == [identity])
  }

  @Test("every same-pass dependency set can invalidate", arguments: [false, true])
  func samePassRegistrationsRemainLive(drafted: Bool) {
    let bridge = ObservationBridge()
    let scheduler = FrameScheduler()
    bridge.attachInvalidator(scheduler)
    let identity = Identity(components: ["same-draft"])
    let firstModel = RegistrationLifetimeModel()
    let currentModel = RegistrationLifetimeModel()
    let draft = drafted ? bridge.makeDraft(attaching: nil) : nil
    _ = bridge.track(identity: identity) { firstModel.count }
    _ = bridge.track(identity: identity) { currentModel.count }
    draft?.commit()
    firstModel.count += 1
    #expect(scheduler.pendingInvalidatedIdentities == [identity])
    scheduler.reset()
    currentModel.count += 1
    #expect(scheduler.pendingInvalidatedIdentities == [identity])
  }

  @Test("publication racing a background fire never loses the invalidation")
  func publicationRacingBackgroundFire() async {
    for index in 0..<100 {
      let bridge = ObservationBridge()
      let scheduler = FrameScheduler()
      bridge.attachInvalidator(scheduler)
      let identity = Identity(components: ["publish-race-\(index)"])
      let model = RegistrationLifetimeModel()
      let draft = bridge.makeDraft(attaching: nil)
      _ = bridge.track(identity: identity) { model.count }
      draft.suspendRecording()
      let writer = Task.detached { model.count += 1 }
      draft.commit()
      await writer.value
      #expect(scheduler.pendingInvalidatedIdentities == [identity])
    }
  }

  @Test("checkpoint restoration also restores the callback wake destination")
  func checkpointRestoresWakeDestination() {
    let bridge = ObservationBridge()
    let original = FrameScheduler()
    let replacement = FrameScheduler()
    bridge.attachInvalidator(original)
    let checkpoint = bridge.makeCheckpoint()
    bridge.attachInvalidator(replacement)
    bridge.restoreCheckpoint(checkpoint)
    let model = RegistrationLifetimeModel()
    let identity = Identity(components: ["restored-wake"])
    _ = bridge.track(identity: identity) { model.count }
    model.count += 1
    #expect(original.pendingInvalidatedIdentities == [identity])
    #expect(replacement.pendingInvalidatedIdentities.isEmpty)
  }

  @Test("an observable does not retain a released observation bridge")
  func observableDoesNotOwnBridge() {
    let model = RegistrationLifetimeModel()
    weak var weakBridge: ObservationBridge?
    do {
      let bridge = ObservationBridge()
      weakBridge = bridge
      _ = bridge.track(identity: Identity(components: ["borrowed-bridge"])) { model.count }
    }
    #expect(weakBridge == nil)
    model.count += 1
  }

  @Test("an aborted registration cannot invalidate a replacement draft")
  func discardedRegistrationCannotInvalidateReplacement() {
    let bridge = ObservationBridge()
    let scheduler = FrameScheduler()
    bridge.attachInvalidator(scheduler)
    let identity = Identity(components: ["replacement"])
    let retiredModel = RegistrationLifetimeModel()
    let currentModel = RegistrationLifetimeModel()

    let discarded = bridge.makeDraft(attaching: nil)
    _ = bridge.track(identity: identity) { retiredModel.count }
    discarded.discard()

    let replacement = bridge.makeDraft(attaching: nil)
    _ = bridge.track(identity: identity) { currentModel.count }
    replacement.commit()

    retiredModel.count += 1
    #expect(scheduler.pendingInvalidatedIdentities.isEmpty)

    currentModel.count += 1
    #expect(scheduler.pendingInvalidatedIdentities == [identity])
  }

  @Test("checkpoint rollback cannot recycle an observation registration token")
  func rolledBackRegistrationCannotInvalidateReplacement() {
    let bridge = ObservationBridge()
    let scheduler = FrameScheduler()
    bridge.attachInvalidator(scheduler)
    let identity = Identity(components: ["rollback"])
    let retiredModel = RegistrationLifetimeModel()
    let currentModel = RegistrationLifetimeModel()
    let baseline = bridge.makeCheckpoint()

    let retired = bridge.makeDraft(attaching: nil)
    _ = bridge.track(identity: identity) { retiredModel.count }
    retired.commit()
    bridge.restoreCheckpoint(baseline)

    let replacement = bridge.makeDraft(attaching: nil)
    _ = bridge.track(identity: identity) { currentModel.count }
    replacement.commit()

    retiredModel.count += 1
    #expect(scheduler.pendingInvalidatedIdentities.isEmpty)

    currentModel.count += 1
    #expect(scheduler.pendingInvalidatedIdentities == [identity])
  }
}

private struct RegistrationOuterBody: View {
  let outer: RegistrationLifetimeModel
  let inner: RegistrationLifetimeModel

  var body: some View {
    RegistrationInnerBody(prefix: "\(outer.count)", model: inner)
  }
}

private struct RegistrationInnerBody: View {
  let prefix: String
  let model: RegistrationLifetimeModel

  var body: some View {
    Text("\(prefix):\(model.count)")
  }
}
