import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// On the real async run loop, a `@State` write made by an early
/// `.logicallyComplete` closure (`Animation.logicallyComplete(after:)`) must
/// not disturb the spring it completes for — even when the loop is running
/// slower than the animation cadence.
///
/// Reduced from the gallery's section 19 (plan 2026-08-25-003 E3, org
/// tracker T5): its frame strip against 0.9.12 shows the bar crawling
/// 10 → 35 with no overshoot, then jumping to its end width on the same
/// frame that renders `logical=1`, with `.removed` following one frame
/// later — a second of remaining bounce swallowed by the write.
///
/// The trigger is pacing, not the surrounding tree: deadline-triggered
/// frames deliberately animate to their *scheduled* instant, so on a loop
/// whose per-frame cost exceeds the cadence the armed deadline chain lags
/// the wall clock. A non-deadline wake (the closure's state write) then
/// derived its frame instant from the wall clock and advanced every
/// in-flight animation by the whole accumulated lag at once. The harness
/// spends deliberate main-actor time on every presented frame (as the
/// gallery's frame-strip predicates do) to hold the loop below cadence;
/// `deriveFrameInstant` now clamps wake frames to the armed chain.
@MainActor
@Suite(.serialized)
struct AnimationLogicalCompletionAsyncTests {
  @Test func earlyLogicalWriteKeepsSpringInFlightOnAsyncLoop() async throws {
    let size = CellSize(width: 60, height: 12)
    let host = LogicalCompletionHost(size: size)
    let rootIdentity = testIdentity("LogicalCompletionAsync")
    let reader = LogicalCompletionInputReader(host: host)
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: reader,
      signalReader: LogicalCompletionSignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: size.width, height: size.height),
      // The stateful fixture nests under a static shell so its writes are
      // not root invalidations, matching where the gallery tab's state sits.
      viewBuilder: { _, _ in
        VStack(alignment: .leading, spacing: 0) {
          Text("shell")
          LogicalCompletionAsyncFixture()
        }
      }
    )
    let result = try await runLoop.run()
    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))

    // The bar is a 40-glyph Text wrapped by its animated `maxWidth`, so the
    // drawn width on a frame is the longest run of bar glyphs on any line.
    let widths = host.frames.map(Self.barWidth(in:))
    let logicalFrame = try #require(
      host.frames.firstIndex { $0.contains("logical=1") },
      ".logicallyComplete never fired; last frame:\n\(host.frames.last ?? "")"
    )
    let removedFrame = try #require(
      host.frames.firstIndex { $0.contains("removed=1") },
      ".removed never fired; last frame:\n\(host.frames.last ?? "")"
    )
    #expect(removedFrame > logicalFrame, ".removed fired before .logicallyComplete")

    // The logical barrier sits at 500 ms of a 1.5 s bounce-0.4 spring: the
    // frame that renders the closure's write must still show the bar
    // mid-flight. In the defect the write snaps the spring, so the first
    // `logical=1` frame already draws the end width.
    #expect(
      widths[logicalFrame] < 40,
      """
      the early logical completion's state write snapped the spring: the frame \
      rendering `logical=1` already draws the end width. widths=\(widths) \
      logicalFrame=\(logicalFrame)
      """
    )
    // And the spring keeps interpolating after the write lands: at least one
    // later frame still draws a mid-flight width before the bar pins at 40.
    #expect(
      widths[(logicalFrame + 1)...].contains { $0 < 40 },
      """
      no frame after the logical write still showed the spring mid-flight — \
      the write cut the remaining second of the curve. widths=\(widths) \
      logicalFrame=\(logicalFrame)
      """
    )
  }

  /// The widest run of `█` on any single line of `frame`.
  private static func barWidth(in frame: String) -> Int {
    frame.split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in
        var best = 0
        var current = 0
        for character in line {
          if character == "█" {
            current += 1
            best = max(best, current)
          } else {
            current = 0
          }
        }
        return best
      }
      .max() ?? 0
  }
}

@MainActor
private struct LogicalCompletionAsyncFixture: View {
  @State private var wide = false
  @State private var logical = 0
  @State private var removed = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("go") {
        var transaction = Transaction(
          animation: .spring(duration: .milliseconds(1_500), bounce: 0.4)
            .logicallyComplete(after: .milliseconds(500))
        )
        transaction.addAnimationCompletion(criteria: .logicallyComplete) { logical += 1 }
        transaction.addAnimationCompletion(criteria: .removed) { removed += 1 }
        withTransaction(transaction) { wide.toggle() }
      }
      Text(String(repeating: "█", count: 40))
        .foregroundStyle(wide ? Color.cyan : Color.yellow)
        .frame(maxWidth: .finite(wide ? 40 : 10), alignment: .leading)
      Text("logical=\(logical) removed=\(removed) wide=\(wide)")
    }
  }
}

/// Clicks "go" once it is on screen, waits for the presented frames to show
/// the logical and then the removed writes, and only then sends the exit
/// chord. Every wait is frame-signal driven; the Support deadline event is
/// the failure bound, never the pacing.
@MainActor
private final class LogicalCompletionInputReader: TerminalInputReading {
  private let host: LogicalCompletionHost

  init(host: LogicalCompletionHost) {
    self.host = host
  }

  nonisolated func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let task = Task { @MainActor in
        let host = self.host
        await LogicalCompletionFrameWaiter(host: host) {
          host.frames.last?.contains("go") == true
        }.wait(within: AsyncTestTimeouts.scaled(.seconds(10)))
        guard let point = host.centerOfText("go") else {
          continuation.finish()
          return
        }
        continuation.yield(.mouse(.init(kind: .down(.primary), location: point)))
        continuation.yield(.mouse(.init(kind: .up(.primary), location: point)))
        await LogicalCompletionFrameWaiter(host: host) {
          host.frames.last?.contains("logical=1") == true
        }.wait(within: AsyncTestTimeouts.scaled(.seconds(15)))
        await LogicalCompletionFrameWaiter(host: host) {
          host.frames.last?.contains("removed=1") == true
        }.wait(within: AsyncTestTimeouts.scaled(.seconds(15)))
        continuation.yield(.key(KeyPress(.character("c"), modifiers: .ctrl)))
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// Non-generic, main-actor-isolated waiter handed to a task group: re-checks
/// its predicate whenever the host presents a frame, bounded by the Support
/// deadline event.
///
/// Every predicate check deliberately costs main-actor time BETWEEN loop
/// turns (after the next deadline was armed), the way the gallery harness's
/// per-frame frame-strip predicates do: that is what holds the loop below
/// the 30 fps animation cadence so the armed deadline chain lags the wall
/// clock — the precondition the regression needs.
@MainActor
private final class LogicalCompletionFrameWaiter {
  private let host: LogicalCompletionHost
  private let predicate: @MainActor () -> Bool

  init(host: LogicalCompletionHost, predicate: @escaping @MainActor () -> Bool) {
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
    await host.frameSignal.wait(until: {
      MainActorTestLatency.inject(seconds: 0.06)
      return predicate()
    })
  }
}

private final class LogicalCompletionSignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

@MainActor
private final class LogicalCompletionHost: PresentationSurface {
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
    // Strip carriage returns at the *scalar* level: "\r\n" is one Character
    // (grapheme cluster), so a Character-level filter keeps CRLF pairs
    // intact, `split(separator: "\n")` never splits, and every row/column
    // computed from the frame is wrong for any target below row 0.
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
