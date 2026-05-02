import SwiftTUI
import Testing

@testable import GalleryDemoViews

// Smoke test for the Borders & Shapes demo tab.
//
// The tab is gallery demo code, not library code, so the bar is
// deliberately low: we just want to catch a future edit that causes
// the tab to stop compiling or stop producing cells. Rendering the
// full tab through `DefaultRenderer` and asserting a non-empty raster
// surface gives us that regression guard without coupling to any
// particular glyph layout.
@MainActor
@Suite
struct BordersAndShapesTabTests {
  @Test("BordersAndShapesTab resolves and rasterises to a non-empty surface")
  func rendersNonEmptySurface() {
    let terminalSize = CellSize(width: 80, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      BordersAndShapesTab(),
      context: .init(
        identity: Identity(components: [.named("BordersAndShapesTabSmoke")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    #expect(artifacts.rasterSurface.cells.count > 0)
    #expect(artifacts.rasterSurface.lines.contains { !$0.isEmpty })
    #expect(
      artifacts.rasterSurface.lines.joined(separator: "\n").contains("chasing light"),
      "expected the animated border card to be visible in the initial viewport"
    )
  }

  @Test(
    "BordersAndShapesTab keeps presenting frames after onAppear starts the chasing-light animation")
  func chasingLightSchedulesVisibleRuntimeFrames() async throws {
    let terminalSize = CellSize(width: 80, height: 28)
    let rootIdentity = Identity(components: [.named("BordersAndShapesRunLoop")])
    let quitGate = GalleryAsyncEventGate()
    let host = GalleryCountingTerminalHost(
      surfaceSize: terminalSize,
      presentObserver: { presentCount in
        guard presentCount >= 3 else {
          return
        }
        Task {
          await quitGate.open()
        }
      }
    )
    let timeoutTask = Task {
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      await quitGate.open()
    }
    defer {
      timeoutTask.cancel()
    }
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: host,
      terminalInputReader: GalleryGateInputReader(gate: quitGate),
      signalReader: nil,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = host.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        BordersAndShapesTab()
      }
    )

    let result = try await runLoop.run()

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(
      result.renderedFrames >= 3,
      "expected the real BordersAndShapesTab to keep scheduling animation ticks; renderedFrames=\(result.renderedFrames)"
    )
    #expect(
      host.presentCount >= 3,
      "expected the terminal host to receive at least three presents; presentCount=\(host.presentCount)"
    )
  }
}

private final class GalleryCountingTerminalHost: TerminalHosting {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private let presentObserver: @Sendable (Int) -> Void
  private(set) var presentCount = 0

  init(
    surfaceSize: CellSize,
    presentObserver: @escaping @Sendable (Int) -> Void = { _ in }
  ) {
    self.surfaceSize = surfaceSize
    self.presentObserver = presentObserver
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    presentCount += 1
    presentObserver(presentCount)
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_: String) throws {}
}

private actor GalleryAsyncEventGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen {
      return
    }

    await withCheckedContinuation { continuation in
      if isOpen {
        continuation.resume()
        return
      }
      waiters.append(continuation)
    }
  }

  func open() {
    guard !isOpen else {
      return
    }
    isOpen = true
    let continuations = waiters
    waiters.removeAll(keepingCapacity: false)

    for continuation in continuations {
      continuation.resume()
    }
  }
}

private final class GalleryGateInputReader: TerminalInputReading {
  let gate: GalleryAsyncEventGate

  init(gate: GalleryAsyncEventGate) {
    self.gate = gate
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let gate = gate
      let task = Task {
        await gate.wait()
        continuation.yield(.key(KeyPress(.character("c"), modifiers: .ctrl)))
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
