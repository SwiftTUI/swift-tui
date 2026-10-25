import Foundation
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCDiagnosticTests {
  @Test(arguments: [91, 92, 93, 94, 95, 99])
  func bodyDiagnosticContracts(id: Int) throws {
    let log = SetCDiagnosticLog()
    let h = try BodyChangeOutput.$sink.withValue(log.sink) {
      try StressRuntimeHarness(
        rootIdentity: testIdentity("setC\(id)"),
        size: .init(width: 45, height: 5)
      ) { SetCDiagnosticRoot(mode: id, log: log) }
    }
    defer { h.shutdown() }
    let model = try #require(log.model)
    let direct = try #require(log.direct)
    let unread = try #require(log.unread)
    let text = try #require(log.text)
    log.records.removeAll()
    try BodyChangeOutput.$sink.withValue(log.sink) {
      switch id {
      case 91: model.count.wrappedValue = 7
      case 92: model.nested.count.wrappedValue = 7
      case 94: unread.wrappedValue = 7
      case 99: text.wrappedValue = "fixture-visible-value-49"
      default: direct.wrappedValue = 7
      }
      _ = try h.render()
    }
    if id == 94 {
      #expect(
        !log.records.contains {
          $0.causes.contains { $0.category == "state" && $0.precision == "exact" }
        })
      #expect(unread.wrappedValue == 7)
      return
    }
    #expect(h.frame.contains(id == 99 ? "fixture-visible-value-49" : "7"))
    #if DEBUG
      let records = log.records.filter { $0.typeName.contains("SetCDiagnosticReader") }
      try #require(!records.isEmpty)
      if id == 95 {
        #expect(records.count == 2)
        #expect(records.first == records.last)
      } else if id == 99 {
        #expect(records.allSatisfy { !$0.formatted(.json).contains("fixture-visible-value-49") })
      } else {
        #expect(
          records.contains { record in
            record.causes.contains {
              $0.category == "state" && $0.precision == "exact" && $0.property == "_value"
            }
          })
      }
    #else
      #expect(log.records.isEmpty)
    #endif
  }

  // Wave 3 (STUI-1131) neighbour: a projection is attributed to its own root
  // slot only. A sibling binding to an unchanged state is not named.
  @Test func wave3b21ProjectedBindingNamesOnlyItsOwnSource() throws {
    let log = SetCDiagnosticLog()
    let h = try BodyChangeOutput.$sink.withValue(log.sink) {
      try StressRuntimeHarness(
        rootIdentity: testIdentity("wave3b21"),
        size: .init(width: 45, height: 5)
      ) { SetCPairedDiagnosticRoot(log: log) }
    }
    defer { h.shutdown() }
    let model = try #require(log.model)
    log.records.removeAll()
    try BodyChangeOutput.$sink.withValue(log.sink) {
      model.nested.count.wrappedValue = 7
      _ = try h.render()
    }
    #expect(h.frame.contains("7 1"), "\(h.frame)")
    #if DEBUG
      let causes = log.records.filter { $0.typeName.contains("SetCPairedDiagnosticReader") }
        .flatMap(\.causes).filter { $0.category == "state" && $0.precision == "exact" }
      #expect(causes.map(\.property) == ["_projected"], "\(causes)")
    #else
      #expect(log.records.isEmpty)
    #endif
  }

  @Test func setC096PrivateTypeNamesDoNotContainContextAddresses() {
    let name = BodyChangeRecord.name(of: SetCDiagnosticModel.self)
    #expect(name.contains("SetCDiagnosticModel"))
    #expect(!name.contains("unknown context at $"))
  }

  @Test func setC097RepeatedCausesHaveDeterministicEncoding() throws {
    let a = BodyChangeRecord.Cause("state", precision: "exact", property: "_a")
    let b = BodyChangeRecord.Cause("environment", precision: "exact", property: "_b")
    let first = BodyChangeRecord(typeName: "Fixture", kind: "view", causes: [b, a, b])
    let second = BodyChangeRecord(typeName: "Fixture", kind: "view", causes: [a, b])
    #expect(first.formatted(.json) == second.formatted(.json))
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(first.formatted(.json).utf8)) as? [String: Any])
    #expect((object["causes"] as? [[String: Any]])?.count == 2)
  }

  @Test func setC098UnicodeDiagnosticBudgetKeepsValidCompleteRecord() throws {
    let record = BodyChangeRecord(
      typeName: "Fixture", kind: "view",
      causes: (0..<80).map {
        .init(
          "state", precision: "exact", property: "field\($0)" + String(repeating: "界", count: 90))
      })
    let encoded = record.formatted(.json)
    #expect(encoded.utf8.count <= BodyChangeRecord.maximumEncodedBytes)
    #expect(encoded.filter { $0 == "\n" }.count == 1)
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
    #expect(object["schema"] as? Int == 1)
    #expect((object["omitted"] as? Int ?? 0) > 0)
  }

  @Test func setC100NestedOutputSinksRestoreOnReturn() {
    let outer = SetCDiagnosticLog()
    let inner = SetCDiagnosticLog()
    func record(_ name: String) {
      BodyChangeOutput.emit(.init(typeName: name, kind: "view", causes: []), format: .json)
    }
    BodyChangeOutput.$sink.withValue(outer.sink) {
      record("a")
      BodyChangeOutput.$sink.withValue(inner.sink) { record("b") }
      record("c")
    }
    #if DEBUG
      #expect(outer.records.map(\.typeName) == ["a", "c"])
      #expect(inner.records.map(\.typeName) == ["b"])
    #else
      // BodyChangeOutput.emit is debug-only (BodyChangeOutput.swift:23-24), so a
      // release build delivers nothing to either sink.
      #expect(outer.records.isEmpty)
      #expect(inner.records.isEmpty)
    #endif
  }
}

