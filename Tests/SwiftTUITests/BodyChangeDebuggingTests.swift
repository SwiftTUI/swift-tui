import Foundation
import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct BodyChangeDebuggingTests {
  @Test("helpers are synchronous, agree, name state, and stay silent on reuse")
  func stateAndReuse() {
    let recorded = DebugBodyProbe()
    let plain = DebugBodyProbe()
    let renderer = DefaultRenderer()
    let oracle = DefaultRenderer()
    let root = testIdentity("DebugRoot")
    for tick in 0..<5 {
      if tick == 3 {
        recorded.binding?.wrappedValue = 19
        plain.binding?.wrappedValue = 19
      }
      let context = ResolveContext(identity: root, invalidatedIdentities: tick == 0 ? [] : [root])
      let result = BodyChangeOutput.$sink.withValue(recorded.sink) {
        renderer.render(DebugBodyRoot(probe: recorded, tick: tick, enabled: true), context: context)
      }
      let expected = oracle.render(
        DebugBodyRoot(probe: plain, tick: tick, enabled: false), context: context)
      #expect(result.rasterSurface == expected.rasterSurface)
      #expect(recorded.evaluations == plain.evaluations)
    }
    #expect(recorded.evaluations == 2)
    #if DEBUG
      #expect(recorded.records.count == 4)
      #expect(recorded.records[0] == recorded.records[1])
      #expect(recorded.records[2] == recorded.records[3])
      #expect(recorded.records[0].causes.contains { $0.property == "@identity" })
      #expect(
        recorded.records[2].causes.contains {
          $0.category == "state" && $0.precision == "exact" && $0.property == "_value"
        })
    #else
      #expect(recorded.records.isEmpty)
    #endif
  }

  @Test("custom modifiers and out-of-context calls use distinct scopes")
  func modifiersAndContext() {
    let probe = DebugBodyProbe()
    BodyChangeOutput.$sink.withValue(probe.sink) {
      DebugCounter._printChanges()
      _ = DefaultRenderer().render(Text("content").modifier(DebugBodyModifier()))
    }
    #if DEBUG
      #expect(
        probe.records.first?.causes == [.init("context-unavailable", precision: "unavailable")])
      let modifiers = probe.records.filter { $0.kind == "modifier" }
      #expect(modifiers.count == 2)
      #expect(modifiers.first == modifiers.last)
      #expect(modifiers.first?.graph != 0)
    #else
      #expect(probe.records.isEmpty)
    #endif
  }

  @Test("formatters escape control scalars and bound complete JSON records")
  func formats() throws {
    let record = BodyChangeRecord(
      typeName: "Type\n\u{1b}\"💡", kind: "view",
      causes: (0..<90).map {
        .init(
          "state", precision: "exact", property: "\($0)" + String(repeating: "💡\u{0}", count: 100))
      })
    let json = record.formatted(.json)
    let decoded = try #require(
      JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(decoded["schema"] as? Int == 1)
    #expect((decoded["omitted"] as? Int ?? 0) > 0)
    for format in [BodyChangeFormat.text, .json] {
      let line = record.formatted(format)
      #expect(line.utf8.count <= BodyChangeRecord.maximumEncodedBytes)
      #expect(line.filter { $0 == "\n" }.count == 1)
      #expect(!line.contains("\u{1b}"))
      #expect(!line.contains("\u{0}"))
      #expect(line == record.formatted(format))
    }
  }

  @Test("multiple owners and graphs do not share a body's history")
  func isolation() {
    let probe = DebugBodyProbe()
    BodyChangeOutput.$sink.withValue(probe.sink) {
      for _ in 0..<2 {
        _ = DefaultRenderer().render(
          VStack {
            DebugCounter(probe: probe, enabled: true)
            DebugCounter(probe: probe, enabled: true)
          })
      }
    }
    #if DEBUG
      #expect(Set(probe.records.map(\.graph)).count == 2)
      #expect(Set(probe.records.map { "\($0.graph)/\($0.owner)/\($0.body)" }).count == 4)
      #expect(probe.records.allSatisfy { $0.causes.contains { $0.property == "@identity" } })
    #else
      #expect(probe.records.isEmpty)
    #endif
  }
}

@MainActor
private final class DebugBodyProbe {
  var evaluations = 0
  var binding: Binding<Int>?
  var records: [BodyChangeRecord] = []
  var sink: BodyChangeSink { BodyChangeSink { [self] record, _ in records.append(record) } }
}

private struct DebugBodyRoot: View {
  let probe: DebugBodyProbe
  let tick: Int
  let enabled: Bool
  var body: some View {
    VStack {
      DebugCounter(probe: probe, enabled: enabled)
      Text("tick \(tick)")
    }
  }
}

private struct DebugCounter: View, Equatable {
  let probe: DebugBodyProbe
  let enabled: Bool
  @State private var value = 7
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.enabled == rhs.enabled }
  var body: some View {
    if enabled {
      Self._printChanges()
      Self._logChanges()
    }
    probe.evaluations += 1
    probe.binding = $value
    return Text("state \(value)")
  }
}

private struct DebugBodyModifier: ViewModifier {
  func body(content: Content) -> some View {
    let _ = Self._printChanges()
    let _ = Self._logChanges()
    content.padding()
  }
}
