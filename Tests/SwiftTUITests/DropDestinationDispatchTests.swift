import Testing

@_spi(Runners) @testable import SwiftTUI
@testable import SwiftTUICore
@testable import SwiftTUIViews

/// End-to-end drop-dispatch tests. Unlike `DropDestinationTests` (which
/// only exercise the registry-registration path) these drive a real
/// `RunLoop` — its focus tracker, its registry, its `handlePaste`
/// routing — using the same `makeRunLoop*Local` + `renderInitial`
/// pattern already used by `KeyCommandTests` and
/// `GalleryStyleDispatchTests`.
///
/// Going through a scheduled-frame render (rather than the full
/// `runTestSceneSession` async scene loop) lets us assert behavior
/// synchronously without racing the scheduler, and lets us inspect
/// `focusTracker` / `latestSemanticSnapshot` directly when a test
/// needs to pin down a precondition.
@MainActor
@Suite
struct DropDestinationDispatchTests {
  @Test("A paste of a single path routes to a Panel's dropDestination")
  func singlePathDispatched() throws {
    let received = Box<[DroppedPath]>([])
    let receivedContext = Box<DropContext?>(nil)
    let runLoop = makeDropRunLoop {
      Panel(id: "inbox") {
        Text("body").focusable(true)
      }
      .dropDestination { paths, context in
        received.value = paths
        receivedContext.value = context
        return true
      }
    }
    try renderInitial(runLoop)
    focusLeafmostFocusable(in: runLoop)
    // Focus must have landed on something whose scopePath includes the
    // Panel's scope identity — otherwise the dispatch below will no-op
    // regardless of how the registry is populated.
    #expect(runLoop.focusTracker.currentFocusIdentity != nil)
    #expect(!runLoop.currentFocusScopePath().isEmpty)

    runLoop.handlePaste(PasteEvent(content: "/Users/me/file.txt"))
    #expect(received.value == [DroppedPath("/Users/me/file.txt")])
    #expect(receivedContext.value?.location == nil)
    #expect(receivedContext.value?.pointer == nil)
  }

  @Test("Spatial drop dispatch supplies location and modifiers without focus")
  func spatialDropDispatchSuppliesContext() throws {
    let received = Box<DropContext?>(nil)
    let runLoop = makeDropRunLoop {
      Panel(id: "inbox") {
        Text("body").focusable(true)
      }
      .dropDestination { _, context in
        received.value = context
        return true
      }
    }
    try renderInitial(runLoop)

    let pointer = PointerLocation.subCell(
      location: Point(x: 1.25, y: 0.5),
      source: .webPixels,
      metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)
    )
    let consumed = runLoop.handleDrop(
      paths: [DroppedPath("/Users/me/file.txt")],
      context: DropContext(
        location: pointer.location,
        pointer: pointer,
        modifiers: .shift
      )
    )

