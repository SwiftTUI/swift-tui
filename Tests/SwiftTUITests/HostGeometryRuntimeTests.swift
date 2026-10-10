import SwiftTUICore
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite struct HostGeometryRuntimeTests {
  @Test func paragraphSpacingIsCapturedAndClearedWithGeometry() throws {
    let host = GeometryTestSurface()
    host.size = .init(width: 32, height: 16)
    let root = testIdentity("ParagraphGeometry")
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("First").paragraph()
        Text("Second").paragraph()
      }
    }
    var rendered = 0
    for spacing in [0, 2, 0] {
      host.paragraphSpacing = spacing
      host.revision += 1
      loop.scheduler.requestSignal(named: "SIGWINCH")
      try loop.renderPendingFrames(renderedFrames: &rendered)
      let frame = try #require(host.frames.last)
      #expect(frame.hostGeometryStamp?.revision == host.revision)
      let paragraphs = frame.semantics.paragraphs
      #expect(paragraphs.count == 2)
      #expect(paragraphs[1].rect.origin.y - paragraphs[0].rect.origin.y == 1 + spacing)
    }
  }

  @Test func cancellationPreservesPendingKeyboardTraversalAndItsContinuation() throws {
    let host = GeometryTestSurface()
    let root = testIdentity("CancelFocusContinuation")
    let state = StateContainer(initialState: true, invalidationIdentities: [root])
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(), stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { showSecond, _ in
      VStack(spacing: 0) {
        Button("First") {}
        if showSecond { Button("Second") {} }
        Button("Third") {}
      }
    }
    loop.scheduler.requestSignal(named: "SIGWINCH")
    var rendered = 0
    try loop.renderPendingFrames(renderedFrames: &rendered)
    let regions = loop.latestSemanticSnapshot.focusRegions
    try #require(regions.count == 3)
    _ = loop.handle(.input(.key(KeyPress(.tab, modifiers: []))))
    #expect(loop.pendingFocusTraversal?.landedIdentity == regions[1].identity)
    state.replace(with: false)
    var cancel = MouseEvent(kind: .cancelled, location: Point(x: 1, y: 1))
    cancel.hostGeometryStamp = .init(session: 7, revision: 1)
    _ = loop.handle(.input(.mouse(cancel)))
    #expect(loop.pendingFocusTraversal?.landedIdentity == regions[1].identity)
    try loop.renderPendingFrames(renderedFrames: &rendered)
    #expect(loop.focusTracker.currentFocusIdentity == regions[2].identity)
  }

  @Test func explicitCancellationClearsGestureWithoutReleaseAndAllowsNextPress() throws {
    let host = GeometryTestSurface()
    let root = testIdentity("CancelledPointer")
    var activations = 0
    var dragEnds = 0
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in
      Button("Activate") { activations += 1 }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in dragEnds += 1 })
    }
    loop.scheduler.requestSignal(named: "SIGWINCH")
    var rendered = 0
    try loop.renderPendingFrames(renderedFrames: &rendered)
    let region = try #require(
      loop.latestSemanticSnapshot.interactionRegions.max { $0.hitTestOrder < $1.hitTestOrder })
    let point = Point(x: Double(region.rect.origin.x), y: Double(region.rect.origin.y))
    func send(_ kind: MouseEvent.Kind) {
      var event = MouseEvent(kind: kind, location: point)
      event.hostGeometryStamp = .init(session: 7, revision: 1)
      _ = loop.handle(.input(.mouse(event)))
    }
    send(.down(.primary))
    send(.dragged(.primary))
    #expect(loop.pointerInteraction.isRouting)
    send(.cancelled)
    #expect(!loop.pointerInteraction.isRouting)
    #expect(loop.localGestureRegistry.activeRecognizers().allSatisfy { !$0.1.isActive })
    #expect(loop.pressedIdentity == nil)
    send(.up(.primary))
    #expect(activations == 0)
    #expect(dragEnds == 0)
    try loop.renderPendingFrames(renderedFrames: &rendered)
    send(.down(.primary))
    send(.up(.primary))
    #expect(activations == 1)
    #expect(dragEnds == 1)
  }

  @Test func hostMotionPreferenceUpdatesLiveWithoutChangingGeometry() throws {
    let host = GeometryTestSurface()
    let root = testIdentity("HostMotion")
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in EnvironmentReader(\.accessibilityReduceMotion) { Text($0 ? "Reduced" : "Normal") } }
    var rendered = 0
    for preference in [false, true, false] {
      host.reduceMotion = preference
      loop.scheduler.requestSignal(named: "SIGWINCH")
      try loop.renderPendingFrames(renderedFrames: &rendered)
      #expect(
        host.frames.last?.raster.lines.joined().contains(preference ? "Reduced" : "Normal") == true)
      let style = TerminalRenderStyle(appearance: .fallback, reduceMotion: preference)
      let encoded = try #require(TerminalRenderStyleCodec.encodeBase64(style))
      #expect(TerminalRenderStyleCodec.decodeBase64(encoded)?.reduceMotion == preference)
    }
  }
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

  @Test func accessibilityAcknowledgementDoesNotOutliveItsHostSession() throws {
    let host = GeometryTestSurface()
    let root = testIdentity("GeometryAcknowledgement")
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in Button("Activate") {} }
    loop.scheduler.requestSignal(named: "SIGWINCH")
    var rendered = 0
    try loop.renderPendingFrames(renderedFrames: &rendered)
    func request(_ requestID: UInt64) throws {
      _ = loop.handle(
        .input(.accessibility(.init(target: "missing", action: .activate, requestID: requestID))))
      try loop.renderPendingFrames(renderedFrames: &rendered)
    }
    func present(revision: UInt64, session: UInt64 = 7) throws -> SemanticHostFrame {
      host.session = session
      host.revision = revision
      loop.scheduler.requestSignal(named: "SIGWINCH")
      try loop.renderPendingFrames(renderedFrames: &rendered)
      let frame = try #require(host.frames.last)
      #expect(frame.hostGeometryStamp == .init(session: session, revision: revision))
      return frame
    }
    try request(40)
    #expect(host.frames.last?.semantics.accessibilityActionResponse?.requestID == 40)
    // A new geometry revision of the same session keeps the acknowledgement.
    #expect(try present(revision: 2).semantics.accessibilityActionResponse?.requestID == 40)
    // A reloaded page opens a new session and numbers its requests from 1, so
    // request 40 must not acknowledge them.
    #expect(try present(revision: 0, session: 8).semantics.accessibilityActionResponse == nil)
    try request(1)
    #expect(host.frames.last?.semantics.accessibilityActionResponse?.requestID == 1)
  }

  @Test func queuedOldSessionEditsCannotMutateOrAcknowledgeTheNewPage() throws {
    let host = GeometryTestSurface()
    let root = testIdentity("QueuedAccessibilitySession")
    var text = "initial"
    var writes = 0
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in
      TextField(
        "Name",
        text: Binding(
          get: { text },
          set: {
            text = $0
            writes += 1
          }))
    }
    loop.scheduler.requestSignal(named: "SIGWINCH")
    var rendered = 0
    try loop.renderPendingFrames(renderedFrames: &rendered)
    let target = try #require(
      loop.latestSemanticSnapshot.accessibilityNodes.first {
        $0.label == "Name"
      }?.actionTarget)
    func send(_ value: String, session: UInt64, requestID: UInt64) throws {
      var request = AccessibilityActionRequest(
        target: target, action: .setValue(.text(value)), requestID: requestID)
      request.hostSession = session
      _ = loop.handle(.input(.accessibility(request)))
      try loop.renderPendingFrames(renderedFrames: &rendered)
    }
    // Both pages can issue ID 1; an ID-only browser filter cannot disambiguate them.
    host.session = 8
    try send("obsolete", session: 7, requestID: 1)
    #expect(text == "initial")
    #expect(writes == 0)
    #expect(loop.latestAccessibilityActionResponse == nil)
    try send("current", session: 8, requestID: 1)
    #expect(text == "current")
    #expect(writes == 1)
    #expect(loop.latestAccessibilityActionResponse?.requestID == 1)
    // A late high watermark cannot replace the current page's acknowledgement.
    try send("obsolete again", session: 7, requestID: 40)
    #expect(text == "current")
    #expect(writes == 1)
    #expect(loop.latestAccessibilityActionResponse?.requestID == 1)
    host.revision += 1
    try send("resized", session: 8, requestID: 2)
    #expect(text == "resized")
    #expect(writes == 2)
    #expect(loop.latestAccessibilityActionResponse?.requestID == 2)
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
  SemanticHostFramePresentationSurface, ClipboardWritingPresentationSurface
{
  var clipboardWrites: [String] = []
  @MainActor func writeClipboard(_ text: String) throws -> Bool {
    clipboardWrites.append(text)
    return true
  }
  var session: UInt64 = 7
  var revision: UInt64 = 1
  var reduceMotion: Bool?
  var preferences = AccessibilityPreferences()
  var paragraphSpacing = 0
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
      geometry: .init(session: session, revision: revision), reduceMotion: reduceMotion,
      accessibilityPreferences: preferences, paragraphSpacing: paragraphSpacing)
  }
  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    frames.append(frame)
    return .rasterHostMetrics(for: frame.raster, damage: frame.rasterDamage)
  }
}

