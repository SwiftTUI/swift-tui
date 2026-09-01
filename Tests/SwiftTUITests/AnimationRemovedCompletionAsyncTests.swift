import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// On the real async run loop, a removal transition's `.removed` completion
/// fires on the controller's own turns with no further input. Once the exit
/// overlay has faded out, every following deadline frame presents an
/// unchanged surface and is elided; an elided frame runs no placed pass, so
/// the purge (and the `.removed` barrier) lives at the head tick
/// (`AnimationController.applyInterpolations`). Before that move the loop
/// spun elided frames until the next outside input finally purged it.
@MainActor
@Suite(.serialized)
struct AnimationRemovedCompletionAsyncTests {
  @Test(arguments: [false, true])
  func removedCompletionFiresWithoutInput(hostedInOverlay: Bool) async throws {
    let size = CellSize(width: 40, height: 6)
    let host = RemovedCompletionHost(size: size)
    let rootIdentity = testIdentity("RemovedCompletionAsync")
    let reader = RemovedCompletionInputReader(host: host)
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: reader,
      signalReader: RemovedCompletionSignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in RemovedCompletionFixture(hostedInOverlay: hostedInOverlay) }
    )
    let result = try await runLoop.run()
    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    let firedAt = host.frames.firstIndex { $0.contains("removed=1") }
    #expect(
      firedAt.map { $0 < reader.frameCountAtExit } == true,
      """
      .removed fired at frame \(firedAt.map(String.init) ?? "never"); the exit chord went out \
      after frame \(reader.frameCountAtExit); last frame:
      \(host.frames.last ?? "")
      """
    )
    #expect(host.frames.last?.contains("gone") == false)
  }
}

@MainActor
private struct RemovedCompletionFixture: View {
  let hostedInOverlay: Bool
  @State private var shown = true
  @State private var removed = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("hide") {
        withAnimation(.linear(duration: .milliseconds(120)), completionCriteria: .removed) {
          shown = false
        } completion: {
          removed += 1
        }
      }
      if hostedInOverlay {
        Text("host").overlay(alignment: .leading) {
          if shown {
            Text("gone").transition(.opacity)
          }
        }
      } else if shown {
        Text("gone").transition(.opacity)
      }
      Text("removed=\(removed)")
    }
  }
}

/// Clicks "hide" once it is on screen, then sends nothing until a presented
/// frame shows the `.removed` write (or the bound lapses), and only then the
/// exit chord. Every wait is frame-signal driven; the Support deadline event
/// is the failure bound, never the pacing.
@MainActor
private final class RemovedCompletionInputReader: TerminalInputReading {
  private let host: RemovedCompletionHost
  private(set) var frameCountAtExit = Int.max

  init(host: RemovedCompletionHost) {
    self.host = host
  }

  nonisolated func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let task = Task { @MainActor in
        let host = self.host
        await RemovedCompletionFrameWaiter(host: host) {
          host.frames.last?.contains("hide") == true
        }.wait(within: AsyncTestTimeouts.scaled(.seconds(10)))
        guard let point = host.centerOfText("hide") else {
          continuation.finish()
          return
        }
        continuation.yield(.mouse(.init(kind: .down(.primary), location: point)))
        continuation.yield(.mouse(.init(kind: .up(.primary), location: point)))
        await RemovedCompletionFrameWaiter(host: host) {
          host.frames.last?.contains("removed=1") == true
        }.wait(within: AsyncTestTimeouts.scaled(.seconds(10)))
        self.frameCountAtExit = host.frames.count
        continuation.yield(.key(KeyPress(.character("c"), modifiers: .ctrl)))
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// Non-generic, main-actor-isolated waiter (so implicitly `Sendable`) handed
/// to a task group: re-checks its predicate whenever the host presents a
/// frame, bounded by the Support deadline event.
@MainActor
private final class RemovedCompletionFrameWaiter {
  private let host: RemovedCompletionHost
  private let predicate: @MainActor () -> Bool

  init(host: RemovedCompletionHost, predicate: @escaping @MainActor () -> Bool) {
    self.host = host
    self.predicate = predicate
  }

  func wait(within limit: Duration) async {
    let deadline = AsyncEvent.firing(after: limit)
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.awaitPredicate() }
      group.addTask { await deadline.wait() }
      await group.next()
      group.cancelAll()
    }
  }

  private func awaitPredicate() async {
    let predicate = self.predicate
    await host.frameSignal.wait(until: { predicate() })
  }
}

private final class RemovedCompletionSignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

@MainActor
private final class RemovedCompletionHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let frameSignal = MainActorConditionSignal()
  private(set) var frames: [String] = []

  init(size: CellSize) {
    surfaceSize = size
  }

  nonisolated func enableRawMode() throws {}
  nonisolated func disableRawMode() throws {}
  nonisolated func write(_: String) throws {}
  nonisolated func clearScreen() throws {}
  nonisolated func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  nonisolated func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
    // Scalar-level strip: "\r\n" is one Character, so a Character-level
    // filter would keep CRLF pairs and break the row/column arithmetic in
    // `centerOfText` for any target below the first row (this fixture's
    // "hide" sits on row 0, which masked the trap).
    let text = String(String.UnicodeScalarView(rendered.unicodeScalars.filter { $0 != "\r" }))
    // The run loop presents on the MainActor; `assumeIsolated` bridges this
    // nonisolated witness to the isolated frame list and signal.
    MainActor.assumeIsolated {
      frames.append(text)
      frameSignal.notify()
    }
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func centerOfText(_ target: String) -> Point? {
    guard let frame = frames.last else { return nil }
    let lines = frame.split(separator: "\n", omittingEmptySubsequences: false)
    for (row, line) in lines.enumerated() {
      guard let start = line.firstRange(of: target) else { continue }
      let column = line.distance(from: line.startIndex, to: start.lowerBound)
      return Point(x: Double(column + target.count / 2), y: Double(row))
    }
    return nil
  }
}
