@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Direct-manipulation panning — dragging a scroll view's own background to
/// move its content — is declared by the host through
/// ``PointerInputCapabilities/supportsScrollPanning`` and is off unless a host
/// asks for it.
///
/// Every behavioral test here is an A/B over that one flag with an otherwise
/// identical event script, so a regression that ignores the declaration fails
/// on one arm rather than passing vacuously on both. The paradigms these arms
/// stand for are real hosts: `false` is a terminal or a desktop pointer, where
/// a press-drag is a click-drag; `true` is Android, iOS, or a coarse-pointer
/// browser, where content follows the finger.
@MainActor
@Suite
struct ScrollPanningHostCapabilityTests {
  private static let terminalSize = CellSize(width: 20, height: 8)

  @Test(
    "a body drag pans only when the host declares scroll panning",
    arguments: [false, true])
  func bodyDragPansOnlyForPanningHosts(hostSupportsPanning: Bool) async throws {
    let box = OffsetBox()
    let rootIdentity = testIdentity("PanCapabilityFixture")
    let scrollIdentity = testIdentity("PanCapabilityFixture", "Scroll")
    @MainActor func makeView() -> some View {
      overflowingScrollView(id: scrollIdentity, box: box, rowLabel: "Pan")
    }

    let viewport = try #require(
      scrollViewportRect(
        for: scrollIdentity,
        in: makeView(),
        rootIdentity: rootIdentity
      )
    )

    // Press at the bottom of the viewport and drag to its top: on a touch host
    // the content follows the finger upward, revealing later rows.
    let result = try await runHarness(
      hostSupportsPanning: hostSupportsPanning,
      rootIdentity: rootIdentity,
      events: [
        .mouse(.init(kind: .down(.primary), location: bottom(of: viewport))),
        .mouse(.init(kind: .dragged(.primary), location: top(of: viewport))),
        .mouse(.init(kind: .up(.primary), location: top(of: viewport))),
      ],
      viewBuilder: makeView
    )