private final class GeometryTestInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}

private struct AccessibilityPreferenceStyleProbe: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    let preferences = configuration.styleEnvironment.accessibilityPreferences
    Text("Style \(preferences.reduceTransparency == true ? "opaque" : "clear")")
  }
}

extension HostGeometryRuntimeTests {
  @Test(arguments: ["zoom", "spacing", "terminalResize", "browserResize", "session"])
  func terminalClicksWaitOnlyForSharedLayoutChanges(change: String) throws {
    let terminal = SharedTerminalTestSurface()
    let browser = GeometryTestSurface()
    browser.size = .init(width: 120, height: 40)
    let shared = SharedSceneSurface(terminal: terminal, terminalIsAttached: true)
    shared.attachBrowser(browser, isConnected: { true })
    let root = testIdentity("TerminalGeometryAcceptance")
    var activations = 0
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: shared, terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in Button("Activate") { activations += 1 } }
    var rendered = 0
    func render() throws {
      loop.scheduler.requestSignal(named: "SIGWINCH")
      try loop.renderPendingFrames(renderedFrames: &rendered)
    }
    func click(origin: InputOrigin, stamp: HostGeometryStamp? = nil) throws {
      let region = try #require(loop.latestSemanticSnapshot.interactionRegions.first)
      let point = Point(x: Double(region.rect.origin.x), y: Double(region.rect.origin.y))
      for kind in [MouseEvent.Kind.down(.primary), .up(.primary)] {
        var event = MouseEvent(kind: kind, location: point)
        event.hostGeometryStamp = stamp
        _ = loop.handle(.scopedInput(.init(.mouse(event), origin: origin)))
      }
    }
    try render()
    let firstStamp = try #require(browser.frames.last?.hostGeometryStamp)
    try click(origin: .terminal)
    #expect(activations == 1)
    switch change {
    case "zoom": browser.pitch = .init(width: 12, height: 28)
    case "spacing": browser.paragraphSpacing = 2
    case "terminalResize": terminal.size = .init(width: 20, height: 5)
    case "browserResize": browser.size = .init(width: 18, height: 4)
    default: browser.session += 1
    }
    browser.revision += 1
    try click(origin: .browser, stamp: firstStamp)
    try click(origin: .browser, stamp: shared.captureHostLayoutConfiguration().geometry)
    #expect(activations == 1)
    try click(origin: .terminal)
    let expected = change == "zoom" ? 2 : 1
    #expect(activations == expected)
    try render()
    try click(origin: .terminal)
    #expect(activations == expected + 1)
    try click(origin: .browser, stamp: browser.frames.last?.hostGeometryStamp)
    #expect(activations == expected + 2)
  }

  @Test func transparencyPreferenceRepaintsRetainedContentAndRestoresAuthoredFade() throws {
    let host = GeometryTestSurface()
    let root = testIdentity("LiveTransparencyPaint")
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in
      Text("X").foregroundStyle(Color.red.opacity(0.3)).cellBackground(Color.blue).opacity(0.5)
    }
    var rendered = 0
    var colors: [Color] = []
    for reduced in [false, true, false] {
      host.preferences.reduceTransparency = reduced
      loop.scheduler.requestSignal(named: "SIGWINCH")
      try loop.renderPendingFrames(renderedFrames: &rendered)
      let frame = try #require(host.frames.last)
      let cell = try #require(frame.raster.cells.flatMap { $0 }.first { $0.character == "X" })
      colors.append(try #require(cell.style?.foregroundColor))
    }
    #expect(colors[1] == .red)
    #expect(colors[0] != colors[1])
    #expect(colors[0] == colors[2])
  }

  @Test func preferencesUpdateRetainedViewsAndCustomStylesLive() throws {
    let host = GeometryTestSurface()
    host.size = .init(width: 72, height: 8)
    let root = testIdentity("LivePreferences")
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in
      VStack {
        EnvironmentReader(\.accessibilityPreferences) { preferences in
          Text("Motion \(preferences.reduceMotion == true ? "reduced" : "normal")")
          Text("Profile \(preferences.colorProfile?.rawValue ?? "auto")")
        }
        Button("Probe") {}.buttonStyle(AccessibilityPreferenceStyleProbe())
      }
    }
    var rendered = 0
    for enabled in [false, true, false] {
      host.preferences = .init(
        reduceMotion: false, contrast: enabled ? .increased : .standard,
        differentiateWithoutColor: enabled, reduceTransparency: enabled,
        colorProfile: enabled ? .monochrome : .standard)
      loop.scheduler.requestSignal(named: "SIGWINCH")
      try loop.renderPendingFrames(renderedFrames: &rendered)
      let painted = try #require(host.frames.last).raster.lines.joined(separator: "\n")
      #expect(painted.contains("Motion normal"))
      #expect(painted.contains(enabled ? "Profile monochrome" : "Profile standard"))
      #expect(painted.contains(enabled ? "Style opaque" : "Style clear"))
    }
  }
}

