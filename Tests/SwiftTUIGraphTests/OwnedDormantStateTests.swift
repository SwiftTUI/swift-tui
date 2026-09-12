import Testing

@testable import SwiftTUIGraph

@MainActor
struct OwnedDormantStateTests {
  private final class Model { var value = 0 }
  private struct Payload { var models: [String: Model?] }
  private final class Probe { weak var value: Model? }

  @Test("detached reference envelopes release their last model owner")
  func releasesDetachedOwnership() {
    let probe = Probe()
    captureAndRelease(probe)
    #expect(probe.value == nil)
  }

  private func captureAndRelease(_ probe: Probe) {
    let model = Model()
    probe.value = model
    let slot = withOwnedDormantStateSlot { AnyStateSlot(model) }
    let snapshot = slot.dormantSnapshot()!
    let restored = AnyStateSlot(restoringDormant: snapshot)
    #expect(restored.dormantPolicy == .owned)
  }

  @Test("authored ownership survives nested envelopes and keeps its provenance")
  func ownedProjection() throws {
    let model = Model()
    let slot = withOwnedDormantStateSlot { AnyStateSlot(Payload(models: ["model": model])) }
    let snapshot = try #require(slot.dormantSnapshot())
    let restored = AnyStateSlot(restoringDormant: snapshot)
    #expect(restored.dormantPolicy == .owned)
    #expect(restored.value(as: Payload.self).models["model"]! === model)
    #expect(restored.dormantSnapshot() != nil)
    let frameworkSlot = withPersistentDormantStateSlot { AnyStateSlot(model) }
    #expect(frameworkSlot.dormantSnapshot() == nil)
    let nested = withPersistentDormantStateSlot { AnyStateSlot([snapshot]) }
    #expect(nested.dormantSnapshot() != nil)
  }

  @Test("owned state still rejects direct closures and runtime identities")
  func runtimeEdgesRemainUnsupported() {
    let closure = withOwnedDormantStateSlot { AnyStateSlot({ 1 }) }
    let metatype = withOwnedDormantStateSlot { AnyStateSlot(Model.self) }
    let identity = withOwnedDormantStateSlot { AnyStateSlot(ObjectIdentifier(Model())) }
    #expect(closure.dormantSnapshot() == nil)
    #expect(metatype.dormantSnapshot() == nil)
    #expect(identity.dormantSnapshot() == nil)
  }

  @Test("checkpoint rollback restores reference ownership without cloning models")
  func checkpointRestoresOwnership() {
    let node = ViewNode(viewNodeID: ViewNodeID(rawValue: 1), identity: testIdentity("Owner"))
    let original = Model()
    withOwnedDormantStateSlot { node.setStateSlotSilently(ordinal: 0, value: original) }
    let checkpoint = node.makeCheckpoint()
    let replacement = Model()
    node.setStateSlotSilently(ordinal: 0, value: replacement)
    original.value = 42
    node.restoreCheckpoint(checkpoint)
    let restored: Model = node.stateSlot(ordinal: 0, seed: Model())
    #expect(restored === original)
    #expect(restored.value == 42)
    #expect(node.stateSlotStorage(ordinal: 0)?.dormantPolicy == .owned)
  }
}
