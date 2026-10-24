@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCElidedPublicationTests {
  @Test func setC108EndAfterElidedFrameDoesNothing() async throws {
    try await SetCElision.scenario(.vertical, name: "setC108") { h, log in
      _ = try h.pressKey(.init(.end))
      // Predicted STUI-1130 route loss did not occur: the elided commit keeps
      // the scroll routes this shape needs (observed, see the pass report).
      #expect(log.outerValue.y > 0, "\(h.frame)")
    }
  }

  @Test func setC109ArrowAfterElidedFrameMoves() async throws {
    try await SetCElision.scenario(.vertical, name: "setC109") { h, log in
      _ = try h.pressKey(.init(.arrowDown))
      #expect(log.outerValue.y == 1, "\(h.frame)")
    }
  }

  @Test func setC110WheelAfterElidedFrameMoves() async throws {
    try await SetCElision.scenario(.vertical, name: "setC110") { h, log in
      let point = try #require(h.point(forText: "row 1"))
      _ = try h.scrollPointer(at: point, deltaY: 1)
      #expect(log.outerValue.y == 1, "\(h.frame)")
    }
  }

  @Test func setC111NestedInnerEndAfterElidedFrame() async throws {
    try await SetCElision.scenario(.nested, name: "setC111") { h, log in
      _ = try h.pressKey(.init(.end))
      #expect(log.outerValue.y == 0, "the unfocused outer view must not move: \(h.frame)")
      #expect(log.innerValue.y > 0, "\(h.frame)")
    }
  }

  @Test func setC112HorizontalEndAfterElidedFrame() async throws {
    try await SetCElision.scenario(.horizontal, name: "setC112") { h, log in
      _ = try h.pressKey(.init(.end))
      #expect(log.outerValue.x > 0, "\(h.frame)")
    }
  }

  @Test func setC113CompletedFrameRestoresEnd() async throws {
    try await SetCElision.scenario(.vertical, name: "setC113") { h, log in
      try #require(log.label).wrappedValue = "B"
      _ = try h.render()
      try #require(h.frame.contains("label B"))
      _ = try h.pressKey(.init(.end))
      #expect(log.outerValue.y > 0, "\(h.frame)")
    }
  }

  @Test func setC114OnScreenAnimationIsNotElidedAndEndMoves() async throws {
    try await SetCElision.scenario(.onScreen, name: "setC114", expectElision: false) { h, log in
      _ = try h.pressKey(.init(.end))
      #expect(log.outerValue.y > 0, "\(h.frame)")
    }
  }
}

@MainActor
private final class SetCElisionClock { var now = MonotonicInstant.now() }

@MainActor
private final class SetCElisionLog {
  var phase: Binding<Double>?
  var label: Binding<String>?
  var outerValue = ScrollCellOffset.zero
  var innerValue = ScrollCellOffset.zero
  var outer: Binding<ScrollCellOffset> {
    .init(get: { self.outerValue }, set: { self.outerValue = $0 })
  }
  var inner: Binding<ScrollCellOffset> {
    .init(get: { self.innerValue }, set: { self.innerValue = $0 })
  }
}

private enum SetCElisionMode {
  case vertical, nested, horizontal, onScreen
}

private struct SetCElisionRoot: View {
  @State private var phase = 0.0
  @State private var label = "A"
  let mode: SetCElisionMode
  let log: SetCElisionLog

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      Text("label \(label)")
      if mode == .onScreen {
        chasing
      }
      switch mode {
      case .horizontal:
        ScrollView(.horizontal, position: log.outer) {
          HStack(alignment: .top, spacing: 0) {
            ForEach(0..<12) { i in Text("col\(i)") }
            chasing
          }
        }.frame(height: 3)
      case .nested:
        ScrollView(.vertical, position: log.outer) {
          VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, position: log.inner) {
              VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<12) { i in Text("inner \(i)") }
              }
            }.frame(height: 3)
            ForEach(0..<20) { i in Text("row \(i)") }
            chasing
          }
        }.frame(height: 4)
      default:
        ScrollView(.vertical, position: log.outer) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<20) { i in Text("row \(i)") }
            if mode != .onScreen {
              chasing
            }
          }
        }.frame(height: 4)
      }
    }
  }

  private var chasing: some View {
    Text("chasing")
      .padding(1)
      .frame(width: 10, height: 3)
      .blendBorder(
        blend: BorderBlend([.red, .yellow, .green, .cyan, .blue, .red]),
        set: .single,
        phase: phase
      )
  }

  private func capture() {
    log.phase = $phase
    log.label = $label
  }
}

@MainActor
private enum SetCElision {
  /// Mounts the fixture, focuses the scroll view (Tab; twice for the nested
  /// inner view), starts an off-screen perpetual border animation on a frozen
  /// clock, drives one deadline-only frame through the production async
  /// acquisition (the synchronous driver never runs the elision gate) and
  /// hands the harness to `body` with the animation sinks still bound.
  static func scenario(
    _ mode: SetCElisionMode, name: String, expectElision: Bool = true,
    _ body: @MainActor (StressRuntimeHarness<SetCElisionRoot>, SetCElisionLog) throws -> Void
  ) async throws {
    let log = SetCElisionLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity(name),
      size: .init(width: 24, height: 8)
    ) { SetCElisionRoot(mode: mode, log: log) }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.tab))
    let outerFocus = h.runLoop.focusTracker.currentFocusIdentity
    try #require(outerFocus != nil, "a scroll view is focused")
    if mode == .nested {
      _ = try h.pressKey(.init(.tab))
      try #require(
        h.runLoop.focusTracker.currentFocusIdentity != outerFocus, "the inner view takes focus")
    }
    let controller = h.runLoop.renderer.internalAnimationController
    let clock = SetCElisionClock()
    h.runLoop.frameClock = { clock.now }
    let phase = try #require(log.phase)
    try await withAnimationSinks(controller) {
      withAnimation(.linear(duration: .seconds(3)).repeatForever(autoreverses: false)) {
        phase.wrappedValue = 1
      }
      _ = try h.render()
      var turns = 0
      while h.runLoop.scheduler.hasPendingFrame(at: clock.now), turns < 64 {
        _ = try h.render()
        turns += 1
      }
      try #require(controller.activeAnimationCount > 0, "the perpetual animation is in flight")
      let elidedBefore = h.runLoop.renderer.elidedFrameCount
      h.runLoop.scheduler.requestDeadline(clock.now)
      var rendered = 0
      _ = try await h.runLoop.renderPendingFramesAsync(renderedFrames: &rendered, eventPump: nil)
      if expectElision {
        try #require(
          h.runLoop.renderer.elidedFrameCount > elidedBefore,
          "the deadline-only tick must elide (before \(elidedBefore))")
      } else {
        try #require(h.runLoop.renderer.elidedFrameCount == elidedBefore)
      }
      try body(h, log)
    }
  }
}