extension HostGeometryRuntimeTests {
  @Test func explicitRuntimePreferencesWinOverLiveHostDetection() throws {
    let host = GeometryTestSurface()
    host.size = .init(width: 60, height: 8)
    host.preferences = .init(reduceMotion: true, contrast: .increased, reduceTransparency: true)
    var configuration = RuntimeConfiguration()
    configuration.accessibilityPreferences = .init(reduceMotion: false, contrast: .standard)
    let root = testIdentity("ExplicitPreferences")
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host, terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      runtimeConfiguration: configuration,
      viewBuilder: ScopedMapper { _ in
        VStack {
          EnvironmentReader(\.accessibilityPreferences) { preferences in
            Text("Motion \(preferences.reduceMotion == true ? "reduced" : "normal")")
            Text("Contrast \(preferences.contrast == .increased ? "increased" : "standard")")
          }
          Button("Probe") {}.buttonStyle(AccessibilityPreferenceStyleProbe())
        }
      })
    var frames = 0
    for opaque in [true, false] {
      host.preferences.reduceTransparency = opaque
      loop.scheduler.requestSignal(named: "SIGWINCH")
      try loop.renderPendingFrames(renderedFrames: &frames)
      let text = try #require(host.frames.last).raster.lines.joined(separator: "\n")
      #expect(text.contains("Motion normal") && text.contains("Contrast standard"))
      #expect(text.contains(opaque ? "Style opaque" : "Style clear"))
    }
  }
}

