import Foundation
import TerminalUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct FullScreenTabGestureTests {
  @Test("fullscreen toy playfield reserves six rows at the bottom")
  func playfieldBoundsReserveBottomInset() {
    let terminalSize = Size(width: 40, height: 12)

    let playfield = FullScreenToyPhysics.playfieldBounds(from: terminalSize)

    #expect(playfield.width == terminalSize.width)
    #expect(playfield.height == terminalSize.height - FullScreenToyPhysics.playfieldHeightInset)
  }

  @Test("fullscreen toy starts at bottom center with its initial launch velocity")
  func spawnStateStartsAtBottomCenter() {
    let terminalSize = Size(width: 40, height: 12)
    let playfield = FullScreenToyPhysics.playfieldBounds(from: terminalSize)
    let floor = FullScreenToyPhysics.maximumOrigin(in: playfield)

    let state = FullScreenToyPhysics.spawnState(in: playfield)

    #expect(state.position.x == floor.x / 2)
    #expect(state.position.y == floor.y)
    #expect(state.velocity.x == FullScreenToyPhysics.initialLaunchX)
    #expect(state.velocity.y == FullScreenToyPhysics.initialLaunchY)
  }

  @Test("fullscreen toy physics applies gravity and bounces off the floor")
  func physicsBouncesOffFloor() {
    let terminalSize = Size(width: 40, height: 12)
    let floor = FullScreenToyPhysics.maximumOrigin(in: terminalSize)
    var state = FullScreenToyPhysics.State(
      position: .init(x: 10 * FullScreenToyPhysics.fixedScale, y: floor.y - 1),
      velocity: .init(x: 0, y: 10)
    )

    FullScreenToyPhysics.step(&state, in: terminalSize)

    #expect(state.position.y == floor.y)
    #expect(state.velocity.y < 0)
  }

  @Test("fullscreen toy physics reflects from the right wall")
  func physicsReflectsOffRightWall() {
    let terminalSize = Size(width: 40, height: 12)
    let wall = FullScreenToyPhysics.maximumOrigin(in: terminalSize)
    var state = FullScreenToyPhysics.State(
      position: .init(x: wall.x - 2, y: 4 * FullScreenToyPhysics.fixedScale),
      velocity: .init(x: 6, y: 0)
    )

    FullScreenToyPhysics.step(&state, in: terminalSize)

    #expect(state.position.x == wall.x)
    #expect(state.velocity.x < 0)
  }

  @Test("fullscreen toy release converts gesture velocity into physics velocity")
  func releaseConvertsGestureVelocity() {
    let terminalSize = Size(width: 40, height: 12)
    var state = FullScreenToyPhysics.State()

    FullScreenToyPhysics.applyRelease(
      to: &state,
      translation: .zero,
      velocity: Size(width: 100, height: -50),
      in: terminalSize
    )

    #expect(state.velocity == .init(x: 64, y: -32))
  }

  @Test("fullscreen demo keeps presenting frames while gravity runs")
  func gravityLoopSchedulesRuntimeFrames() async throws {
    let terminalSize = Size(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("FullScreenTabGravityLoop")])
    let host = GestureRecordingHost(size: terminalSize)
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { FullScreenTab() },
      eventSchedule: [
        .init(
          delayNanoseconds: 700_000_000,
          event: .key(.character("q"))
        )
      ]
    )

    #expect(result.exitReason == .quitKey)
    #expect(result.renderedFrames >= 2)

    let uniqueSurfaces = deduplicated(host.surfaces)
    #expect(uniqueSurfaces.count >= 2)
    #expect(uniqueSurfaces.first != uniqueSurfaces.last)
  }

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

  @Test("fullscreen demo rectangle remains draggable after its offset changes")
  func draggingRectangleTwiceTracksItsMovedPosition() async throws {
    let terminalSize = Size(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("FullScreenTabGestureTwiceTest")])
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
    let firstEnd = Point(x: start.x + 5, y: start.y + 2)
    let secondEnd = Point(x: firstEnd.x + 4, y: firstEnd.y + 1)

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
          event: .mouse(.init(kind: .dragged(.primary), location: firstEnd))
        ),
        .init(
          delayNanoseconds: 30_000_000,
          event: .mouse(.init(kind: .up(.primary), location: firstEnd))
        ),
        .init(
          delayNanoseconds: 30_000_000,
          event: .mouse(.init(kind: .down(.primary), location: firstEnd))
        ),
        .init(
          delayNanoseconds: 30_000_000,
          event: .mouse(.init(kind: .dragged(.primary), location: secondEnd))
        ),
        .init(
          delayNanoseconds: 30_000_000,
          event: .mouse(.init(kind: .up(.primary), location: secondEnd))
        ),
      ]
    )

    #expect(result.exitReason == .inputEnded)

    let uniqueSurfaces = deduplicated(host.surfaces)
    #expect(uniqueSurfaces.count >= 3)
    #expect(uniqueSurfaces.first != uniqueSurfaces.last)
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

private func deduplicated(
  _ surfaces: [RasterSurface]
) -> [RasterSurface] {
  var result: [RasterSurface] = []
  result.reserveCapacity(surfaces.count)
  for surface in surfaces where result.last != surface {
    result.append(surface)
  }
  return result
}
