import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

@MainActor
@Suite("GIF editor presentation runtime")
struct PresentationRuntimeTests {
  @Test("help sheet spinner advances and editor responds after dismissal")
  func helpSheetSpinnerAdvancesAndEditorRespondsAfterDismissal() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime"])
    let advancedGlyphs = Set(["⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])

    let inputReader = GIFEditorPresentationInputReader(steps: [
      .press(KeyPress(.character("?"), modifiers: [])),
      .waitUntil(timeoutNanoseconds: 3_000_000_000) {
        terminal.frames.contains { $0.contains("Keyboard help") && $0.contains("⠋") }
          && terminal.frames.contains { frame in
            advancedGlyphs.contains { frame.contains($0) }
          }
      },
      .press(KeyPress(.escape, modifiers: [])),
      .waitUntil(timeoutNanoseconds: 1_000_000_000) {
        terminal.latestFrame?.contains("Keyboard help") == false
      },
      .press(KeyPress(.character("]"), modifiers: [])),
      .waitUntil(timeoutNanoseconds: 1_000_000_000) {
        terminal.frames.contains { $0.contains("B2") }
      },
    ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminal,
      inputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(document: GIFDocument.blank(size: .init(width: 16, height: 16)))
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Keyboard help") })
    #expect(
      terminal.frames.contains { frame in
        advancedGlyphs.contains { frame.contains($0) }
      })
    #expect(terminal.frames.contains { $0.contains("B2") })
  }
}

private final class GIFEditorPresentationRecordingTerminalHost: TerminalHosting {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  private(set) var frames: [String] = []

  var latestFrame: String? {
    frames.last
  }

  init(
    surfaceSize: CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSize = surfaceSize
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    ).render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    return TerminalPresentationMetrics(
      bytesWritten: rendered.utf8.count,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
  }
}

private enum GIFEditorPresentationInputStep {
  case press(KeyPress, delayNanoseconds: UInt64 = 0)
  case waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    predicate: @MainActor () -> Bool
  )
}

private final class GIFEditorPresentationInputReader: InputReading {
  private let steps: [GIFEditorPresentationInputStep]
  private let pollNanoseconds: UInt64

  init(
    steps: [GIFEditorPresentationInputStep],
    pollNanoseconds: UInt64 = 10_000_000
  ) {
    self.steps = steps
    self.pollNanoseconds = pollNanoseconds
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      let steps = self.steps
      let pollNanoseconds = self.pollNanoseconds
      let task = Task { @MainActor in
        for step in steps {
          switch step {
          case .press(let event, let delayNanoseconds):
            if delayNanoseconds > 0 {
              try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            continuation.yield(event)
          case .waitUntil(let timeoutNanoseconds, let predicate):
            var elapsedNanoseconds: UInt64 = 0
            while !predicate() && elapsedNanoseconds < timeoutNanoseconds {
              try? await Task.sleep(nanoseconds: pollNanoseconds)
              elapsedNanoseconds += pollNanoseconds
            }
          }
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class GIFEditorPresentationEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
