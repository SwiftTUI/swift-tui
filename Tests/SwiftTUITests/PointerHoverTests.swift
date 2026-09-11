import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct PointerHoverTests {
  @Test("onPointerHover receives entered moved and exited phases")
  func hoverReceivesEnteredMovedExited() throws {
    let phases = HoverPhaseBox()
    let runLoop = makeHoverRunLoop {
      Text("hover")
        .onPointerHover { phase in
          phases.append(phase)
        }
    }

    try renderInitial(runLoop)

    _ = runLoop.handle(
      .input(
        .mouse(
          .init(
            kind: .moved,
            location: .subCell(
              location: Point(x: 1.2, y: 0.4),
              source: .nativePixels,
              metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)
            )
          )
        )
      )
    )
    _ = runLoop.handle(
      .input(
        .mouse(
          .init(
            kind: .moved,
            location: .subCell(
              location: Point(x: 2.4, y: 0.4),
              source: .webPixels,
              metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)
            )
          )
        )
      )
    )
    _ = runLoop.handle(.input(.mouse(.init(kind: .moved, location: Point(x: 10, y: 4)))))

    #expect(
      phases.values == [
        .entered(Point(x: 1.2, y: 0.4)),
        .moved(Point(x: 2.4, y: 0.4)),
        .exited,
      ]
    )
  }

  @Test("hover registration toggles terminal all-motion mode")
  func hoverRegistrationTogglesTerminalAllMotionMode() throws {
    let terminal = HoverTerminalHost(surfaceSizeProvider: { CellSize(width: 20, height: 5) })
    let runLoop = makeHoverRunLoop(terminal: terminal) {
      Text("hover")
        .onPointerHover { _ in }
    }

    try renderInitial(runLoop)
    #expect(terminal.pointerHoverEnabledChanges == [true])
  }

  @Test("hover does not steal click gesture dispatch")
  func hoverDoesNotStealClickGestureDispatch() throws {
    let tapCount = CounterBox()
    let hoverPhases = HoverPhaseBox()
    let runLoop = makeHoverRunLoop {
      Text("tap")
        .onPointerHover { phase in
          hoverPhases.append(phase)
        }
        .onTapGesture {
          tapCount.increment()
        }
    }

    try renderInitial(runLoop)

    _ = runLoop.handle(.input(.mouse(.init(kind: .moved, location: Point(x: 0, y: 0)))))
    _ = runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: Point(x: 0, y: 0)))))
    _ = runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: Point(x: 0, y: 0)))))

    #expect(!hoverPhases.values.isEmpty)
    #expect(tapCount.value == 1)
  }
}

