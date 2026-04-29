import Foundation
@_spi(Testing) import TerminalUI
import Testing

@testable import GalleryDemoViews

// End-to-end regression test for the gallery calculator: clicking the
// "7" button must flip the display from "0" to "7". This exercises the
// full mouseDown → mouseUp → action → @State mutation → re-render loop
// against the real `CalculatorTab` view, which puts its buttons inside
// a custom `CalculatorButton` wrapper.

@MainActor
@Suite
struct CalculatorTabClickTests {
  @Test("clicking the 7 button in the real CalculatorTab flips the display from 0 to 7")
  func clickingSevenFiresEnterDigit() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("CalcTabClickTest")])

    let view = CalculatorTab()

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let initial = DefaultRenderer().render(
      view,
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let sevenBounds = try #require(Self.boundsOfText("7", in: initial.placedTree))
    let clickCenter = centerPoint(of: sevenBounds)

    let host = RecordingHost(size: terminalSize)
    _ = try await Self.runHarness(
      host: host,
      terminalSize: terminalSize,
      events: [
        .mouse(.init(kind: .down(.primary), location: clickCenter)),
        .mouse(.init(kind: .up(.primary), location: clickCenter)),
      ],
      rootIdentity: rootIdentity,
      viewBuilder: { view }
    )

    let lastPresented = try #require(host.lastPresentedSurface)
    let initialSignature = Self.glyphSignature(in: initial.rasterSurface)
    let finalSignature = Self.glyphSignature(in: lastPresented)
    #expect(
      initialSignature != finalSignature,
      """
      CalculatorTab display figlet did not change after clicking '7'.
      initial: \(initialSignature)
      final:   \(finalSignature)
      """
    )
  }

  // MARK: - Helpers

  private static func boundsOfText(_ target: String, in node: PlacedNode) -> CellRect? {
    if case .text(let content) = node.drawPayload, content == target {
      return node.bounds
    }
    for child in node.children {
      if let match = boundsOfText(target, in: child) {
        return match
      }
    }
    return nil
  }

  private static func glyphSignature(in surface: RasterSurface) -> String {
    let glyphChars: Set<Character> = ["┏", "┓", "┗", "┛", "┃", "━"]
    var chars: [Character] = []
    for line in surface.lines {
      for ch in line where glyphChars.contains(ch) {
        chars.append(ch)
      }
    }
    return String(chars)
  }

  @MainActor
  private static func runHarness<V: View>(
    host: RecordingHost,
    terminalSize: CellSize,
    events: [InputEvent],
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: host,
      terminalInputReader: ScriptedInput(events: events),
      signalReader: EmptySignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: env,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder() }
    )
    return try await runLoop.run()
  }
}

private func centerPoint(of rect: CellRect) -> Point {
  Point(
    CellPoint(
      x: rect.origin.x + rect.size.width / 2,
      y: rect.origin.y + rect.size.height / 2
    )
  )
}

private final class ScriptedInput: TerminalInputReading {
  private let scriptedEvents: [InputEvent]
  init(events: [InputEvent]) { self.scriptedEvents = events }
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class EmptySignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class RecordingHost: TerminalHosting {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var lastPresentedSurface: RasterSurface?

  init(size: CellSize) { self.surfaceSize = size }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    lastPresentedSurface = surface
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}