private struct SetCDiagnosticModel: Equatable, Sendable {
  struct Nested: Equatable, Sendable { var count = 1 }
  var count = 1
  var nested = Nested()
}

@MainActor
private final class SetCDiagnosticLog {
  var records: [BodyChangeRecord] = []
  var evaluations = 0
  var model: Binding<SetCDiagnosticModel>?
  var direct: Binding<Int>?
  var unread: Binding<Int>?
  var text: Binding<String>?
  var sink: BodyChangeSink { .init { [self] record, _ in records.append(record) } }
}

private struct SetCDiagnosticRoot: View {
  @State private var model = SetCDiagnosticModel()
  @State private var direct = 1
  @State private var unread = 1
  @State private var text = "initial"
  let mode: Int
  let log: SetCDiagnosticLog
  var body: some View {
    let _ = capture()
    if mode == 91 {
      SetCDiagnosticReader(value: $model.count, log: log, both: false)
    } else if mode == 92 {
      SetCDiagnosticReader(value: $model.nested.count, log: log, both: false)
    } else if mode == 99 {
      SetCDiagnosticReader(value: $text, log: log, both: false)
    } else {
      SetCDiagnosticReader(value: $direct, log: log, both: mode == 95)
    }
  }
  private func capture() {
    log.model = $model
    log.direct = $direct
    log.unread = $unread
    log.text = $text
  }
}

private struct SetCPairedDiagnosticRoot: View {
  @State private var model = SetCDiagnosticModel()
  @State private var other = 1
  let log: SetCDiagnosticLog
  var body: some View {
    let _ = capture()
    SetCPairedDiagnosticReader(projected: $model.nested.count, other: $other)
  }
  private func capture() { log.model = $model }
}

private struct SetCPairedDiagnosticReader: View {
  @Binding var projected: Int
  @Binding var other: Int
  var body: some View {
    Self._printChanges()
    return Text("\(projected) \(other)")
  }
}

private struct SetCDiagnosticReader<Value: Equatable & Sendable>: View {
  @Binding var value: Value
  let log: SetCDiagnosticLog
  let both: Bool
  var body: some View {
    Self._printChanges()
    if both { Self._logChanges() }
    log.evaluations += 1
    return Text(String(describing: value))
  }
}
