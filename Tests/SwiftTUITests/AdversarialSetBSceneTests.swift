// Adversarial set B, pass 4: scenes and App lifecycle (311–320).
//
// The scene layer turns an `App` into window descriptors, selects one scene
// for a host and hands it to a run loop; a hosted session owns an injected
// reader, an in-process signal reader and a raster surface; a shared endpoint
// fans one graph out to a terminal and a browser companion; the size
// negotiator maps host lengths to a cell grid. The register fixes one active
// root scene, the CLI fixes `noScenes` for an empty app, and the run loop
// fixes that a programmatic request is one flag. These probes open an empty
// app, nest builder artifacts, propose zero, negative and oversized host
// lengths, send input before and restart after a hosted session, let a
// browser companion throw, fail a terminal re-attach, and raise an exit twice
// from the first frame.

@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: scenes and app lifecycle", .serialized, .timeLimit(.minutes(1)))
struct AdversarialSetBSceneTests {
  // An app whose builder yields no window scene is `noScenes`; the manifest
  // must not advertise a phantom "window" default that a host then fails
  // to find.
  @Test func setB311EmptyAppIsNoScenesNotAPhantomDefault() throws {
    let app = SetBEmptyApp()
    let manifest = SceneManifest(for: app)
    #expect(manifest.scenes.isEmpty, "\(manifest.scenes)")
    #expect(collectWindowSceneDescriptors(from: app.body).isEmpty)
    do {
      #expect(manifest.defaultSceneID == nil)
      #expect(manifest.jsonString == #"{"defaultSceneID":null,"scenes":[]}"#)
      #expect(throws: AppLaunchError.noScenes) {
        _ = try HostedSceneSession(
          for: app, sceneID: "window",
          surface: HostedRasterSurface(
            surfaceSize: .init(width: 8, height: 2), appearance: .fallback, onFrame: { _ in }))
      }
    }
  }

  // Builder artifacts nest: a `for` loop, an `AnyScene` over a composite
  // scene and an explicit empty `else` branch traverse in declaration order
  // with exactly one default, and a `.stop` visitor halts after one scene.
  @Test func setB312NestedBuilderArtifactsTraverseInDeclarationOrder() {
    let app = SetBNestedApp()
    let descriptors = collectWindowSceneDescriptors(from: app.body)
    #expect(descriptors.map(\.id.rawValue) == ["x", "y", "pair-a", "pair-b"], "\(descriptors)")
    #expect(descriptors.map(\.isDefault) == [true, false, false, false], "\(descriptors)")
    let manifest = SceneManifest(for: app)
    #expect(manifest.defaultSceneID == WindowIdentifier("x"))
    #expect(manifest.scenes == descriptors)
    let selections = collectWindowSceneSelections(from: app.body)
    let selectedIDs = selections.map { $0.identifier }
    let selectedRoots = selections.map { $0.rootIdentity }
    let expectedRoots = descriptors.map { Identity(components: ["App", $0.id.rawValue]) }
    #expect(selectedIDs == descriptors.map(\.id), "\(selectedIDs)")
    #expect(selectedRoots == expectedRoots, "\(selectedRoots)")
    var stopper = SetBStoppingVisitor()
    #expect(traverseWindowScenes(app.body, visitor: &stopper) == .stop)
    #expect(stopper.visited == [WindowIdentifier("x")], "\(stopper.visited)")
    #expect(stopper.defaults == [true])
  }

  // `stop()` publishes `.none` as the session's own state; the exit flush
  // that follows a key drained in the same batch must not publish a live
  // focus presentation after it.
  @Test func setB313NoFocusPresentationFollowsStop() async throws {
    let recorder = SetBFocusRecorder()
    let session = try HostedSceneSession(
      for: SetBFocusApp(), sceneID: "primary", surface: setBHostedSurface(),
      onFocusPresentationChange: { recorder.record($0) })
    let task = Task { try await session.start() }
    await recorder.updates.wait(until: { recorder.presentations.last?.semantics == .activate })
    try #require(
      recorder.presentations.map(\.semantics) == [.activate], "\(recorder.presentations)")
    session.sendInput([0x09])
    session.stop()
    let reason = try await task.value
    let semantics = recorder.presentations.map(\.semantics)
    #expect(reason == .inputEnded)
    #expect(session.currentFocusPresentation == .none)
    #expect(semantics.last == .some(.none), "\(semantics)")
    let afterStop = semantics.drop(while: { $0 != .none }).dropFirst()
    do {
      #expect(afterStop.allSatisfy({ $0 == .none }), "\(semantics)")
    }
  }

  // Zero and negative host proposals ask for the minimum grid; the answer
  // must not exceed the answer to a one-point proposal.
  @Test func setB314ZeroAndNegativeProposalsDoNotOutgrowAOnePointProposal() {
    let cell = HostLengthSize(width: 8, height: 16)
    let oneCell = HostLengthSize(width: 8, height: 16)
    let fresh = HostedSurfaceSizeNegotiator(cellSize: cell)
    let settled = HostedSurfaceSizeNegotiator(
      cellSize: cell, preferredGridSize: .init(width: 12, height: 3),
      renderedGridSize: .init(width: 80, height: 24))
    #expect(
      fresh.sizeThatFits(proposedWidth: nil, proposedHeight: nil)
        == HostLengthSize(width: 640, height: 384))
    #expect(fresh.sizeThatFits(proposedWidth: 1, proposedHeight: 1) == oneCell)
    #expect(settled.sizeThatFits(proposedWidth: 1, proposedHeight: 1) == oneCell)
    let freshZero = fresh.negotiate(proposedWidth: 0, proposedHeight: 0)
    let freshNegative = fresh.negotiate(proposedWidth: -64, proposedHeight: -32)
    let settledZero = settled.sizeThatFits(proposedWidth: 0, proposedHeight: 0)
    do {
      #expect(freshZero.size == oneCell, "\(freshZero)")
      #expect(freshNegative.size == oneCell, "\(freshNegative)")
      #expect(settledZero == oneCell, "\(settledZero)")
    }
    #expect(freshZero.probeGridSize == nil, "\(freshZero)")
  }

  // An oversized finite host proposal negotiates a bounded grid instead of
  // trapping in the Double-to-Int cell conversion.
  @Test func setB315OversizedProposalDoesNotTrap() async {
    do {
      await #expect(processExitsWith: .success) {
        let negotiator = HostedSurfaceSizeNegotiator(
          cellSize: HostLengthSize(width: 8, height: 16))
        let negotiated = negotiator.negotiate(
          proposedWidth: Double(Int.max) * 16, proposedHeight: 16)
        #expect(negotiated.size.width.isFinite && negotiated.size.width > 0, "\(negotiated)")
      }
    }
  }

  // Input sent to a hosted session before `start()` is buffered and handled
  // once the first frame has mounted the key command.
  @Test func setB316InputSentBeforeStartIsDelivered() async throws {
    let recorder = SetBHostedRecorder()
    let session = try HostedSceneSession(
      for: SetBCounterApp(), sceneID: "primary", surface: setBHostedSurface(recorder))
    session.send(.key(SetBKeys.increment))
    session.send([.key(SetBKeys.increment)])
    let task = Task { try await session.start() }
    await recorder.updates.wait(until: { recorder.latestText.contains("Count 2") })
    #expect(recorder.latestText.contains("Count 2"), "\(recorder.latestText)")
    #expect(try await session.stopAndWait() == .inputEnded)
    #expect(try await task.value == .inputEnded)
  }

  // A hosted session whose run was stopped can be started again and accepts
  // input; it must not end at once with `.inputEnded`.
  @Test func setB317RestartAfterStopAcceptsInput() async throws {
    let recorder = SetBHostedRecorder()
    let session = try HostedSceneSession(
      for: SetBCounterApp(), sceneID: "primary", surface: setBHostedSurface(recorder))
    let first = Task { try await session.start() }
    await recorder.updates.wait(until: { recorder.latestText.contains("Count 0") })
    try #require(recorder.latestText.contains("Count 0"), "\(recorder.latestText)")
    #expect(try await session.stopAndWait() == .inputEnded)
    // Restart before awaiting the original start caller: its late cleanup
    // must not close the next run’s readers.
    // Either the restarted run presents the increment or it completes on its
    // own; both pulse the recorder's signal, so one of them decides the wait.
    let done = SetBFlag(notifying: recorder.updates)
    let second = Task {
      defer { done.set() }
      return try await session.start()
    }
    session.send(.key(SetBKeys.increment))
    await recorder.updates.wait(until: {
      recorder.latestText.contains("Count 1") || done.isSet
    })
    let sawIncrement = recorder.latestText.contains("Count 1")
    #expect(try await first.value == .inputEnded)
    session.stop()
    let reason = try await second.value
    #expect(reason == .inputEnded)
    do {
      #expect(sawIncrement, "\(recorder.latestText)")
    }
  }

  // A browser companion is an attachment, never the scene owner: its
  // presentation failure must not stop the terminal's frame or the scene.
  @Test func setB318ThrowingBrowserCompanionDoesNotStarveTheTerminal() throws {
    let terminal = SetBSharedTerminal()
    let surface = SharedSceneSurface(terminal: terminal, terminalIsAttached: true)
    let companion = SetBCompanionSurface(fails: false)
    surface.attachBrowser(companion, isConnected: { true })
    _ = try surface.present(SetBFrames.frame(sequence: 1, text: "alpha"))
    #expect(terminal.frames == ["alpha"], "\(terminal.frames)")
    #expect(companion.presented == [1])
    let failing = SetBCompanionSurface(fails: true)
    surface.attachBrowser(failing, isConnected: { false })
    var thrown: (any Error)?
    do {
      _ = try surface.present(SetBFrames.frame(sequence: 2, text: "bravo"))
    } catch {
      thrown = error
    }
    do {
      #expect(thrown == nil, "\(String(describing: thrown))")
      #expect(terminal.frames == ["alpha", "bravo"], "\(terminal.frames)")
    }
    #expect(surface.terminalIsAttached)
    surface.attachBrowser(failing, isConnected: { true })
    #expect(throws: Never.self) {
      _ = try surface.present(SetBFrames.frame(sequence: 3, text: "charlie"))
    }
    #expect(terminal.frames == ["alpha", "bravo", "charlie"])
  }

  // Re-attaching the terminal is one transition: when raw mode cannot be
  // restored the surface must not report itself attached while the
  // endpoint's input stays detached.
  @Test func setB319FailedTerminalReattachDoesNotSplitSurfaceAndInput() async throws {
    let terminal = SetBSharedTerminal()
    let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
    let endpoint = SharedSceneEndpoint(
      descriptor: .init(id: "shared", title: "Shared", isDefault: true),
      resources: SceneSessionResources(
        presentationSurface: terminal as any PresentationSurfaceMetricsProvider,
        terminalInputReader: reader, surfaceName: "setb-scenes"),
      isPrimary: true)
    let received = SetBEventLog()
    let stream = endpoint.input.scopedInputEvents()
    let consumer = Task {
      for await scoped in stream {
        received.record(scoped.event)
      }
    }
    defer {
      consumer.cancel()
      endpoint.stop()
    }
    try endpoint.surface.enableRawMode()
    reader.send(.key(KeyPress(.character("a"))))
    await received.updates.wait(until: { !received.events.isEmpty })
    try #require(received.keys == [KeyPress(.character("a"))], "\(received.events)")
    try endpoint.setTerminalAttached(false)
    #expect(!endpoint.surface.terminalIsAttached)
    #expect(terminal.rawModeEvents == ["enable", "disable"], "\(terminal.rawModeEvents)")
    terminal.failsNextEnable = true
    #expect(throws: SetBTerminalFailure.self) {
      try endpoint.setTerminalAttached(true)
    }
    // "b" takes the terminal path, which only a re-attached pump forwards;
    // "c" bypasses the pump through the reader seam and decides the wait, so
    // the order of arrival shows whether the input side re-attached.
    reader.send(.key(KeyPress(.character("b"))))
    endpoint.input.sendReaderEvent(.key(KeyPress(.character("c"))))
    await received.updates.wait(until: { received.keys.contains(KeyPress(.character("c"))) })
    #expect(
      received.keys == [KeyPress(.character("a")), KeyPress(.character("c"))],
      "\(received.events)")
    do {
      #expect(!endpoint.surface.terminalIsAttached)
    }
  }

  // Two programmatic requests raised while the first frame's `onAppear`
  // runs resolve to one `.programmatic` exit after that frame, dispatched
  // once to the handler that frame mounted.
  @Test func setB320DoubleRequestFromFirstFrameOnAppearExitsOnce() async throws {
    let recorder = SetBLifecycleRecorder()
    let selections = collectWindowSceneSelections(
      from: WindowGroup("Exit", id: "exit") { SetBDoubleRequestView(recorder: recorder) })
    let selection = try #require(selections.first)
    let terminal = SetBSharedTerminal()
    let input = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
    let result = try await selection.run(
      sessionName: "SetBScenes.DoubleRequest",
      resources: SceneSessionResources(
        presentationSurface: terminal as any PresentationSurfaceMetricsProvider,
        terminalInputReader: input, surfaceName: "setb-scenes"),
      stateContainer: StateContainer(
        initialState: SceneSessionState(), invalidationIdentities: [selection.rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [selection.rootIdentity]))
    #expect(result.exitReason == .programmatic)
    // The first frame plus the exit-flush frame that consumes the request.
    #expect(result.renderedFrames == 2)
    #expect(terminal.frames.count == 2, "\(terminal.frames)")
    #expect(terminal.frames.first?.contains("first frame") == true, "\(terminal.frames)")
    #expect(recorder.results == [true, true])
    #expect(recorder.requests == [.programmatic], "\(recorder.requests)")
    #expect(terminal.rawModeEvents == ["enable", "disable"], "\(terminal.rawModeEvents)")
  }
}

