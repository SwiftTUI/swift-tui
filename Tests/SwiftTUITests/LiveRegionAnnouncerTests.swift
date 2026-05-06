import Testing

@testable import SwiftTUI
@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct LiveRegionAnnouncerTests {
  @Test("announcer suppresses first-frame live-region content")
  func announcerSuppressesFirstFrameContent() {
    var announcer = LiveRegionAnnouncer()

    let first = announcer.renderAnnouncements(
      for: liveRegionSnapshot([
        liveRegionNode("Status", label: "Loading", politeness: .polite)
      ])
    )
    let second = announcer.renderAnnouncements(
      for: liveRegionSnapshot([
        liveRegionNode("Status", label: "Loaded", politeness: .polite)
      ])
    )

    #expect(first == "")
    #expect(second == "polite: Loaded\n")
  }

  @Test("announcer orders assertive changes before polite changes")
  func announcerOrdersAssertiveBeforePolite() {
    var announcer = LiveRegionAnnouncer()
    _ = announcer.renderAnnouncements(
      for: liveRegionSnapshot([
        liveRegionNode("Polite", label: "Idle", politeness: .polite),
        liveRegionNode("Assertive", label: "Ready", politeness: .assertive),
      ])
    )

    let output = announcer.renderAnnouncements(
      for: liveRegionSnapshot([
        liveRegionNode("Polite", label: "Saved", politeness: .polite),
        liveRegionNode("Assertive", label: "Failed", politeness: .assertive),
      ])
    )

    #expect(output == "assertive: Failed\npolite: Saved\n")
  }

  @Test("announcer drops removed nodes instead of announcing removal or reappearance")
  func announcerDropsRemovedNodes() {
    var announcer = LiveRegionAnnouncer()
    _ = announcer.renderAnnouncements(
      for: liveRegionSnapshot([
        liveRegionNode("Status", label: "Loading", politeness: .polite)
      ])
    )

    let removed = announcer.renderAnnouncements(for: liveRegionSnapshot([]))
    let reappeared = announcer.renderAnnouncements(
      for: liveRegionSnapshot([
        liveRegionNode("Status", label: "Loaded", politeness: .polite)
      ])
    )

    #expect(removed == "")
    #expect(reappeared == "")
  }

  @Test("announcer suppresses off live regions")
  func announcerSuppressesOffLiveRegions() {
    var announcer = LiveRegionAnnouncer()
    _ = announcer.renderAnnouncements(
      for: liveRegionSnapshot([
        liveRegionNode("Status", label: "Loading", politeness: .off)
      ])
    )

    let output = announcer.renderAnnouncements(
      for: liveRegionSnapshot([
        liveRegionNode("Status", label: "Loaded", politeness: .off)
      ])
    )

    #expect(output == "")
  }

  @Test("accessible runtime appends changed live-region announcements")
  func accessibleRuntimeAppendsChangedAnnouncements() throws {
    let surface = LiveRegionTestSurface()
    let rootIdentity = testIdentity("AccessibleLiveRegionRoot")
    let scheduler = FrameScheduler()
    let stateContainer = StateContainer(
      initialState: "One",
      invalidationIdentities: [rootIdentity]
    )
    stateContainer.invalidator = scheduler
    let runLoop = liveRegionRunLoop(
      rootIdentity: rootIdentity,
      surface: surface,
      scheduler: scheduler,
      stateContainer: stateContainer,
      runtimeConfiguration: RuntimeConfiguration(output: .accessible)
    )

    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    stateContainer.replace(with: "Two")
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let output = surface.writes.joined()
    #expect(output.contains("status: One"))
    #expect(output.contains("status: Two"))
    #expect(output.contains("polite: Two"))
    #expect(!output.contains("polite: One"))
  }

  @Test("normal TUI runtime does not write live-region side-channel output")
  func normalTUIRuntimeDoesNotWriteLiveRegionSideChannel() throws {
    let surface = LiveRegionTestSurface()
    let rootIdentity = testIdentity("NormalLiveRegionRoot")
    let scheduler = FrameScheduler()
    let stateContainer = StateContainer(
      initialState: "One",
      invalidationIdentities: [rootIdentity]
    )
    stateContainer.invalidator = scheduler
    let runLoop = liveRegionRunLoop(
      rootIdentity: rootIdentity,
      surface: surface,
      scheduler: scheduler,
      stateContainer: stateContainer,
      runtimeConfiguration: .default
    )

    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    stateContainer.replace(with: "Two")
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let output = surface.writes.joined()
    #expect(surface.presentedSurfaces.count == 2)
    #expect(!output.contains("polite:"))
    #expect(!output.contains("assertive:"))
  }
}

@MainActor
private func liveRegionRunLoop(
  rootIdentity: Identity,
  surface: LiveRegionTestSurface,
  scheduler: FrameScheduler,
  stateContainer: StateContainer<String>,
  runtimeConfiguration: RuntimeConfiguration
) -> RunLoop<String, LiveRegionStatusView> {
  RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: surface,
    terminalInputReader: LiveRegionInputReader(),
    scheduler: scheduler,
    stateContainer: stateContainer,
    focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
    runtimeConfiguration: runtimeConfiguration,
    proposal: .init(width: 40, height: 8),
    viewBuilder: ScopedMapper { input in
      LiveRegionStatusView(label: input.state)
    }
  )
}

private struct LiveRegionStatusView: View {
  var label: String

  var body: some View {
    Text(label)
      .accessibilityRole(.status)
      .accessibilityLabel(label)
      .accessibilityLiveRegion(.polite)
  }
}

private func liveRegionSnapshot(
  _ nodes: [AccessibilityNode]
) -> SemanticSnapshot {
  SemanticSnapshot(accessibilityNodes: nodes)
}

private func liveRegionNode(
  _ name: String,
  label: String,
  politeness: AccessibilityPoliteness
) -> AccessibilityNode {
  AccessibilityNode(
    identity: testIdentity("LiveRegion", name),
    rect: CellRect(origin: .zero, size: .init(width: 10, height: 1)),
    role: .status,
    label: label,
    liveRegion: politeness
  )
}

private final class LiveRegionTestSurface: PresentationSurface {
  let surfaceSize = CellSize(width: 40, height: 8)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var writes: [String] = []
  private(set) var presentedSurfaces: [RasterSurface] = []

  func enableRawMode() throws {}
  func disableRawMode() throws {}

  func write(_ output: String) throws {
    writes.append(output)
  }

  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    presentedSurfaces.append(surface)
    return TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: surface.lines.count,
      cellsChanged: 0
    )
  }
}

private final class LiveRegionInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
