import Foundation
@_spi(Testing) import TerminalUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct PhysicsTabGestureTests {

  @Test("fullscreen toy starts at bottom center with its initial launch velocity")
  func spawnStateStartsAtBottomCenter() {
    let terminalSize = CellSize(width: 40, height: 12)
    let playfield = FullScreenToyPhysics.playfieldBounds(from: terminalSize)
    let floor = FullScreenToyPhysics.maximumOrigin(in: playfield, metrics: .estimated)

    let state = FullScreenToyPhysics.spawnState(in: playfield, metrics: .estimated)

    #expect(state.position.x == floor.x / 2)
    #expect(state.position.y == floor.y)
    #expect(state.velocity.x == FullScreenToyPhysics.initialLaunchX)
    #expect(state.velocity.y == FullScreenToyPhysics.initialLaunchY)
  }

  @Test("fullscreen toy physics applies gravity and bounces off the floor")
  func physicsBouncesOffFloor() {
    let terminalSize = CellSize(width: 40, height: 12)
    let floor = FullScreenToyPhysics.maximumOrigin(in: terminalSize, metrics: .estimated)
    var state = FullScreenToyPhysics.State(
      position: .init(x: 10 * FullScreenToyPhysics.fixedScale, y: floor.y - 1),
      velocity: .init(x: 0, y: 10)
    )

    FullScreenToyPhysics.step(&state, in: terminalSize, metrics: .estimated)

    #expect(state.position.y == floor.y)
    #expect(state.velocity.y < 0)
  }

  @Test("fullscreen toy physics reflects from the right wall")
  func physicsReflectsOffRightWall() {
    let terminalSize = CellSize(width: 40, height: 12)
    let wall = FullScreenToyPhysics.maximumOrigin(in: terminalSize, metrics: .estimated)
    var state = FullScreenToyPhysics.State(
      position: .init(x: wall.x - 2, y: 4 * FullScreenToyPhysics.fixedScale),
      velocity: .init(x: 6, y: 0)
    )

    FullScreenToyPhysics.step(&state, in: terminalSize, metrics: .estimated)

    #expect(state.position.x == wall.x)
    #expect(state.velocity.x < 0)
  }

  @Test("fullscreen toy release converts gesture velocity into physics velocity")
  func releaseConvertsGestureVelocity() {
    let terminalSize = CellSize(width: 40, height: 12)
    var state = FullScreenToyPhysics.State()

    FullScreenToyPhysics.applyRelease(
      to: &state,
      translation: .zero,
      velocity: Vector(dx: 100, dy: -50),
      in: terminalSize,
      metrics: .estimated
    )

    #expect(state.velocity == .init(x: 64, y: -16))
  }

  @Test("fullscreen demo keeps presenting frames while gravity runs")
  func gravityLoopSchedulesRuntimeFrames() async throws {
    let terminalSize = CellSize(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("PhysicsTabGravityLoop")])
    let host = GestureRecordingHost(size: terminalSize)
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { PhysicsTab() },
      terminalInputReader: AwaitedTerminalInputReader(steps: [
        .waitUntil(timeoutNanoseconds: 2_000_000_000) {
          deduplicated(host.surfaces).count >= 2
        },
        .event(.key(KeyPress(.character("c"), modifiers: .ctrl))),
      ])
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(result.renderedFrames >= 2)

    let uniqueSurfaces = deduplicated(host.surfaces)
    #expect(uniqueSurfaces.count >= 2)
    #expect(uniqueSurfaces.first != uniqueSurfaces.last)
  }

  @Test("dragging the fullscreen demo rectangle updates the rendered surface and commits position")
  func draggingRectangleUpdatesAndCommits() async throws {
    let terminalSize = CellSize(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("PhysicsTabGestureTest")])
    let view = PhysicsTab()

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
    let terminalSize = CellSize(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("PhysicsTabGestureTwiceTest")])
    let view = PhysicsTab()

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

  @Test("fullscreen tab wrapped in a bottom toolbar renders the palette item")
  func fullscreenToolbarRendersPaletteItem() {
    let terminalSize = CellSize(width: 40, height: 12)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      PhysicsTab()
        .toolbarItem(.init(title: "⌃K Palette", action: {}))
        .panel(id: "gallery")
        .toolbar(style: DefaultBottomToolbarStyle()),
      context: .init(
        identity: Identity(components: [.named("FullScreenToolbarVisibility")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let paletteRows = artifacts.rasterSurface.lines.enumerated().compactMap { index, line in
      line.contains("⌃K Palette") ? index : nil
    }
    #expect(!paletteRows.isEmpty, "expected toolbar row to contain the palette item")
  }

  @Test("fullscreen toolbar stays present in the rendered surface while animation ticks")
  func fullscreenToolbarStaysPresentAcrossAnimationFrames() async throws {
    let terminalSize = CellSize(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("FullScreenToolbarAnimationVisibility")])
    let host = GestureRecordingHost(size: terminalSize)

    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: {
        PhysicsTab()
          .toolbarItem(.init(title: "⌃K Palette", action: {}))
          .panel(id: "gallery")
          .toolbar(style: DefaultBottomToolbarStyle())
      },
      terminalInputReader: AwaitedTerminalInputReader(steps: [
        .waitUntil(timeoutNanoseconds: 2_000_000_000) {
          deduplicated(host.surfaces).count >= 2
        },
        .event(.key(KeyPress(.character("c"), modifiers: .ctrl))),
      ])
    )

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(!host.surfaces.isEmpty)
    let missingPalette = host.surfaces.enumerated().filter { _, surface in
      !surface.lines.contains { $0.contains("⌃K Palette") }
    }
    #expect(
      missingPalette.isEmpty,
      "expected every rendered surface to retain the palette toolbar item; missing on frames: \(missingPalette.map { $0.0 })"
    )
  }
}

