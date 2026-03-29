import Observation
import Testing

@testable import Core
@testable import TerminalUI
@testable import TerminalUIScenes
@testable import View

@MainActor
@Suite(.serialized)
struct Phase4ObservationAndEnvironmentTests {
  @Test("observable child mutations invalidate only the observed subtree identity")
  func observableChildMutationsInvalidateOnlyObservedSubtree() throws {
    let model = Phase4ObservableCounter()
    let invalidator = Phase4RecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let renderer = DefaultRenderer()
    var initialContext = ResolveContext(identity: testIdentity("Root"))
    initialContext.observationBridge = bridge

    let initialArtifacts = renderer.render(
      ObservableCounterRoot(model: model),
      context: initialContext
    )
    let observedIdentity = try #require(
      initialArtifacts.resolvedTree.descendant(withText: "Count 0")?.identity
    )

    model.count = 1

    #expect(invalidator.requests == [[observedIdentity]])

    var updatedContext = ResolveContext(
      identity: testIdentity("Root"),
      invalidatedIdentities: invalidator.requests[0]
    )
    updatedContext.observationBridge = bridge

    let updatedArtifacts = renderer.render(
      ObservableCounterRoot(model: model),
      context: updatedContext
    )
    #expect(updatedArtifacts.rasterSurface.lines.contains("Count 1"))
    #expect(updatedArtifacts.diagnostics.measuredNodesReused >= 1)
    #expect(updatedArtifacts.diagnostics.placedNodesReused >= 1)
  }

  @Test("observation bridge suppresses stale callbacks after repeated rerenders")
  func observationBridgeSuppressesStaleCallbacks() {
    let model = Phase4ObservableCounter()
    let invalidator = Phase4RecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let renderer = DefaultRenderer()
    var context = ResolveContext(identity: testIdentity("ObservedRoot"))
    context.observationBridge = bridge

    _ = renderer.render(
      ObservableCounterLabel(model: model),
      context: context
    )
    _ = renderer.render(
      ObservableCounterLabel(model: model),
      context: context
    )

    model.count = 1

    #expect(invalidator.requests == [[testIdentity("ObservedRoot")]])
  }

  @Test("pruned observed identities stop invalidating removed subtrees")
  func prunedObservedIdentitiesStopInvalidatingRemovedSubtrees() throws {
    let model = Phase4ObservableCounter()
    let invalidator = Phase4RecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let renderer = DefaultRenderer()

    var shownContext = ResolveContext(identity: testIdentity("Root"))
    shownContext.observationBridge = bridge
    _ = renderer.render(
      ConditionalObservableRoot(showCounter: true, model: model),
      context: shownContext
    )
    let shownResolvedTreeIndex = try #require(renderer.latestResolvedTreeIndex())
    bridge.prune(keeping: shownResolvedTreeIndex)

    var hiddenContext = ResolveContext(identity: testIdentity("Root"))
    hiddenContext.observationBridge = bridge
    _ = renderer.render(
      ConditionalObservableRoot(showCounter: false, model: model),
      context: hiddenContext
    )
    let hiddenResolvedTreeIndex = try #require(renderer.latestResolvedTreeIndex())
    bridge.prune(keeping: hiddenResolvedTreeIndex)
    invalidator.clear()

    model.count = 1

    #expect(invalidator.requests.isEmpty)
  }

  @Test("bindable projection edits observable models through text field controls")
  func bindableProjectionEditsObservableModels() throws {
    let model = Phase4ObservableForm()
    let invalidator = Phase4RecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let renderer = DefaultRenderer()
    let keyRegistry = LocalKeyHandlerRegistry()

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localKeyHandlerRegistry: keyRegistry,
      applyEnvironmentValues: true
    )
    initialContext.observationBridge = bridge

    let initialArtifacts = renderer.render(
      BindableFormView(model: model),
      context: initialContext
    )
    let fieldIdentity = try #require(initialArtifacts.semanticSnapshot.focusRegions.first?.identity)

    #expect(keyRegistry.dispatch(identity: fieldIdentity, event: .character("H")))
    #expect(invalidator.requests == [[testIdentity("Root")]])

    var updatedContext = ResolveContext(
      identity: testIdentity("Root"),
      invalidatedIdentities: invalidator.requests[0],
      localKeyHandlerRegistry: keyRegistry,
      applyEnvironmentValues: true
    )
    updatedContext.observationBridge = bridge
    _ = renderer.render(
      BindableFormView(model: model),
      context: updatedContext
    )

    invalidator.clear()
    #expect(keyRegistry.dispatch(identity: fieldIdentity, event: .character("i")))
    #expect(model.name == "Hi")
    #expect(invalidator.requests == [[testIdentity("Root")]])

    var finalContext = ResolveContext(
      identity: testIdentity("Root"),
      invalidatedIdentities: invalidator.requests[0],
      localKeyHandlerRegistry: keyRegistry,
      applyEnvironmentValues: true
    )
    finalContext.observationBridge = bridge
    let finalArtifacts = renderer.render(
      BindableFormView(model: model),
      context: finalContext
    )

    #expect(finalArtifacts.rasterSurface.lines.contains(where: { $0.contains("Name: Hi") }))
  }

  @Test("environment reader closures observe injected observable models")
  func environmentReaderClosuresObserveInjectedObservableModels() {
    let model = Phase4ObservableCounter()
    let invalidator = Phase4RecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    var environmentValues = EnvironmentValues()
    environmentValues.phase4ObservableCounter = model

    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues
    )
    context.observationBridge = bridge

    let renderer = DefaultRenderer()
    _ = renderer.render(
      EnvironmentReader(\.phase4ObservableCounter) { model in
        Text("Count \(model.count)")
      },
      context: context
    )

    model.count = 1

    #expect(invalidator.requests == [[testIdentity("Root")]])
  }

  @Test("nested environment overrides stay local to their subtree snapshots")
  func nestedEnvironmentOverridesStayLocal() throws {
    var rootEnvironmentValues = EnvironmentValues()
    rootEnvironmentValues.phase4Theme = .init(
      accent: "root-accent",
      emphasis: "root-emphasis"
    )

    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        EnvironmentReader(\.phase4Theme) { theme in
          Text("Root: \(theme.accent)-\(theme.emphasis)")
        }
        Group {
          EnvironmentReader(\.phase4Theme) { theme in
            Text("Nested: \(theme.accent)-\(theme.emphasis)")
          }
          .id(testIdentity("NestedReader"))
        }
        .transformEnvironment(\.phase4Theme) { theme in
          theme.emphasis = "nested-deep"
        }
        .environment(
          \.phase4Theme,
          .init(accent: "nested-accent", emphasis: "nested-base")
        )
        EnvironmentReader(\.phase4Theme) { theme in
          Text("Sibling: \(theme.accent)-\(theme.emphasis)")
        }
        .id(testIdentity("SiblingReader"))
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: rootEnvironmentValues
      )
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "Root: root-accent-root-emphasis",
        "Nested: nested-accent-nested-deep",
        "Sibling: root-accent-root-emphasis",
      ]
    )

    let nestedNode = try #require(
      artifacts.resolvedTree.descendant(withIdentity: testIdentity("NestedReader"))
    )
    let siblingNode = try #require(
      artifacts.resolvedTree.descendant(withIdentity: testIdentity("SiblingReader"))
    )
    let themeKey = String(reflecting: Phase4ThemeKey.self)

    #expect(
      nestedNode.environmentSnapshot.values[themeKey]
        == String(reflecting: Phase4Theme(accent: "nested-accent", emphasis: "nested-deep"))
    )
    #expect(
      siblingNode.environmentSnapshot.values[themeKey]
        == String(reflecting: Phase4Theme(accent: "root-accent", emphasis: "root-emphasis"))
    )
  }

  @Test("draw-only environment changes update style snapshots without changing text layout output")
  func drawOnlyEnvironmentChangesUpdateStyleSnapshots() {
    let renderer = DefaultRenderer()

    var firstEnvironment = EnvironmentValues()
    firstEnvironment.foregroundStyle = AnyShapeStyle(Color.blue)

    var secondEnvironment = EnvironmentValues()
    secondEnvironment.foregroundStyle = AnyShapeStyle(Color.red)

    let firstArtifacts = renderer.render(
      Text("Styled"),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: firstEnvironment
      )
    )
    let secondArtifacts = renderer.render(
      Text("Styled"),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: secondEnvironment
      )
    )

    #expect(firstArtifacts.rasterSurface.lines == secondArtifacts.rasterSurface.lines)
    #expect(
      firstArtifacts.resolvedTree.environmentSnapshot.style.foregroundStyle
        == AnyShapeStyle(Color.blue)
    )
    #expect(
      secondArtifacts.resolvedTree.environmentSnapshot.style.foregroundStyle
        == AnyShapeStyle(Color.red)
    )
  }

  @MainActor
  @Test("runtime rerenders bindable observable models across committed frames")
  func runtimeRerendersBindableObservableModels() async throws {
    let model = Phase4ObservableForm()
    let terminal = Phase4RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Observable Form") {
        BindableFormView(model: model)
      },
      sessionName: "Phase4ObservationAndEnvironmentTests.BindableRuntime",
      terminalHost: terminal,
      inputReader: Phase4ScriptedInputReader(
        events: [
          .enter,
          .character("H"),
          .character("i"),
          .ctrlC,
        ]
      ),
      signalReader: Phase4EmptySignalReader()
    )

    #expect(result.exitReason == .ctrlC)
    #expect(model.name == "Hi")
    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("Name: Hi"))
  }

  @MainActor
  @Test("runtime refreshes environment readers when terminal appearance changes")
  func runtimeRefreshesEnvironmentReadersWhenTerminalAppearanceChanges() async throws {
    let darkAppearance = TerminalAppearance.fallback
    let lightAppearance = TerminalAppearance(
      foregroundColor: .init(hex: 0x161A20),
      backgroundColor: .init(hex: 0xF6F7F9),
      tintColor: .blue,
      colorScheme: .light,
      source: .fallback
    )

    let terminal = Phase4MutableAppearanceTerminalHost(
      initialAppearance: darkAppearance,
      nextAppearance: lightAppearance
    )

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Appearance Probe") {
        AppearanceProbeView()
      },
      sessionName: "Phase4ObservationAndEnvironmentTests.AppearanceRuntime",
      terminalHost: terminal,
      inputReader: Phase4ScriptedInputReader(
        events: [
          .enter,
          .character("q"),
        ]
      ),
      signalReader: Phase4EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)
    let firstFrame = try #require(terminal.frames.first)
    let lastFrame = try #require(terminal.frames.last)
    #expect(firstFrame.contains("Scheme dark"))
    #expect(lastFrame.contains("Scheme light"))
  }

  @MainActor
  @Test("runtime exposes terminal surface size through environment readers")
  func runtimeExposesTerminalSurfaceSizeThroughEnvironmentReaders() async throws {
    let terminal = Phase4RecordingTerminalHost()

    let result = try await MultiSceneLauncher.run(
      scene: WindowGroup("Terminal Size Probe") {
        TerminalSizeProbeView()
      },
      sessionName: "Phase4ObservationAndEnvironmentTests.TerminalSizeRuntime",
      terminalHost: terminal,
      inputReader: Phase4ScriptedInputReader(events: [.character("q")]),
      signalReader: Phase4EmptySignalReader()
    )

    #expect(result.exitReason == .quitKey)
    let firstFrame = try #require(terminal.frames.first)
    #expect(firstFrame.contains("Terminal 60x18"))
  }
}

