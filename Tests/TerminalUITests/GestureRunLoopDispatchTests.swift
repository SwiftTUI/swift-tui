import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct GestureRunLoopDispatchTests {
  @Test("TapGesture fires through the full RunLoop mouse path")
  func tapGestureFiresThroughRunLoop() async throws {
    @MainActor final class Box {
      var count = 0
    }

    let box = Box()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("GestureRunLoopTap")])
    let view = Text("Tap")
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .onTapGesture {
        box.count += 1
      }

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let probePointerRegistry = LocalPointerHandlerRegistry()
    let probeGestureRegistry = LocalGestureRegistry()
    let probeGestureStateRegistry = LocalGestureStateRegistry()
    var probeContext = ResolveContext(identity: rootIdentity, environmentValues: env)
    probeContext.localPointerHandlerRegistry = probePointerRegistry
    probeContext.localGestureRegistry = probeGestureRegistry
    probeContext.localGestureStateRegistry = probeGestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: probeContext,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let region = try #require(initial.semanticSnapshot.interactionRegions.first)
    let point = centerPoint(of: region.rect)

    let host = RecordingGestureTerminalHost(size: terminalSize)
    let pointer = PointerLocation.subCell(
      location: point,
      source: .nativePixels,
      metrics: .estimated
    )
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: pointer))),
        .init(event: .mouse(.init(kind: .up(.primary), location: pointer))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(box.count == 1)
  }

  @Test("SpatialTapGesture delivers local coordinates through the full RunLoop mouse path")
  func spatialTapGestureCarriesLocalCoordinatesThroughRunLoop() async throws {
    @MainActor final class Box {
      var location: Point?
    }

    let box = Box()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("GestureRunLoopSpatialTap")])
    let view = Text("Tap")
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .gesture(
        SpatialTapGesture().onEnded { value in
          box.location = value.location
        }
      )

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let probePointerRegistry = LocalPointerHandlerRegistry()
    let probeGestureRegistry = LocalGestureRegistry()
    let probeGestureStateRegistry = LocalGestureStateRegistry()
    var probeContext = ResolveContext(identity: rootIdentity, environmentValues: env)
    probeContext.localPointerHandlerRegistry = probePointerRegistry
    probeContext.localGestureRegistry = probeGestureRegistry
    probeContext.localGestureStateRegistry = probeGestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: probeContext,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let region = try #require(initial.semanticSnapshot.interactionRegions.first)
    let point = Point(
      x: Double(region.rect.origin.x + 3),
      y: Double(region.rect.origin.y)
    )

    let host = RecordingGestureTerminalHost(size: terminalSize)
    let pointer = PointerLocation.subCell(
      location: point,
      source: .nativePixels,
      metrics: .estimated
    )
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: pointer))),
        .init(event: .mouse(.init(kind: .up(.primary), location: pointer))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(box.location == Point(x: 3, y: 0))
  }

  @Test("Terminal-pixel mouse input reaches DragGesture as fractional location")
  func terminalPixelMouseInputReachesDragGestureAsFractionalLocation() async throws {
    @MainActor final class Box {
      var location: Point?
    }

    let box = Box()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("GestureRunLoopTerminalPixelDrag")])
    let view = Text("Drag")
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .gesture(
        DragGesture().onChanged { value in
          box.location = value.location
        }
      )

    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    var parser = TerminalInputParser(
      mouseCoordinateMode: .pixels(metrics: metrics, source: .terminalPixels)
    )
    let events = parser.feed(
      Array("\u{001B}[<0;5;9M\u{001B}[<32;13;9M\u{001B}[<0;13;9m".utf8)
    )

    let result = try await runHarness(
      host: RecordingGestureTerminalHost(size: terminalSize),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: events.map { ScheduledGestureInputEvent(event: $0) },
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(box.location == Point(x: 1.5, y: 0.5))
  }

  @Test("LongPressGesture fires through the full RunLoop deadline path")
  func longPressGestureFiresThroughRunLoop() async throws {
    @MainActor final class Box {
      var count = 0
    }

    let box = Box()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("GestureRunLoopLongPress")])
    let view = Text("Hold")
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .onLongPressGesture(minimumDuration: .milliseconds(20)) {
        box.count += 1
      }

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let probePointerRegistry = LocalPointerHandlerRegistry()
    let probeGestureRegistry = LocalGestureRegistry()
    let probeGestureStateRegistry = LocalGestureStateRegistry()
    var probeContext = ResolveContext(identity: rootIdentity, environmentValues: env)
    probeContext.localPointerHandlerRegistry = probePointerRegistry
    probeContext.localGestureRegistry = probeGestureRegistry
    probeContext.localGestureStateRegistry = probeGestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: probeContext,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let region = try #require(initial.semanticSnapshot.interactionRegions.first)
    let point = centerPoint(of: region.rect)

    let host = RecordingGestureTerminalHost(size: terminalSize)
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(
          delayNanoseconds: 75_000_000,
          event: .mouse(.init(kind: .up(.primary), location: point))
        ),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(box.count == 1)
  }

  @Test("Exclusive tap composition works through the full RunLoop mouse path")
  func exclusiveTapCompositionFiresThroughRunLoop() async throws {
    @MainActor final class Counts {
      var single = 0
      var double = 0
    }

    let counts = Counts()
    let terminalSize = CellSize(width: 20, height: 5)
    let rootIdentity = Identity(components: [.named("GestureRunLoopExclusiveTap")])
    let view = Text("Tap")
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .gesture(
        TapGesture(count: 2).onEnded { counts.double += 1 }
          .exclusively(before: TapGesture().onEnded { counts.single += 1 })
      )

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let probePointerRegistry = LocalPointerHandlerRegistry()
    let probeGestureRegistry = LocalGestureRegistry()
    let probeGestureStateRegistry = LocalGestureStateRegistry()
    var probeContext = ResolveContext(identity: rootIdentity, environmentValues: env)
    probeContext.localPointerHandlerRegistry = probePointerRegistry
    probeContext.localGestureRegistry = probeGestureRegistry
    probeContext.localGestureStateRegistry = probeGestureStateRegistry
    let initial = DefaultRenderer().render(
      view,
      context: probeContext,
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let region = try #require(initial.semanticSnapshot.interactionRegions.first)
    let point = centerPoint(of: region.rect)

    let host = RecordingGestureTerminalHost(size: terminalSize)
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      schedule: [
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: point))),
        .init(event: .mouse(.init(kind: .down(.primary), location: point))),
        .init(event: .mouse(.init(kind: .up(.primary), location: point))),
      ],
      viewBuilder: { view }
    )

    #expect(result.exitReason == .inputEnded)
    #expect(counts.double == 1)
    #expect(counts.single == 0)
  }
}

