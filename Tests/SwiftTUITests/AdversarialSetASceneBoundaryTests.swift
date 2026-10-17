@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Scene ownership and host attachment probes, independent of transport codecs.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AdversarialSetASceneBoundaryTests {
  @Test func setA351ErasedEmptyScenePrefixesCannotConsumeTheDefaultWindow() {
    // Hypothesis: an empty erased/array branch consumes the default marker
    // before the first actual window is visited.
    let scene = SceneBuilder.buildArray([
      AnyScene(EmptyScene()),
      AnyScene(SceneBuilder.buildArray([AnyScene(EmptyScene())])),
      AnyScene(WindowGroup("Visible", id: "visible") { Text("First") }),
      AnyScene(WindowGroup("Later", id: "later") { Text("Second") }),
    ])
    let descriptors = collectWindowSceneDescriptors(from: scene)
    #expect(descriptors.map(\.id) == ["visible", "later"])
    #expect(descriptors.map(\.isDefault) == [true, false])
  }

  @Test func setA352UnselectedDuplicateIDsRejectAnOtherwiseUniqueRequestedWindow() {
    // Hypothesis: a successful early scene lookup bypasses duplicate-ID
    // validation for later, unselected windows before starting the host.
    let probe = SceneBoundaryProbe()
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 20, height: 4), appearance: .fallback,
      frameDelivery: .assumedMainActor, onFrame: { _ in probe.first += 1 })
    #expect(throws: AppLaunchError.duplicateSceneIdentifier("duplicate")) {
      _ = try HostedSceneSession(
        for: SceneBoundaryDuplicateApp(), sceneID: "unique", surface: surface)
    }
    #expect(probe.first == 0)
  }

  @Test func setA353EarlySelectionStopsBeforeEvaluatingLaterSceneBodies() throws {
    // Hypothesis: traversal stops the visitor but still evaluates a subsequent
    // composite scene body, violating first-window selection laziness.
    let probe = SceneBoundaryProbe()
    let scene = SceneBuilder.buildArray([
      AnyScene(WindowGroup("First", id: "first") { Text("One") }),
      AnyScene(SceneBoundaryDeferredScene(probe: probe)),
    ])
    var visitor = SceneBoundarySelectionVisitor()
    let selected = try #require(withFirstWindowSceneConfiguration(in: scene, visitor: &visitor))
    #expect(selected.id == "first")
    #expect(visitor.visits == 1)
    #expect(probe.builds == 0)
  }

  @Test func setA354EqualTitlesStillLaunchTheExplicitlySelectedWindowOwner() async throws {
    // Hypothesis: selection or root closure erasure uses a shared display title
    // instead of the explicit scene ID and invokes the first window's action.
    let probe = SceneBoundaryProbe()
    let scene = SceneBuilder.buildArray([
      WindowGroup("Same title", id: "alpha") { Button("Alpha") { probe.first += 1 } },
      WindowGroup("Same title", id: "beta") { Button("Beta") { probe.second += 1 } },
    ])
    let selection = try #require(collectWindowSceneSelections(from: scene).last)
    let terminal = SceneBoundaryTerminal()
    let result = try await selection.run(
      sessionName: "setA354", resources: resources(terminal, keys: [.init(.return)]),
      stateContainer: StateContainer(
        initialState: SceneSessionState(), invalidationIdentities: [selection.rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [selection.rootIdentity]))
    #expect(result.exitReason == .inputEnded)
    #expect(probe.first == 0 && probe.second == 1)
    #expect(terminal.frames.first?.raster.lines.joined().contains("Beta") == true)
    #expect(selection.rootIdentity == testIdentity("App", "beta"))
  }

  @Test func setA355ExitPolicyCopiesCannotMutateTheirSiblingConfigurations() {
    // Hypothesis: copying a WindowGroup shares mutable exit-policy storage,
    // allowing one launch's policy to alter another launch of the same content.
    let base = WindowGroup("Policy", id: "policy") { Text("Body") }
    let disabled = base.exitOnKeys([]).windowSceneConfiguration()
    let custom = base.exitOnKey(.escape).windowSceneConfiguration()
    let original = base.windowSceneConfiguration()
    #expect(original.exitKeyBindings == .default)
    #expect(disabled.exitKeyBindings == .none)
    #expect(custom.exitKeyBindings == ExitKeyBindings([.init(.escape)]))
    #expect(original.rootIdentity == disabled.rootIdentity)
    #expect(original.rootIdentity == custom.rootIdentity)
  }

  @Test func setA356RepeatedSceneTraversalsResetTheirDefaultMarker() {
    // Hypothesis: type-erased scene storage retains traversal state, so a later
    // manifest loses its default flag after selection already visited the tree.
    let scene = AnyScene(
      SceneBuilder.buildArray([
        WindowGroup("One", id: "one") { Text("1") },
        WindowGroup("Two", id: "two") { Text("2") },
      ]))
    let first = collectWindowSceneDescriptors(from: scene)
    _ = collectWindowSceneSelections(from: scene)
    let repeated = collectWindowSceneDescriptors(from: scene)
    #expect(repeated == first)
    #expect(repeated.map(\.isDefault) == [true, false])
  }

  @Test func setA357EmptyExitReplacementLetsFormerChordsReachFocusedHandlers() async throws {
    // Hypothesis: chaining an empty exit policy leaves a previously configured
    // chord in the run loop's exit matcher instead of replacing the set.
    let probe = SceneBoundaryProbe()
    let key = KeyPress(.character("q"), modifiers: .ctrl)
    let scene = WindowGroup("Replacement") {
      Text("Receiver").focusable(true).onKeyPress(.any) { received in
        guard received == key else { return .ignored }
        probe.first += 1
        return .handled
      }
    }.exitOnKeys([key]).exitOnKeys([])
    let result = try await run(scene, number: 357, keys: [key, key])
    #expect(result.exitReason == .inputEnded)
    #expect(probe.first == 2)
  }

  @Test func setA358CommandOwnedTerminationKeepsItsProgrammaticReason() async throws {
    // Hypothesis: a handled command discards its pending programmatic exit or
    // misreports it as the competing configured key's user-exit request.
    let probe = SceneBoundaryProbe()
    let chord = KeyPress(.functionKey(2))
    let scene = WindowGroup("Commands") {
      SceneBoundaryTerminationCommand(probe: probe)
    }.exitOnKeys([chord])
    let result = try await run(scene, number: 358, keys: [chord])
    #expect(probe.first == 1)
    #expect(probe.terminationAccepted)
    #expect(result.exitReason == .programmatic)
    #expect(probe.terminations == [.programmatic])
  }

  @Test func setA359InactiveSiblingScopeCannotClaimTheActiveWindowsExitChord() async throws {
    // Hypothesis: scene-wide registration makes a visible but inactive sibling
    // command intercept an exit key outside its own focus chain.
    let probe = SceneBoundaryProbe()
    let exit = KeyPress(.character("q"), modifiers: .ctrl)
    let scene = WindowGroup("Scope") {
      HStack {
        Panel(id: "active") { Text("First").focusable(true) }
        Panel(id: "inactive") { Text("Second").focusable(true) }
          .keyCommand("Wrong owner", key: .character("q"), modifiers: .ctrl) { probe.first += 1 }
      }
    }.exitOnKeys([exit])
    let result = try await run(scene, number: 359, keys: [exit])
    #expect(result.exitReason == .userExit(exit))
    #expect(probe.first == 0)
  }

  @Test func setA360PrimarySharedReaderEOFDrainsItsFinalLeasedActions() async throws {
    // Hypothesis: primary EOF retires the input lease before its final queued
    // events are dispatched, silently dropping the terminal's last burst.
    let probe = SceneBoundaryProbe()
    let input = SharedSceneInputReader(
      terminal: SceneBoundaryInput(keys: [.init(.return), .init(.return), .init(.return)]),
      attached: true, endsSession: true)
    let result = try await run(
      WindowGroup("Final burst") { Button("Count") { probe.first += 1 } },
      number: 360, terminal: SceneBoundaryTerminal(), input: input)
    #expect(result.exitReason == .inputEnded)
    #expect(probe.first == 3)
  }

  @Test func setA361BrowserIngressEOFDoesNotTerminateTheTerminalOwnedSession() async throws {
    // Hypothesis: completion of one merged ingress ends the scene although its
    // owning terminal still has a live input channel and registered handlers.
    let probe = SceneBoundaryProbe()
    let terminal = SceneBoundaryTerminal()
    let terminalInput = InjectedTerminalInputReader()
    let input = SharedSceneInputReader(terminal: terminalInput, attached: true, endsSession: true)
    input.attachBrowser(SceneBoundaryEmptyBrowserInput())
    let task = Task {
      try await run(
        WindowGroup("Ingress") { Button("Still alive") { probe.first += 1 } },
        number: 361, terminal: terminal, input: input)
    }
    defer {
      input.finish()
      terminalInput.finish()
      task.cancel()
    }
    await terminal.firstPresentation.wait()
    try Task.checkCancellation()
    terminalInput.send(.key(.init(.return)))
    try await wait(on: probe.changed) { probe.first == 1 }
    terminalInput.finish()
    #expect(try await task.value.exitReason == .inputEnded)
    #expect(probe.first == 1)
  }

  @Test func setA362ExitDecisionFencesLaterEventsInTheAlreadyQueuedBurst() async throws {
    // Hypothesis: input draining continues dispatching buffered actions after
    // an earlier event has committed to terminating the session.
    let probe = SceneBoundaryProbe()
    let exit = KeyPress(.escape)
    let result = try await run(
      WindowGroup("Fence") { Button("Late") { probe.first += 1 } }.exitOnKeys([exit]),
      number: 362, keys: [exit, .init(.return), .init(.return)])
    #expect(result.exitReason == .userExit(exit))
    #expect(probe.first == 0)
  }

  @Test func setA363ConcurrentHostedStartWaitersShareOneLiveGraph() async throws {
    // Hypothesis: reentrant start creates another graph/input consumer instead
    // of waiting for the existing run task, duplicating lifecycle or actions.
    let probe = SceneBoundaryProbe()
    let session = try hosted(probe)
    let first = Task { try await session.start() }
    let second = Task { try await session.start() }
    defer {
      session.stop()
      first.cancel()
      second.cancel()
    }
    try await wait(on: probe.changed) { probe.frames.last?.contains("First=0") == true }
    session.send(.key(.init(.return)))
    try await wait(on: probe.changed) { probe.frames.last?.contains("First=1") == true }
    #expect(probe.appearances == 1)
    #expect(probe.first == 1)
    _ = try await session.stopAndWait()
    #expect(try await first.value == .inputEnded)
    #expect(try await second.value == .inputEnded)
  }

  @Test func setA364StoppingOneSameIDHostCannotTearDownItsLivePeer() async throws {
    // Hypothesis: two retained hosts with identical scene IDs share teardown
    // registries, so stopping one retires the other's handlers or state.
    let left = SceneBoundaryProbe()
    let right = SceneBoundaryProbe()
    let first = try hosted(left)
    let second = try hosted(right)
    let firstTask = Task { try await first.start() }
    let secondTask = Task { try await second.start() }
    defer {
      first.stop()
      second.stop()
      firstTask.cancel()
      secondTask.cancel()
    }
    try await wait(on: left.changed) { !left.frames.isEmpty }
    try await wait(on: right.changed) { !right.frames.isEmpty }
    _ = try await first.stopAndWait()
    second.send(.key(.init(.return)))
    try await wait(on: right.changed) { right.frames.last?.contains("First=1") == true }
    #expect(left.first == 0 && right.first == 1)
    #expect(first.currentFocusPresentation == .none)
    #expect(second.currentFocusPresentation.semantics == .activate)
    _ = try await second.stopAndWait()
    #expect(try await firstTask.value == .inputEnded)
    #expect(try await secondTask.value == .inputEnded)
  }

  @Test func setA365DirectInputQueuedBeforeHostedStartSurvivesSubscriberInstallation() async throws
  {
    // Hypothesis: installing the run loop's input subscriber clears host events
    // that arrived after construction but before start was awaited.
    let probe = SceneBoundaryProbe()
    let session = try hosted(probe)
    session.send([.key(.init(.return)), .key(.init(.return))])
    let task = Task { try await session.start() }
    defer {
      session.stop()
      task.cancel()
    }
    try await wait(on: probe.changed) { probe.frames.last?.contains("First=2") == true }
    #expect(probe.first == 2)
    _ = try await session.stopAndWait()
    #expect(try await task.value == .inputEnded)
  }

  @Test func setA366CanceledUserExitCannotSuppressSubsequentUnavoidableEOF() async throws {
    // Hypothesis: cancellation remains latched after one exit request and
    // suppresses the independent EOF request or repeats its notification.
    let probe = SceneBoundaryProbe()
    let exit = KeyPress(.escape)
    let scene = WindowGroup("Cancellation") {
      Button("After cancellation") { probe.first += 1 }
        .onTerminationRequest { request in
          probe.terminations.append(request)
          return .cancel
        }
    }.exitOnKeys([exit])
    let result = try await run(scene, number: 366, keys: [exit, .init(.return)])
    #expect(result.exitReason == .inputEnded)
    #expect(probe.first == 1)
    #expect(probe.terminations == [.userExit(exit), .inputEnded])
  }

  @Test func setA367HostedResizeRetainsTheFocusedControlAndItsStateOwner() async throws {
    // Hypothesis: native size refresh recreates the scene root or seeds initial
    // focus again, moving a later activation to the first control.
    let probe = SceneBoundaryProbe()
    let session = try hosted(probe)
    let task = Task { try await session.start() }
    defer {
      session.stop()
      task.cancel()
    }
    try await wait(on: probe.changed) { !probe.frames.isEmpty }
    session.send([.key(.init(.tab)), .key(.init(.return))])
    try await wait(on: probe.changed) { probe.frames.last?.contains("Second=1") == true }
    let focus = session.currentFocusPresentation.focusedIdentity
    session.surface.updateSurfaceSize(.init(width: 38, height: 12))
    session.requestSurfaceRefresh()
    try await wait(on: probe.changed) { probe.sizes.last == .init(width: 38, height: 12) }
    #expect(session.currentFocusPresentation.focusedIdentity == focus)
    session.send(.key(.init(.return)))
    try await wait(on: probe.changed) { probe.frames.last?.contains("Second=2") == true }
    #expect(probe.first == 0 && probe.second == 2)
    #expect(probe.appearances == 1)
    _ = try await session.stopAndWait()
    #expect(try await task.value == .inputEnded)
  }

  @Test func setA368DeferredRawModeFollowsAttachmentWithoutDuplicateTransitions() throws {
    // Hypothesis: requesting raw mode while detached is forgotten, or repeated
    // attachment calls enter/leave the physical terminal more than once.
    let terminal = SceneBoundaryTerminal()
    let shared = SharedSceneSurface(terminal: terminal, terminalIsAttached: false)
    try shared.enableRawMode()
    #expect(terminal.rawEnables == 0)
    try shared.setTerminalAttached(true)
    try shared.setTerminalAttached(true)
    try shared.setTerminalAttached(false)
    try shared.setTerminalAttached(false)
    #expect(terminal.rawEnables == 1 && terminal.rawDisables == 1)
    try shared.disableRawMode()
    try shared.setTerminalAttached(true)
    #expect(terminal.rawEnables == 1 && terminal.rawDisables == 1)
  }

  @Test func setA369TerminalReattachmentRepaintsWithoutDiscardingBrowserDamage() throws {
    // Hypothesis: a shared damage object clears both host deltas on reattach,
    // or preserves a terminal delta whose predecessor was never displayed.
    let terminal = SceneBoundaryTerminal()
    let browser = SceneBoundaryTerminal()
    let shared = SharedSceneSurface(terminal: terminal, terminalIsAttached: true)
    shared.attachBrowser(browser, isConnected: { true })
    _ = try shared.present(frame(sequence: 0))
    try shared.setTerminalAttached(false)
    _ = try shared.present(frame(sequence: 1))
    try shared.setTerminalAttached(true)
    let current = frame(sequence: 2)
    _ = try shared.present(current)
    #expect(terminal.frames.map(\.sequence) == [0, 2])
    #expect(terminal.frames.last?.rasterDamage == nil)
    #expect(browser.frames.last?.rasterDamage == current.rasterDamage)
    _ = try shared.present(frame(sequence: 3))
    #expect(terminal.frames.last?.rasterDamage == current.rasterDamage)
  }

  @Test func setA370SecondaryTerminalFailureCannotAbortItsBrowserPresentation() throws {
    // Hypothesis: a detachable secondary host propagates a terminal failure
    // after successfully presenting to the browser, or primary failures vanish.
    let terminal = SceneBoundaryTerminal()
    terminal.failsPresentation = true
    let browser = SceneBoundaryTerminal()
    let secondary = SharedSceneSurface(
      terminal: terminal, terminalIsAttached: true, toleratesTerminalDetach: true)
    secondary.attachBrowser(browser, isConnected: { true })
    _ = try secondary.present(frame(sequence: 0))
    _ = try secondary.present(frame(sequence: 1))
    #expect(!secondary.terminalIsAttached)
    #expect(browser.frames.map(\.sequence) == [0, 1])
    #expect(terminal.presentationAttempts == 1)
    let primary = SharedSceneSurface(terminal: terminal, terminalIsAttached: true)
    #expect(throws: SceneBoundaryFailure.presentation) {
      _ = try primary.present(frame(sequence: 2))
    }
  }

  @Test func setA371SharedGridArbitratesEachAxisAndPreservesTerminalGraphics() {
    // Hypothesis: arbitration chooses an entire host size/capability bundle,
    // overflowing one viewport or replacing physical-terminal pixel metrics.
    let terminal = SceneBoundaryTerminal()
    terminal.size = .init(width: 80, height: 12)
    terminal.pitch = .init(width: 8, height: 16)
    let browser = SceneBoundaryTerminal()
    browser.size = .init(width: 30, height: 40)
    browser.pitch = .init(width: 15, height: 23)
    browser.pointer = .init(supportsHover: true, supportsPreciseScroll: true)
    let shared = SharedSceneSurface(terminal: terminal, terminalIsAttached: true)
    shared.attachBrowser(browser, isConnected: { true })
    let layout = shared.captureHostLayoutConfiguration()
    #expect(layout.size == .init(width: 30, height: 12))
    #expect(layout.graphics.cellPixelSize == terminal.pitch)
    #expect(layout.pointer == browser.pointer)
    #expect(shared.supportsUserExit)
  }

  @Test func setA372SharedEndpointRetainsItsOwnersConfigurationAndCallbacks() {
    // Hypothesis: wrapping resources for shared hosting reconstructs defaults
    // and drops render mode, diagnostics, or focus notifications.
    let probe = SceneBoundaryProbe()
    let original = SceneSessionResources(
      presentationSurface: SceneBoundaryTerminal(),
      terminalInputReader: SceneBoundaryInput(keys: []),
      surfaceName: "owner", environmentValues: ["marker": "retained"],
      runtimeConfiguration: .init(debug: true), renderMode: .sync,
      focusPresentationHandler: { _ in probe.first += 1 })
    original.runtimeIssueSink = .init { issue in probe.issueCodes.append(issue.code) }
    let endpoint = SharedSceneEndpoint(
      descriptor: .init(id: "secondary", title: nil, isDefault: false),
      resources: original, isPrimary: false)
    defer { endpoint.stop() }
    #expect(endpoint.resources.surfaceName == "owner")
    #expect(endpoint.resources.environmentValues["marker"] == "retained")
    #expect(endpoint.resources.runtimeConfiguration.debug)
    #expect(endpoint.resources.renderMode == .sync)
    endpoint.resources.focusPresentationHandler?(.none)
    endpoint.resources.runtimeIssueSink?.report(
      .init(severity: .warning, code: "probe", message: "probe"))
    #expect(probe.first == 1)
    #expect(probe.issueCodes == ["probe"])
  }

  @Test func setA373PreferredWidthChangeInvalidatesOnlyItsConfirmedSlackAxis() {
    // Hypothesis: slack validation is global, retaining stale width evidence
    // or discarding valid height evidence when only width content changes.
    var slack = HostedSurfaceConfirmedSlack()
    slack.update(
      preferredGridSize: .init(width: 4, height: 2), renderedGridSize: .init(width: 12, height: 8))
    slack.update(
      preferredGridSize: .init(width: 6, height: 2), renderedGridSize: .init(width: 6, height: 2))
    #expect(slack.confirmedPreferredWidth(proposed: 12, preferred: 6, rendered: 6) == nil)
    #expect(slack.confirmedPreferredHeight(proposed: 8, preferred: 2, rendered: 2) == 2)
  }

  @Test func setA374OneAxisGrowthProbeCarriesTheOtherAxesResolvedSize() {
    // Hypothesis: probing saturated width uses stale render height or fallback
    // height instead of the independently resolved intrinsic height.
    let result = HostedSurfaceSizeNegotiator(
      cellSize: .init(width: 8, height: 16), preferredGridSize: .init(width: 5, height: 2),
      renderedGridSize: .init(width: 5, height: 9)
    ).negotiate(proposedWidth: 96, proposedHeight: nil)
    #expect(result.size == .init(width: 40, height: 32))
    #expect(result.probeGridSize == .init(width: 12, height: 2))
  }

  @Test func setA375MissingMeasurementRetiresEarlierSlackEvidence() {
    // Hypothesis: a missing preferred-size measurement preserves stale slack
    // that incorrectly suppresses a fresh growth probe after content returns.
    var slack = HostedSurfaceConfirmedSlack()
    slack.update(
      preferredGridSize: .init(width: 4, height: 2), renderedGridSize: .init(width: 10, height: 8))
    slack.update(preferredGridSize: nil, renderedGridSize: .init(width: 4, height: 2))
    let result = HostedSurfaceSizeNegotiator(
      cellSize: .init(width: 8, height: 16), preferredGridSize: .init(width: 4, height: 2),
      renderedGridSize: .init(width: 4, height: 2), confirmedSlack: slack
    ).negotiate(proposedWidth: 80, proposedHeight: 128)
    #expect(result.probeGridSize == .init(width: 10, height: 8))
  }

  private func run<S: Scene>(_ scene: S, number: Int, keys: [KeyPress]) async throws
    -> RunLoopResult<SceneSessionState>
  {
    try await run(
      scene, number: number, terminal: SceneBoundaryTerminal(),
      input: SceneBoundaryInput(keys: keys))
  }

  private func run<S: Scene>(
    _ scene: S, number: Int, terminal: SceneBoundaryTerminal, input: any TerminalInputReading
  ) async throws -> RunLoopResult<SceneSessionState> {
    let selections = collectWindowSceneSelections(from: scene)
    try #require(selections.count == 1)
    let selection = try #require(selections.first)
    return try await selection.run(
      sessionName: "setA\(number)",
      resources: SceneSessionResources(presentationSurface: terminal, terminalInputReader: input),
      stateContainer: StateContainer(
        initialState: SceneSessionState(), invalidationIdentities: [selection.rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [selection.rootIdentity]))
  }

  private func resources(_ terminal: SceneBoundaryTerminal, keys: [KeyPress])
    -> SceneSessionResources
  {
    SceneSessionResources(
      presentationSurface: terminal, terminalInputReader: SceneBoundaryInput(keys: keys))
  }

  private func hosted(_ probe: SceneBoundaryProbe) throws -> HostedSceneSession {
    try HostedSceneSession(
      for: SceneBoundaryHostedApp(probe: probe), sceneID: "retained",
      surface: HostedRasterSurface(
        surfaceSize: .init(width: 30, height: 8), appearance: .fallback,
        frameDelivery: .assumedMainActor,
        onFrame: { frame in
          probe.frames.append(frame.raster.lines.joined(separator: "\n"))
          probe.sizes.append(frame.raster.size)
        }))
  }

  private func wait(
    on signal: MainActorConditionSignal, _ predicate: @escaping @MainActor () -> Bool
  ) async throws {
    await signal.wait(until: predicate)
    try Task.checkCancellation()
  }

  private func frame(sequence: UInt64) -> SemanticHostFrame {
    .init(
      sequence: sequence, raster: .init(size: .init(width: 3, height: 1), lines: ["abc"]),
      semantics: .init(), focusedIdentity: nil, rasterDamage: .init(dirtyRows: [0]))
  }
}

