@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
private final class ReloadFidelityProbe {
  var select: ((Int) -> Void)?
  var increment: (() -> Void)?
  var jump: (() -> Void)?
}

private struct ReloadFocusScrollRoot: View {
  let version: String
  let probe: ReloadFidelityProbe
  @State private var offset = ScrollCellOffset.zero

  var body: some View {
    VStack {
      Button("First") {}
      Button("Second") {}
      Text(version)
      ScrollView(.vertical, position: $offset) {
        VStack { ForEach(0..<30) { Text("line\($0)") } }
      }
    }
    .onAppear { probe.jump = { offset.y = 6 } }
  }
}

private struct ReloadTabRoot: View {
  let probe: ReloadFidelityProbe
  @State private var selection = 0
  var body: some View {
    TabView(selection: $selection) {
      Tab("A", value: 0) { ReloadTabCounter(label: "A", probe: probe).padding(0) }
      Tab("B", value: 1) { ReloadTabCounter(label: "B", probe: probe).padding(0) }
    }
    .onAppear { probe.select = { selection = $0 } }
  }
}

// STUI-506: a transparent wrapper forwards this DynamicProperty payload at
// its canonical root path, including when replaying a dormant tab.
private struct ReloadTabCounter: View, DynamicProperty {
  let label: String
  let probe: ReloadFidelityProbe
  @State private var count = 0
  var body: some View {
    Text("\(label) count=\(count)")
      .onAppear { probe.increment = { count += 1 } }
      .task { await suspendUntilCancelled() }
  }
}

private struct ReloadCounterModifier: ViewModifier, DynamicProperty {
  let probe: ReloadFidelityProbe
  @State private var count = 0
  func body(content: Content) -> some View {
    content
      .overlay { Text("forwarded=\(count)") }
      .onAppear { probe.increment = { count += 1 } }
  }
}

private struct ReloadForwardedTabRoot: View {
  let probe: ReloadFidelityProbe
  @State private var selection = 0
  var body: some View {
    TabView(selection: $selection) {
      Tab("A", value: 0) {
        Text("counter").frame(width: 20).modifier(ReloadCounterModifier(probe: probe))
      }
      Tab("B", value: 1) { Text("other tab") }
    }.onAppear { probe.select = { selection = $0 } }
  }
}

@MainActor
private final class ReloadFidelityHarness {
  let session: HotReloadSession
  let surface = RecordingPresentationSurface(surfaceSize: .init(width: 40, height: 10))
  let loop: RunLoop<Int, HotReloadHost>
  var frames = 0

  init<Content: View>(@ViewBuilder content: @escaping @MainActor () -> Content) throws {
    let session = HotReloadSession(content: HotReloadGeneration(content: content))
    self.session = session
    let identity = Identity(components: ["ReloadFidelity"])
    loop = RunLoop(
      rootIdentity: identity, presentationSurface: surface,
      terminalInputReader: InjectedTerminalInputReader(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity]),
      proposal: .init(width: 40, height: 10)
    ) { _, _ in HotReloadHost(session: session) }
    loop.installHotReloadSession(session)
    loop.scheduler.requestInvalidation(of: [identity])
    try drain()
  }
  func drain() throws { try loop.renderPendingFrames(renderedFrames: &frames) }
  func reload<Content: View>(@ViewBuilder content: @escaping @MainActor () -> Content) throws {
    try loop.replaceHotReloadGeneration(HotReloadGeneration(content: content))
    try drain()
  }
}

