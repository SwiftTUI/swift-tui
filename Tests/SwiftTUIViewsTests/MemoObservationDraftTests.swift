import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@Observable
private final class DraftCertificateModel { var value = 1 }

@MainActor
struct MemoObservationDraftTests {
  @Test("discarding a draft retires its read certificate")
  func discardedDraft() {
    let graph = ViewGraph()
    let bridge = ObservationBridge()
    bridge.attachViewGraph(graph)
    let model = DraftCertificateModel()
    let identity = Identity(components: ["reader"])
    graph.beginFrame()
    let reader = graph.beginEvaluation(identity: identity, invalidator: nil)
    let draft = bridge.makeDraft(attaching: graph)
    ViewNodeContext.withValue(reader) { _ = bridge.track(identity: identity) { model.value } }
    _ = reader.finishEvaluation(accessedStateSlots: 0)
    #expect(reader.hasCurrentMemoReadCertificates)
    draft.suspendRecording()
    draft.discard()
    #expect(!reader.hasCurrentMemoReadCertificates)
  }
}