@MainActor
private final class SceneBoundaryProbe {
  let changed = MainActorConditionSignal()
  var builds = 0
  var first = 0 { didSet { changed.notify() } }
  var second = 0
  var appearances = 0
  var frames: [String] = [] { didSet { changed.notify() } }
  var sizes: [CellSize] = [] { didSet { changed.notify() } }
  var terminations: [TerminationRequest] = []
  var terminationAccepted = false
  var issueCodes: [String] = []
}

private struct SceneBoundaryDuplicateApp: App {
  var body: some Scene {
    WindowGroup("Unique", id: "unique") { Text("Requested") }
    WindowGroup("Duplicate one", id: "duplicate") { Text("One") }
    WindowGroup("Duplicate two", id: "duplicate") { Text("Two") }
  }
}

private struct SceneBoundaryTerminationCommand: View {
  let probe: SceneBoundaryProbe
  @Environment(\.requestTermination) private var requestTermination
  var body: some View {
    Panel(id: "terminate-command") { Text("Focus").focusable(true) }
      .keyCommand("Terminate", key: .functionKey(2), modifiers: []) {
        probe.first += 1
        probe.terminationAccepted = requestTermination()
      }
      .onTerminationRequest { request in
        probe.terminations.append(request)
        return .allow
      }
  }
}

