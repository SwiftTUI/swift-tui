import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCRemovalTests {
  @Test(arguments: Array(51...60))
  func removalCompletesAndRetires(id: Int) throws {
    let log = SetCRemovalLog()
    defer {
      log.remove = nil
      log.visibility = nil
    }
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC\(id)"),
      size: .init(width: 40, height: 12)
    ) { SetCRemovalRoot(mode: id, log: log) }
    defer { h.shutdown() }
    try #require(h.frame.contains("gone"))
    let controller = h.runLoop.renderer.internalAnimationController
    let clock = SetCRemovalClock()
    h.runLoop.frameClock = { clock.now }
    let remove = try #require(log.remove)
    if id == 59 {
      let visible = try #require(log.visibility)
      try withAnimationSinks(controller) {
        withAnimation(.linear(duration: .seconds(1))) { visible.wrappedValue = false }
        _ = try h.render()
        clock.now = clock.now.advanced(by: .milliseconds(200))
        withAnimation(.linear(duration: .seconds(1))) { visible.wrappedValue = true }
        _ = try h.render()
      }
    }
    let animation: Animation? =
      id == 57
      ? .linear(duration: .seconds(1))
      : id == 58 ? .linear(duration: .zero) : nil
    try withAnimationSinks(controller) {
      remove(animation)
      _ = try h.render()
      let target = clock.now.advanced(by: .seconds(3))
      var turns = 0
      while let wake = h.runLoop.scheduler.nextWakeInstant(after: clock.now), wake <= target,
        turns < 256
      {
        clock.now = wake
        _ = try h.render()
        turns += 1
      }
      #expect(turns < 256, "scheduler must settle within the fixed turn budget")
    }
    #expect(log.completions == 1)
    #expect(!h.frame.contains("gone"))
    let state = controller.debugStateSnapshot()
    #expect(state.removingNodeIDs.isEmpty)
    #expect(state.completionClosureBatchIDs.isEmpty)
    #expect(!controller.requiresContinuedAnimationFrames)
    #expect(h.runLoop.scheduler.nextWakeInstant(after: clock.now) == nil)
    if id == 60 { #expect(h.frame.contains("completed 1")) }
  }
}

@MainActor
private final class SetCRemovalClock { var now = MonotonicInstant.now() }

@MainActor
private final class SetCRemovalLog {
  var remove: ((Animation?) -> Void)?
  var visibility: Binding<Bool>?
  var completions = 0
}

private struct SetCRemovalRoot: View {
  @State private var shown = true
  @State private var completed = 0
  let mode: Int
  let log: SetCRemovalLog

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      Text("completed \(completed)")
      switch mode {
      case 51:
        Text("host").frame(width: 20, height: 3).background(alignment: .bottomLeading) {
          if shown { Text("gone").transition(.opacity) }
        }
      case 52:
        ZStack {
          Text("host")
          if shown { Text("gone").transition(.opacity) }
        }
      case 53:
        GroupBox("host") { if shown { Text("gone").transition(.opacity) } }
      case 54:
        ForEach(shown ? [1, 2] : [], id: \.self) { i in Text("gone \(i)").transition(.opacity) }
      case 55:
        List {
          if shown {
            Text("gone 1")
            Text("gone 2")
          }
        }.listStyle(.plain)
      case 56:
        if shown { Text("gone").padding(1).frame(width: 20).id("wrapped").transition(.opacity) }
      case 57:
        if shown { Text("gone").transition(.identity) }
      case 58:
        if shown { Text("gone").transition(.opacity.combined(with: .scale)) }
      default:
        if shown { Text("gone").transition(.opacity) }
      }
    }
  }

  private func capture() {
    log.visibility = $shown
    log.remove = { animation in
      withAnimation(animation, completionCriteria: .removed) {
        shown = false
      } completion: {
        log.completions += 1
        if mode == 60 { completed += 1 }
      }
    }
  }
}
