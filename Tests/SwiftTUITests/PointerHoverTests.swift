import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct PointerHoverTests {
  @Test("onPointerHover receives entered moved and exited phases")
  func hoverReceivesEnteredMovedExited() throws {
    let phases = HoverPhaseBox()
    let runLoop = makeHoverRunLoop {
      Text("hover")
        .onPointerHover { phase in
          phases.append(phase)
        }
    }

    try renderInitial(runLoop)

    _ = runLoop.handle(
      .input(
        .mouse(
          .init(
            kind: .moved,
            location: .subCell(
              location: Point(x: 1.2, y: 0.4),
              source: .nativePixels,
              metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)
            )
          )
        )
      )
    )
    _ = runLoop.handle(
      .input(
        .mouse(
          .init(
            kind: .moved,
            location: .subCell(
              location: Point(x: 2.4, y: 0.4),
              source: .webPixels,
              metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)
            )
          )
        )
      )
    )
    _ = runLoop.handle(.input(.mouse(.init(kind: .moved, location: Point(x: 10, y: 4)))))

    #expect(
      phases.values == [
        .entered(Point(x: 1.2, y: 0.4)),
        .moved(Point(x: 2.4, y: 0.4)),
        .exited,
      ]
    )
  }

  @Test("hover registration toggles terminal all-motion mode")
  func hoverRegistrationTogglesTerminalAllMotionMode() throws {
    let terminal = HoverTerminalHost(surfaceSizeProvider: { CellSize(width: 20, height: 5) })
    let runLoop = makeHoverRunLoop(terminal: terminal) {
      Text("hover")
        .onPointerHover { _ in }
    }

    try renderInitial(runLoop)
    #expect(terminal.pointerHoverEnabledChanges == [true])
  }

  @Test("hover does not steal click gesture dispatch")
  func hoverDoesNotStealClickGestureDispatch() throws {
    let tapCount = CounterBox()
    let hoverPhases = HoverPhaseBox()
    let runLoop = makeHoverRunLoop {
      Text("tap")
        .onPointerHover { phase in
          hoverPhases.append(phase)
        }
        .onTapGesture {
          tapCount.increment()
        }
    }

    try renderInitial(runLoop)

    _ = runLoop.handle(.input(.mouse(.init(kind: .moved, location: Point(x: 0, y: 0)))))
    _ = runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: Point(x: 0, y: 0)))))
    _ = runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: Point(x: 0, y: 0)))))

    #expect(!hoverPhases.values.isEmpty)
    #expect(tapCount.value == 1)
  }
}

@MainActor
private final class HoverPhaseBox {
  private(set) var values: [HoverPhase] = []

  func append(_ phase: HoverPhase) {
    values.append(phase)
  }
}

@MainActor
private final class CounterBox {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}

@MainActor
private func makeHoverRunLoop<V: View>(
  terminal: HoverTerminalHost? = nil,
  @ViewBuilder content: @escaping () -> V
) -> RunLoop<Int, V> {
  let terminalSize = CellSize(width: 20, height: 5)
  let terminal = terminal ?? HoverTerminalHost(surfaceSizeProvider: { terminalSize })
  let rootIdentity = testIdentity("PointerHoverRoot")
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = terminal.appearance
  environmentValues.terminalSize = terminalSize
  let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: terminal,
    terminalInputReader: HoverInputReader(),
    signalReader: HoverSignalReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
    focusTracker: focusTracker,
    environmentValues: environmentValues,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in content() }
  )
  focusTracker.invalidator = runLoop.scheduler
  return runLoop
}

@MainActor
private func renderInitial<State, V: View>(_ runLoop: RunLoop<State, V>) throws {
  runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  runLoop.renderer.enableSelectiveEvaluation()
}

private final class HoverTerminalHost: PresentationSurface {
  var surfaceSize: CellSize { surfaceSizeProvider() }
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }
  private(set) var pointerHoverEnabledChanges: [Bool] = []
  private let surfaceSizeProvider: () -> CellSize

  init(surfaceSizeProvider: @escaping () -> CellSize) {
    self.surfaceSizeProvider = surfaceSizeProvider
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  func setPointerHoverEnabled(_ enabled: Bool) throws {
    pointerHoverEnabledChanges.append(enabled)
  }

  @discardableResult
  func present(_: RasterSurface) throws -> TerminalPresentationMetrics {
    TerminalPresentationMetrics()
  }
}

private final class HoverInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class HoverSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
