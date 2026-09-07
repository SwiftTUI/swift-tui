import Foundation
import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct ForEachObservableProducerTests {
  @Test("equal row reuse installs the replacement observable producer")
  func equalOutputReplacementTracksCurrentProducer() throws {
    let original = ProducerModel()
    let replacement = ProducerModel()
    let selection = ProducerSelection(model: original)
    let ledger = ProducerLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ProducerReplacement"), size: .init(width: 40, height: 5),
      selectiveEvaluation: true
    ) {
      ProducerReplacementFixture(model: selection.model, ledger: ledger)
    }
    defer { harness.shutdown() }
    let initialHome = try elementHome(harness, suffix: "ID[0]")
    let initialBodies = ledger.bodyCalls
    #expect(harness.frame.contains("value=0"))

    // Only the external producer replacement needs an explicit root pass.
    // Equal rendered input must reuse the leaf while installing the new factory.
    selection.model = replacement
    _ = try harness.renderAfterExternalMutation()
    #expect(ledger.bodyCalls == initialBodies, "the equal leaf must actually be reused")
    #expect(try elementHome(harness, suffix: "ID[0]") == initialHome)

    for value in [1, 2, 25] {
      replacement.value = value
      let frame = try harness.render()
      #expect(frame.contains("value=\(value)"))
      #expect(try elementHome(harness, suffix: "ID[0]") == initialHome)
    }
    let currentBodies = ledger.bodyCalls
    original.value = 99
    let afterStaleWrite = try harness.render()
    #expect(afterStaleWrite.contains("value=25"))
    #expect(!afterStaleWrite.contains("value=99"))
    #expect(ledger.bodyCalls == currentBodies, "a retired producer must not update the row")
  }

  @Test("observable producers rebuild empty and grouped row shapes", arguments: [false, true])
  func producerRebuildsStructuralShapes(selectiveEvaluation: Bool) throws {
    let model = ProducerModel()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ProducerShapes"), size: .init(width: 40, height: 8),
      selectiveEvaluation: selectiveEvaluation
    ) {
      ProducerShapeFixture(model: model)
    }
    defer { harness.shutdown() }
    #expect(harness.frame.contains("anchor"))
    #expect(!harness.frame.contains("head="))

    for (shape, value) in [(2, 10), (1, 11), (0, 12), (2, 13), (1, 14)] {
      model.shape = shape
      model.value = value
      let frame = try harness.render()
      #expect(frame.contains("anchor"))
      #expect(frame.contains("head=\(value)") == (shape > 0))
      #expect(frame.contains("tail=\(value)") == (shape == 2))
      #expect(
        frame.contains("tail=") == (shape == 2), "a removed tail must not survive with an old value"
      )
      if shape == 0 {
        #expect(!frame.contains("head="))
        #expect(!frame.contains("tail="))
      }
    }
  }

  @Test(
    "producer replay keeps exact row identity and state across reorder", arguments: [false, true])
  func exactIdentityStateSurvivesProducerReplayAndReorder(selectiveEvaluation: Bool) throws {
    let model = ProducerModel()
    let ledger = ProducerLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ProducerState"), size: .init(width: 50, height: 8),
      selectiveEvaluation: selectiveEvaluation
    ) {
      ProducerStateFixture(model: model, ledger: ledger)
    }
    defer { harness.shutdown() }
    let initialHome = try exactHome(harness, row: 1)
    let bump = try #require(ledger.bumps[1])
    bump()
    #expect(try harness.render().contains("row=1 value=0 taps=1"))
    for value in [1, 2] {
      model.value = value
      #expect(try harness.render().contains("row=1 value=\(value) taps=1"))
    }
    model.order = [2, 1]
    let reordered = try harness.render()
    #expect(reordered.contains("row=1 value=2 taps=1"))
    let secondRow = try #require(reordered.range(of: "row=2 value=2 taps=0"))
    let firstRow = try #require(reordered.range(of: "row=1 value=2 taps=1"))
    #expect(secondRow.lowerBound < firstRow.lowerBound, "the rows must actually reorder")
    #expect(try exactHome(harness, row: 1) == initialHome)
    bump()
    let oldBumpFrame = try harness.render()
    #expect(oldBumpFrame.contains("row=1 value=2 taps=2"))
    model.value = 25
    #expect(try harness.render().contains("row=1 value=25 taps=2"))
    #expect(try exactHome(harness, row: 1) == initialHome)
    let currentBump = try #require(ledger.bumps[1])
    currentBump()
    let currentBumpFrame = try harness.render()
    #expect(currentBumpFrame.contains("row=1 value=25 taps=3"))
  }

  @Test(
    "lazy, enumerated-tab, and portal consumers replay observable row producers",
    arguments: ProducerConsumer.allCases)
  func deferredConsumersTrackRepeatedWrites(consumer: ProducerConsumer) throws {
    let model = ProducerModel()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ProducerConsumer", consumer.rawValue),
      size: .init(width: 50, height: 12), selectiveEvaluation: true
    ) {
      ProducerConsumerFixture(model: model, consumer: consumer)
    }
    defer { harness.shutdown() }
    #expect(harness.frame.contains("producer=0 value=0"))
    for value in [1, 2, 25] {
      model.value = value
      #expect(try harness.render().contains("producer=0 value=\(value)"))
    }
  }

  @Test("shape replay publishes current actions while scalar updates stay in the row")
  func shapeReplayPublishesCurrentActions() throws {
    let model = ProducerModel()
    model.shape = 1
    let ledger = ProducerPublicationLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ProducerPublication"), size: .init(width: 50, height: 10),
      selectiveEvaluation: true
    ) {
      ProducerPublicationFixture(model: model, ledger: ledger)
    }
    defer { harness.shutdown() }

    model.value = 1
    #expect(try harness.render().contains("head=1"))
    let establishedHostCalls = ledger.hostResolveCalls
    model.value = 2
    #expect(try harness.render().contains("head=2"))
    #expect(ledger.hostResolveCalls == establishedHostCalls, "scalar replay must stay in the row")
    let removedHead = try harness.focusIdentity(forText: "head=2")

    ledger.generation = 1
    model.shape = 0
    let empty = try harness.render()
    #expect(empty.contains("host action"))
    #expect(!empty.contains("head="))
    #expect(!harness.runLoop.focusTracker.focusRegions.contains { $0.identity == removedHead })
    #expect(!harness.runLoop.localActionRegistry.hasHandler(identity: removedHead))
    try activatePresentedText("host action", in: harness)
    #expect(ledger.activations == ["host=1"])
    _ = try harness.render()

    for (generation, value) in [(2, 4), (4, 5)] {
      ledger.generation = generation
      model.shape = 2
      model.value = value
      let grouped = try harness.render()
      #expect(grouped.contains("host action"))
      #expect(grouped.contains("head=\(value)"))
      #expect(grouped.contains("tail=\(value)"))
      let head = try harness.focusIdentity(forText: "head=\(value)")
      let tail = try harness.focusIdentity(forText: "tail=\(value)")
      ledger.activations.removeAll()
      try activatePresentedText("host action", in: harness)
      try activatePresentedText("head=\(value)", in: harness)
      try activatePresentedText("tail=\(value)", in: harness)
      #expect(ledger.activations == ["host=\(generation)", "head=\(value)", "tail=\(value)"])
      _ = try harness.render()

      ledger.generation = generation + 1
      model.shape = 0
      let removed = try harness.render()
      #expect(removed.contains("host action"))
      #expect(!removed.contains("head="))
      #expect(!removed.contains("tail="))
      for identity in [head, tail] {
        #expect(!harness.runLoop.focusTracker.focusRegions.contains { $0.identity == identity })
        #expect(!harness.runLoop.localActionRegistry.hasHandler(identity: identity))
      }
      ledger.activations.removeAll()
      try activatePresentedText("host action", in: harness)
      #expect(ledger.activations == ["host=\(generation + 1)"])
      _ = try harness.render()
    }
  }

  private func activatePresentedText<V: View>(
    _ label: String, in harness: StressRuntimeHarness<V>
  ) throws {
    let point = try #require(harness.point(forText: label))
    // Inspect the handlers published with this frame. A render between down
    // and up could refresh a stale handler and conceal a publication defect.
    #expect(
      harness.runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: point)))
      ) == nil)
    #expect(
      harness.runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: point)))
      ) == nil)
  }

  private func elementHome<V: View>(
    _ harness: StressRuntimeHarness<V>, suffix: String
  ) throws -> String {
    let graph = harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().viewGraph
    let matches = graph.nodeIDByIdentity.filter { $0.key.path.hasSuffix("/" + suffix) }
    #expect(matches.count == 1)
    let entry = try #require(matches.first)
    return "\(entry.key.path):\(entry.value.rawValue)"
  }

  private func exactHome<V: View>(_ harness: StressRuntimeHarness<V>, row: Int) throws -> String {
    let graph = harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().viewGraph
    let identity = testIdentity("ObservableExactRow", String(row))
    let node = try #require(graph.nodeIDByIdentity[identity])
    return "\(identity.path):\(node.rawValue)"
  }
}

