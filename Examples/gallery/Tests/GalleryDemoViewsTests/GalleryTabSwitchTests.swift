import TerminalUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct GalleryTabSwitchTests {
  @Test("clicking a gallery tab switches tabs without crashing")
  func clickingGalleryTabSwitchesSelection() async throws {
    let terminalSize = Size(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryTabSwitchClickTest")])
    let view = GalleryView()

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let initial = DefaultRenderer().render(
      view,
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let todoBounds = try #require(Self.boundsOfText("Todo", in: initial.placedTree))
    let clickCenter = Point(
      x: todoBounds.origin.x + todoBounds.size.width / 2,
      y: todoBounds.origin.y + todoBounds.size.height / 2
    )

    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    _ = try await Self.runHarness(
      host: host,
      terminalSize: terminalSize,
      events: [
        .mouse(.init(kind: .down(.primary), location: clickCenter)),
        .mouse(.init(kind: .up(.primary), location: clickCenter)),
      ],
      rootIdentity: rootIdentity,
      viewBuilder: { view }
    )

    let lastPresented = try #require(host.lastPresentedSurface)
    let surface = lastPresented.lines.joined(separator: "\n")
    #expect(
      surface.contains("remaining"),
      "expected Todo tab content after clicking the Todo tab; surface was:\n\(surface)"
    )
  }

  private static func boundsOfText(_ target: String, in node: PlacedNode) -> Rect? {
    if case .text(let content) = node.drawPayload, content == target {
      return node.bounds
    }
    for child in node.children {
      if let match = boundsOfText(target, in: child) {
        return match
      }
    }
    return nil
  }

  @MainActor
  private static func runHarness<V: View>(
    host: GalleryTabSwitchRecordingHost,
    terminalSize: Size,
    events: [InputEvent],
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: host,
      terminalInputReader: GalleryTabSwitchScriptedInput(events: events),
      signalReader: GalleryTabSwitchEmptySignals(),
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
}

private final class GalleryTabSwitchScriptedInput: TerminalInputReading {
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

private final class GalleryTabSwitchEmptySignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class GalleryTabSwitchRecordingHost: TerminalHosting {
  let surfaceSize: Size
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var lastPresentedSurface: RasterSurface?

  init(size: Size) {
    surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: Point) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    lastPresentedSurface = surface
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}