    #expect(consumed)
    #expect(received.value?.location == Point(x: 1.25, y: 0.5))
    #expect(received.value?.pointer == pointer)
    #expect(received.value?.modifiers == .shift)
  }

  @Test("InputEvent.drop routes through spatial drop dispatch")
  func inputEventDropRoutesThroughSpatialDispatch() throws {
    let received = Box<[DroppedPath]>([])
    let runLoop = makeDropRunLoop {
      Panel(id: "inbox") {
        Text("body").focusable(true)
      }
      .dropDestination { paths, _ in
        received.value = paths
        return true
      }
    }
    try renderInitial(runLoop)

    _ = runLoop.handle(
      .input(
        .drop(
          paths: [DroppedPath("/Users/me/native.txt")],
          context: DropContext(location: Point(x: 1, y: 0))
        )
      )
    )

    #expect(received.value == [DroppedPath("/Users/me/native.txt")])
  }

  @Test("Inner scope consumes before outer scope (leafmost-first)")
  func leafmostWins() throws {
    let outerFired = Box(0)
    let innerFired = Box(0)
    let runLoop = makeDropRunLoop {
      Panel(id: "outer") {
        Panel(id: "inner") {
          Text("body").focusable(true)
        }
        .dropDestination { _ in
          innerFired.value += 1
          return true
        }
      }
      .dropDestination { _ in
        outerFired.value += 1
        return true
      }
    }
    try renderInitial(runLoop)
    focusLeafmostFocusable(in: runLoop)

    runLoop.handlePaste(PasteEvent(content: "/a"))
    #expect(innerFired.value == 1)
    #expect(outerFired.value == 0)
  }

  @Test("Inner handler returning false bubbles the drop to the outer scope")
  func bubblesOnFalse() throws {
    let outerFired = Box(0)
    let innerFired = Box(0)
    let runLoop = makeDropRunLoop {
      Panel(id: "outer") {
        Panel(id: "inner") {
          Text("body").focusable(true)
        }
        .dropDestination { _ in
          innerFired.value += 1
          return false
        }
      }
      .dropDestination { _ in
        outerFired.value += 1
        return true
      }
    }
    try renderInitial(runLoop)
    focusLeafmostFocusable(in: runLoop)

    runLoop.handlePaste(PasteEvent(content: "/a"))
    #expect(innerFired.value == 1)
    #expect(outerFired.value == 1)
  }

  @Test("Non-path paste is not delivered to the drop destination")
  func nonPathIsNotDelivered() throws {
    let fired = Box(0)
    let runLoop = makeDropRunLoop {
      Panel(id: "editor") {
        TextEditor(text: .constant("")).focusable(true)
      }
      .dropDestination { _ in
        fired.value += 1
        return false
      }
    }
    try renderInitial(runLoop)
    focusLeafmostFocusable(in: runLoop)

    runLoop.handlePaste(PasteEvent(content: "plain typed text, not a path"))
    #expect(fired.value == 0)
  }

  @Test("Path paste routes to drop destination before focused text input paste handling")
  func pathPasteRoutesToDropDestinationBeforeFocusedTextInput() throws {
    final class TextBox {
      var value = ""
    }

    let box = TextBox()
    let received = Box<[DroppedPath]>([])
    let runLoop = makeDropRunLoop {
      Panel(id: "editor") {
        TextField(
          "Name",
          text: Binding(
            get: { box.value },
            set: { box.value = $0 }
          )
        )
        .id(testIdentity("PathPasteTextField"))
      }
      .dropDestination { paths in
        received.value = paths
        return true
      }
    }
    try renderInitial(runLoop)
    _ = runLoop.focusTracker.setFocus(to: testIdentity("PathPasteTextField"))

    runLoop.handlePaste(PasteEvent(content: "/tmp/file.txt"))

    #expect(received.value == [DroppedPath("/tmp/file.txt")])
    #expect(box.value.isEmpty)
  }
}

/// Moves focus to the region with the deepest `scopePath` in the
/// current semantic snapshot. The tests above declare a focusable leaf
/// (`Text("body").focusable(true)`) nested inside one or two Panels,
/// but Panels are *also* focusable — and they appear first in the
/// focus region list (outermost first). `FocusTracker` auto-adopts
/// the first region, so without this helper focus lands on the
/// outermost Panel and the inner drop destination is never reached.
@MainActor
private func focusLeafmostFocusable<State, V: View>(
  in runLoop: RunLoop<State, V>
) {
  guard
    let leafmost = runLoop.latestSemanticSnapshot.focusRegions
      .max(by: { $0.scopePath.count < $1.scopePath.count })
  else { return }
  _ = runLoop.focusTracker.setFocus(to: leafmost.identity)
}

@MainActor
private final class Box<Value> {
  var value: Value
  init(_ initial: Value) { value = initial }
}

@MainActor
private func makeDropRunLoop<V: View>(
  @ViewBuilder content: @escaping () -> V
) -> RunLoop<Int, V> {
  let terminalSize = CellSize(width: 40, height: 10)
  let terminal = DropDispatchTerminalHost(surfaceSizeProvider: { terminalSize })
  let rootIdentity = testIdentity("DropDispatchRoot")
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = terminal.appearance
  environmentValues.terminalSize = terminalSize
  let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: terminal,
    terminalInputReader: DropDispatchInputReader(),
    signalReader: DropDispatchSignalReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
    focusTracker: focusTracker,
    environmentValues: environmentValues,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in content() }
  )
  focusTracker.invalidator = runLoop.scheduler
  return runLoop
}

@MainActor
private func renderInitial<State, V: View>(_ runLoop: RunLoop<State, V>) throws {
  runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  runLoop.renderer.enableSelectiveEvaluation()
}

private final class DropDispatchTerminalHost: PresentationSurface {
  var surfaceSize: CellSize { surfaceSizeProvider() }
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }
  private(set) var latestSurface: RasterSurface?
  private let surfaceSizeProvider: () -> CellSize

  init(
    surfaceSizeProvider: @escaping () -> CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSizeProvider = surfaceSizeProvider
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    latestSurface = surface
    return TerminalPresentationMetrics(
      bytesWritten: 0, linesTouched: surface.lines.count, cellsChanged: 0
    )
  }
}

extension DropDispatchTerminalHost: DamageAwarePresentationSurface {
  func present(_ surface: RasterSurface, damage: PresentationDamage?) throws
    -> TerminalPresentationMetrics
  {
    try present(surface)
  }
}

private final class DropDispatchInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class DropDispatchSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
