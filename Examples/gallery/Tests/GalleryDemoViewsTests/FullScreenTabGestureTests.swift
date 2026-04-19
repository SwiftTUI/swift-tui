import Foundation
import TerminalUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct FullScreenTabGestureTests {
  @Test("dragging the fullscreen demo rectangle updates the rendered surface and commits position")
  func draggingRectangleUpdatesAndCommits() async throws {
    let terminalSize = Size(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("FullScreenTabGestureTest")])
    let view = FullScreenTab()

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let initial = DefaultRenderer().render(
      view,
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let shapeBounds = try #require(firstShapeBounds(in: initial.placedTree))
    let start = centerPoint(of: shapeBounds)
    let end = Point(x: start.x + 5, y: start.y + 2)

    let host = GestureRecordingHost(size: terminalSize)
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { view },
      eventSchedule: [
        .init(delayNanoseconds: 0, event: .mouse(.init(kind: .down(.primary), location: start))),
        .init(
          delayNanoseconds: 30_000_000,
          event: .mouse(.init(kind: .dragged(.primary), location: end))
        ),
        .init(
          delayNanoseconds: 30_000_000, event: .mouse(.init(kind: .up(.primary), location: end))),
      ]
    )

    #expect(result.exitReason == .inputEnded)
    #expect(host.surfaces.count >= 3)

    let firstFrame = try #require(host.surfaces.first)
    let lastFrame = try #require(host.surfaces.last)
    #expect(
      firstFrame != lastFrame,
      "dragging should change the fullscreen demo surface after release"
    )
  }
}

private struct ScheduledInputEvent {
  let delayNanoseconds: UInt64
  let event: InputEvent
}

private final class ScheduledTerminalInputReader: TerminalInputReading {
  let schedule: [ScheduledInputEvent]

  init(schedule: [ScheduledInputEvent]) {
    self.schedule = schedule
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let schedule = self.schedule
      let task = Task {
        for item in schedule {
          if item.delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: item.delayNanoseconds)
          }
          continuation.yield(item.event)
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class GestureRecordingHost: TerminalHosting {
  let surfaceSize: Size
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var surfaces: [RasterSurface] = []

  init(size: Size) {
    self.surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: Point) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    surfaces.append(surface)
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}

@MainActor
private func runHarness<V: View>(
  host: GestureRecordingHost,
  terminalSize: Size,
  rootIdentity: Identity,
  viewBuilder: @escaping () -> V,
  eventSchedule: [ScheduledInputEvent]
) async throws -> RunLoopResult<Int> {
  var env = EnvironmentValues()
  env.terminalSize = terminalSize
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    terminalHost: host,
    terminalInputReader: ScheduledTerminalInputReader(schedule: eventSchedule),
    signalReader: nil,
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    ),
    focusTracker: FocusTracker(
      invalidationIdentities: [rootIdentity]
    ),
    environmentValues: env,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in viewBuilder() }
  )
  return try await runLoop.run()
}

private func centerPoint(of rect: Rect) -> Point {
  Point(
    x: rect.origin.x + rect.size.width / 2,
    y: rect.origin.y + rect.size.height / 2
  )
}

private func firstShapeBounds(in node: PlacedNode) -> Rect? {
  if case .shape = node.drawPayload {
    return node.bounds
  }
  for child in node.children {
    if let match = firstShapeBounds(in: child) {
      return match
    }
  }
  return nil
}