@Observable
@MainActor
private final class ProducerModel {
  var value = 0
  var shape = 0
  var order = [1, 2]
}

@MainActor
private final class ProducerSelection {
  var model: ProducerModel
  init(model: ProducerModel) { self.model = model }
}

@MainActor
private final class ProducerLedger {
  var bodyCalls = 0
  var bumps: [Int: () -> Void] = [:]
}

private struct ProducerReplacementFixture: View {
  let model: ProducerModel
  let ledger: ProducerLedger
  var body: some View {
    VStack {
      ForEach(0..<1, id: \.self) { _ in
        ProducerEqualLeaf(value: model.value, ledger: ledger)
      }
    }
  }
}

private struct ProducerEqualLeaf: View, Equatable {
  let value: Int
  let ledger: ProducerLedger
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
  var body: some View {
    let _ = { ledger.bodyCalls += 1 }()
    Text("value=\(value)")
  }
}

private struct ProducerShapeFixture: View {
  let model: ProducerModel
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("anchor")
      ForEach(0..<1, id: \.self) { _ in
        if model.shape == 0 {
          EmptyView()
        } else if model.shape == 1 {
          Text("head=\(model.value)")
        } else {
          Group {
            Text("head=\(model.value)")
            Text("tail=\(model.value)")
          }
        }
      }
    }
  }
}