@MainActor
@Suite
struct ScrollWheelTests {
  @Test("a wheel handler on a non-overflowing ScrollView remains reachable")
  func nonOverflowingScrollViewWheelHandler() throws {
    let events = ScrollWheelEventBox()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NonOverflowingWheel"), size: .init(width: 20, height: 5)
    ) {
      ScrollView {
        Text("Short content").onTapGesture {}
      }.onScrollWheel { event in
        events.append(event)
        return .handled
      }
    }
    defer { harness.shutdown() }
    let point = try #require(harness.point(forText: "Short content"))
    _ = try harness.scrollPointer(at: point, deltaY: 1)
    #expect(events.values == [ScrollWheelEvent(deltaX: 0, deltaY: 1)])
  }

  @Test(
    "collection row wheel handlers can consume or pass through to List and Table",
    arguments: [false, true], [false, true])
  func collectionRowInterception(table: Bool, handled: Bool) throws {
    let events = ScrollWheelEventBox()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CollectionWheelInterception"),
      size: .init(width: 24, height: 8)
    ) {
      if table {
        Table(0..<10, id: \.self, columns: [TableColumn("Name", width: 16)]) { row in
          Text("Row \(row)").onScrollWheel { event in
            events.append(event)
            return handled ? .handled : .ignored
          }
        }.tableHeaders(.hidden)
      } else {
        List {
          ForEach(0..<10) { row in
            Text("Row \(row)").onScrollWheel { event in
              events.append(event)
              return handled ? .handled : .ignored
            }
          }
        }.listStyle(.plain)
      }
    }
    defer { harness.shutdown() }
    let initialFrame = harness.frame
    let point = try #require(
      harness.point(forText: "Row 0"), "Rendered collection: \(initialFrame)")
    let frame = try harness.scrollPointer(at: point, deltaY: 1)
    #expect(events.values == [ScrollWheelEvent(deltaX: 0, deltaY: 1)])
    if handled {
      #expect(frame == initialFrame)
    } else {
      #expect(frame != initialFrame)
      #expect(!frame.contains("Row 0"))
    }
  }

  @Test(
    "ignored content handlers run once before nested scroll boundary chaining",
    arguments: [false, true])
  func ignoredContentChainsAcrossSiblingScrollIdentities(atEdge: Bool) throws {
    let events = ScrollWheelEventBox()
    let inner = WheelPositionBox(y: atEdge ? 5 : 0)
    let outer = WheelPositionBox(y: 0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedWheelInterception"), size: .init(width: 30, height: 8)
    ) {
      ScrollView(.vertical, position: outer.binding) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Header")
          ScrollView(.vertical, position: inner.binding) {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<8) { row in
                Text("Inner \(row)")
                  .onScrollWheel { event in
                    events.append(event)
                    return .ignored
                  }
              }
            }
            .onScrollWheel { event in
              events.append(ScrollWheelEvent(deltaX: event.deltaX, deltaY: 100))
              return .ignored
            }
          }.scrollIndicators(.hidden)
            .id(testIdentity("NestedWheelInterception", "Inner"))
            .frame(width: 20, height: 3, alignment: .topLeading)
          ForEach(0..<8) { row in Text("Tail \(row)") }
        }
      }.scrollIndicators(.hidden)
        .id(testIdentity("NestedWheelInterception", "Outer"))
        .frame(width: 24, height: 6, alignment: .topLeading)
    }
    defer { harness.shutdown() }
    let point = try #require(harness.point(forText: atEdge ? "Inner 6" : "Inner 1"))
    let frame = try harness.scrollPointer(at: point, deltaY: 1)

    #expect(
      events.values == [
        ScrollWheelEvent(deltaX: 0, deltaY: 1),
        ScrollWheelEvent(deltaX: 0, deltaY: 100),
      ])
    #expect(inner.value.y == (atEdge ? 5 : 1))
    #expect(outer.value.y == (atEdge ? 1 : 0))
    #expect(frame.contains("Header") == !atEdge)
    #expect(frame.contains(atEdge ? "Inner 5" : "Inner 3"))
  }

  @Test(
    "content wheel handlers precede ScrollView, including at its edge",
    arguments: [false, true], [false, true])
  func contentWheelPrecedesScrollView(handled: Bool, atEdge: Bool) throws {
    let events = ScrollWheelEventBox()
    let position = WheelPositionBox(y: atEdge ? 5 : 0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("WheelInterception"), size: .init(width: 20, height: 5)
    ) {
      ScrollView(.vertical, position: position.binding) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<8) { row in
            Text("Row \(row)")
              .onScrollWheel { event in
                events.append(event)
                return handled ? .handled : .ignored
              }
          }
        }
      }.scrollIndicators(.hidden)
        .id(testIdentity("WheelInterception", "Scroll"))
        .frame(width: 16, height: 3, alignment: .topLeading)
    }
    defer { harness.shutdown() }
    let initialFrame = harness.frame
    let focus = harness.runLoop.focusTracker.currentFocusIdentity
    let point = try #require(harness.point(forText: atEdge ? "Row 6" : "Row 1"))
    let frame = try harness.scrollPointer(at: point, deltaY: 1)

    #expect(events.values == [ScrollWheelEvent(deltaX: 0, deltaY: 1)])
    #expect(position.value.y == (atEdge ? 5 : handled ? 0 : 1))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == focus)
    if handled || atEdge {
      #expect(frame == initialFrame)
    } else {
      #expect(!frame.contains("Row 0"))
      #expect(frame.contains("Row 3"))
    }
  }

  @Test("onScrollWheel receives deltas and ignores other pointer events")
  func wheelReceivesOnlyScrollEvents() throws {
    let events = ScrollWheelEventBox()
    let runLoop = makeHoverRunLoop {
      Text("wheel")
        .onScrollWheel { event in
          events.append(event)
          return .handled
        }
    }

    try renderInitial(runLoop)

    _ = runLoop.handle(.input(.mouse(.init(kind: .moved, location: Point(x: 1, y: 0)))))
    _ = runLoop.handle(
      .input(
        .mouse(
          .init(
            kind: .scrolled(deltaX: -2, deltaY: 3),
            location: Point(x: 1, y: 0)
          )
        )
      )
    )

    #expect(events.values == [ScrollWheelEvent(deltaX: -2, deltaY: 3)])
  }

  @Test("ignored wheel events bubble to an enclosing handler")
  func ignoredWheelBubbles() throws {
    let events = ScrollWheelEventBox()
    let runLoop = makeHoverRunLoop {
      VStack {
        Text("child")
          .onScrollWheel { event in
            events.append(ScrollWheelEvent(deltaX: event.deltaX, deltaY: 100))
            return .ignored
          }
      }
      .onScrollWheel { event in
        events.append(event)
        return .handled
      }
    }

    try renderInitial(runLoop)
    _ = runLoop.handle(
      .input(
        .mouse(
          .init(
            kind: .scrolled(deltaX: 1, deltaY: 2),
            location: Point(x: 1, y: 0)
          )
        )
      )
    )

    #expect(
      events.values == [
        ScrollWheelEvent(deltaX: 1, deltaY: 100),
        ScrollWheelEvent(deltaX: 1, deltaY: 2),
      ]
    )
  }
}