@Observable
private final class Phase4ObservableCounter: @unchecked Sendable {
  var count = 0
}

@Observable
private final class Phase4ObservableForm: @unchecked Sendable {
  var name = ""
}

private struct Phase4Theme: Equatable, Sendable {
  var accent: String
  var emphasis: String
}

private enum Phase4ObservableCounterKey: EnvironmentKey {
  static let defaultValue = Phase4ObservableCounter()
}

private enum Phase4ThemeKey: EnvironmentKey {
  static let defaultValue = Phase4Theme(
    accent: "default-accent",
    emphasis: "default-emphasis"
  )
}

extension EnvironmentValues {
  fileprivate var phase4ObservableCounter: Phase4ObservableCounter {
    get { self[Phase4ObservableCounterKey.self] }
    set { self[Phase4ObservableCounterKey.self] = newValue }
  }

  fileprivate var phase4Theme: Phase4Theme {
    get { self[Phase4ThemeKey.self] }
    set { self[Phase4ThemeKey.self] = newValue }
  }
}

private struct ObservableCounterLabel: View {
  let model: Phase4ObservableCounter

  var body: some View {
    Text("Count \(model.count)")
  }
}

private struct ObservableCounterRoot: View {
  let model: Phase4ObservableCounter

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ObservableCounterLabel(model: model)
        .id(testIdentity("ObservedCounter"))
      Text("Stable sibling")
        .id(testIdentity("StableSibling"))
    }
  }
}

