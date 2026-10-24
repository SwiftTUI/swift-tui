import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F2 resize during control interaction", .serialized)
struct AdversarialSetDResizeControlTests {
  @Test(arguments: Array(31...40))
  func resizedControl(id: Int) throws {
    let kind = id - 30
    let model = SetDControlModel()
    let root = testIdentity("setD", String(id))
    let surface = SetDResizableSurface()
    let scheduler = FrameScheduler()
    let focus = FocusTracker(invalidationIdentities: [root])
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: surface,
      terminalInputReader: SetDFiniteInput([]), signalReader: nil, scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: focus, viewBuilder: { _, _ in SetDControlForm(kind: kind, model: model) })
    focus.invalidator = scheduler
    defer { loop.lifecycleCoordinator.shutdown() }
    var rendered = 0
    scheduler.requestInvalidation(of: [root])
    try loop.renderPendingFrames(renderedFrames: &rendered)
    loop.renderer.enableSelectiveEvaluation()
    let identity = try #require(focus.focusRegions.first?.identity)
    let moved = focus.setFocus(to: identity)
    #expect(moved || focus.currentFocusIdentity == identity)
    try loop.renderPendingFrames(renderedFrames: &rendered)
    func key(_ key: KeyEvent) throws {
      #expect(loop.withRuntimeRegistrationScope { loop.handleKeyPress(.init(key)) } == nil)
      try loop.renderPendingFrames(renderedFrames: &rendered)
    }
    for size in [CellSize(width: 30, height: 6), CellSize(width: 40, height: 8)] {
      switch kind {
      case 1, 10: try key(.return)
      case 2: try key(.space)
      case 3, 4, 6: try key(.arrowRight)
      case 5: try key(.arrowDown)
      default:
        try key(.end)
        try key(.character("z"))
      }
      let before = model.snapshot
      surface.surfaceSize = size
      #expect(loop.withRuntimeRegistrationScope { loop.handle(.signal("SIGWINCH")) } == nil)
      try loop.renderPendingFrames(renderedFrames: &rendered)
      #expect(surface.raster?.size == size)
      #expect(focus.currentFocusIdentity == identity)
      #expect(model.snapshot == before)
      if kind == 8 { #expect(surface.raster?.lines.joined().contains("seed") == false) }
    }
    #expect(model.mutations == 2)
    switch kind {
    case 1, 3...6: #expect(model.number == 2)
    case 2, 10: #expect(!model.flag)
    default: #expect(model.text == "seedzz")
    }
  }
}

final class SetDResizableSurface: PresentationSurface {
  let supportsUserExit = true
  var surfaceSize = CellSize(width: 40, height: 8)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  var raster: RasterSurface?
  var presentCount = 0
  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}
  func present(_ surface: RasterSurface) throws -> PresentationMetrics {
    raster = surface
    presentCount += 1
    return .init(
      linesTouched: surface.size.height, cellsChanged: surface.size.width * surface.size.height)
  }
}