// MARK: - Keys and flags

private enum SetBKeys {
  static let increment = KeyPress(.character("i"), modifiers: .ctrl)
}

private enum SetBSceneFlags {
  static let includesHiddenWindow = false
}

private struct SetBTerminalFailure: Error {}

private struct SetBCompanionFailure: Error {}

// MARK: - Apps and scenes

private struct SetBEmptyApp: App {
  var body: some Scene {
    if SetBSceneFlags.includesHiddenWindow {
      WindowGroup("Hidden", id: "hidden") { Text("hidden") }
    }
  }
}

private struct SetBPairScene: Scene {
  @SceneBuilder var body: some Scene {
    WindowGroup("Pair A", id: "pair-a") { Text("a") }
    WindowGroup("Pair B", id: "pair-b") { Text("b") }
  }
}

private struct SetBNestedApp: App {
  var body: some Scene {
    for name in ["x", "y"] {
      WindowGroup(name, id: WindowIdentifier(name)) { Text(verbatim: name) }
    }
    AnyScene(SetBPairScene())
    if SetBSceneFlags.includesHiddenWindow {
      WindowGroup("Hidden", id: "hidden") { Text("hidden") }
    } else {
      EmptyScene()
    }
  }
}

private struct SetBCounterApp: App {
  var body: some Scene {
    WindowGroup("Counter", id: "primary") { SetBCounterView() }
  }
}

