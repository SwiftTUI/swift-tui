import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct ScrollCrashReproductionTests {

  @Test("ScrollView with many children does not crash on click")
  func scrollViewWithManyChildrenClick() async throws {
    let terminalSize = Size(width: 40, height: 20)
    let rootIdentity = testIdentity("ScrollCrashRepro")

    let result = try await runCrashReproHarness(
      events: [
        .mouse(.init(kind: .down(.primary), location: .init(x: 5, y: 5))),
        .mouse(.init(kind: .up(.primary), location: .init(x: 5, y: 5))),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize
    ) {
      ScrollView {
        VStack {
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
        }
      }
    }

    _ = result
  }

  @Test("ScrollView with many children does not crash on scroll")
  func scrollViewWithManyChildrenScroll() async throws {
    let terminalSize = Size(width: 40, height: 20)
    let rootIdentity = testIdentity("ScrollCrashReproScroll")

    let result = try await runCrashReproHarness(
      events: [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 3), location: .init(x: 5, y: 5))),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize
    ) {
      ScrollView {
        VStack {
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
          Text("one")
          Text("two")
          Text("three")
          Text("four")
          Text("five")
        }
      }
    }

    _ = result
  }
}

// MARK: - Test Infrastructure

private final class CrashReproScriptedInputReader: TerminalInputReading {
  private let scriptedEvents: [InputEvent]

  init(events: [InputEvent]) {
    scriptedEvents = events
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class CrashReproEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class CrashReproTerminalHost: TerminalHosting {
  let surfaceSize: Size
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance

  init(
    surfaceSize: Size,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSize = surfaceSize
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_ output: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: Point) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: 0,
      cellsChanged: 0,
      strategy: .fullRepaint
    )
  }
}

@MainActor
private func runCrashReproHarness<V: View>(
  events: [InputEvent],
  rootIdentity: Identity,
  terminalSize: Size,
  viewBuilder: @escaping () -> V
) async throws -> RunLoopResult<Int> {
  let terminal = CrashReproTerminalHost(surfaceSize: terminalSize)
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = terminal.appearance
  environmentValues.terminalSize = terminalSize

  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    terminalHost: terminal,
    terminalInputReader: CrashReproScriptedInputReader(events: events),
    signalReader: CrashReproEmptySignalReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    ),
    focusTracker: FocusTracker(
      invalidationIdentities: [rootIdentity]
    ),
    environmentValues: environmentValues,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in
      viewBuilder()
    }
  )

  return try await runLoop.run()
}