private struct ConditionalObservableRoot: View {
  let showCounter: Bool
  let model: Phase4ObservableCounter

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showCounter {
        ObservableCounterLabel(model: model)
          .id(testIdentity("ObservedCounter"))
      }
    }
  }
}

private struct BindableFormView: View {
  @Bindable var model: Phase4ObservableForm

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      TextField("Name", text: $model.name)
        .frame(width: 14, alignment: .leading)
      Text("Name: \(model.name)")
    }
  }
}

private struct AppearanceProbeView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      EnvironmentReader(\.colorScheme) { scheme in
        Text("Scheme \(scheme == .dark ? "dark" : "light")")
      }
      Button("Refresh") {}
    }
  }
}

private struct TerminalSizeProbeView: View {
  var body: some View {
    EnvironmentReader(\.terminalSize) { terminalSize in
      Text("Terminal \(terminalSize.width)x\(terminalSize.height)")
    }
  }
}

private final class Phase4RecordingInvalidator: Invalidating {
  var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }

  func clear() {
    requests.removeAll(keepingCapacity: true)
  }
}

private final class Phase4RecordingTerminalHost: TerminalHosting {
  let surfaceSize = Size(width: 60, height: 18)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []
  private var lastPresentedSurface: RasterSurface?

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: Point) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let renderer = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile)
    let rendered = renderer.render(surface)
    let plan = TerminalPresentationPlanner(capabilityProfile: capabilityProfile).plan(
      previousSurface: lastPresentedSurface,
      currentSurface: surface
    )
    frames.append(rendered)
    lastPresentedSurface = surface

    let bytesWritten: Int =
      switch plan.strategy {
      case .fullRepaint:
        TerminalPresentationMetrics.fullRepaint(
          for: surface,
          renderedOutput: rendered
        ).bytesWritten
      case .incremental:
        plan.spanUpdates.reduce(0) { partial, update in
          partial
            + update.renderedSpan.utf8.count
        }
      }

    return TerminalPresentationMetrics(
      bytesWritten: bytesWritten,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: plan.strategy == .fullRepaint ? .fullRepaint : .incremental
    )
  }
}