extension HostGeometryRuntimeTests {
  @Test func sharedClipboardUsesInputOriginAndNeverReadsServerForBrowser() throws {
    let terminal = SharedTerminalTestSurface()
    let browser = GeometryTestSurface()
    let shared = SharedSceneSurface(terminal: terminal, terminalIsAttached: true)
    shared.attachBrowser(browser, isConnected: { true })
    try InputDispatchContext.$origin.withValue(.browser) { () throws -> Void in
      #expect(try shared.readClipboard() == nil)
      #expect(try shared.writeClipboard("browser copy"))
    }
    #expect(terminal.clipboardReads == 0)
    #expect(terminal.clipboardWrites.isEmpty)
    #expect(browser.clipboardWrites == ["browser copy"])
    try InputDispatchContext.$origin.withValue(.terminal) { () throws -> Void in
      #expect(try shared.readClipboard() == "server clipboard")
      #expect(try shared.writeClipboard("terminal copy"))
    }
    #expect(terminal.clipboardReads == 1)
    #expect(terminal.clipboardWrites == ["terminal copy"])
    try shared.setTerminalAttached(false)
    #expect(try shared.readClipboard() == nil)
    #expect(terminal.clipboardReads == 1)
  }

  @Test func retiredIngressDropsQueuedKeysPasteAndActionsBeforeMutation() throws {
    let host = GeometryTestSurface()
    let root = testIdentity("RetiredIngress")
    var text = ""
    var writes = 0
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host,
      terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in
      TextField(
        "Name",
        text: Binding(
          get: { text },
          set: {
            text = $0
            writes += 1
          }))
    }
    loop.scheduler.requestSignal(named: "SIGWINCH")
    var rendered = 0
    try loop.renderPendingFrames(renderedFrames: &rendered)
    let target = try #require(
      loop.latestSemanticSnapshot.accessibilityNodes.first {
        $0.label == "Name"
      }?.actionTarget)
    _ = loop.handle(.input(.accessibility(.init(target: target, action: .focus))))
    let oldLease = InputConnectionLease()
    let queued: [InputEvent] = [
      .key(.init(.character("X"))), .paste(.init(content: "obsolete")),
      .accessibility(.init(target: target, action: .setValue(.text("old")), requestID: 99)),
    ]
    let pump = EventPumpBuffer()
    for event in queued {
      _ = pump.enqueue(.scopedInput(.init(event, origin: .browser, lease: oldLease)))
    }
    oldLease.retire()
    while pump.hasPendingEvents() {
      for event in pump.drain() { _ = loop.handle(event.event, arrival: event.arrival) }
    }
    #expect(text.isEmpty && writes == 0)
    #expect(loop.latestAccessibilityActionResponse == nil)
    _ = loop.handle(.scopedInput(.init(.key(.init(.character("T"))), origin: .terminal)))
    #expect(text == "T" && writes == 1)
    let lease = InputConnectionLease()
    _ = loop.handle(
      .scopedInput(
        .init(
          .accessibility(.init(target: target, action: .setValue(.text("shared")), requestID: 1)),
          origin: .browser, lease: lease)))
    #expect(text == "shared" && writes == 2)
    #expect(loop.latestAccessibilityActionResponse?.requestID == 1)
    #expect(loop.currentInputOrigin == nil)
  }

  @Test func terminalPointerUsesItsGridAndCannotCompleteBrowserPress() throws {
    let host = GeometryTestSurface()
    let root = testIdentity("SharedPointerOrigins")
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
    func send(_ kind: MouseEvent.Kind, origin: InputOrigin) {
      var event = MouseEvent(kind: kind, location: point)
      if origin == .browser { event.hostGeometryStamp = .init(session: 7, revision: 1) }
      _ = loop.handle(.scopedInput(.init(.mouse(event), origin: origin)))
    }
    send(.down(.primary), origin: .browser)
    send(.up(.primary), origin: .terminal)
    #expect(activations == 0)
    send(.down(.primary), origin: .terminal)
    send(.up(.primary), origin: .terminal)
    #expect(activations == 1)
    send(.down(.primary), origin: .browser)
    send(.up(.primary), origin: .browser)
    #expect(activations == 2)
  }
}