private struct SetBFocusApp: App {
  var body: some Scene {
    WindowGroup("Focus", id: "primary") {
      VStack {
        Text("Activate").focusable(true, interactions: .activate)
        Text("Edit").focusable(true, interactions: .edit)
      }
    }
  }
}

// MARK: - Views

@MainActor
private struct SetBCounterView: View {
  @State private var count = 0

  var body: some View {
    Panel(id: "counter") {
      Text("Count \(count)").focusable(true)
    }
    .keyCommand("Increment", key: .character("i"), modifiers: .ctrl) {
      count += 1
    }
  }
}

private struct SetBDoubleRequestView: View {
  let recorder: SetBLifecycleRecorder
  @Environment(\.requestTermination) private var requestTermination

  var body: some View {
    Text("first frame")
      .onAppear {
        recorder.results.append(requestTermination())
        recorder.results.append(requestTermination())
      }
      .onTerminationRequest { request in
        recorder.requests.append(request)
        return .allow
      }
  }
}

// MARK: - Visitors

@MainActor
private struct SetBStoppingVisitor: WindowSceneVisitor {
  var visited: [WindowIdentifier] = []
  var defaults: [Bool] = []

  mutating func visit<Content: View>(
    _ scene: WindowGroup<Content>,
    isDefault: Bool
  ) -> SceneTraversalControl {
    visited.append(scene.id)
    defaults.append(isDefault)
    return .stop
  }
}

