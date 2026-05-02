import Foundation
@_spi(Testing) import TerminalUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct AnimationRegressionTests {
  @Test(
    "AnimationsTab offset button renders intermediate frames while PhaseAnimator is visible")
  func animationsTabOffsetButtonRendersIntermediateFramesWhilePhaseAnimatorIsVisible()
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
      inputReader: AnimationRegressionAwaitedInputReader(steps: [
        .waitUntil(timeoutNanoseconds: 2_000_000_000) {
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
        .waitUntil(timeoutNanoseconds: 2_500_000_000) {
          guard let initialColumn else {
            return false
          }
          markerColumnsAfterToggle = Array(
            Self.slideMarkerColumns(in: host.surfaces)
              .dropFirst(framesBeforeToggle)
          )
          return markerColumnsAfterToggle.contains(initialColumn + 30)
        },
        .event(.key(KeyPress(.character("c"), modifiers: .ctrl))),
      ]),
      viewBuilder: { AnimationsTab() }
    )

    let startingColumn = try #require(initialColumn)
    let finalColumn = startingColumn + 30
    let renderedFinalFrame = markerColumnsAfterToggle.contains(finalColumn)
    let renderedIntermediateFrame = markerColumnsAfterToggle.contains { column in
      column > startingColumn && column < finalColumn
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(
      renderedFinalFrame,
      """
      Expected clicking the real AnimationsTab "right" button to move the \
      slide marker from column \(startingColumn) to \(finalColumn). Captured \
      marker columns after input: \(markerColumnsAfterToggle).
      """
    )
    #expect(
      renderedIntermediateFrame,
      """
      Expected the real AnimationsTab offset example to render at least one \
      intermediate slide-marker column after the button's withAnimation state \
      write. A direct jump, or no movement at all, means the gallery-visible \
      animation transaction was not committed through the runtime path. \
      Captured marker columns after input: \(markerColumnsAfterToggle).
      """
    )
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
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var env = EnvironmentValues()
    env.terminalAppearance = host.appearance
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: host,
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
    return try await runLoop.run()
  }
}

private enum AnimationRegressionAwaitedInputStep {
  case event(InputEvent, delayNanoseconds: UInt64 = 0)
  case waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    predicate: @MainActor () -> Bool
  )
}

private final class AnimationRegressionAwaitedInputReader: TerminalInputReading {
  private let steps: [AnimationRegressionAwaitedInputStep]
  private let pollNanoseconds: UInt64

  init(
    steps: [AnimationRegressionAwaitedInputStep],
    pollNanoseconds: UInt64 = 10_000_000
  ) {
    self.steps = steps
    self.pollNanoseconds = pollNanoseconds
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let steps = self.steps
      let pollNanoseconds = self.pollNanoseconds
      let task = Task { @MainActor in
        for step in steps {
          switch step {
          case .event(let event, let delayNanoseconds):
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

private final class AnimationRegressionEmptySignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class AnimationRegressionRecordingHost: TerminalHosting {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var surfaces: [RasterSurface] = []

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
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }
}
