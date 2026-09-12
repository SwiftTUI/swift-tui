import Testing

@testable import SwiftTUIGraph

@MainActor
struct MemoReadCertificateTests {
  @Test("silent writes deny memo reuse and checkpoint restoration restores the exact read")
  func stateCurrencyAndRollback() {
    let graph = ViewGraph()
    graph.beginFrame()
    let owner = graph.prepareDynamicPropertyUpdate(identity: testIdentity("Owner"))
    let reader = graph.beginEvaluation(identity: testIdentity("Reader"), invalidator: nil)
    ViewNodeContext.withValue(reader) { _ = owner.stateSlot(ordinal: 0, seed: 7) }
    _ = reader.finishEvaluation(accessedStateSlots: 0)
    #expect(reader.hasCurrentMemoReadCertificates)
    let checkpoint = owner.makeCheckpoint()
    owner.setStateSlotSilently(ordinal: 0, value: 8)
    #expect(!reader.hasCurrentMemoReadCertificates)
    owner.restoreCheckpoint(checkpoint)
    #expect(reader.hasCurrentMemoReadCertificates)
    owner.setStateSlotSilently(ordinal: 0, value: 9)
    #expect(!reader.hasCurrentMemoReadCertificates)
  }

  @Test("multiple versions within a body remain uncovered")
  func conflictingReadVersions() {
    let graph = ViewGraph()
    graph.beginFrame()
    let owner = graph.prepareDynamicPropertyUpdate(identity: testIdentity("Owner"))
    let reader = graph.beginEvaluation(identity: testIdentity("Reader"), invalidator: nil)
    ViewNodeContext.withValue(reader) {
      _ = owner.stateSlot(ordinal: 0, seed: 7)
      owner.setStateSlotSilently(ordinal: 0, value: 8)
      _ = owner.stateSlot(ordinal: 0, seed: 7)
    }
    _ = reader.finishEvaluation(accessedStateSlots: 0)
    #expect(!reader.hasCurrentMemoReadCertificates)
  }

  @Test("conditional reevaluation retires the former state read")
  func conditionalReads() {
    let graph = ViewGraph()
    graph.beginFrame()
    let owner = graph.prepareDynamicPropertyUpdate(identity: testIdentity("Owner"))
    let reader = graph.beginEvaluation(identity: testIdentity("Reader"), invalidator: nil)
    ViewNodeContext.withValue(reader) { _ = owner.stateSlot(ordinal: 0, seed: 7) }
    _ = reader.finishEvaluation(accessedStateSlots: 0)
    graph.beginFrame()
    reader.beginEvaluation(frameID: graph.currentFrameID, invalidator: nil)
    ViewNodeContext.withValue(reader) { _ = owner.stateSlot(ordinal: 1, seed: 9) }
    _ = reader.finishEvaluation(accessedStateSlots: 0)
    owner.setStateSlotSilently(ordinal: 0, value: 8)
    #expect(reader.hasCurrentMemoReadCertificates)
    owner.setStateSlotSilently(ordinal: 1, value: 10)
    #expect(!reader.hasCurrentMemoReadCertificates)
  }

  @Test("reference replacement tokens do not certify mutable model internals")
  func mutableReferencesRemainUncovered() {
    final class Model { var value = 0 }
    let graph = ViewGraph()
    graph.beginFrame()
    let owner = graph.beginEvaluation(identity: testIdentity("Owner"), invalidator: nil)
    ViewNodeContext.withValue(owner) { _ = owner.stateSlot(ordinal: 0, seed: Model()).value }
    _ = owner.finishEvaluation(accessedStateSlots: 0)
    #expect(!owner.hasCurrentMemoReadCertificates)
  }
}