@MainActor
private final class HoverPhaseBox {
  private(set) var values: [HoverPhase] = []

  func append(_ phase: HoverPhase) {
    values.append(phase)
  }
}

@MainActor
private final class ScrollWheelEventBox {
  private(set) var values: [ScrollWheelEvent] = []

  func append(_ event: ScrollWheelEvent) {
    values.append(event)
  }
}

@MainActor
private final class WheelPositionBox {
  var value: ScrollCellOffset

  init(y: Int) { value = .init(x: 0, y: y) }

  var binding: Binding<ScrollCellOffset> {
    Binding(get: { self.value }, set: { self.value = $0 })
  }
}

@MainActor
private final class CounterBox {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}

@MainActor
private func makeHoverRunLoop<V: View>(
  terminal: HoverTerminalHost? = nil,
  @ViewBuilder content: @escaping () -> V
) -> RunLoop<Int, V> {
  let terminalSize = CellSize(width: 20, height: 5)
  let terminal = terminal ?? HoverTerminalHost(surfaceSizeProvider: { terminalSize })
  let rootIdentity = testIdentity("PointerHoverRoot")
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = terminal.appearance
  environmentValues.terminalSize = terminalSize
  let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: terminal,
    terminalInputReader: HoverInputReader(),
    signalReader: HoverSignalReader(),
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

private final class HoverTerminalHost: PresentationSurface {
  var surfaceSize: CellSize { surfaceSizeProvider() }
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }
  private(set) var pointerHoverEnabledChanges: [Bool] = []
  private let surfaceSizeProvider: () -> CellSize

  init(surfaceSizeProvider: @escaping () -> CellSize) {
    self.surfaceSizeProvider = surfaceSizeProvider
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  func setPointerHoverEnabled(_ enabled: Bool) throws {
    pointerHoverEnabledChanges.append(enabled)
  }

  @discardableResult
  func present(_: RasterSurface) throws -> TerminalPresentationMetrics {
    TerminalPresentationMetrics()
  }
}

private final class HoverInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class HoverSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
