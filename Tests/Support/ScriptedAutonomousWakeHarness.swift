package import SwiftTUICore
package import SwiftTUIRuntime

// Shared, poll-free harness for driving a real `RunLoop` from a test without
// re-declaring private doubles in every suite: a recording presentation surface
// that pulses a `MainActorConditionSignal` on each frame, and a keep-open
// scripted input reader (both the keyboard `InputReading` and terminal
// `TerminalInputReading` paths) that can stay open across an autonomous
// `.task`/state-write wake, then quit deterministically.
//
// `package`-scoped (reusable by every test target in this package, the
// proposal's stated goal). The `package import`s keep the runtime surface out of
// this support module's *public* API while still letting the harness conform to
// the public reader/surface protocols.

/// A scripted step for ``ScriptedAutonomousWakeInputReader``.
package enum ScriptedWakeStep: Sendable {
  /// A keyboard event (also valid on the terminal path, wrapped as `.key`).
  case press(KeyPress)
  /// A terminal event (key/mouse/paste); on the keyboard path only `.key` maps.
  case event(InputEvent)
  /// Keep the stream **open** until the predicate holds — used to await an
  /// autonomous frame so the loop does not exit `.inputEnded` before it lands.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

/// Records every presented frame as text and pulses ``frameSignal`` so a
/// keep-open reader can await an autonomous frame poll-free.
package final class RecordingPresentationSurface: PresentationSurface {
  package let surfaceSize: CellSize
  package let capabilityProfile: TerminalCapabilityProfile
  package let appearance: TerminalAppearance
  package private(set) var frames: [String] = []

  package let frameSignal = MainActorConditionSignal()

  package init(
    surfaceSize: CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSize = surfaceSize
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  package func enableRawMode() throws {}
  package func disableRawMode() throws {}
  package func clearScreen() throws {}
  package func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  package func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    ).render(surface)
    frames.append(normalizedNewlines(rendered))
    notifyFrameObservers()
    return TerminalPresentationMetrics.fullRepaint(
      for: surface,
      capabilityProfile: capabilityProfile
    )
  }

  package func write(_ output: String) throws {
    frames.append(normalizedNewlines(output))
    notifyFrameObservers()
  }

  private func notifyFrameObservers() {
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
  }
}

/// A `SignalReading` double that produces no out-of-band signals.
package final class ImmediateFinishSignalReader: SignalReading {
  package init() {}

  package func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}

/// A dual `InputReading` + `TerminalInputReading` double that walks scripted
/// steps, **staying open** across an autonomous wake via a direct
/// `MainActorConditionSignal` (no per-test sleep), then quits with `quitKey`
/// (Ctrl+D → `.userExit`). `onTermination` cancels the driver task.
package final class ScriptedAutonomousWakeInputReader:
  InputReading, TerminalInputReading
{
  private let steps: [ScriptedWakeStep]
  private let frameSignal: MainActorConditionSignal
  private let quitKey: KeyPress

  package init(
    frameSignal: MainActorConditionSignal,
    steps: [ScriptedWakeStep],
    quitKey: KeyPress = KeyPress(.character("d"), modifiers: .ctrl)
  ) {
    self.frameSignal = frameSignal
    self.steps = steps
    self.quitKey = quitKey
  }

  /// Keyboard path. Never finishes in the same step as a scripted event, or the
  /// loop would exit `.inputEnded` before the awaited wake lands.
  package func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let quitKey = self.quitKey
      let driver = Task { @MainActor in
        for step in steps {
          switch step {
          case .press(let keyPress):
            continuation.yield(keyPress)
          case .event(.key(let keyPress)):
            continuation.yield(keyPress)
          case .event:
            break  // non-key terminal events have no keyboard-path representation
          case .awaitCondition(let predicate):
            await frameSignal.wait(until: predicate)
          }
        }
        continuation.yield(quitKey)
        continuation.finish()
      }
      continuation.onTermination = { _ in driver.cancel() }
    }
  }

  /// Terminal path.
  package func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let quitKey = self.quitKey
      let driver = Task { @MainActor in
        for step in steps {
          switch step {
          case .press(let keyPress):
            continuation.yield(.key(keyPress))
          case .event(let event):
            continuation.yield(event)
          case .awaitCondition(let predicate):
            await frameSignal.wait(until: predicate)
          }
        }
        continuation.yield(.key(quitKey))
        continuation.finish()
      }
      continuation.onTermination = { _ in driver.cancel() }
    }
  }
}

/// Foundation-free CRLF → LF (the renderer only emits `\r\n`, never a lone `\r`).
private func normalizedNewlines(_ string: String) -> String {
  String(string.filter { $0 != "\r" })
}
