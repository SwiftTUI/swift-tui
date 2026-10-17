@_spi(Testing) import SwiftTUITestSupport
// Adversarial set B, pass 3: action scopes, key commands, palette, toolbar
// and drops (291–300).
//
// Key dispatch runs command scopes, then the focused hosting chain, then the
// built-in routes; palette and toolbar contributions are hoisted by
// preference; drops are routed to destination scopes. The register fixes the
// scope rules and the DocC guide fixes that a disabled subtree handles no
// keys. These probes pop a destination under edit focus, intercept keys
// beneath a modal, position a toolbar item, contribute commands and items
// from disabled subtrees, parse the host form of a file URL, declare bindings
// the parser can never produce, drop nothing, select a disabled palette row,
// and pin how authored handlers gate the built-ins.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: commands and scopes", .serialized)
struct AdversarialSetBCommandTests {
  private func harness<V: View>(
    _ name: String, width: Int = 48, height: Int = 14, @ViewBuilder content: @escaping () -> V
  ) throws -> StressRuntimeHarness<V> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBCommand", name), size: .init(width: width, height: height),
      content: content)
  }

  // Escape pops a pushed destination even while a text field inside it has
  // focus, once the field's exit handler declines.
  @Test func setB291EscapePopsADestinationUnderEditFocus() throws {
    let log = SetBCommandLog()
    let h = try harness("EditPop") { SetBEditPopFixture(log: log) }
    defer { h.shutdown() }
    _ = try h.clickText("Push")
    try #require(h.frame.contains("Name"), "\(h.frame)")
    _ = try h.focus(SetBEditPopFixture.fieldIdentity)
    _ = try h.pressKey(KeyPress(.escape))
    #expect(log.events == ["exit"], "\(log.events)")
    do {
      #expect(!h.frame.contains("Name"), "\(h.frame)")
      #expect(h.frame.contains("Push"), "\(h.frame)")
    }
    _ = try h.clickText("Push")
    _ = try h.focusText("Dest")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(h.frame.contains("Push") && !h.frame.contains("Dest"), "\(h.frame)")
  }

  // A key handler on the presenter does not intercept keys pressed inside a
  // modal sheet; the sheet's content gets them.
  @Test func setB292PresenterKeyHandlerDoesNotInterceptInsideAModalSheet() throws {
    let log = SetBCommandLog()
    let h = try harness("SheetKeys") { SetBSheetKeysFixture(log: log) }
    defer { h.shutdown() }
    _ = try h.clickText("Open")
    try #require(h.frame.contains("A") && h.frame.contains("B"), "\(h.frame)")
    _ = try h.focusText("A")
    let a = h.runLoop.focusTracker.currentFocusIdentity
    let b = try h.focusIdentity(forText: "B")
    _ = try h.focus(try #require(a))
    _ = try h.pressKey(KeyPress(.arrowDown))
    do {
      #expect(log.events.isEmpty, "\(log.events)")
      #expect(
        h.runLoop.focusTracker.currentFocusIdentity == b,
        "\(String(describing: h.runLoop.focusTracker.currentFocusIdentity))")
    }
  }

  // A toolbar item's `position` places it: `.top` sits above the body even
  // under a bottom toolbar style.
  @Test func setB293ToolbarItemPositionIsHonoured() throws {
    let snapshot = DefaultRenderer().render(
      Panel(id: "strip") {
        Text("body").toolbarItem(.init(title: "Up", position: .top) {})
      }
      .toolbar().toolbarStyle(.defaultBottom).frame(width: 20, height: 5),
      context: .init(identity: testIdentity("SetBCommand", "position")),
      proposal: .init(width: 20, height: 5))
    let lines = snapshot.rasterSurface.lines
    let up = try #require(lines.firstIndex { $0.contains("Up") }, "\(lines)")
    let body = try #require(lines.firstIndex { $0.contains("body") }, "\(lines)")
    do {
      #expect(up < body, "Up at \(up), body at \(body): \(lines)")
    }
  }

  @Test(arguments: [false, true])
  func mixedToolbarEdgesRetireAndRestoreTheirActions(bottomStyle: Bool) throws {
    let log = SetBCommandLog()
    let h = try harness("BothEdges") { SetBToolbarEdges(log: log, bottomStyle: bottomStyle) }
    defer { h.shutdown() }
    for _ in 0..<3 {
      let top = try #require(h.point(forText: "TopItem"))
      let body = try #require(h.point(forText: "BodyMarker"))
      let bottom = try #require(h.point(forText: "BottomItem"))
      #expect(top.y < body.y && body.y < bottom.y, "\(h.frame)")
      _ = try h.clickText("TopItem")
      _ = try h.pressKey(.init(.character("h"), modifiers: .ctrl))
      #expect(!h.frame.contains("TopItem") && h.frame.contains("BottomItem"), "\(h.frame)")
      _ = try h.clickText("BottomItem")
      _ = try h.pressKey(.init(.character("h"), modifiers: .ctrl))
    }
    #expect(log.events == ["top", "bottom", "top", "bottom", "top", "bottom"])
  }

  // A palette command declared inside a disabled subtree is disabled too.
  @Test func setB294PaletteCommandInADisabledSubtreeDoesNotRun() throws {
    let log = SetBCommandLog()
    let h = try harness("DisabledPalette") {
      Panel(id: "host") {
        Panel(id: "inner") { EmptyView() }
          .paletteCommand(name: "Delete") { log.events.append("Delete") }
          .disabled(true)
      }
      .paletteSheet("Cmds", isPresented: .constant(true))
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Delete"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.return))
    do {
      #expect(log.events.isEmpty, "\(log.events)")
    }
  }

  // A toolbar item contributed from a disabled subtree renders disabled.
  @Test func setB295ToolbarItemFromADisabledSubtreeIsDisabled() throws {
    let h = try harness("DisabledToolbar") { SetBDisabledToolbarFixture() }
    defer { h.shutdown() }
    try #require(h.frame.contains("Bump"), "\(h.frame)")
    _ = try h.clickText("Bump")
    let node = h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
      $0.label == "Bump"
    }
    do {
      #expect(h.frame.contains("count:0"), "\(h.frame)")
      #expect(node?.isEnabled == false, "\(String(describing: node))")
    }
  }

  // The host form of a file URL and an uppercase scheme are path-shaped
  // drops like the three-slash form.
  @Test func setB296HostFormFileURLsParseAsDroppedPaths() {
    #expect(parseDroppedPaths("file:///Users/me/a.txt").map(\.rawValue) == ["/Users/me/a.txt"])
    let host = parseDroppedPaths("file://localhost/Users/me/a.txt").map(\.rawValue)
    let upper = parseDroppedPaths("FILE:///Users/me/b.txt").map(\.rawValue)
    do {
      #expect(host == ["/Users/me/a.txt"], "\(host)")
      #expect(upper == ["/Users/me/b.txt"], "\(upper)")
    }
    #expect(parseDroppedPaths("file://evil.example/etc/passwd").isEmpty)
  }

  // A key binding the terminal can never deliver (Shift+letter, Ctrl+upper
  // case) is reported like a modifier-less one instead of registering dead.
  @Test func setB297UndeliverableBindingsAreReported() throws {
    let log = SetBCommandLog()
    let h = try harness("Dead") {
      Panel(id: "dead") {
        Text("x").focusable(true)
      }
      .keyCommand("Upper", key: .character("A"), modifiers: .shift) { log.events.append("upper") }
      .keyCommand("CtrlUpper", key: .character("S"), modifiers: .ctrl) {
        log.events.append("ctrlUpper")
      }
    }
    defer { h.shutdown() }
    var parser = KeyParser()
    let shifted = parser.feed([0x41])
    #expect(shifted == [KeyPress(.character("A"))], "\(shifted)")
    let control = parser.feed([0x13])
    #expect(control == [KeyPress(.character("s"), modifiers: .ctrl)], "\(control)")
    _ = try h.focusText("x")
    for key in shifted + control {
      _ = try h.pressKey(key)
    }
    #expect(
      log.events.isEmpty, "the parser's keys never match the declared bindings: \(log.events)")
    let issues = h.runLoop.renderer.viewGraph.frameRuntimeIssues.map(\.code)
    do {
      #expect(issues.contains { $0.hasPrefix("keyCommand.") }, "\(issues)")
    }
  }

  // A drop that carries no paths does not invoke the destination; a drop
  // with duplicate paths delivers them verbatim.
  @Test func setB298EmptyDropDoesNotInvokeTheDestination() throws {
    let log = SetBDropLog()
    let h = try harness("EmptyDrop") {
      Panel(id: "drop") {
        Text("x").focusable(true)
      }
      .dropDestination { paths, _ in
        log.drops.append(paths.map(\.rawValue))
        return true
      }
    }
    defer { h.shutdown() }
    _ = try h.focusText("x")
    _ = try h.drop(paths: [], context: .init())
    do {
      #expect(log.drops.isEmpty, "\(log.drops)")
    }
    log.drops.removeAll()
    _ = try h.drop(paths: ["/tmp/a", "/tmp/a"], context: .init())
    #expect(log.drops == [["/tmp/a", "/tmp/a"]], "\(log.drops)")
  }

  // Palette keyboard selection skips disabled commands and never parks on
  // one.
  @Test func setB299PaletteSelectionSkipsDisabledCommands() throws {
    let log = SetBCommandLog()
    let h = try harness("DisabledRow") {
      Panel(id: "commands") { EmptyView() }
        .paletteCommand(name: "Alpha") { log.events.append("Alpha") }
        .paletteCommand(name: "Bravo", isEnabled: false) { log.events.append("Bravo") }
        .paletteCommand(name: "Charlie") { log.events.append("Charlie") }
        .paletteSheet("Cmds", isPresented: .constant(true))
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("> Alpha"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.arrowDown))
    let afterDown = h.frame
    _ = try h.pressKey(KeyPress(.return))
    do {
      #expect(afterDown.contains("> Charlie"), "\(afterDown)")
      #expect(log.events == ["Charlie"], "\(log.events)")
    }
    #expect(!log.events.contains("Bravo"), "\(log.events)")
  }

  // Authored handlers gate the built-ins: a handled Tab stops traversal, an
  // ignored Return lets the focused button activate, a handled one does not.
  @Test func setB300AuthoredHandlersGateBuiltInKeyBehavior() throws {
    let tabLog = SetBCommandLog()
    let tab = try harness("TabGate") {
      VStack(alignment: .leading) {
        Button("A") {}
        Button("B") {}
      }
      .onKeyPress(.key(.tab)) { _ in
        tabLog.events.append("tab")
        return .handled
      }
    }
    defer { tab.shutdown() }
    let a = try tab.focusIdentity(forText: "A")
    _ = try tab.focus(a)
    _ = try tab.pressKey(KeyPress(.tab))
    #expect(tab.runLoop.focusTracker.currentFocusIdentity == a)
    #expect(tabLog.events == ["tab"])

    for handled in [false, true] {
      let probe = SetBCommandLog()
      let h = try harness("ReturnGate-\(handled)") {
        VStack(alignment: .leading) {
          Button("Go") { probe.events.append("go") }
        }
        .onKeyPress(.key(.return)) { _ in handled ? .handled : .ignored }
      }
      defer { h.shutdown() }
      _ = try h.focusText("Go")
      _ = try h.pressKey(KeyPress(.return))
      #expect(probe.events == (handled ? [] : ["go"]), "handled=\(handled): \(probe.events)")
    }
  }
}