private struct ScheduledInputEvent {
  let delayNanoseconds: UInt64
  let event: InputEvent
}

private enum AwaitedTerminalInputStep {
  case event(InputEvent, delayNanoseconds: UInt64 = 0)
  case waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    predicate: @MainActor () -> Bool
  )
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

private final class AwaitedTerminalInputReader: TerminalInputReading {
  private let steps: [AwaitedTerminalInputStep]
  private let pollNanoseconds: UInt64

  init(
    steps: [AwaitedTerminalInputStep],
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

private final class GestureRecordingHost: TerminalHosting {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var surfaces: [RasterSurface] = []

  init(size: CellSize) {
    self.surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    surfaces.append(surface)
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}

@MainActor
private func runHarness<V: View>(
  host: GestureRecordingHost,
  terminalSize: CellSize,
  rootIdentity: Identity,
  viewBuilder: @escaping () -> V,
  eventSchedule: [ScheduledInputEvent]
) async throws -> RunLoopResult<Int> {
  try await runHarness(
    host: host,
    terminalSize: terminalSize,
    rootIdentity: rootIdentity,
    viewBuilder: viewBuilder,
    terminalInputReader: ScheduledTerminalInputReader(schedule: eventSchedule)
  )
}

@MainActor
private func runHarness<V: View>(
  host: GestureRecordingHost,
  terminalSize: CellSize,
  rootIdentity: Identity,
  viewBuilder: @escaping () -> V,
  terminalInputReader: any TerminalInputReading
) async throws -> RunLoopResult<Int> {
  var env = EnvironmentValues()
  env.terminalSize = terminalSize
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    terminalHost: host,
    terminalInputReader: terminalInputReader,
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

private func centerPoint(of rect: CellRect) -> Point {
  Point(
    CellPoint(
      x: rect.origin.x + rect.size.width / 2,
      y: rect.origin.y + rect.size.height / 2
    )
  )
}

private func firstShapeBounds(in node: PlacedNode) -> CellRect? {
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