private struct SceneBoundaryDeferredScene: Scene {
  let probe: SceneBoundaryProbe
  var body: some Scene {
    probe.builds += 1
    return WindowGroup("Unvisited") { Text("Unvisited") }
  }
}

@MainActor
private struct SceneBoundarySelectionVisitor: WindowSceneConfigurationVisitor {
  var visits = 0
  mutating func visit<Content: View>(
    descriptor: SceneDescriptor, configuration: WindowSceneConfiguration<Content>
  ) -> WindowSceneConfigurationVisitResult<SceneDescriptor> {
    visits += 1
    return .finish(descriptor)
  }
}

private struct SceneBoundaryHostedApp: App {
  let probe: SceneBoundaryProbe?
  nonisolated init() { probe = nil }
  init(probe: SceneBoundaryProbe) { self.probe = probe }
  var body: some Scene {
    WindowGroup("Retained", id: "retained") { SceneBoundaryCounter(probe: probe) }
  }
}

private struct SceneBoundaryCounter: View {
  let probe: SceneBoundaryProbe?
  @State private var first = 0
  @State private var second = 0
  var body: some View {
    VStack {
      Button("First=\(first)") {
        first += 1
        probe?.first += 1
      }
      Button("Second=\(second)") {
        second += 1
        probe?.second += 1
      }
    }.onAppear { probe?.appearances += 1 }
  }
}

