import GIFEditorCore
import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
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

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("?"), modifiers: [])),
        .awaitCondition {
          terminal.frames.contains { $0.contains("Keyboard help") && $0.contains("⠋") }
            && terminal.frames.contains { frame in
              advancedGlyphs.contains { frame.contains($0) }
            }
        },
        .press(KeyPress(.escape, modifiers: [])),
        .awaitCondition {
          terminal.latestFrame?.contains("Keyboard help") == false
        },
        .press(KeyPress(.character("]"), modifiers: [])),
        .awaitCondition {
          terminal.frames.contains { $0.contains("B2") }
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
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

  @Test("help sheet spinner remains dismissible through the close button")
  func helpSheetSpinnerRemainsDismissibleThroughTheCloseButton() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.close-button"])
    let advancedGlyphs = Set(["⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("?"), modifiers: [])),
        .awaitCondition {
          terminal.frames.contains { $0.contains("Keyboard help") && $0.contains("⠋") }
            && terminal.frames.contains { frame in
              advancedGlyphs.contains { frame.contains($0) }
            }
        },
        .click(.init(x: 76, y: 2)),
        .awaitCondition {
          terminal.latestFrame?.contains("Keyboard help") == false
        },
        .press(KeyPress(.character("]"), modifiers: [])),
        .awaitCondition {
          terminal.frames.contains { $0.contains("B2") }
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
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
    #expect(terminal.latestFrame?.contains("Keyboard help") == false)
    #expect(terminal.frames.contains { $0.contains("B2") })
  }

  @Test("help sheet spinner does not block the configured exit key")
  func helpSheetSpinnerDoesNotBlockTheConfiguredExitKey() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.exit-key"])
    let exitKey = KeyPress(.character("q"), modifiers: .ctrl)
    let advancedGlyphs = Set(["⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("?"), modifiers: [])),
        .awaitCondition {
          terminal.frames.contains { $0.contains("Keyboard help") && $0.contains("⠋") }
            && terminal.frames.contains { frame in
              advancedGlyphs.contains { frame.contains($0) }
            }
        },
        .press(exitKey),
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      exitKeyBindings: ExitKeyBindings([exitKey]),
      viewBuilder: { _, _ in
        EditorView(document: GIFDocument.blank(size: .init(width: 16, height: 16)))
      }
    ).run()

    #expect(result.exitReason == .userExit(exitKey))
    #expect(terminal.frames.contains { $0.contains("Keyboard help") })
    #expect(
      terminal.frames.contains { frame in
        advancedGlyphs.contains { frame.contains($0) }
      })
  }

}

private final class GIFEditorPresentationRecordingTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  private(set) var frames: [String] = []

  var latestFrame: String? {
    frames.last
  }

  /// Notified after every appended frame, so an awaited input step can
  /// re-check its predicate the instant a frame lands instead of polling.
  let frameSignal = MainActorConditionSignal()

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
    notifyFrameObservers()
    return TerminalPresentationMetrics(
      bytesWritten: rendered.utf8.count,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
  }

  /// The run loop only ever presents on the MainActor; `assumeIsolated`
  /// bridges these nonisolated protocol witnesses to the MainActor-isolated
  /// signal.
  private func notifyFrameObservers() {
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
  }
}

private enum GIFEditorPresentationInputStep {
  case press(KeyPress)
  case click(CellPoint)
  /// Suspends the input script until `predicate` holds, re-evaluated only when
  /// the host appends a frame (`frameSignal.notify()`) rather than on a clock.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class GIFEditorPresentationInputReader: TerminalInputReading {
  private let steps: [GIFEditorPresentationInputStep]
  private let frameSignal: MainActorConditionSignal

  init(
    frameSignal: MainActorConditionSignal,
    steps: [GIFEditorPresentationInputStep]
  ) {
    self.frameSignal = frameSignal
    self.steps = steps
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let task = Task { @MainActor in
        for step in steps {
          switch step {
          case .press(let event):
            continuation.yield(.key(event))
          case .click(let cell):
            continuation.yield(
              .mouse(.init(kind: .down(.primary), location: .cellFallback(cell)))
            )
            continuation.yield(
              .mouse(.init(kind: .up(.primary), location: .cellFallback(cell)))
            )
          case .awaitCondition(let predicate):
            await frameSignal.wait(until: predicate)
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