// MARK: - Recorders

@MainActor
private final class SetBHostedRecorder {
  private(set) var frames: [RasterSurface] = []
  let updates = MainActorConditionSignal()

  var latestText: String {
    frames.last?.lines.joined(separator: "\n") ?? ""
  }

  func record(_ frame: SemanticHostFrame) {
    frames.append(frame.raster)
    updates.notify()
  }
}

@MainActor
private final class SetBFocusRecorder {
  private(set) var presentations: [FocusPresentation] = []
  let updates = MainActorConditionSignal()

  func record(_ presentation: FocusPresentation) {
    presentations.append(presentation)
    updates.notify()
  }
}

@MainActor
private final class SetBLifecycleRecorder {
  var results: [Bool] = []
  var requests: [TerminationRequest] = []
}

@MainActor
private final class SetBEventLog {
  private(set) var events: [InputEvent] = []
  let updates = MainActorConditionSignal()

  var keys: [KeyPress] {
    events.compactMap { event in
      if case .key(let key) = event {
        return key
      }
      return nil
    }
  }

  func record(_ event: InputEvent) {
    events.append(event)
    updates.notify()
  }
}

@MainActor
private final class SetBFlag {
  private(set) var isSet = false
  private let updates: MainActorConditionSignal

  init(notifying updates: MainActorConditionSignal) {
    self.updates = updates
  }