private final class Phase4MutableAppearanceTerminalHost: TerminalHosting {
  let surfaceSize = Size(width: 60, height: 18)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  private(set) var appearance: TerminalAppearance
  private let nextAppearance: TerminalAppearance
  private(set) var frames: [String] = []
  private var lastPresentedSurface: RasterSurface?
  private var presentationCount = 0

  init(
    initialAppearance: TerminalAppearance,
    nextAppearance: TerminalAppearance
  ) {
    appearance = initialAppearance
    self.nextAppearance = nextAppearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: Point) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let renderer = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile)
    let rendered = renderer.render(surface)
    let plan = TerminalPresentationPlanner(capabilityProfile: capabilityProfile).plan(
      previousSurface: lastPresentedSurface,
      currentSurface: surface
    )
    frames.append(rendered)
    lastPresentedSurface = surface
    presentationCount += 1
    if presentationCount == 1 {
      appearance = nextAppearance
    }

    let bytesWritten: Int =
      switch plan.strategy {
      case .fullRepaint:
        TerminalPresentationMetrics.fullRepaint(
          for: surface,
          renderedOutput: rendered
        ).bytesWritten
      case .incremental:
        plan.spanUpdates.reduce(0) { partial, update in
          partial
            + update.renderedSpan.utf8.count
        }
      }

    return TerminalPresentationMetrics(
      bytesWritten: bytesWritten,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: plan.strategy == .fullRepaint ? .fullRepaint : .incremental
    )
  }
}

private final class Phase4ScriptedInputReader: InputReading {
  private let scriptedEvents: [KeyEvent]

  init(events: [KeyEvent]) {
    scriptedEvents = events
  }

  func events() -> AsyncStream<KeyEvent> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class Phase4EmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

extension ResolvedNode {
  fileprivate func descendant(withText text: String) -> ResolvedNode? {
    if drawPayload == .text(text) {
      return self
    }

    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }

    return nil
  }

  fileprivate func descendant(withIdentity identity: Identity) -> ResolvedNode? {
    if self.identity == identity {
      return self
    }

    for child in children {
      if let match = child.descendant(withIdentity: identity) {
        return match
      }
    }

    return nil
  }
}
