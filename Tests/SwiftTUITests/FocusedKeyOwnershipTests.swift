import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct FocusedKeyOwnershipTests {
  @Test("STUI-491: synthetic List rows reach their owner's authored handlers across id/frame")
  func listOwnerRouting() throws {
    let log = KeyOwnershipLog()
    let harness = try listHarness(log)
    defer { harness.shutdown() }
    _ = try harness.focusText("Row zero")
    let focus = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    #expect(harness.runLoop.renderer.viewGraph.nodeForIdentity(focus) == nil)
    #expect(harness.runLoop.focusTracker.currentFocusOwnerNodeID != nil)

    for label in ["Row zero", "Row one"] {
      _ = try harness.focusText(label)
      log.events = []
      _ = try harness.pressKey(KeyPress(.space))
      #expect(log.events == ["outer", "list"])
      #expect(log.activations.isEmpty)
    }

    log.listHandles = false
    log.events = []
    _ = try harness.pressKey(KeyPress(.space))
    #expect(log.events == ["outer", "list"])
    #expect(log.activations == [1])
    #expect(log.selection == 1)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(log.activations == [1, 1])
  }

  @Test("STUI-492: enclosing interception precedes List selection and focus movement")
  func interceptedArrowsDoNotMutate() throws {
    let log = KeyOwnershipLog()
    log.outerHandles = true
    let harness = try listHarness(log)
    defer { harness.shutdown() }
    _ = try harness.focusText("Row zero")
    let startFocus = harness.runLoop.focusTracker.currentFocusIdentity
    _ = try harness.pressKey(KeyPress(.arrowDown))
    #expect(log.events == ["outer"])
    #expect(log.selection == 0)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == startFocus)

    log.outerHandles = false
    log.events = []
    _ = try harness.pressKey(KeyPress(.arrowDown))
    #expect(log.events == ["outer", "list"])
    #expect(log.selection == 1)
    let secondRow = try harness.focusIdentity(forText: "Row one")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == secondRow)
    _ = try harness.pressKey(KeyPress(.arrowDown))
    #expect(log.selection == 2)
    let thirdRow = try harness.focusIdentity(forText: "Row two")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == thirdRow)
    _ = try harness.pressKey(KeyPress(.arrowUp))
    #expect(log.selection == 1)
  }

  @Test("synthetic focus ownership works without pointer hit regions")
  func ownerDoesNotDependOnPointerRegions() throws {
    let log = KeyOwnershipLog()
    log.allowsHitTesting = false
    let harness = try listHarness(log)
    defer { harness.shutdown() }
    _ = try harness.focusText("Row zero")
    _ = try harness.pressKey(KeyPress(.space))
    #expect(log.events == ["outer", "list"])
    #expect(log.activations.isEmpty)
  }

  @Test("windowed List navigation advances once across the realized row band")
  func windowedNavigation() throws {
    let log = KeyOwnershipLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("WindowedKeyOwnership"), size: .init(width: 44, height: 8)
    ) {
      List(
        0..<30, id: \.self,
        selection: Binding(get: { log.optionalSelection }, set: { log.optionalSelection = $0 }),
        onActivate: { log.activations.append($0) }
      ) { row in
        Text("Indexed \(row)")
      }
      .frame(width: 36, height: 4)
      .onKeyPress(.space) { _ in
        log.events.append("list")
        return .handled
      }
      .onKeyPress(.tab) { _ in .handled }
    }
    defer { harness.shutdown() }
    _ = try harness.focusText("Indexed 0")
    for index in 1...7 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      #expect(log.optionalSelection == index)
      let expectedFocus = try harness.focusIdentity(forText: "Indexed \(index)")
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == expectedFocus)
      log.events = []
      _ = try harness.pressKey(KeyPress(.space))
      #expect(log.events == ["list"])
    }
    // Later inputs in a pump batch advance from the pending offscreen target.
    for _ in 0..<5 { _ = harness.runLoop.handleKeyPress(KeyPress(.arrowDown)) }
    #expect(log.optionalSelection == 12)
    _ = harness.runLoop.handleKeyPress(KeyPress(.arrowUp))
    #expect(log.optionalSelection == 11)
    _ = harness.runLoop.handleKeyPress(KeyPress(.return))
    #expect(log.activations == [11])
    let pending = try #require(harness.runLoop.pendingKeyFocus)
    _ = harness.runLoop.handleKeyPress(KeyPress(.tab))
    #expect(harness.runLoop.pendingKeyFocus?.identity == pending.identity)
    _ = try harness.render()
    let expectedFocus = try harness.focusIdentity(forText: "Indexed 11")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == expectedFocus)
    #expect(harness.runLoop.pendingKeyFocus == nil)
  }

  @Test("List navigation skips unselectable rows with selection and focus together")
  func navigationSkipsUntaggedRows() throws {
    let log = KeyOwnershipLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("UntaggedKeyOwnership"), size: .init(width: 44, height: 12)
    ) {
      List(selection: Binding(get: { log.selection }, set: { log.selection = $0 })) {
        Text("Selectable zero").tag(0)
        Text("No selection tag")
        Text("Selectable two").tag(2)
      }
    }
    defer { harness.shutdown() }
    _ = try harness.focusText("Selectable zero")
    _ = try harness.pressKey(KeyPress(.arrowDown))
    #expect(log.selection == 2)
    let expectedFocus = try harness.focusIdentity(forText: "Selectable two")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == expectedFocus)
    _ = try harness.pressKey(KeyPress(.arrowUp))
    #expect(log.selection == 0)
  }

  @Test("List arrows use the live focus target when several inputs arrive before a frame")
  func batchedArrowsMoveOnce() throws {
    let log = KeyOwnershipLog()
    let harness = try listHarness(log)
    defer { harness.shutdown() }
    _ = try harness.focusText("Row zero")
    _ = harness.runLoop.handleKeyPress(KeyPress(.arrowDown))
    #expect(log.selection == 1)
    _ = harness.runLoop.handleKeyPress(KeyPress(.arrowDown))
    #expect(log.selection == 2)
    _ = try harness.render()
    let thirdRow = try harness.focusIdentity(forText: "Row two")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == thirdRow)
  }

  @Test("multiple selection moves focus without selection and toggles Space once")
  func multipleSelection() throws {
    let log = KeyOwnershipLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MultiKeyOwnership"), size: .init(width: 44, height: 12)
    ) {
      List(selection: Binding(get: { log.multipleSelection }, set: { log.multipleSelection = $0 }))
      {
        Text("Row zero").tag(0)
        Text("Row one").tag(1)
        Text("Row two").tag(2)
      }.onKeyPress(.space) { _ in
        log.events.append("list")
        return log.listHandles ? .handled : .ignored
      }
    }
    defer { harness.shutdown() }
    _ = try harness.focusText("Row zero")
    _ = try harness.pressKey(KeyPress(.arrowDown))
    #expect(log.multipleSelection.isEmpty)
    let secondRow = try harness.focusIdentity(forText: "Row one")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == secondRow)
    _ = try harness.pressKey(KeyPress(.space))
    #expect(log.multipleSelection.isEmpty)
    log.listHandles = false
    _ = try harness.pressKey(KeyPress(.space))
    #expect(log.multipleSelection == [1])
    _ = try harness.pressKey(KeyPress(.space))
    #expect(log.multipleSelection.isEmpty)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(log.multipleSelection == [1])
    _ = try harness.pressKey(KeyPress(.return))
    #expect(log.multipleSelection.isEmpty)
  }

  @Test("pasted spaces declined by List ancestors do not activate rows")
  func listPasteDoesNotActivate() throws {
    let log = KeyOwnershipLog()
    log.listHandles = false
    let harness = try listHarness(log)
    defer { harness.shutdown() }
    _ = try harness.focusText("Row zero")
    let startFocus = harness.runLoop.focusTracker.currentFocusIdentity
    _ = try harness.paste("a b\n\t")
    #expect(log.events == ["outer", "list", "outer", "list", "outer", "list"])
    #expect(log.activations.isEmpty)
    #expect(log.selection == 0)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == startFocus)
  }

  @Test("enclosing handlers intercept hosted text input before built-in editing")
  func hostedEditor() throws {
    let log = KeyOwnershipLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HostedEditorKeys"), size: .init(width: 44, height: 12)
    ) {
      List(selection: Binding(get: { log.selection }, set: { log.selection = $0 })) {
        TextField("Editor", text: Binding(get: { log.text }, set: { log.text = $0 }))
          .id(testIdentity("hosted-editor")).tag(0)
        Text("Row one").tag(1)
      }.onKeyPress(.character("x")) { _ in
        log.events.append("list")
        return .handled
      }
    }
    defer { harness.shutdown() }
    _ = try harness.focus(testIdentity("hosted-editor"))
    _ = try harness.pressKey(KeyPress(.character("x")))
    #expect(log.text.isEmpty)
    #expect(log.events == ["list"])
    _ = try harness.pressKey(KeyPress(.character("y")))
    #expect(log.text == "y")
    _ = try harness.pressKey(KeyPress(.arrowDown))
    #expect(log.selection == 0)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == testIdentity("hosted-editor"))
  }

  @Test("interception phases and stacked order survive selective state updates")
  func retainedInterception() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("RetainedKeyOwnership"), size: .init(width: 44, height: 12)
    ) { RetainedKeyOwnershipFixture() }
    defer { harness.shutdown() }
    _ = try harness.focusText("Target")
    for count in 1...4 {
      let frame = try harness.pressKey(KeyPress(.space))
      #expect(frame.contains("outer \(count) inner \(count) default 0"))
    }
  }

  @Test("a retired explicit focus owner cannot route through a same-identity replacement")
  func retiredOwnerDoesNotGuess() throws {
    let renderer = DefaultRenderer()
    let frame = renderer.renderArtifacts(Text("Target").focusable().id("target"))
    let focus = try #require(frame.semanticSnapshot.focusRegions.first)
    let path = renderer.viewGraph.keyEventHostingPath(
      from: focus.identity, ownerNodeID: ViewNodeID(rawValue: UInt64.max)
    )
    #expect(path.isEmpty)
  }

  private func listHarness(_ log: KeyOwnershipLog) throws -> StressRuntimeHarness<
    KeyOwnershipListFixture
  > {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("ListKeyOwnership"), size: .init(width: 44, height: 12)
    ) { KeyOwnershipListFixture(log: log) }
  }
}

