import Testing

@testable import SwiftTUIGraph

@MainActor
struct MemoReadOwnerLifetimeTests {
  @Test("recycled raw node IDs cannot restore discarded state read currency")
  func discardedOwner() {
    let graph = ViewGraph()
    graph.beginFrame()
    let checkpoint = graph.makeCheckpoint()
    let identity = testIdentity("Owner")
    let owner = graph.prepareDynamicPropertyUpdate(identity: identity)
    let reader = graph.beginEvaluation(identity: testIdentity("Reader"), invalidator: nil)
    ViewNodeContext.withValue(reader) { _ = owner.stateSlot(ordinal: 0, seed: 7) }
    _ = reader.finishEvaluation(accessedStateSlots: 0)
    #expect(reader.hasCurrentMemoReadCertificates)
    graph.restoreCheckpoint(checkpoint)
    let replacement = graph.prepareDynamicPropertyUpdate(identity: identity)
    #expect(replacement.viewNodeID == owner.viewNodeID)
    #expect(replacement.ownerLifetimeID != owner.ownerLifetimeID)
    _ = replacement.stateSlot(ordinal: 0, seed: 7)
    #expect(!reader.hasCurrentMemoReadCertificates)
  }
}
