import Foundation
import Testing

@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct PublicSemanticDifferentialTests {
  @Test("emit six public-semantic fixture observations for the differential adapter")
  func emitObservations() throws {
    var results: [String: [String]] = [:]
    for name in PublicSemanticRecorder.fixtures {
      let recorder = PublicSemanticRecorder()
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("PublicSemantic", name), size: .init(width: 70, height: 4)
      ) {
        PublicSemanticFixture(name: name, recorder: recorder)
      }
      defer { harness.shutdown() }
      #expect(recorder.count == 0)
      recorder.events.removeAll()
      func action(_ key: String) throws {
        let perform = try #require(recorder.actions[key])
        perform()
        try harness.render()
      }
      switch name {
      case "state-batching": try action("batch")
      case "equal-value-write": try action("equal")
      case "binding-projection": try action("project")
      default:
        try action("increment")
        try action("replace")
      }
      results[name] = recorder.events + ["final:\(recorder.count):\(recorder.pair)"]
    }
    let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
    print("[public-semantics] \(String(decoding: data, as: UTF8.self))")
  }
}
