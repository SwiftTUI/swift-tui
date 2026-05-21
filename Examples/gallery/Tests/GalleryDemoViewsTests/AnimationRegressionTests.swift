import Foundation
@_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite(.serialized)
struct AnimationRegressionTests {
  @Test(
    "AnimationsTab offset button commits animated offset while PhaseAnimator is visible")
  func animationsTabOffsetButtonCommitsAnimatedOffsetWhilePhaseAnimatorIsVisible()
    async throws
  {
    let terminalSize = CellSize(width: 96, height: 60)
    let rootIdentity = Identity(components: [.named("AnimationsTabOffsetRegression")])
    let buttonLocation = try Self.centerOfText(
      "right",
      in: AnimationsTab(),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity
    )
    let host = AnimationRegressionRecordingHost(size: terminalSize)
    var initialColumn: Int?
    var framesBeforeToggle = 0
    var markerColumnsAfterToggle: [Int] = []

    let result = try await Self.runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      inputReader: AnimationRegressionAwaitedInputReader(
        frameSignal: host.frameSignal,
        steps: [
          .awaitCondition {
            let markerColumns = Self.slideMarkerColumns(in: host.surfaces)
            guard let latestColumn = markerColumns.last else {
              return false
            }
            initialColumn = latestColumn
            framesBeforeToggle = host.surfaces.count
            return true
          },
          .event(.mouse(.init(kind: .down(.primary), location: buttonLocation))),
          .event(.mouse(.init(kind: .up(.primary), location: buttonLocation))),
          .awaitCondition {
            guard let initialColumn else {
              return false
            }
            markerColumnsAfterToggle = Array(
              Self.slideMarkerColumns(in: host.surfaces)
                .dropFirst(framesBeforeToggle)
            )
            return markerColumnsAfterToggle.contains(initialColumn + 30)
          },
          .event(.key(KeyPress(.character("d"), modifiers: .ctrl))),
        ]),
      viewBuilder: { AnimationsTab() }
    )