private struct ProducerStateFixture: View {
  let model: ProducerModel
  let ledger: ProducerLedger
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(model.order, id: \.self) { row in
        ProducerStateRow(row: row, value: model.value, ledger: ledger)
          .id(testIdentity("ObservableExactRow", String(row)))
          .frame(height: 1)
      }
    }
  }
}

private struct ProducerStateRow: View {
  let row: Int
  let value: Int
  let ledger: ProducerLedger
  @State private var taps = 0
  var body: some View {
    let _ = { ledger.bumps[row] = { taps += 1 } }()
    Text("row=\(row) value=\(value) taps=\(taps)")
  }
}

@MainActor
private final class ProducerPublicationLedger {
  var generation = 0
  var hostResolveCalls = 0
  var activations: [String] = []
}

private struct ProducerPublicationFixture: PrimitiveView, ResolvableView {
  let model: ProducerModel
  let ledger: ProducerPublicationLedger
  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    ledger.hostResolveCalls += 1
    let generation = ledger.generation
    // Register the sibling action on the consumer itself. Its stable label
    // keeps clean style-subtree reuse independent from action publication.
    let host = Button("host action") { ledger.activations.append("host=\(generation)") }
      .resolve(in: context.child(component: .named("host")))
    var stack = VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<1, id: \.self) { _ in
        let value = model.value
        if model.shape == 0 {
          EmptyView()
        } else if model.shape == 1 {
          Button("head=\(value)") { ledger.activations.append("head=\(value)") }
        } else {
          Group {
            Button("head=\(value)") { ledger.activations.append("head=\(value)") }
            Button("tail=\(value)") { ledger.activations.append("tail=\(value)") }
          }
        }
      }
    }
    .resolveElements(in: context)[0]
    stack.children.insert(host, at: 0)
    return [stack]
  }
}

enum ProducerConsumer: String, CaseIterable, Sendable {
  case lazy, tabs, portal
}

private struct ProducerConsumerFixture: View {
  let model: ProducerModel
  let consumer: ProducerConsumer
  @State private var presented = true
  var body: some View {
    switch consumer {
    case .lazy:
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<20, id: \.self) { row in
            Text("producer=\(row) value=\(model.value)")
          }
        }
      }
    case .tabs:
      TabView(selection: .constant(0)) {
        ForEach(0..<2, id: \.self) { row in
          let label = "producer=\(row) value=\(model.value)"
          Tab("tab \(row)", value: row) {
            Text(label)
          }
        }
      }
    case .portal:
      Text("host")
        .sheet(isPresented: $presented) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<2, id: \.self) { row in
              Text("producer=\(row) value=\(model.value)")
            }
          }
        }
    }
  }
}
