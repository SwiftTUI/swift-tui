import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCControlLayoutTests {
  @Test func setC073PointerAndKeyboardActionsStayIndependent() throws {
    let box = SetCControlBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC073"),
      size: .init(width: 30, height: 6)
    ) {
      VStack {
        Button("Alpha") { box.a += 1 }
        Button("Beta") { box.b += 1 }
      }
    }
    defer { h.shutdown() }
    let a = try #require(h.point(forText: "Alpha"))
    _ = try h.sendMouse(.down(.primary), at: a)
    _ = try h.focusText("Beta")
    _ = try h.pressKey(.init(.return))
    #expect(box.a == 0)
    #expect(box.b == 1)
    _ = try h.sendMouse(.up(.primary), at: a)
    #expect(box.a == 1)
    #expect(box.b == 1)
  }

  @Test func setC074DisablingHeldButtonPreventsReleaseAction() throws {
    let box = SetCControlBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC074"),
      size: .init(width: 30, height: 6)
    ) {
      Button("Hold") { box.a += 1 }.disabled(!box.enabled)
    }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "Hold"))
    _ = try h.sendMouse(.down(.primary), at: point)
    box.enabled = false
    _ = try h.renderAfterExternalMutation()
    _ = try h.sendMouse(.up(.primary), at: point)
    #expect(box.a == 0)
  }

  @Test func setC075ReleaseOutsideDoesNotActivate() throws {
    let box = SetCControlBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC075"),
      size: .init(width: 30, height: 6)
    ) { Button("Hold") { box.a += 1 } }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "Hold"))
    let outside = Point(x: 29, y: 5)
    _ = try h.sendMouse(.down(.primary), at: point)
    _ = try h.sendMouse(.dragged(.primary), at: outside)
    _ = try h.sendMouse(.up(.primary), at: outside)
    #expect(box.a == 0)
  }

  @Test func setC076ListSpinnerRegistrationsRetireBeforeFirstTick() throws {
    let box = SetCControlBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC076"),
      size: .init(width: 30, height: 16)
    ) {
      List {
        if box.visible {
          ForEach(0..<8) { i in Spinner().accessibilityLabel("S\(i)") }
        }
      }.listStyle(.plain).environment(\.accessibilityReduceMotion, box.reduced)
    }
    // This synchronous test cancels every registration before any task body
    // can enter its first actor turn. Running-body termination is a separate census.
    defer { h.shutdown() }
    #expect(h.activeTaskCount == 8)
    box.reduced = true
    _ = try h.renderAfterExternalMutation()
    #expect(h.activeTaskCount == 0)
    box.visible = false
    _ = try h.renderAfterExternalMutation()
    #expect(h.activeTaskCount == 0)
    #expect(h.runLoop.lifecycleCoordinator.taskStartSkipCount == 0)
  }

  @Test func setC077NegativeFixedWidthPreservesOtherAxis() {
    let frame = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("L")
        Text("abc").frame(width: -3, height: 2)
        Text("R")
      }, context: .init(identity: testIdentity("setC077")),
      proposal: .init(width: 20, height: 4))
    #expect(frame.measuredTree.measuredSize == .init(width: 5, height: 2))
    #expect(frame.rasterSurface.lines.joined().contains("abc"))
  }

  @Test func setC078NegativeSpacerMinimumIsZeroInDeficit() {
    let frame = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("L")
        Spacer(minLength: -4)
        Text("R")
      },
      context: .init(identity: testIdentity("setC078")),
      proposal: .init(width: 2, height: 1))
    #expect(frame.measuredTree.measuredSize == .init(width: 2, height: 1))
    #expect(frame.rasterSurface.lines == ["LR"])
  }

  @Test func setC079MinimumOnlyFrameClampsProposalAndContent() {
    func measure<V: View>(_ content: V) -> Int {
      DefaultRenderer().render(
        content,
        context: .init(identity: testIdentity("setC079")),
        proposal: .init(width: 10, height: 1)
      ).measuredTree.measuredSize.width
    }
    #expect(measure(Text("x").frame(width: 20).frame(minWidth: 5)) == 10)
    #expect(measure(Text("abcdefgh").frame(minWidth: 5)) == 8)
    #expect(measure(Text("ab").frame(minWidth: 5)) == 5)
  }

  @Test func setC080AdoptingFocusAfterEmptyFrameSettlesOnce() throws {
    let box = SetCControlBox()
    box.visible = false
    let root = testIdentity("setC080")
    let target = testIdentity("setC080-button")
    let h = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 30, height: 6)) {
      if box.visible { Button("B") {}.id(target) } else { Text("none") }
    }
    defer { h.shutdown() }
    try #require(h.runLoop.focusTracker.currentFocusIdentity == nil)
    box.visible = true
    h.runLoop.scheduler.requestInvalidation(of: [root])
    var frames = 0
    try h.runLoop.renderPendingFrames(renderedFrames: &frames)
    #expect(h.runLoop.focusTracker.currentFocusIdentity == target)
    #expect(frames == 1)
    try h.runLoop.renderPendingFrames(renderedFrames: &frames)
    #expect(frames == 1)
  }
}

@MainActor
private final class SetCControlBox {
  var a = 0
  var b = 0
  var enabled = true
  var reduced = false
  var visible = true
}