@MainActor
private final class SetBCommandLog {
  var events: [String] = []
}

@MainActor
private final class SetBDropLog {
  var drops: [[String]] = []
}

@MainActor
private struct SetBEditPopFixture: View {
  static let fieldIdentity = testIdentity("SetBCommand", "PopField")
  let log: SetBCommandLog
  @State private var pushed = false
  @State private var text = ""

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading) {
        Button("Push") { pushed = true }
      }
      .navigationDestination(isPresented: $pushed) {
        VStack(alignment: .leading) {
          Text("Dest").focusable()
          TextField("Name", text: $text).textFieldStyle(.plain).id(Self.fieldIdentity)
            .onExitCommand {
              log.events.append("exit")
              return .ignored
            }
        }
      }
    }
  }
}

@MainActor
private struct SetBSheetKeysFixture: View {
  let log: SetBCommandLog
  @State private var show = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Open") { show = true }
    }
    .onKeyPress(.key(.arrowDown)) { _ in
      log.events.append("base")
      return .handled
    }
    .sheet("S", isPresented: $show) {
      VStack(alignment: .leading) {
        Button("A") {}
        Button("B") {}
      }
    }
  }
}

@MainActor
private struct SetBDisabledToolbarFixture: View {
  @State private var n = 0

  var body: some View {
    Panel(id: "strip") {
      VStack(alignment: .leading) {
        Text("count:\(n)").toolbarItem(.init(title: "Bump") { n += 1 }).disabled(true)
      }
    }
    .toolbar().toolbarStyle(.defaultBottom)
  }
}

@MainActor
private struct SetBToolbarEdges: View {
  let log: SetBCommandLog
  let bottomStyle: Bool
  @State private var showsTop = true

  var body: some View {
    Panel(id: "edges") {
      VStack {
        if showsTop {
          Text("BodyMarker").toolbarItem(
            .init(title: "TopItem", position: .top) {
              log.events.append("top")
            })
        } else {
          Text("BodyMarker")
        }
      }
      .toolbarItem(.init(title: "BottomItem", position: .bottom) { log.events.append("bottom") })
    }
    .keyCommand("Toggle top", key: .character("h"), modifiers: .ctrl) { showsTop.toggle() }
    .toolbar().toolbarStyle(bottomStyle ? .defaultBottom : .defaultTop)
  }
}