  func set() {
    isSet = true
    updates.notify()
  }
}

// MARK: - Surfaces

private func setBHostedSurface(_ recorder: SetBHostedRecorder? = nil) -> HostedRasterSurface {
  HostedRasterSurface(
    surfaceSize: .init(width: 24, height: 6), appearance: .fallback,
    onFrame: { frame in recorder?.record(frame) })
}

private enum SetBFrames {
  static func frame(sequence: UInt64, text: String) -> SemanticHostFrame {
    SemanticHostFrame(
      sequence: sequence,
      raster: RasterSurface(size: .init(width: text.count, height: 1), lines: [text]),
      semantics: SemanticSnapshot(),
      focusedIdentity: nil)
  }
}

private final class SetBSharedTerminal: PresentationSurface {
  var surfaceSize = CellSize(width: 30, height: 3)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  var failsNextEnable = false
  private(set) var frames: [String] = []
  private(set) var rawModeEvents: [String] = []

  func enableRawMode() throws {
    rawModeEvents.append("enable")
    if failsNextEnable {
      failsNextEnable = false
      throw SetBTerminalFailure()
    }
  }

  func disableRawMode() throws {
    rawModeEvents.append("disable")
  }

  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    frames.append(surface.lines.joined(separator: "\n"))
    return .fullRepaint(for: surface, capabilityProfile: capabilityProfile)
  }
}

private final class SetBCompanionSurface: SemanticHostFramePresentationSurface {
  let surfaceSize = CellSize(width: 30, height: 3)
  let capabilityProfile = TerminalCapabilityProfile.trueColor
  let appearance = TerminalAppearance.fallback
  let fails: Bool
  private(set) var presented: [UInt64] = []

  init(fails: Bool) {
    self.fails = fails
  }

  @discardableResult
  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    if fails {
      throw SetBCompanionFailure()
    }
    presented.append(frame.sequence)
    return .rasterHostMetrics(for: frame.raster, damage: frame.rasterDamage)
  }
}