@MainActor
private final class KeyOwnershipLog {
  var selection = 0
  var optionalSelection: Int? = 0
  var multipleSelection: Set<Int> = []
  var text = ""
  var events: [String] = []
  var activations: [Int] = []
  var outerHandles = false
  var listHandles = true
  var allowsHitTesting = true
}

private struct KeyOwnershipListFixture: View {
  let log: KeyOwnershipLog
  var body: some View {
    VStack {
      List(
        selection: Binding(get: { log.selection }, set: { log.selection = $0 }),
        onActivate: { log.activations.append($0) }
      ) {
        Text("Row zero").tag(0).onKeyPress { _ in
          log.events.append("unfocused-label")
          return .handled
        }
        Text("Row one").tag(1)
        Text("Row two").tag(2)
      }
      .id("owned-list")
      .frame(width: 36, height: 5)
      .allowsHitTesting(log.allowsHitTesting)
      .onKeyPress { key in
        log.events.append("list")
        return key.key == .space && log.listHandles ? .handled : .ignored
      }
      Button("Sibling") {}.onKeyPress { _ in
        log.events.append("sibling")
        return .handled
      }
    }.onKeyPress { _ in
      log.events.append("outer")
      return log.outerHandles ? .handled : .ignored
    }
  }
}

private struct RetainedKeyOwnershipFixture: View {
  @State private var outer = 0
  @State private var inner = 0
  @State private var activations = 0
  var body: some View {
    VStack {
      Button("Target") { activations += 1 }
        .id("retained-target")
        .onKeyPress(.space) { _ in
          inner += 1
          return .handled
        }
      Text("outer \(outer) inner \(inner) default \(activations)")
    }.onKeyPress(.space) { _ in
      outer += 1
      return .ignored
    }
  }
}
