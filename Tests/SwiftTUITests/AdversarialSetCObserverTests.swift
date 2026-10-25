@_spi(Testing) import SwiftTUITestSupport
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
      // STUI-1174: the initial event queued on the cold-resolve interior mount
      // survives that node's chain-collapse reclaim.
      #expect(log.notes.map(\.old) == [1])
      #expect(log.notes.map(\.new) == [1])
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

  // Wave-2 repair regressions for STUI-1174 (onChange(of:initial:) delivers its
  // initial action when the view appears, Coming-From-SwiftUI.md). The four
  // shapes are F1 pass 1's minimization: a root conditional, a nested branch,
  // and the initial observer inside or outside a sibling observer.
  @Test(arguments: [0, 1, 2, 3])
  func conditionalInitialChangeDelivers(shape: Int) throws {
    let log = SetCInitialLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC036-shape-\(shape)"),
      size: .init(width: 30, height: 4)
    ) {
      if shape == 0 {
        Text("one").onChange(of: 1, initial: true) { old, new in log.notes.append([old, new]) }
      } else {
        SetCInitialLeaf(shape: shape, log: log)
      }
    }
    defer { h.shutdown() }
    #expect(log.notes == [[1, 1]])
    #expect(h.runLoop.lifecycleCoordinator.changeHandlerSkipCount == 0)
    log.notes.removeAll()
    _ = try h.renderAfterExternalMutation()
    #expect(log.notes.isEmpty)
  }

  @Test func unwrappedInitialChangeDeliversOnce() throws {
    let log = SetCInitialLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC036-unwrapped"),
      size: .init(width: 30, height: 4)
    ) {
      Text("one").onChange(of: 1, initial: true) { old, new in log.notes.append([old, new]) }
    }
    defer { h.shutdown() }
    #expect(log.notes == [[1, 1]])
    _ = try h.renderAfterExternalMutation()
    #expect(log.notes == [[1, 1]])
  }

  @Test func conditionalNonInitialChangeIsSilentAtMount() throws {
    let log = SetCInitialLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC036-not-initial"),
      size: .init(width: 30, height: 4)
    ) {
      if log.visible {
        Text("one").onChange(of: 1, initial: false) { old, new in log.notes.append([old, new]) }
      } else {
        Text("absent")
      }
    }
    defer { h.shutdown() }
    #expect(log.notes.isEmpty)
  }

  @Test func conditionalRemountDeliversFreshInitialChange() throws {
    let log = SetCInitialLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC036-remount"),
      size: .init(width: 30, height: 4)
    ) {
      if log.visible {
        Text("one").onChange(of: 1, initial: true) { old, new in log.notes.append([old, new]) }
      } else {
        Text("absent")
      }
    }
    defer { h.shutdown() }
    #expect(log.notes == [[1, 1]])
    log.visible = false
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("absent"))
    #expect(log.notes == [[1, 1]])
    log.visible = true
    _ = try h.renderAfterExternalMutation()
    #expect(log.notes == [[1, 1], [1, 1]])
  }

  /// Conditional composition must not reorder the unwrapped control's
  /// initial callbacks. Each leg has its own harness so the unwrapped leg's
  /// root is not itself a conditional.
  @Test func conditionalInitialChangesKeepUnwrappedOrder() throws {
    let unwrappedLog = SetCInitialLog()
    let unwrapped = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC036-order-unwrapped"),
      size: .init(width: 30, height: 4)
    ) {
      Text("pair")
        .onChange(of: 1, initial: true) { unwrappedLog.order.append("inner") }
        .onChange(of: 2, initial: true) { unwrappedLog.order.append("outer") }
    }
    defer { unwrapped.shutdown() }
    let conditionalLog = SetCInitialLog()
    let conditional = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC036-order-conditional"),
      size: .init(width: 30, height: 4)
    ) {
      if conditionalLog.visible {
        Text("pair")
          .onChange(of: 1, initial: true) { conditionalLog.order.append("inner") }
          .onChange(of: 2, initial: true) { conditionalLog.order.append("outer") }
      } else {
        Text("absent")
      }
    }
    defer { conditional.shutdown() }
    #expect(unwrappedLog.order.count == 2, "unwrapped \(unwrappedLog.order)")
    #expect(conditionalLog.order == unwrappedLog.order, "conditional \(conditionalLog.order)")
  }

  /// The same delivery through the production asynchronous run loop with
  /// finite input (F1 pass 1's minimization, production-loop leg).
  @Test func productionLoopDeliversConditionalInitialChange() async throws {
    let log = SetCInitialLog()
    let root = testIdentity("setC036-loop")
    let loop = RunLoop(
      rootIdentity: root,
      presentationSurface: RecordingPresentationSurface(surfaceSize: .init(width: 30, height: 4)),
      terminalInputReader: SetCInitialEmptyInput(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      viewBuilder: { _, _ in SetCInitialLeaf(shape: 2, log: log) }
    )
    let result = try await loop.run()
    #expect(result.exitReason == .inputEnded)
    #expect(log.notes == [[1, 1]])
  }
}

private final class SetCInitialEmptyInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}

@MainActor
private final class SetCInitialLog {
  var notes: [[Int]] = []
  var order: [String] = []
  var visible = true
}

private struct SetCInitialLeaf: View {
  @State private var value = 1
  @State private var sibling = 1
  let shape: Int
  let log: SetCInitialLog

  var body: some View {
    if shape == 1 {
      Text("one").onChange(of: value, initial: true) { old, new in log.notes.append([old, new]) }
    } else if shape == 2 {
      Text("two").onChange(of: value, initial: true) { old, new in log.notes.append([old, new]) }
        .onChange(of: sibling) { _, _ in }
    } else {
      Text("three").onChange(of: sibling) { _, _ in }
        .onChange(of: value, initial: true) { old, new in log.notes.append([old, new]) }
    }
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
