@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
private final class ReloadEvents {
  var values: [String] = []
  var reload: (() -> Void)?
}

private struct StaticReloadRoot: View {
  let version: String
  let events: ReloadEvents
  @State private var count = 0

  var body: some View {
    VStack {
      Text("\(version) count=\(count)")
      Button("Increment") { count += 1 }
    }
    .onAppear { events.values.append("appear \(version) \(count)") }
    .onDisappear { events.values.append("disappear \(version)") }
  }
}

private struct AsyncReloadRoot: View {
  let version: String
  let events: ReloadEvents
  @State private var count = 0
  var body: some View {
    Button("\(version) count=\(count)") {
      events.values.append("action \(version)")
      count += 1
    }
    .onAppear { events.values.append("appear \(version) \(count)") }
    .onDisappear { events.values.append("disappear \(version)") }
    .task {
      events.values.append("start \(version)")
      await suspendUntilCancelled()
      events.values.append("cancel \(version)")
    }
    .onKeyPress { key in
      guard key.key == .character("r") else { return .ignored }
      events.reload?()
      return .handled
    }
  }
}

@MainActor
@Suite("Static hot-reload generations", .serialized, FailOnSoundnessViolationGrowth())
struct HotReloadHostTests {
  @Test(.timeLimit(.minutes(1))) func asynchronousLoopReplacesHandlersAndCancelsOldTasks()
    async throws
  {
    let events = ReloadEvents()
    let session = HotReloadSession(
      content: HotReloadGeneration {
        AsyncReloadRoot(version: "one", events: events)
      })
    let surface = RecordingPresentationSurface(surfaceSize: .init(width: 40, height: 6))
    let identity = Identity(components: ["AsyncReload"])
    let input = ScriptedAutonomousWakeInputReader(
      frameSignal: surface.frameSignal,
      steps: [
        .awaitCondition { surface.frames.last?.contains("one count=0") == true },
        .press(KeyPress(.return)),
        .awaitCondition { surface.frames.last?.contains("one count=1") == true },
        .press(KeyPress(.character("r"))),
        .awaitCondition { surface.frames.last?.contains("two count=1") == true },
        .press(KeyPress(.return)),
        .awaitCondition { surface.frames.last?.contains("two count=2") == true },
      ])
    let loop = RunLoop(
      rootIdentity: identity, presentationSurface: surface, inputReader: input,
      signalReader: ImmediateFinishSignalReader(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity]),
      proposal: .init(width: 40, height: 6)
    ) { _, _ in HotReloadHost(session: session) }
    loop.installHotReloadSession(session)
    events.reload = { [weak loop] in
      do {
        try loop?.replaceHotReloadGeneration(
          HotReloadGeneration {
            AsyncReloadRoot(version: "two", events: events)
          })
      } catch { Issue.record("Reload failed: \(error)") }
    }
    defer { events.reload = nil }
    _ = try await loop.run()
    #expect(events.values.filter { $0.hasPrefix("action") } == ["action one", "action two"])
    #expect(events.values.contains("cancel one"))
    let disappeared = try #require(events.values.firstIndex(of: "disappear one"))
    let appeared = try #require(events.values.firstIndex(of: "appear two 1"))
    #expect(disappeared < appeared)
    #expect(loop.lifecycleCoordinator.activeTaskCount == 0)
    #expect(session.lastReport.isEmpty)
  }

  @Test func replacementRestoresStateBeforeAppearAndRehearsalHasNoLifecycle() throws {
    let events = ReloadEvents()
    let session = HotReloadSession(
      content: HotReloadGeneration {
        StaticReloadRoot(version: "one", events: events)
      })
    let surface = RecordingPresentationSurface(surfaceSize: .init(width: 40, height: 6))
    let identity = Identity(components: ["HotReloadTest"])
    let loop = RunLoop(
      rootIdentity: identity, presentationSurface: surface,
      terminalInputReader: InjectedTerminalInputReader(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity]),
      proposal: .init(width: 40, height: 6)
    ) { _, _ in HotReloadHost(session: session) }
    loop.installHotReloadSession(session)
    var frames = 0
    loop.scheduler.requestInvalidation(of: [identity])
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(events.values == ["appear one 0"])
    _ = loop.handle(.input(.key(KeyPress(.return))))
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(surface.frames.last?.contains("one count=1") == true)
    let originalRoot = session.generationRoot
    try session.replace(
      with: HotReloadGeneration {
        StaticReloadRoot(version: "two", events: events)
      }, proposal: .init(width: 40, height: 6))
    #expect(events.values == ["appear one 0"])
    session.finishCommittedReplay()
    #expect(session.awaitingCommit)
    #expect(session.lastReport.isEmpty)
    try loop.renderPendingFrames(renderedFrames: &frames)
    session.finishCommittedReplay()
    #expect(session.generationRoot != originalRoot)
    #expect(surface.frames.last?.contains("two count=1") == true)
    #expect(events.values == ["appear one 0", "disappear one", "appear two 1"])
    #expect(session.lastReport.isEmpty)
  }

  @Test func identicalRootKeepsRasterAndFailedRehearsalKeepsLiveGeneration() throws {
    let events = ReloadEvents()
    let generation = HotReloadGeneration { StaticReloadRoot(version: "same", events: events) }
    let session = HotReloadSession(content: generation)
    let renderer = DefaultRenderer()
    let identity = Identity(components: ["HotReloadSnapshot"])
    let invalidator = FrameScheduler()
    var context = ResolveContext(identity: identity)
    context.invalidationProxy = .init(invalidator: invalidator)
    let first = renderer.render(
      HotReloadHost(session: session), context: context,
      proposal: .init(width: 30, height: 5))
    #expect(throws: HotReloadSwapError.schemaDidNotConverge) {
      try session.replace(
        with: generation, proposal: .init(width: 30, height: 5), maximumAttempts: 1)
    }
    #expect(session.generation == 0)
    try session.replace(with: generation, proposal: .init(width: 30, height: 5))
    renderer.forceRootEvaluation()
    context.invalidatedIdentities = [identity]
    let second = renderer.render(
      HotReloadHost(session: session), context: context,
      proposal: .init(width: 30, height: 5))
    session.finishCommittedReplay()
    #expect(first.rasterSurface == second.rasterSurface)
    #expect(session.lastReport.isEmpty)
  }
}
