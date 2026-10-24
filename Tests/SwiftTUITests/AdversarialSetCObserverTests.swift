import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCObserverTests {
  @Test(arguments: [31, 33, 34, 35, 36, 38, 39, 40])
  func callbackContracts(id: Int) throws {
    let log = SetCObserverLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC\(id)"),
      size: .init(width: 30, height: 8)
    ) { SetCObserverLeaf(mode: id, log: log) }
    defer { h.shutdown() }
    let entry = try #require(log.entries["a"])
    if id == 36 {
      setCKnown("STUI-1174: conditional composition drops the initial onChange old value") {
        #expect(log.notes.map(\.old) == [1])
      }
      setCKnown("STUI-1174: conditional composition drops the initial onChange new value") {
        #expect(log.notes.map(\.new) == [1])
      }
      log.notes.removeAll()
      _ = try h.renderAfterExternalMutation()
      #expect(log.notes.isEmpty)
      return
    }
    log.notes.removeAll()
    if id == 38 {
      log.contributes = false
      _ = try h.renderAfterExternalMutation()
    } else {
      entry.value.wrappedValue = 2
      if id == 33 { entry.sibling.wrappedValue = 4 }
      if id == 35 { entry.value.wrappedValue = 3 }
      _ = try h.render()
    }
    let value = id == 38 ? 1 : id == 35 ? 3 : 2
    let expectedNew = id == 38 ? 0 : id == 39 ? 4 : value
    let mainNotes = log.notes.filter { $0.kind == "main" }
    #expect(mainNotes.count == 1)
    #expect(mainNotes.last?.new == expectedNew)
    #expect(mainNotes.last?.read == value)
    #expect(log.notes.allSatisfy { $0.ownerMatches })
    if id == 33 {
      #expect(log.notes.filter { $0.kind == "sibling" }.map(\.new) == [4])
      #expect(log.notes.filter { $0.kind == "sibling" }.map(\.old) == [1])
    }
    if id == 35 { #expect(mainNotes.last?.old == 1) }
    if id == 40 { #expect(h.frame.contains("value 2 derived 20")) }
  }

  @Test func setC032CopiedPreferenceObserversKeepDeclarationOwners() throws {
    let log = SetCObserverLog()
    let leaf = SetCObserverLeaf(mode: 32, log: log)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC032"),
      size: .init(width: 60, height: 8)
    ) {
      HStack {
        leaf.environment(\.imageResourceRoots, ["a"]).id("a")
        leaf.environment(\.imageResourceRoots, ["b"]).id("b")
      }
    }
    defer { h.shutdown() }
    let a = try #require(log.entries["a"])
    let b = try #require(log.entries["b"])
    log.notes.removeAll()
    a.value.wrappedValue = 7
    _ = try h.render()
    #expect(log.notes.map(\.name) == ["a"])
    #expect(log.notes.map(\.new) == [7])
    #expect(log.notes.allSatisfy { $0.ownerMatches })
    #expect(b.value.wrappedValue == 1)
  }

  @Test func setC037RemovedObserverGetsFreshBaseline() throws {
    let log = SetCObserverLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC037"),
      size: .init(width: 30, height: 8)
    ) {
      if log.visible { SetCObserverLeaf(mode: 37, log: log) } else { Text("absent") }
    }
    defer { h.shutdown() }
    let original = try #require(log.entries["a"])
    original.value.wrappedValue = 8
    _ = try h.render()
    log.visible = false
    _ = try h.renderAfterExternalMutation()
    log.notes.removeAll()
    log.visible = true
    _ = try h.renderAfterExternalMutation()
    #expect(log.notes.isEmpty)
    let fresh = try #require(log.entries["a"])
    #expect(fresh.value.wrappedValue == 1)
    fresh.value.wrappedValue = 3
    _ = try h.render()
    #expect(log.notes.map(\.old) == [1])
    #expect(log.notes.map(\.new) == [3])
    #expect(log.notes.allSatisfy { $0.ownerMatches })
  }
}

@MainActor
private final class SetCObserverLog {
  struct Entry {
    var value: Binding<Int>
    var sibling: Binding<Int>
  }
  struct Note {
    var name: String
    var kind: String
    var old: Int
    var new: Int
    var read: Int
    var ownerMatches: Bool
  }
  var entries: [String: Entry] = [:]
  var notes: [Note] = []
  var visible = true
  var contributes = true
}

private enum SetCIntPreference: PreferenceKey {
  static let defaultValue = 0
  static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

private struct SetCObserverLeaf: View {
  @State private var value = 1
  @State private var sibling = 1
  @State private var derived = 0
  @Environment(\.imageResourceRoots) private var roots
  let mode: Int
  let log: SetCObserverLog

  var body: some View {
    let name = roots.first ?? "a"
    let owner = currentAuthoringContext()?.stateOwnerHandle
    let _ = { log.entries[name] = .init(value: $value, sibling: $sibling) }()
    let record: (String, Int, Int) -> Void = { kind, old, new in
      log.notes.append(
        .init(
          name: name, kind: kind, old: old, new: new, read: value,
          ownerMatches: owner != nil && owner == currentAuthoringContext()?.stateOwnerHandle))
    }
    if [31, 32, 38, 39, 40].contains(mode) {
      ScrollViewReader { _ in
        Group {
          if log.contributes {
            Text("value \(value) derived \(derived)").preference(
              key: SetCIntPreference.self, value: value)
          } else {
            Text("no contribution")
          }
        }
        .transformPreference(SetCIntPreference.self) { if mode == 39 { $0 *= 2 } }
        .onPreferenceChange(SetCIntPreference.self) { new in
          record("main", 0, new)
          if mode == 40 { derived = new * 10 }
        }
      }
    } else if mode == 34 {
      Text("value \(value)").onChange(of: value) { record("main", 0, value) }
    } else {
      Text("value \(value)")
        .onChange(of: value, initial: mode == 36) { old, new in record("main", old, new) }
        .onChange(of: sibling) { old, new in record("sibling", old, new) }
    }
  }
}
