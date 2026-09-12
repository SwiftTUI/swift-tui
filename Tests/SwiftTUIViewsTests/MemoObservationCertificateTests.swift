import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@Observable
private final class CertificateModel {
  var first = 1
  var second = 2
}

@MainActor
struct MemoObservationCertificateTests {
  @Test("rollback cannot revive a fired observation certificate; reevaluation renews it")
  func rollbackAndRenewal() {
    let graph = ViewGraph()
    let bridge = ObservationBridge()
    bridge.attachViewGraph(graph)
    let model = CertificateModel()
    let identity = Identity(components: ["reader"])
    graph.beginFrame()
    let reader = graph.beginEvaluation(identity: identity, invalidator: nil)
    bridge.beginTrackingPass()
    ViewNodeContext.withValue(reader) { _ = bridge.track(identity: identity) { model.first } }
    _ = reader.finishEvaluation(accessedStateSlots: 0)
    #expect(reader.hasCurrentMemoReadCertificates)
    let graphCheckpoint = graph.makeCheckpoint()
    let observationCheckpoint = bridge.makeCheckpoint()
    model.first = 3
    #expect(!reader.hasCurrentMemoReadCertificates)
    graph.restoreCheckpoint(graphCheckpoint)
    bridge.restoreCheckpoint(observationCheckpoint)
    #expect(!reader.hasCurrentMemoReadCertificates)
    graph.beginFrame()
    _ = graph.beginEvaluation(identity: identity, invalidator: nil)
    bridge.beginTrackingPass()
    ViewNodeContext.withValue(reader) { _ = bridge.track(identity: identity) { model.second } }
    _ = reader.finishEvaluation(accessedStateSlots: 0)
    #expect(reader.hasCurrentMemoReadCertificates)
    model.first = 4
    #expect(reader.hasCurrentMemoReadCertificates)
    model.second = 5
    #expect(!reader.hasCurrentMemoReadCertificates)
  }

  @Test("retiring the registration denies a still-retained dependency snapshot")
  func prunedRegistration() {
    let graph = ViewGraph()
    let bridge = ObservationBridge()
    bridge.attachViewGraph(graph)
    let model = CertificateModel()
    let identity = Identity(components: ["reader"])
    graph.beginFrame()
    let reader = graph.beginEvaluation(identity: identity, invalidator: nil)
    bridge.beginTrackingPass()
    ViewNodeContext.withValue(reader) { _ = bridge.track(identity: identity) { model.first } }
    _ = reader.finishEvaluation(accessedStateSlots: 0)
    #expect(reader.hasCurrentMemoReadCertificates)
    bridge.prune(keeping: Set<ViewNodeID>())
    #expect(!reader.hasCurrentMemoReadCertificates)
  }
}