    #expect(result.exitReason == .inputEnded)
    if hostSupportsPanning {
      #expect(box.position.y > 0, "a touch host must pan the content with the drag")
    } else {
      #expect(
        box.position.y == 0,
        "a desktop/terminal host must leave the offset alone; a press-drag there is a click-drag")
    }
  }

  @Test(
    "wheel scrolling is unaffected by the panning declaration",
    arguments: [false, true])
  func wheelScrollingIgnoresPanningDeclaration(hostSupportsPanning: Bool) async throws {
    let box = OffsetBox()
    let rootIdentity = testIdentity("WheelCapabilityFixture")
    let scrollIdentity = testIdentity("WheelCapabilityFixture", "Scroll")
    @MainActor func makeView() -> some View {
      overflowingScrollView(id: scrollIdentity, box: box, rowLabel: "Wheel")
    }

    let viewport = try #require(
      scrollViewportRect(
        for: scrollIdentity,
        in: makeView(),
        rootIdentity: rootIdentity
      )
    )

    let result = try await runHarness(
      hostSupportsPanning: hostSupportsPanning,
      rootIdentity: rootIdentity,
      events: [
        .mouse(
          .init(kind: .scrolled(deltaX: 0, deltaY: 2), location: center(of: viewport)))
      ],
      viewBuilder: makeView
    )

    #expect(result.exitReason == .inputEnded)
    #expect(
      box.position.y > 0,
      "the wheel is the desktop scrolling paradigm and must work on every host")
  }

  /// The drag-threshold takeover is the second half of panning: it *cancels* a
  /// pressed control so an enclosing scroll view can claim the gesture. Without
  /// the declaration the control must survive the same stroke — otherwise a
  /// desktop user who wobbles the mouse during a click loses the click.
  @Test(
    "a drag off and back onto a control cancels it only when the host pans",
    arguments: [false, true])
  func dragThresholdCancelsControlOnlyForPanningHosts(
    hostSupportsPanning: Bool
  ) async throws {
    let box = OffsetBox()
    let rootIdentity = testIdentity("TakeoverCapabilityFixture")
    let scrollIdentity = testIdentity("TakeoverCapabilityFixture", "Scroll")
    let buttonIdentity = testIdentity("TakeoverCapabilityFixture", "Button")
    @MainActor func makeView() -> some View {
      ScrollView(
        .vertical,
        position: Binding(get: { box.position }, set: { box.position = $0 })
      ) {
        VStack(alignment: .leading, spacing: 0) {
          // Headers push the button down so an upward drag has both threshold
          // room and scroll headroom above it.
          Text("Header A")
          Text("Header B")
          Button("Tap") { box.taps += 1 }
            .id(buttonIdentity)
          ForEach(0..<15) { index in
            Text("Row \(index)")
          }
        }
      }
      .id(scrollIdentity)
      .frame(width: 10, height: 5, alignment: .topLeading)
    }

    let viewport = try #require(
      scrollViewportRect(
        for: scrollIdentity,
        in: makeView(),
        rootIdentity: rootIdentity
      )
    )
    let buttonRect = try #require(
      interactionRect(
        for: buttonIdentity,
        in: makeView(),
        rootIdentity: rootIdentity
      )
    )
    let column = Double(buttonRect.origin.x + buttonRect.size.width / 2)
    let press = Point(x: column, y: Double(buttonRect.origin.y + buttonRect.size.height / 2))
    let away = Point(x: column, y: Double(viewport.origin.y))

    // Press the button, drag well past the takeover threshold, come back, and
    // release over the button. The release lands on the control either way, so
    // the only thing that decides the outcome is whether the drag was allowed
    // to steal the gesture.
    let result = try await runHarness(
      hostSupportsPanning: hostSupportsPanning,
      rootIdentity: rootIdentity,
      events: [
        .mouse(.init(kind: .down(.primary), location: press)),
        .mouse(.init(kind: .dragged(.primary), location: away)),
        .mouse(.init(kind: .dragged(.primary), location: press)),
        .mouse(.init(kind: .up(.primary), location: press)),
      ],
      viewBuilder: makeView
    )

    #expect(result.exitReason == .inputEnded)
    if hostSupportsPanning {
      #expect(box.taps == 0, "takeover must cancel the pressed control")
    } else {
      #expect(
        box.taps == 1,
        "without panning the drag is an ordinary click-drag and the button still fires")
      #expect(box.position.y == 0, "and nothing scrolled")
    }
  }

  /// The semantic snapshot must agree with the handler. `captureOnPress` is
  /// what makes the run loop route a whole press stream to the scroll body; a
  /// host that does not pan would otherwise capture presses for a handler that
  /// ignores them.
  @Test(
    "the scroll body captures the press stream only when the host pans",
    arguments: [false, true])
  func scrollBodyCapturesPressOnlyForPanningHosts(hostSupportsPanning: Bool) throws {
    let box = OffsetBox()
    let rootIdentity = testIdentity("CaptureCapabilityFixture")
    let scrollIdentity = testIdentity("CaptureCapabilityFixture", "Scroll")

    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Self.terminalSize
    environmentValues.pointerInputCapabilities = PointerInputCapabilities(
      supportsScrollPanning: hostSupportsPanning
    )

    let artifacts = DefaultRenderer().render(
      overflowingScrollView(id: scrollIdentity, box: box, rowLabel: "Capture"),
      context: .init(identity: rootIdentity, environmentValues: environmentValues),
      proposal: .init(width: Self.terminalSize.width, height: Self.terminalSize.height)
    )

    let region = try #require(
      artifacts.semanticSnapshot.interactionRegions.first { $0.identity == scrollIdentity }
    )
    #expect(region.captureOnPress == hostSupportsPanning)
  }

  // MARK: - Fixtures

  @MainActor
  private final class OffsetBox {
    var position = ScrollCellOffset.zero
    var taps = 0
  }

  @MainActor
  @ViewBuilder
  private func overflowingScrollView(
    id: Identity,
    box: OffsetBox,
    rowLabel: String
  ) -> some View {
    ScrollView(
      .vertical,
      position: Binding(get: { box.position }, set: { box.position = $0 })
    ) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<20) { index in
          Text("\(rowLabel) \(index)")
        }
      }
    }
    .id(id)
    .frame(width: 10, height: 5, alignment: .topLeading)
  }

  private func runHarness<V: View>(
    hostSupportsPanning: Bool,
    rootIdentity: Identity,
    events: [InputEvent],
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Self.terminalSize

    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      // The declaration reaches views through the host, never through the seed
      // environment: `RunLoop.resolveContext` overwrites the environment's
      // `pointerInputCapabilities` with the surface's on every frame.
      presentationSurface: PanningCapabilityHost(
        surfaceSize: Self.terminalSize,
        supportsScrollPanning: hostSupportsPanning
      ),
      terminalInputReader: ScriptedInputReader(events: events),
      signalReader: SilentSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: environmentValues,
      proposal: .init(width: Self.terminalSize.width, height: Self.terminalSize.height),
      viewBuilder: { _, _ in
        viewBuilder()
      }
    )

    return try await runLoop.run()
  }

  private func scrollViewportRect<V: View>(
    for identity: Identity,
    in view: V,
    rootIdentity: Identity
  ) -> CellRect? {
    renderedSnapshot(of: view, rootIdentity: rootIdentity)
      .scrollRoutes
      .first { $0.identity == identity }?
      .viewportRect
  }

  private func interactionRect<V: View>(
    for identity: Identity,
    in view: V,
    rootIdentity: Identity
  ) -> CellRect? {
    renderedSnapshot(of: view, rootIdentity: rootIdentity)
      .interactionRegions
      .first { $0.identity == identity }?
      .rect
  }

  private func renderedSnapshot<V: View>(
    of view: V,
    rootIdentity: Identity
  ) -> SemanticSnapshot {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Self.terminalSize
    return DefaultRenderer().render(
      view,
      context: .init(identity: rootIdentity, environmentValues: environmentValues),
      proposal: .init(width: Self.terminalSize.width, height: Self.terminalSize.height)
    ).semanticSnapshot
  }

  private func center(of rect: CellRect) -> Point {
    Point(
      CellPoint(
        x: rect.origin.x + max(0, rect.size.width / 2),
        y: rect.origin.y + max(0, rect.size.height / 2)
      ))
  }

  private func top(of rect: CellRect) -> Point {
    Point(
      CellPoint(
        x: rect.origin.x + max(0, rect.size.width / 2),
        y: rect.origin.y
      ))
  }

  private func bottom(of rect: CellRect) -> Point {
    Point(
      CellPoint(
        x: rect.origin.x + max(0, rect.size.width / 2),
        y: rect.origin.y + max(0, rect.size.height - 1)
      ))
  }
}

/// A minimal presentation surface whose only interesting property is the
/// pointer declaration under test.
private final class PanningCapabilityHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let pointerInputCapabilities: PointerInputCapabilities

  init(
    surfaceSize: CellSize,
    supportsScrollPanning: Bool
  ) {
    self.surfaceSize = surfaceSize
    pointerInputCapabilities = PointerInputCapabilities(
      supportsScrollPanning: supportsScrollPanning
    )
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}

  @discardableResult
  func present(_: RasterSurface) throws -> TerminalPresentationMetrics { .init() }
}

private final class ScriptedInputReader: TerminalInputReading {
  private let scriptedEvents: [InputEvent]

  init(events: [InputEvent]) {
    scriptedEvents = events
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class SilentSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
