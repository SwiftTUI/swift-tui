import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite("Campaign F2 finite input batches across controls", .serialized)
struct AdversarialSetDBatchedControlTests {
  @Test(arguments: Array(21...30))
  func batchedControl(id: Int) async throws {
    let kind = id - 20
    let model = SetDControlModel()
    let root = testIdentity("setD", String(id))
    let keys: [KeyPress]
    switch kind {
    case 1, 2, 10: keys = [.init(.return), .init(.space)]
    case 3, 4, 6: keys = [.init(.arrowRight), .init(.arrowRight)]
    case 5: keys = [.init(.arrowDown), .init(.arrowDown)]
    default: keys = [.init(.character("A")), .init(.character("界"))]
    }
    let input: [InputEvent] = [.key(.init(.tab))] + keys.map { .key($0) }
    let surface = RecordingPresentationSurface(surfaceSize: .init(width: 40, height: 8))
    let scheduler = FrameScheduler()
    let focus = FocusTracker(invalidationIdentities: [root])
    focus.invalidator = scheduler
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: surface,
      terminalInputReader: SetDFiniteInput(input), signalReader: ImmediateFinishSignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: focus, proposal: .init(width: 40, height: 8),
      viewBuilder: { _, _ in SetDControlForm(kind: kind, model: model) })
    loop.renderMode = .asyncNoCancel
    let result = try await loop.run()
    #expect(result.exitReason == .inputEnded)
    #expect(loop.lifecycleCoordinator.activeTaskCount == 0)
    #expect(model.mutations == 2)
    switch kind {
    case 1, 3...6: #expect(model.number == 2)
    case 2, 10: #expect(!model.flag)
    default:
      #expect(model.text == "seedA界")
      if kind == 8 {
        let frame = try #require(surface.frames.last)
        #expect(!frame.contains("seed"))
      }
    }
  }
}

final class SetDFiniteInput: TerminalInputReading {
  let stream: AsyncStream<InputEvent>
  init(_ events: [InputEvent]) {
    stream = AsyncStream { continuation in
      for event in events { continuation.yield(event) }
      continuation.finish()
    }
  }
  func inputEvents() -> AsyncStream<InputEvent> { stream }
}
