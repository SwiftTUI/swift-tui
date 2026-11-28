import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@MainActor
@Suite struct IdentifiedTransitionTests {
  enum Decoration: CaseIterable {
    case overlay, background

    var transition: AnyTransition {
      switch self {
      case .overlay: AnyTransition(Marked())
      case .background: AnyTransition(Backed())
      }
    }

    var expected: String { self == .overlay ? "i*em" : "item" }
  }

  @Test(arguments: Decoration.allCases, [true, false])
  func firstFrame(decoration: Decoration, idFirst: Bool) throws {
    let transition = decoration.transition
    if idFirst {
      try checkContainers(Text("item").id(0).transition(transition), expected: decoration.expected)
    } else {
      try checkContainers(Text("item").transition(transition).id(0), expected: decoration.expected)
    }
  }

  private func checkContainers<Item: View>(_ item: Item, expected: String) throws {
    func rows<Root: View>(@ViewBuilder _ root: @escaping () -> Root) throws -> [String] {
      let probe = try StagesReviewProbe(
        named: "identified-transition", size: .init(width: 12, height: 3)
      ) {
        _, _, _ in root()
      }
      defer { probe.shutdown() }
      #expect(probe.harness.runLoop.reportedRuntimeIssues.isEmpty)
      return [probe.line(0), probe.line(1)]
    }

    #expect(try rows { VStack { item } }.first == expected)
    #expect(
      try rows {
        VStack(alignment: .leading, spacing: 0) {
          Group {
            Text("a")
            item
          }
        }
      }.prefix(2) == ["a", expected])
    let shown = true
    #expect(
      try rows {
        VStack(alignment: .leading, spacing: 0) {
          Text("a")
          if shown { item }
        }
      }.prefix(2) == ["a", expected])
  }

  @Test func conditionalItemAnimatesInAndOut() throws {
    let terminal = try RunLoopTestHarness(size: .init(width: 12, height: 3)) { ToggleScene() }
    defer { terminal.shutdown() }
    func expectIntermediatePosition() {
      let row = terminal.lines[1]
      let offset = row.prefix { $0 == " " }.count
      #expect((1..<6).contains(offset))
      #expect(row.dropFirst(offset) == "i*em")
    }

    let toggle = KeyPress(.character("t"))
    #expect(terminal.lines[1].isEmpty)
    try terminal.press(toggle)
    #expect(terminal.lines[1] == "      i*em")
    try terminal.advance(by: .milliseconds(400))
    expectIntermediatePosition()
    try terminal.advance(by: .milliseconds(500))
    #expect(terminal.lines[1] == "i*em")

    try terminal.press(toggle)
    #expect(terminal.lines[1] == "i*em")
    try terminal.advance(by: .milliseconds(400))
    expectIntermediatePosition()
    try terminal.advance(by: .milliseconds(500))
    #expect(terminal.lines[1].isEmpty)
    #expect(terminal.nextWake == nil)

    // Mount a new ID in the same frame that makes the item visible again.
    try terminal.press(toggle)
    try terminal.advance(by: .milliseconds(900))
    #expect(terminal.lines[1] == "i*em")
  }
}

private struct Marked: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.overlay { Text("*") }
  }
}

private struct Backed: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.background { Text("*") }
  }
}

private struct SlidingMark: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.overlay { Text("*") }.offset(x: phase.isIdentity ? 0 : 6, y: 0)
  }
}

private struct ToggleScene: View {
  @State private var shown = false
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("toggle").focusable().onKeyPress(.character("t")) { _ in
        withAnimation(.linear(duration: .milliseconds(800))) {
          shown.toggle()
          if shown { generation += 1 }
        }
        return .handled
      }
      if shown {
        Text("item").id(generation).transition(SlidingMark())
      }
    }
    .frame(width: 12, height: 3, alignment: .topLeading)
  }
}
