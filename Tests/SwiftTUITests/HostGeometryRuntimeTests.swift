import SwiftTUICore
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite struct HostGeometryRuntimeTests {
  @Test(arguments: [false, true])
  func captureSurvivesHostChangeDuringAcquisition(asynchronous: Bool) async throws {
    let host = GeometryTestSurface()
    let root = testIdentity("GeometryCapture")
    var changed = false
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in
      if !changed {
        changed = true
        host.revision = 2
        host.size = .init(width: 30, height: 8)
        host.pitch = .init(width: 12, height: 24)
      }
      return GeometryEnvironmentText()
    }
    loop.renderMode = asynchronous ? .async : .sync
    loop.scheduler.requestSignal(named: "SIGWINCH")
    var rendered = 0
    if asynchronous {
      try await loop.renderPendingFramesAsync(renderedFrames: &rendered)
    } else {
      try loop.renderPendingFrames(renderedFrames: &rendered)
    }
    let first = try #require(host.frames.first)
    #expect(first.hostGeometryStamp == .init(session: 7, revision: 1))
    #expect(first.raster.size == .init(width: 24, height: 6))
    #expect(first.raster.lines.joined().contains("24 / 9"))

    // Same grid, new font metrics must still be presented even with no text damage.
    host.size = .init(width: 24, height: 6)
    loop.scheduler.requestSignal(named: "SIGWINCH")
    if asynchronous {
      try await loop.renderPendingFramesAsync(renderedFrames: &rendered)
    } else {
      try loop.renderPendingFrames(renderedFrames: &rendered)
    }
    let last = try #require(host.frames.last)
    #expect(last.hostGeometryStamp == .init(session: 7, revision: 2))
    #expect(last.raster.lines.joined().contains("24 / 12"))
  }

  @Test func sameGridMetricChangePublishesRevisionWithEmptyDamage() async throws {
    let host = GeometryTestSurface()
    let root = testIdentity("GeometryEmptyDamage")
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in Text("Unchanged") }
    loop.scheduler.requestSignal(named: "SIGWINCH")
    var rendered = 0
    try await loop.renderPendingFramesAsync(renderedFrames: &rendered)
    host.revision = 2
    host.pitch = .init(width: 12, height: 24)
    loop.scheduler.requestSignal(named: "SIGWINCH")
    try await loop.renderPendingFramesAsync(renderedFrames: &rendered)
    #expect(host.frames.count == 2)
    let last = try #require(host.frames.last)
    #expect(last.hostGeometryStamp?.revision == 2)
    #expect(last.rasterDamage?.textRows.isEmpty == true)
    #expect(last.raster == host.frames.first?.raster)
  }

  @Test func pointerRequiresCurrentRequestAndAppliedMapAndCancelsOldPress() throws {
    let host = GeometryTestSurface()
    let root = testIdentity("GeometryPointer")
    var activations = 0
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in Button("Activate") { activations += 1 } }
    loop.scheduler.requestSignal(named: "SIGWINCH")
    var rendered = 0
    try loop.renderPendingFrames(renderedFrames: &rendered)
    let region = try #require(loop.latestSemanticSnapshot.interactionRegions.first)
    let point = Point(x: Double(region.rect.origin.x), y: Double(region.rect.origin.y))
    func mouse(_ kind: MouseEvent.Kind, _ revision: UInt64, session: UInt64 = 7) -> MouseEvent {
      var event = MouseEvent(kind: kind, location: point)
      event.hostGeometryStamp = .init(session: session, revision: revision)
      return event
    }
    _ = loop.handle(.input(.mouse(mouse(.down(.primary), 1))))
    #expect(loop.pointerInteraction.isRouting)
    host.revision = 2
    #expect(!loop.acceptsHostPointer(mouse(.up(.primary), 1)))
    #expect(!loop.pointerInteraction.isRouting)
    #expect(!loop.acceptsHostPointer(mouse(.down(.primary), 2)))
    loop.scheduler.requestSignal(named: "SIGWINCH")
    try loop.renderPendingFrames(renderedFrames: &rendered)
    _ = loop.handle(.input(.mouse(mouse(.up(.primary), 2))))
    #expect(activations == 0)
    #expect(!loop.acceptsHostPointer(mouse(.down(.primary), 2, session: 6)))
    _ = loop.handle(.input(.mouse(mouse(.down(.primary), 2))))
    _ = loop.handle(.input(.mouse(mouse(.up(.primary), 2))))
    #expect(activations == 1)
    #expect(loop.rejectedHostGeometryPointerCount == 3)
    #expect(loop.cancelledHostGeometryGestureCount == 1)
    #expect(loop.reportedRuntimeIssues.contains { $0.code == "host.geometry.stalePointer" })
  }

  @Test func wheelCoalescingKeepsGeometryAndLatestTimestamp() {
    var first = MouseEvent(kind: .scrolled(deltaX: 1, deltaY: 2), location: Point.zero)
    first.hostGeometryStamp = .init(session: 1, revision: 4)
    var second = first
    second.kind = .scrolled(deltaX: 3, deltaY: 4)
    let merged = first.merged(with: second)
    #expect(merged?.kind == .scrolled(deltaX: 4, deltaY: 6))
    #expect(merged?.hostGeometryStamp == first.hostGeometryStamp)
    second.hostGeometryStamp = .init(session: 1, revision: 5)
    #expect(first.merged(with: second) == nil)
    second.hostGeometryStamp = .init(session: 2, revision: 4)
    #expect(first.merged(with: second) == nil)
  }
}

private struct GeometryEnvironmentText: View {
  @Environment(\.terminalSize) private var size
  @Environment(\.cellPixelMetrics) private var metrics
  var body: some View { Text("\(size.width) / \(metrics.width)") }
}

private final class GeometryTestSurface: HostGeometryPresentationSurface,
  SemanticHostFramePresentationSurface
{
  var revision: UInt64 = 1
  var size = CellSize(width: 24, height: 6)
  var pitch = PixelSize(width: 9, height: 21)
  var frames: [SemanticHostFrame] = []
  var surfaceSize: CellSize { size }
  let appearance: TerminalAppearance = .fallback
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  func captureHostLayoutConfiguration() -> HostLayoutConfiguration {
    .init(
      size: size, appearance: appearance, theme: nil,
      graphics: .init(cellPixelSize: pitch), pointer: .cellOnly,
      geometry: .init(session: 7, revision: revision))
  }
  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    frames.append(frame)
    return .rasterHostMetrics(for: frame.raster, damage: frame.rasterDamage)
  }
}

private final class GeometryTestInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}
