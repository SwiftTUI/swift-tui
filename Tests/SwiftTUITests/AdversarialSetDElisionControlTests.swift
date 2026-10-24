import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F2 control routes after frame elision", .serialized)
struct AdversarialSetDElisionControlTests {
  @Test(arguments: Array(91...100))
  func elidedControl(id: Int) async throws {
    let kind = id - 90
    let model = SetDControlModel()
    let root = testIdentity("setD", String(id))
    let surface = SetDResizableSurface()
    let scheduler = FrameScheduler()
    let focus = FocusTracker(invalidationIdentities: [root])
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: surface,
      terminalInputReader: SetDFiniteInput([]), signalReader: nil, scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: focus,
      viewBuilder: { _, _ in
        VStack(alignment: .leading, spacing: 0) {
          SetDControlForm(kind: kind, model: model).frame(height: 4, alignment: .topLeading)
          SetDElisionNeighbor()
        }
      })
    focus.invalidator = scheduler
    let frozen = MonotonicInstant.now()
    loop.frameClock = { frozen }
    loop.renderMode = .asyncNoCancel
    defer { loop.lifecycleCoordinator.shutdown() }
    try await withAnimationSinks(loop.renderer.internalAnimationController) {
      var rendered = 0
      scheduler.requestInvalidation(of: [root])
      try loop.renderPendingFrames(renderedFrames: &rendered)
      loop.renderer.enableSelectiveEvaluation()
      let identity = try #require(focus.focusRegions.first?.identity)
      let moved = focus.setFocus(to: identity)
      try #require(moved || focus.currentFocusIdentity == identity)
      try loop.renderPendingFrames(renderedFrames: &rendered)
      try #require(loop.renderer.internalAnimationController.activeAnimationCount > 0)
      let elided = loop.renderer.elidedFrameCount
      let presented = surface.presentCount
      scheduler.requestDeadline(frozen)
      _ = try await loop.renderPendingFramesAsync(renderedFrames: &rendered, eventPump: nil)
      try #require(loop.renderer.elidedFrameCount > elided)
      #expect(surface.presentCount == presented)
      #expect(focus.currentFocusIdentity == identity)
      @MainActor func key(_ key: KeyEvent) throws {
        #expect(loop.withRuntimeRegistrationScope { loop.handleKeyPress(.init(key)) } == nil)
        try loop.renderPendingFrames(renderedFrames: &rendered)
      }
      switch kind {
      case 1, 10: try key(.return)
      case 2: try key(.space)
      case 3, 4, 6: try key(.arrowRight)
      case 5: try key(.arrowDown)
      default:
        try key(.end)
        try key(.character("z"))
      }
      #expect(model.mutations == 1)
      switch kind {
      case 1, 3...6: #expect(model.number == 1)
      case 2, 10: #expect(model.flag)
      default: #expect(model.text == "seedz")
      }
    }
  }
}

private struct SetDElisionNeighbor: View {
  @State private var phase: Double = 0
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("filler").frame(height: 6)
        Text("paint").padding(1).frame(width: 10, height: 3)
          .blendBorder(blend: BorderBlend([.red, .blue, .red]), set: .single, phase: phase)
      }
    }
    .frame(width: 20, height: 1)
    .onAppear { withAnimation(.linear(duration: .seconds(1))) { phase = 1 } }
  }
}