    let startingColumn = try #require(initialColumn)
    let finalColumn = startingColumn + 30
    let renderedFinalFrame = markerColumnsAfterToggle.contains(finalColumn)

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(
      renderedFinalFrame,
      """
      Expected clicking the real AnimationsTab "right" button to move the \
      slide marker from column \(startingColumn) to \(finalColumn). Captured \
      marker columns after input: \(markerColumnsAfterToggle).
      """
    )
  }

  @Test(
    "diagnostics expose animation intent and cancellation state on the gallery path")
  func diagnosticsExposeAnimationIntentAndCancellationStateOnGalleryPath()
    async throws
  {
    let terminalSize = CellSize(width: 96, height: 60)
    let rootIdentity = Identity(components: [.named("AnimationsTabOffsetDiagnostics")])
    let buttonLocation = try Self.centerOfText(
      "right",
      in: AnimationsTab(),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity
    )
    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-animation-regression-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }
    let host = AnimationRegressionRecordingHost(size: terminalSize)
    var initialColumn: Int?
    var framesBeforeToggle = 0
    var markerColumnsAfterToggle: [Int] = []

    let result = try await Self.runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      inputReader: AnimationRegressionAwaitedInputReader(
        frameSignal: host.frameSignal,
        steps: [
          .awaitCondition {
            let markerColumns = Self.slideMarkerColumns(in: host.surfaces)
            guard let latestColumn = markerColumns.last else {
              return false
            }
            initialColumn = latestColumn
            framesBeforeToggle = host.surfaces.count
            return true
          },
          .event(.mouse(.init(kind: .down(.primary), location: buttonLocation))),
          .event(.mouse(.init(kind: .up(.primary), location: buttonLocation))),
          .awaitCondition {
            guard let initialColumn else {
              return false
            }
            markerColumnsAfterToggle = Array(
              Self.slideMarkerColumns(in: host.surfaces)
                .dropFirst(framesBeforeToggle)
            )
            return markerColumnsAfterToggle.contains(initialColumn + 30)
          },
          .event(.key(KeyPress(.character("d"), modifiers: .ctrl))),
        ]),
      diagnosticsPath: diagnosticsURL.path,
      viewBuilder: { AnimationsTab() }
    )

    let startingColumn = try #require(initialColumn)
    let finalColumn = startingColumn + 30
    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(
      markerColumnsAfterToggle.contains(finalColumn),
      "expected the diagnostic probe to click the real gallery offset button"
    )

    let rows = Self.diagnosticRows(
      try String(contentsOf: diagnosticsURL, encoding: .utf8)
    )
    let animationCommitIndex = rows.firstIndex { row in
      row["tail_job_state"] == "completed"
        && row["stale_frame_policy"] == "commit_ordered"
        && row["scheduled_animation_request"] == "animate"
        && (Int(row["animation_controller_active_animations"] ?? "") ?? 0) > 0
    }
    #expect(
      animationCommitIndex != nil,
      """
      Expected diagnostics to record the real gallery button click committing \
      under explicit animation intent. Rows: \(rows).
      """
    )

    let cancellationRows = rows.filter { row in
      row["tail_job_state"] == "cancelled_before_start"
    }
    #expect(
      cancellationRows.allSatisfy { row in
        row["tail_cancel_reason"] == "newer_render_intent"
          && row["stale_frame_policy"] == "cancel_pending_before_start"
          && row["scheduled_animation_request"] != nil
          && row["animation_controller_pending_work"] != nil
      },
      """
      Expected any gallery pre-start cancellation diagnostics to include the \
      cancellation reason, policy, animation request, and pending-work fields. \
      Rows: \(rows).
      """
    )

    let cancelledAnimationIndex = rows.firstIndex { row in
      row["tail_job_state"] == "cancelled_before_start"
        && row["tail_cancel_reason"] == "newer_render_intent"
        && row["scheduled_animation_request"] == "animate"
        && row["scheduled_animation_batch"] == "-"
    }
    if let cancelledAnimationIndex {
      let replayedAnimationCommit = rows.suffix(from: rows.index(after: cancelledAnimationIndex))
        .contains { row in
          row["tail_job_state"] == "completed"
            && row["stale_frame_policy"] == "commit_ordered"
            && row["scheduled_animation_request"] == "animate"
            && row["scheduled_animation_batch"] == "-"
        }
      #expect(
        replayedAnimationCommit,
        """
        Expected an animation-bearing cancelled frame to be followed by a \
        committed frame that still carries animation intent. A committed final \
        visual state under inherited animation means the one-shot transaction \
        was consumed before commit. Rows: \(rows).
        """
      )
    }
  }

  private static func centerOfText(
    _ target: String,
    in view: some View,
    terminalSize: CellSize,
    rootIdentity: Identity
  ) throws -> Point {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let artifacts = DefaultRenderer().render(
      AnyView(view),
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )
    let bounds = try #require(Self.boundsOfText(target, in: artifacts.placedTree))
    return Point(
      CellPoint(
        x: bounds.origin.x + bounds.size.width / 2,
        y: bounds.origin.y + bounds.size.height / 2
      )
    )
  }

  private static func boundsOfText(
    _ target: String,
    in node: PlacedNode
  ) -> CellRect? {
    if case .text(let content) = node.drawPayload, content == target {
      return node.bounds
    }
    for child in node.children {
      if let bounds = boundsOfText(target, in: child) {
        return bounds
      }
    }
    return nil
  }

  private static func slideMarkerColumns(
    in surfaces: [RasterSurface]
  ) -> [Int] {
    surfaces.compactMap { surface in
      surface.lines.compactMap { line in
        line.range(of: "slide me")?.lowerBound.utf16Offset(in: line)
      }
      .first
    }
  }

  private static func runHarness<V: View>(
    host: AnimationRegressionRecordingHost,
    terminalSize: CellSize,
    rootIdentity: Identity,
    inputReader: any TerminalInputReading,
    diagnosticsPath: String? = nil,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var env = EnvironmentValues()
    env.terminalAppearance = host.appearance
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: inputReader,
      signalReader: AnimationRegressionEmptySignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      environmentValues: env,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder() }
    )
    if let diagnosticsPath {
      let diagnosticsLogger = try #require(FrameDiagnosticsLogger(path: diagnosticsPath))
      runLoop.diagnosticsLogger = diagnosticsLogger
    }
    return try await runLoop.run()
  }

  private static func diagnosticRows(_ text: String) -> [[String: String]] {
    let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
    guard let headerLine = lines.first else {
      return []
    }
    let headers = headerLine.components(separatedBy: "\t")
    return lines.dropFirst().map { line in
      let fields = line.components(separatedBy: "\t")
      var row: [String: String] = [:]
      for (index, header) in headers.enumerated() where index < fields.count {
        row[header] = fields[index]
      }
      return row
    }
  }
}

private enum AnimationRegressionAwaitedInputStep {
  case event(InputEvent)
  /// Suspends the input script until `predicate` holds, re-evaluated only when
  /// the host presents a new frame (`frameSignal.notify()`) rather than on a
  /// clock — a starved run loop slows the test instead of timing it out.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class AnimationRegressionAwaitedInputReader: TerminalInputReading {
  private let steps: [AnimationRegressionAwaitedInputStep]
  private let frameSignal: MainActorConditionSignal

  init(
    frameSignal: MainActorConditionSignal,
    steps: [AnimationRegressionAwaitedInputStep]
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
          case .event(let event):
            continuation.yield(event)
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

private final class AnimationRegressionEmptySignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class AnimationRegressionRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var surfaces: [RasterSurface] = []

  /// Notified after every present, so an awaited input step can re-check its
  /// predicate the instant a frame lands instead of polling under a timeout.
  let frameSignal = MainActorConditionSignal()

  init(size: CellSize) {
    surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    surfaces.append(surface)
    // The run loop only ever presents on the MainActor; `assumeIsolated`
    // bridges this nonisolated witness to the MainActor-isolated signal.
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }
}