@MainActor
@Suite("Hot-reload runtime fidelity", .serialized, FailOnSoundnessViolationGrowth())
struct HotReloadFidelityTests {
  @Test("STUI-506: dormant forwarded DynamicProperty state retains canonical slot paths")
  func dormantForwardedModifier() throws {
    let probe = ReloadFidelityProbe()
    let harness = try ReloadFidelityHarness { ReloadForwardedTabRoot(probe: probe) }
    defer { harness.loop.lifecycleCoordinator.shutdown() }
    probe.increment?()
    try harness.drain()
    #expect(harness.surface.frames.last?.contains("forwarded=1") == true)
    probe.select?(1)
    try harness.drain()
    try harness.reload { ReloadForwardedTabRoot(probe: probe) }
    probe.select?(0)
    try harness.drain()
    #expect(
      harness.surface.frames.last?.contains("forwarded=1") == true,
      "\(harness.surface.frames.last ?? "")\n\(harness.session.lastReport)")
  }

  @Test func oneWrapperEditPreservesTheUniqueOwner() throws {
    let probe = ReloadFidelityProbe()
    let harness = try ReloadFidelityHarness { ReloadTabCounter(label: "C", probe: probe) }
    defer { harness.loop.lifecycleCoordinator.shutdown() }
    probe.increment?()
    try harness.drain()
    try harness.reload { ReloadTabCounter(label: "C", probe: probe).padding(1) }
    #expect(
      harness.surface.frames.last?.contains("C count=1") == true,
      "\(harness.session.lastReport)")
  }

  @Test func oneHundredSwapsKeepOneTaskAndABoundedLiveGraph() throws {
    let probe = ReloadFidelityProbe()
    let harness = try ReloadFidelityHarness { ReloadTabCounter(label: "C", probe: probe) }
    defer { harness.loop.lifecycleCoordinator.shutdown() }
    probe.increment?()
    try harness.drain()
    let nodeCount = harness.loop.renderer.viewGraph.nodesByNodeID.count
    for _ in 0..<100 {
      try harness.reload { ReloadTabCounter(label: "C", probe: probe) }
      #expect(harness.surface.frames.last?.contains("C count=1") == true)
      #expect(harness.loop.lifecycleCoordinator.activeTaskCount == 1)
      #expect(harness.loop.renderer.viewGraph.nodesByNodeID.count == nodeCount)
      #expect(harness.session.lastReport.isEmpty)
    }
  }

  @Test func focusAndScrollRestoreThroughRuntime() throws {
    let probe = ReloadFidelityProbe()
    let harness = try ReloadFidelityHarness { ReloadFocusScrollRoot(version: "one", probe: probe) }
    defer { harness.loop.lifecycleCoordinator.shutdown() }
    probe.jump?()
    _ = harness.loop.handle(.input(.key(KeyPress(.tab))))
    try harness.drain()
    let oldFocus = try #require(harness.loop.focusTracker.currentFocusIdentity)
    let oldRoot = try #require(harness.session.generationRoot)
    let relativeFocus = HotReloadReplay.relative(oldFocus, to: oldRoot)
    #expect(harness.surface.frames.last?.contains("line6") == true)
    try harness.reload { ReloadFocusScrollRoot(version: "two", probe: probe) }
    let newFocus = try #require(harness.loop.focusTracker.currentFocusIdentity)
    let newRoot = try #require(harness.session.generationRoot)
    #expect(newFocus != oldFocus)
    #expect(HotReloadReplay.relative(newFocus, to: newRoot) == relativeFocus)
    #expect(harness.surface.frames.last?.contains("line6") == true)
    #expect(harness.surface.frames.last?.contains("two") == true)
  }

  @Test func inactiveTabStateSurvivesAndOnlyCurrentGenerationOwnsTasks() throws {
    let probe = ReloadFidelityProbe()
    let harness = try ReloadFidelityHarness { ReloadTabRoot(probe: probe) }
    defer { harness.loop.lifecycleCoordinator.shutdown() }
    probe.increment?()
    probe.increment?()
    try harness.drain()
    #expect(harness.surface.frames.last?.contains("A count=2") == true)
    probe.select?(1)
    try harness.drain()
    #expect(harness.surface.frames.last?.contains("B count=0") == true)
    #expect(harness.loop.lifecycleCoordinator.activeTaskCount == 1)
    try harness.reload { ReloadTabRoot(probe: probe) }
    #expect(
      harness.surface.frames.last?.contains("B count=0") == true,
      "\(harness.surface.frames.last ?? "")\n\(harness.session.lastReport)")
    #expect(harness.loop.lifecycleCoordinator.activeTaskCount == 1)
    let root = try #require(harness.session.generationRoot)
    #expect(
      harness.loop.lifecycleCoordinator.activeTaskDescriptors.keys.allSatisfy {
        $0 == root || $0.isDescendant(of: root)
      })
    probe.select?(0)
    try harness.drain()
    #expect(harness.surface.frames.last?.contains("A count=2") == true)
    #expect(harness.loop.lifecycleCoordinator.activeTaskCount == 1)
  }
}