@MainActor
private func runHarness<V: View>(
  host: RecordingGestureTerminalHost,
  terminalSize: CellSize,
  rootIdentity: Identity,
  schedule: [ScheduledGestureInputEvent],
  viewBuilder: @escaping () -> V
) async throws -> RunLoopResult<Int> {
  var env = EnvironmentValues()
  env.terminalSize = terminalSize
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    terminalHost: host,
    terminalInputReader: ScriptedGestureInput(schedule: schedule),
    signalReader: EmptyGestureSignals(),
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

private struct ScheduledGestureInputEvent {
  let delayNanoseconds: UInt64
  let event: InputEvent

  init(delayNanoseconds: UInt64 = 0, event: InputEvent) {
    self.delayNanoseconds = delayNanoseconds
    self.event = event
  }
}

private func centerPoint(of rect: CellRect) -> Point {
  Point(
    x: Double(rect.origin.x + rect.size.width / 2),
    y: Double(rect.origin.y + rect.size.height / 2)
  )
}

private final class ScriptedGestureInput: TerminalInputReading {
  private let schedule: [ScheduledGestureInputEvent]

  init(schedule: [ScheduledGestureInputEvent]) {
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

private final class EmptyGestureSignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class RecordingGestureTerminalHost: TerminalHosting {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback

  init(size: CellSize) {
    self.surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_: RasterSurface) throws -> TerminalPresentationMetrics {
    .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}
