import Foundation
import SwiftTUICore
import SwiftTUITerminal
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUIRuntime

@Suite("TerminalView render diff", .serialized)
struct RenderDiffTests {
  @MainActor
  @Test("running cat over a large file stays within the byte budget")
  func catLargeFileDoesNotBlowByteBudget() async throws {
    let fixtureURL = try makeLargeTextFixture(byteCount: 1_048_576)
    defer {
      try? FileManager.default.removeItem(at: fixtureURL.deletingLastPathComponent())
    }

    let terminalSize = CellSize(width: 80, height: 24)
    let inputReader = ManualTerminalInputReader()
    let host = ByteCountingTerminalHost(surfaceSize: terminalSize)
    let session = TerminalProcessSession(
      command: "/bin/cat",
      arguments: [fixtureURL.path],
      initialSize: terminalSize
    )
    let rootIdentity = Identity(components: [.named("TerminalViewRenderDiffCat")])
    let runLoop = terminalRunLoop(
      rootIdentity: rootIdentity,
      host: host,
      inputReader: inputReader,
      session: session,
      terminalSize: terminalSize
    )

    let result = try await valueWithTimeout(timeoutNanoseconds: 10_000_000_000) {
      try await runLoop.run()
    }

    #expect(result.exitReason == RunLoopExitReason.inputEnded)
    #expect(host.presentationMetrics.count > 1)
    #expect(host.presentationMetrics.contains { $0.strategy == .incremental })
    #expect(host.bytesEmittedToTerminal < 200_000)
  }

  @MainActor
  @Test("50ms presentation latency preserves incremental TerminalView commit shape")
  func latencyInjectedPresentationPreservesIncrementalCommitShape() async throws {
    let fixtureURL = try makeLargeTextFixture(byteCount: 64 * 1024)
    defer {
      try? FileManager.default.removeItem(at: fixtureURL.deletingLastPathComponent())
    }

    let terminalSize = CellSize(width: 80, height: 24)
    let inputReader = ManualTerminalInputReader()
    let host = ByteCountingTerminalHost(
      surfaceSize: terminalSize,
      artificialPresentationDelay: 0.050
    )
    let session = TerminalProcessSession(
      command: "/bin/cat",
      arguments: [fixtureURL.path],
      initialSize: terminalSize
    )
    let rootIdentity = Identity(components: [.named("TerminalViewRenderDiffLatency")])
    let runLoop = terminalRunLoop(
      rootIdentity: rootIdentity,
      host: host,
      inputReader: inputReader,
      session: session,
      terminalSize: terminalSize
    )

    let result = try await valueWithTimeout(timeoutNanoseconds: 10_000_000_000) {
      try await runLoop.run()
    }

    #expect(result.exitReason == RunLoopExitReason.inputEnded)
    #expect(host.presentationMetrics.count > 1)
    let incrementalMetrics = host.presentationMetrics.filter { $0.strategy == .incremental }
    #expect(!incrementalMetrics.isEmpty)
    #expect(incrementalMetrics.allSatisfy { $0.linesTouched <= terminalSize.height })
    #expect(host.bytesEmittedToTerminal < 80_000)
  }

  @MainActor
  private func terminalRunLoop(
    rootIdentity: Identity,
    host: ByteCountingTerminalHost,
    inputReader: ManualTerminalInputReader,
    session: TerminalProcessSession,
    terminalSize: CellSize
  ) -> SwiftTUIRuntime.RunLoop<Int, TerminalView<TerminalProcessSession>> {
    SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: inputReader,
      signalReader: EmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: ProposedSize(width: terminalSize.width, height: terminalSize.height),
      exitKeyBindings: .none,
      viewBuilder: { _, _ in
        TerminalView(
          session: session,
          onExit: { _ in
            inputReader.finish()
          }
        )
      }
    )
  }
}

private final class ByteCountingTerminalHost: PresentationSurface {
  var surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance = .fallback
  private(set) var presentationMetrics: [TerminalPresentationMetrics] = []
  private(set) var outOfBandBytes = 0
  private var previousSurface: RasterSurface?
  private let artificialPresentationDelay: TimeInterval

  init(
    surfaceSize: CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    artificialPresentationDelay: TimeInterval = 0
  ) {
    self.surfaceSize = surfaceSize
    self.capabilityProfile = capabilityProfile
    self.artificialPresentationDelay = artificialPresentationDelay
  }

  var bytesEmittedToTerminal: Int {
    outOfBandBytes + presentationMetrics.map(\.bytesWritten).reduce(0, +)
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    if artificialPresentationDelay > 0 {
      Thread.sleep(forTimeInterval: artificialPresentationDelay)
    }

    let plan = TerminalPresentationPlanner(
      capabilityProfile: capabilityProfile
    ).plan(
      previousSurface: previousSurface,
      currentSurface: surface
    )
    let metrics = metrics(for: plan, surface: surface)
    presentationMetrics.append(metrics)
    previousSurface = surface
    return metrics
  }

  func write(_ output: String) throws {
    outOfBandBytes += output.utf8.count
  }

  private func metrics(
    for plan: TerminalPresentationPlan,
    surface: RasterSurface
  ) -> TerminalPresentationMetrics {
    let bytesWritten =
      switch plan.strategy {
      case .fullRepaint:
        TerminalPresentationMetrics.fullRepaint(
          for: surface,
          capabilityProfile: capabilityProfile
        ).bytesWritten
      case .incremental:
        plan.rowBatches.reduce(0) { partial, rowBatch in
          partial
            + cursorSequence(row: rowBatch.row, column: rowBatch.anchorColumn).utf8.count
            + rowBatch.renderedBatch.utf8.count
        }
      }

    return TerminalPresentationMetrics(
      bytesWritten: bytesWritten,
      linesTouched: plan.linesTouched,
      cellsChanged: plan.cellsChanged,
      strategy: plan.strategy == .fullRepaint ? .fullRepaint : .incremental
    )
  }

  private func cursorSequence(row: Int, column: Int) -> String {
    "\u{001B}[\(max(1, row + 1));\(max(1, column + 1))H"
  }
}

private final class ManualTerminalInputReader: TerminalInputReading, Sendable {
  private struct State: Sendable {
    var continuation: AsyncStream<InputEvent>.Continuation?
    var finished = false
  }

  private let state = Mutex(State())

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let shouldFinish = state.withLock { state in
        if state.finished {
          return true
        }
        state.continuation = continuation
        return false
      }

      if shouldFinish {
        continuation.finish()
      }
    }
  }

  func finish() {
    let continuation = state.withLock { state in
      state.finished = true
      let continuation = state.continuation
      state.continuation = nil
      return continuation
    }
    continuation?.finish()
  }
}

private final class EmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private func makeLargeTextFixture(byteCount: Int) throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "swift-tui-render-diff-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(
    at: directory,
    withIntermediateDirectories: true
  )
  let url = directory.appendingPathComponent("large.txt")
  let line = String(repeating: "x", count: 79) + "\n"
  let repetitions = max(1, byteCount / line.utf8.count + 1)
  let contents = String(repeating: line, count: repetitions)
  try contents.write(to: url, atomically: true, encoding: .utf8)
  return url
}