extension HostGeometryRuntimeTests {
  @Test func sharedGridFitsBothAndRejectsOldViewportPointersAfterTerminalResize() throws {
    let terminal = SharedTerminalTestSurface()
    let browser = GeometryTestSurface()
    browser.size = .init(width: 120, height: 40)
    var connected = true
    let shared = SharedSceneSurface(terminal: terminal, terminalIsAttached: true)
    shared.attachBrowser(browser, isConnected: { connected })
    let root = testIdentity("CommonViewport")
    var activations = 0
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: shared, terminalInputReader: GeometryTestInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root])
    ) { _, _ in Button("Activate") { activations += 1 } }
    var rendered = 0
    func render() throws {
      loop.scheduler.requestSignal(named: "SIGWINCH")
      try loop.renderPendingFrames(renderedFrames: &rendered)
    }
    try render()
    let first = try #require(browser.frames.last)
    #expect(first.raster.size == terminal.size)
    #expect(terminal.frames.last == first.raster)
    let region = try #require(first.semantics.interactionRegions.first)
    let point = Point(x: Double(region.rect.origin.x), y: Double(region.rect.origin.y))
    func browserEvent(_ kind: MouseEvent.Kind, stamp: HostGeometryStamp?) {
      var event = MouseEvent(kind: kind, location: point)
      event.hostGeometryStamp = stamp
      _ = loop.handle(.scopedInput(.init(.mouse(event), origin: .browser)))
    }
    browserEvent(.down(.primary), stamp: first.hostGeometryStamp)
    terminal.size = .init(width: 16, height: 5)
    browserEvent(.up(.primary), stamp: first.hostGeometryStamp)
    #expect(activations == 0)
    try render()
    let resized = try #require(browser.frames.last)
    #expect(resized.raster.size == terminal.size)
    #expect(
      resized.hostGeometryStamp?.viewportRevision != first.hostGeometryStamp?.viewportRevision)
    browserEvent(.down(.primary), stamp: first.hostGeometryStamp)
    browserEvent(.up(.primary), stamp: first.hostGeometryStamp)
    #expect(activations == 0)
    browserEvent(.down(.primary), stamp: resized.hostGeometryStamp)
    browserEvent(.up(.primary), stamp: resized.hostGeometryStamp)
    #expect(activations == 1)
    browser.size = .init(width: 12, height: 4)
    browser.revision += 1
    try render()
    #expect(browser.frames.last?.raster.size == browser.size)
    connected = false
    try render()
    #expect(browser.frames.last?.raster.size == terminal.size)
    #expect(activations == 1)
  }
}

private final class SharedTerminalTestSurface: PresentationSurface,
  ClipboardWritingPresentationSurface, ClipboardReadingPresentationSurface
{
  var clipboardWrites: [String] = []
  var clipboardReads = 0
  @MainActor func writeClipboard(_ text: String) throws -> Bool {
    clipboardWrites.append(text)
    return true
  }
  @MainActor func readClipboard() throws -> String? {
    clipboardReads += 1
    return "server clipboard"
  }
  var size = CellSize(width: 24, height: 6)
  var frames: [RasterSurface] = []
  var surfaceSize: CellSize { size }
  let appearance: TerminalAppearance = .fallback
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_ output: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to point: CellPoint) throws {}
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    frames.append(surface)
    return .rasterHostMetrics(for: surface, damage: nil)
  }
}