private final class SceneBoundaryInput: TerminalInputReading {
  let keys: [KeyPress]
  init(keys: [KeyPress]) { self.keys = keys }
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for key in keys { continuation.yield(.key(key)) }
      continuation.finish()
    }
  }
}

private final class SceneBoundaryEmptyBrowserInput: ScopedInputReading {
  func scopedInputEvents() -> AsyncStream<ScopedInputEvent> { AsyncStream { $0.finish() } }
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}

private enum SceneBoundaryFailure: Error, Equatable { case presentation }

private final class SceneBoundaryTerminal: PresentationSurface, SemanticHostFramePresentationSurface
{
  let firstPresentation = AsyncEvent()
  var size = CellSize(width: 40, height: 12)
  var pitch: PixelSize? = nil
  var pointer = PointerInputCapabilities.cellOnly
  var frames: [SemanticHostFrame] = []
  var rawEnables = 0
  var rawDisables = 0
  var presentationAttempts = 0
  var failsPresentation = false
  var surfaceSize: CellSize { size }
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init(cellPixelSize: pitch) }
  var pointerInputCapabilities: PointerInputCapabilities { pointer }
  let appearance = TerminalAppearance.fallback
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let supportsUserExit = true
  func enableRawMode() throws { rawEnables += 1 }
  func disableRawMode() throws { rawDisables += 1 }
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    try present(
      .init(
        sequence: UInt64(frames.count), raster: surface, semantics: .init(), focusedIdentity: nil))
  }
  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    presentationAttempts += 1
    if failsPresentation { throw SceneBoundaryFailure.presentation }
    frames.append(frame)
    firstPresentation.fire()
    return .rasterHostMetrics(for: frame.raster, damage: frame.rasterDamage)
  }
}
