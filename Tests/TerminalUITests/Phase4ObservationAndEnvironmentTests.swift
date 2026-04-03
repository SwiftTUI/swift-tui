import Observation
import Testing

@testable import Core
@_spi(Runners) @testable import TerminalUI
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
    bridge.prune(keeping: renderer.liveIdentitySnapshot())

    var hiddenContext = ResolveContext(identity: testIdentity("Root"))
    hiddenContext.observationBridge = bridge
    _ = renderer.render(
      ConditionalObservableRoot(showCounter: false, model: model),
      context: hiddenContext
    )
    bridge.prune(keeping: renderer.liveIdentitySnapshot())
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

  @Test(
    "geometry reader closures invalidate the root when sibling previews depend on observable state")
  func geometryReaderClosuresInvalidateTheRootWhenSiblingPreviewsDependOnObservableState() throws {
    let model = Phase4SelectionModel()
    let invalidator = Phase4RecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let renderer = DefaultRenderer()
    var initialContext = ResolveContext(identity: testIdentity("Root"))
    initialContext.observationBridge = bridge

    let initialArtifacts = renderer.render(
      GeometryReaderSelectionWorkbench(model: model),
      context: initialContext,
      proposal: .init(width: 32, height: 4)
    )
    let initialSurface = initialArtifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(initialSurface.contains("Mode browser"))
    #expect(initialSurface.contains("Browser Pane"))

    model.selection = "outline"

    #expect(invalidator.requests == [[testIdentity("Root")]])

    var updatedContext = ResolveContext(
      identity: testIdentity("Root"),
      invalidatedIdentities: invalidator.requests[0].union([testIdentity("SelectionHeader")])
    )
    updatedContext.observationBridge = bridge

    let updatedArtifacts = renderer.render(
      GeometryReaderSelectionWorkbench(model: model),
      context: updatedContext,
      proposal: .init(width: 32, height: 4)
    )
    let updatedSurface = updatedArtifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(updatedSurface.contains("Mode outline"))
    #expect(updatedSurface.contains("Outline Pane"))
    #expect(!updatedSurface.contains("Browser Pane"))
  }

  @Test("for each row builders observe row models read inside their content")
  func forEachRowBuildersObserveRowModelsReadInsideTheirContent() {
    let rows = [
      Phase4ObservableRow(id: 1, title: "Alpha"),
      Phase4ObservableRow(id: 2, title: "Beta"),
    ]
    let invalidator = Phase4RecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let renderer = DefaultRenderer()
    var initialContext = ResolveContext(identity: testIdentity("Root"))
    initialContext.observationBridge = bridge

    _ = renderer.render(
      ObservableRowsView(rows: rows),
      context: initialContext
    )

    rows[1].title = "Gamma"

    #expect(invalidator.requests == [[testIdentity("Root", "VStack[0]").explicitID(2)]])

    var updatedContext = ResolveContext(
      identity: testIdentity("Root"),
      invalidatedIdentities: invalidator.requests[0]
    )
    updatedContext.observationBridge = bridge

    let updatedArtifacts = renderer.render(
      ObservableRowsView(rows: rows),
      context: updatedContext
    )

    #expect(updatedArtifacts.rasterSurface.lines.contains("Alpha"))
    #expect(updatedArtifacts.rasterSurface.lines.contains("Gamma"))
    #expect(updatedArtifacts.diagnostics.measuredNodesReused >= 1)
    #expect(updatedArtifacts.diagnostics.placedNodesReused >= 1)
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

  @Test(
    "observable button actions stay invalidated through wrapper bodies that share the same identity"
  )
  func observableButtonActionsStayInvalidatedThroughWrapperBodies() throws {
    let model = Phase4ObservableCounter()
    let invalidator = Phase4RecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let renderer = DefaultRenderer()
    let actionRegistry = LocalActionRegistry()

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localActionRegistry: actionRegistry,
      applyEnvironmentValues: true
    )
    initialContext.observationBridge = bridge

    let initialArtifacts = renderer.render(
      ObservableAlertCounterView(
        model: model,
        initialAlertPresented: false
      ),
      context: initialContext
    )
    #expect(initialArtifacts.resolvedTree.descendant(withText: "Count 0") != nil)

    #expect(actionRegistry.dispatch(identity: testIdentity("PrimaryAction")))
    #expect(model.count == 1)

    let invalidatedIdentities = invalidator.requests.reduce(into: Set<Identity>()) {
      partial, request in
      partial.formUnion(request)
    }
    #expect(!invalidatedIdentities.isEmpty)

    var updatedContext = initialContext
    updatedContext.invalidatedIdentities = invalidatedIdentities
    let updatedArtifacts = renderer.render(
      ObservableAlertCounterView(
        model: model,
        initialAlertPresented: false
      ),
      context: updatedContext
    )

    #expect(updatedArtifacts.resolvedTree.descendant(withText: "Count 1") != nil)
  }

  @Test(
    "alert action buttons preserve the original state owner when dismissed from stored builder children"
  )
  func alertActionButtonsPreserveTheOriginalStateOwner() throws {
    let invalidator = Phase4RecordingInvalidator()
    let actionRegistry = LocalActionRegistry()
    let renderer = DefaultRenderer()
    let invalidationProxy = ResolveInvalidationProxy(invalidator: invalidator)

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localActionRegistry: actionRegistry,
      applyEnvironmentValues: true
    )
    initialContext.invalidationProxy = invalidationProxy

    let initialArtifacts = renderer.render(
      PresentedAlertDismissView(),
      context: initialContext
    )
    #expect(
      initialArtifacts.resolvedTree.descendant(withIdentity: testIdentity("CancelAction")) != nil)

    #expect(actionRegistry.dispatch(identity: testIdentity("CancelAction")))

    let invalidatedIdentities = invalidator.requests.reduce(into: Set<Identity>()) {
      partial, request in
      partial.formUnion(request)
    }
    #expect(!invalidatedIdentities.isEmpty)

    var updatedContext = initialContext
    updatedContext.invalidatedIdentities = invalidatedIdentities
    let updatedArtifacts = renderer.render(
      PresentedAlertDismissView(),
      context: updatedContext
    )

    #expect(
      updatedArtifacts.resolvedTree.descendant(withIdentity: testIdentity("CancelAction")) == nil)
  }

  @Test("alert action buttons rerender observed models inside wrapped content")
  func alertActionButtonsRerenderObservedModelsInsideWrappedContent() throws {
    let model = Phase4ObservableCounter()
    model.count = 3

    let invalidator = Phase4RecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let renderer = DefaultRenderer()
    let actionRegistry = LocalActionRegistry()

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localActionRegistry: actionRegistry,
      applyEnvironmentValues: true
    )
    initialContext.observationBridge = bridge

    let initialArtifacts = renderer.render(
      ObservableAlertCounterView(
        model: model,
        initialAlertPresented: true
      ),
      context: initialContext
    )
    #expect(initialArtifacts.resolvedTree.descendant(withText: "Count 3") != nil)

    #expect(actionRegistry.dispatch(identity: testIdentity("ResetAction")))
    #expect(model.count == 0)

    let invalidatedIdentities = invalidator.requests.reduce(into: Set<Identity>()) {
      partial, request in
      partial.formUnion(request)
    }
    #expect(!invalidatedIdentities.isEmpty)

    var updatedContext = initialContext
    updatedContext.invalidatedIdentities = invalidatedIdentities
    let updatedArtifacts = renderer.render(
      ObservableAlertCounterView(
        model: model,
        initialAlertPresented: true
      ),
      context: updatedContext
    )

    #expect(updatedArtifacts.resolvedTree.descendant(withText: "Count 0") != nil)
  }

  @Test("ForEach content closures preserve the original state owner")
  func forEachContentClosuresPreserveTheOriginalStateOwner() throws {
    let invalidator = Phase4RecordingInvalidator()
    let actionRegistry = LocalActionRegistry()
    let renderer = DefaultRenderer()
    let invalidationProxy = ResolveInvalidationProxy(invalidator: invalidator)

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localActionRegistry: actionRegistry,
      applyEnvironmentValues: true
    )
    initialContext.invalidationProxy = invalidationProxy

    let initialArtifacts = renderer.render(
      ForEachActionCounterView(),
      context: initialContext
    )
    #expect(initialArtifacts.resolvedTree.descendant(withText: "Count 0") != nil)

    #expect(actionRegistry.dispatch(identity: testIdentity("ForEachAction")))

    let invalidatedIdentities = collectedInvalidatedIdentities(from: invalidator)
    #expect(!invalidatedIdentities.isEmpty)

    var updatedContext = initialContext
    updatedContext.invalidatedIdentities = invalidatedIdentities
    let updatedArtifacts = renderer.render(
      ForEachActionCounterView(),
      context: updatedContext
    )

    #expect(updatedArtifacts.resolvedTree.descendant(withText: "Count 1") != nil)
  }

  @Test("EnvironmentReader content closures preserve the original state owner")
  func environmentReaderContentClosuresPreserveTheOriginalStateOwner() throws {
    let invalidator = Phase4RecordingInvalidator()
    let actionRegistry = LocalActionRegistry()
    let renderer = DefaultRenderer()
    let invalidationProxy = ResolveInvalidationProxy(invalidator: invalidator)

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localActionRegistry: actionRegistry,
      applyEnvironmentValues: true
    )
    initialContext.invalidationProxy = invalidationProxy

    let initialArtifacts = renderer.render(
      EnvironmentReaderActionCounterView(),
      context: initialContext
    )
    #expect(initialArtifacts.resolvedTree.descendant(withText: "Count 0") != nil)

    #expect(actionRegistry.dispatch(identity: testIdentity("EnvironmentReaderAction")))

    let invalidatedIdentities = collectedInvalidatedIdentities(from: invalidator)
    #expect(!invalidatedIdentities.isEmpty)

    var updatedContext = initialContext
    updatedContext.invalidatedIdentities = invalidatedIdentities
    let updatedArtifacts = renderer.render(
      EnvironmentReaderActionCounterView(),
      context: updatedContext
    )

    #expect(updatedArtifacts.resolvedTree.descendant(withText: "Count 1") != nil)
  }

  @Test("NavigationSplitView preserves stored builder panels under stateful actions")
  func navigationSplitViewPreservesStoredBuilderPanels() throws {
    let invalidator = Phase4RecordingInvalidator()
    let actionRegistry = LocalActionRegistry()
    let renderer = DefaultRenderer()
    let invalidationProxy = ResolveInvalidationProxy(invalidator: invalidator)

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localActionRegistry: actionRegistry,
      applyEnvironmentValues: true
    )
    initialContext.invalidationProxy = invalidationProxy

    let initialArtifacts = renderer.render(
      NavigationSplitActionCounterView(),
      context: initialContext
    )
    #expect(initialArtifacts.resolvedTree.descendant(withText: "Count 0") != nil)

    #expect(actionRegistry.dispatch(identity: testIdentity("NavigationSplitAction")))

    let invalidatedIdentities = collectedInvalidatedIdentities(from: invalidator)
    #expect(!invalidatedIdentities.isEmpty)

    var updatedContext = initialContext
    updatedContext.invalidatedIdentities = invalidatedIdentities
    let updatedArtifacts = renderer.render(
      NavigationSplitActionCounterView(),
      context: updatedContext
    )

    #expect(updatedArtifacts.resolvedTree.descendant(withText: "Count 1") != nil)
  }

  @Test("OutlineGroup row builders preserve the original state owner")
  func outlineGroupRowBuildersPreserveTheOriginalStateOwner() throws {
    let invalidator = Phase4RecordingInvalidator()
    let actionRegistry = LocalActionRegistry()
    let renderer = DefaultRenderer()
    let invalidationProxy = ResolveInvalidationProxy(invalidator: invalidator)

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localActionRegistry: actionRegistry,
      applyEnvironmentValues: true
    )
    initialContext.invalidationProxy = invalidationProxy

    let initialArtifacts = renderer.render(
      OutlineActionCounterView(),
      context: initialContext
    )
    #expect(initialArtifacts.resolvedTree.descendant(withText: "Count 0") != nil)

    #expect(actionRegistry.dispatch(identity: testIdentity("OutlineAction")))

    let invalidatedIdentities = collectedInvalidatedIdentities(from: invalidator)
    #expect(!invalidatedIdentities.isEmpty)

    var updatedContext = initialContext
    updatedContext.invalidatedIdentities = invalidatedIdentities
    let updatedArtifacts = renderer.render(
      OutlineActionCounterView(),
      context: updatedContext
    )

    #expect(updatedArtifacts.resolvedTree.descendant(withText: "Count 1") != nil)
  }

  @Test("WindowGroup stored content preserves deferred authoring scope")
  func windowGroupStoredContentPreservesDeferredAuthoringScope() throws {
    let actionRegistry = LocalActionRegistry()
    let renderer = DefaultRenderer()
    let scopeIdentity = testIdentity("WindowGroupAuthoring")
    let scopeRecorder = Phase4ScopeRecorder()
    let authoringScope = AuthoringContext(
      viewIdentity: scopeIdentity,
      focusedValues: FocusedValues()
    )

    let scene = withAuthoringContext(authoringScope) {
      WindowGroup("Scoped Window") {
        ForEach([0], id: \.self) { _ in
          Button("Primary") {
            scopeRecorder.identity = currentAuthoringContext()?.viewIdentity
          }
          .id(testIdentity("WindowGroupForEachAction"))
        }
      }
    }

    let configurations = collectWindowSceneConfigurations(from: scene)
    #expect(configurations.count == 1)
    let configuration = try #require(configurations.first)
    let artifacts = renderer.render(
      configuration.makeRootView(),
      context: .init(
        identity: configuration.rootIdentity,
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(artifacts.resolvedTree.descendant(withText: "Primary") != nil)
    #expect(actionRegistry.dispatch(identity: testIdentity("WindowGroupForEachAction")))
    #expect(scopeRecorder.identity == scopeIdentity)
  }

  @Test("Picker arrow-key handlers preserve the original state owner")
  func pickerArrowKeyHandlersPreserveTheOriginalStateOwner() throws {
    let invalidator = Phase4RecordingInvalidator()
    let keyRegistry = LocalKeyHandlerRegistry()
    let renderer = DefaultRenderer()
    let invalidationProxy = ResolveInvalidationProxy(invalidator: invalidator)

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("StatefulPicker")

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues,
      localKeyHandlerRegistry: keyRegistry,
      applyEnvironmentValues: true
    )
    initialContext.invalidationProxy = invalidationProxy

    let initialArtifacts = renderer.render(
      StatefulPickerCounterView(),
      context: initialContext
    )
    #expect(initialArtifacts.resolvedTree.descendant(withText: "Selection 0") != nil)

    #expect(keyRegistry.dispatch(identity: testIdentity("StatefulPicker"), event: .arrowDown))

    let invalidatedIdentities = collectedInvalidatedIdentities(from: invalidator)
    #expect(!invalidatedIdentities.isEmpty)

    var updatedContext = initialContext
    updatedContext.invalidatedIdentities = invalidatedIdentities
    let updatedArtifacts = renderer.render(
      StatefulPickerCounterView(),
      context: updatedContext
    )

    #expect(updatedArtifacts.resolvedTree.descendant(withText: "Selection 2") != nil)
  }

  @Test("Stepper arrow-key handlers preserve the original state owner")
  func stepperArrowKeyHandlersPreserveTheOriginalStateOwner() throws {
    let invalidator = Phase4RecordingInvalidator()
    let keyRegistry = LocalKeyHandlerRegistry()
    let renderer = DefaultRenderer()
    let invalidationProxy = ResolveInvalidationProxy(invalidator: invalidator)

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("StatefulStepper")

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues,
      localKeyHandlerRegistry: keyRegistry,
      applyEnvironmentValues: true
    )
    initialContext.invalidationProxy = invalidationProxy

    let initialArtifacts = renderer.render(
      StatefulStepperCounterView(),
      context: initialContext
    )
    #expect(initialArtifacts.resolvedTree.descendant(withText: "Value 0") != nil)

    #expect(keyRegistry.dispatch(identity: testIdentity("StatefulStepper"), event: .arrowRight))

    let invalidatedIdentities = collectedInvalidatedIdentities(from: invalidator)
    #expect(!invalidatedIdentities.isEmpty)

    var updatedContext = initialContext
    updatedContext.invalidatedIdentities = invalidatedIdentities
    let updatedArtifacts = renderer.render(
      StatefulStepperCounterView(),
      context: updatedContext
    )

    #expect(updatedArtifacts.resolvedTree.descendant(withText: "Value 1") != nil)
  }

  @MainActor
  @Test("runtime rerenders bindable observable models across committed frames")
  func runtimeRerendersBindableObservableModels() async throws {
    let model = Phase4ObservableForm()
    let terminal = Phase4RecordingTerminalHost()

    let result = try await runTestSceneSession(
      scene: WindowGroup("Observable Form") {
        BindableFormView(model: model)
      },
      sessionName: "Phase4ObservationAndEnvironmentTests.BindableRuntime",
      terminalHost: terminal,
      inputReader: Phase4ScriptedInputReader(
        events: [
          KeyPress(.return),
          KeyPress(.character("H")),
          KeyPress(.character("i")),
          KeyPress(.character("c"), modifiers: .ctrl),
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
  @Test("runtime rerenders gallery-like observable button taps immediately")
  func runtimeRerendersGalleryLikeObservableButtonTapsImmediately() async throws {
    let model = Phase4GalleryLikeModel()
    let terminal = Phase4RecordingTerminalHost()
    let rootIdentity = testIdentity("GalleryLikeRoot")
    let terminalSize = terminal.surfaceSize
    let view = GalleryLikeObservableSceneView(model: model)

    let primaryRect = try #require(
      interactionRect(
        containingText: "Primary",
        in: view,
        rootIdentity: rootIdentity,
        terminalSize: terminalSize
      )
    )

    let result = try await runObservableRuntimeHarness(
      rootIdentity: rootIdentity,
      terminal: terminal,
      events: [
        .mouse(.init(kind: .down(.primary), location: centerPoint(of: primaryRect))),
        .mouse(.init(kind: .up(.primary), location: centerPoint(of: primaryRect))),
        .key(.character("q")),
      ],
      viewBuilder: {
        GalleryLikeObservableSceneView(model: model)
      }
    )

    #expect(result.exitReason == .quitKey)
    #expect(model.primaryCount == 1)
    #expect(terminal.frames.contains(where: { $0.contains("Pressed 1 times") }))
    let lastFrame = try #require(terminal.frames.last)
    #expect(lastFrame.contains("Pressed 1 times"))
  }

  @MainActor
  @Test("runtime refreshes environment readers when terminal appearance changes")
  func runtimeRefreshesEnvironmentReadersWhenTerminalAppearanceChanges() async throws {
    let darkAppearance = TerminalAppearance.fallback
    let lightAppearance = TerminalAppearance(
      foregroundColor: hexColor("#161A20"),
      backgroundColor: hexColor("#F6F7F9"),
      tintColor: .blue,
      colorScheme: .light,
      source: .fallback
    )

    let terminal = Phase4MutableAppearanceTerminalHost(
      initialAppearance: darkAppearance,
      nextAppearance: lightAppearance
    )

    let result = try await runTestSceneSession(
      scene: WindowGroup("Appearance Probe") {
        AppearanceProbeView()
      },
      sessionName: "Phase4ObservationAndEnvironmentTests.AppearanceRuntime",
      terminalHost: terminal,
      inputReader: Phase4ScriptedInputReader(
        events: [
          .return,
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

    let result = try await runTestSceneSession(
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

@Observable
private final class Phase4SelectionModel: @unchecked Sendable {
  var selection = "browser"
}

@Observable
private final class Phase4ObservableRow: Identifiable, @unchecked Sendable {
  let id: Int
  var title: String

  init(id: Int, title: String) {
    self.id = id
    self.title = title
  }
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

private struct ObservableAlertCounterView: View {
  @Bindable var model: Phase4ObservableCounter
  @State private var isAlertPresented: Bool

  init(
    model: Phase4ObservableCounter,
    initialAlertPresented: Bool
  ) {
    self.model = model
    _isAlertPresented = State(initialValue: initialAlertPresented)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Primary") {
        model.count += 1
      }
      .id(testIdentity("PrimaryAction"))

      Text("Count \(model.count)")
    }
    .alert(
      "Reset counter?",
      isPresented: $isAlertPresented,
      actions: {
        Button("Reset") {
          model.count = 0
        }
        .id(testIdentity("ResetAction"))

        Button("Cancel") {
          isAlertPresented = false
        }
        .id(testIdentity("CancelAction"))
      },
      message: {
        Text("Reset the observed counter?")
      }
    )
  }
}

private struct PresentedAlertDismissView: View {
  @State private var isAlertPresented = true

  var body: some View {
    Text("Background")
      .alert(
        "Dismiss me?",
        isPresented: $isAlertPresented,
        actions: {
          Button("Cancel") {
            isAlertPresented = false
          }
          .id(testIdentity("CancelAction"))
        },
        message: {
          Text("Close the alert")
        }
      )
  }
}

private struct ForEachActionCounterView: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      ForEach([0], id: \.self) { _ in
        Button("Primary") {
          count += 1
        }
        .id(testIdentity("ForEachAction"))
      }

      Text("Count \(count)")
    }
  }
}

private struct EnvironmentReaderActionCounterView: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      EnvironmentReader(\.colorScheme) { _ in
        Button("Primary") {
          count += 1
        }
        .id(testIdentity("EnvironmentReaderAction"))
      }

      Text("Count \(count)")
    }
  }
}

private struct NavigationSplitActionCounterView: View {
  @State private var count = 0

  var body: some View {
    NavigationSplitView {
      Button("Primary") {
        count += 1
      }
      .id(testIdentity("NavigationSplitAction"))
    } detail: {
      Text("Count \(count)")
    }
  }
}

private struct OutlineActionCounterView: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      OutlineGroup(
        [Phase4OutlineNode(id: 1, title: "Primary", children: nil)],
        children: \.children
      ) { node in
        Button(node.title) {
          count += 1
        }
        .id(testIdentity("OutlineAction"))
      }

      Text("Count \(count)")
    }
  }
}

private struct StatefulPickerCounterView: View {
  @State private var selection = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Picker("Mode", selection: $selection) {
        Text("Zero").tag(0)
        Text("Two").tag(2)
      }
      .id(testIdentity("StatefulPicker"))
      .pickerStyle(.inline)

      Text("Selection \(selection)")
    }
  }
}

private struct StatefulStepperCounterView: View {
  @State private var value = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Stepper("Count", value: $value, in: 0...2)
        .id(testIdentity("StatefulStepper"))

      Text("Value \(value)")
    }
  }
}

@Observable
private final class Phase4GalleryLikeModel: @unchecked Sendable {
  var activeTab = "controls"
  var selectedControlDemo = "buttons"
  var primaryCount = 0

  func increment() {
    primaryCount += 1
  }

  func reset() {
    activeTab = "controls"
    selectedControlDemo = "buttons"
    primaryCount = 0
  }
}

private struct GalleryLikeObservableSceneView: View {
  @Bindable var model: Phase4GalleryLikeModel
  @State private var isResetAlertPresented = false

  init(model: Phase4GalleryLikeModel) {
    _model = Bindable(model)
  }

  var body: some View {
    GeometryReader { geometry in
      shell(contentHeight: max(0, geometry.size.height - 4))
    }
  }

  private func shell(contentHeight: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Gallery")
        .bold()
        .padding(.init(horizontal: 1, vertical: 0))
      Divider()
      TabView(selection: $model.activeTab) {
        workbenchSurface(
          selection: $model.selectedControlDemo,
          entries: [
            ("Buttons", "buttons"),
            ("Inputs", "inputs"),
            ("Value Controls", "values"),
          ],
          title: "Buttons",
          subtitle: "Filled primary actions with plain secondary actions."
        ) {
          controlsPreview
        }
        .tabItem("Controls")
        .tag("controls")
      }
      .frame(
        maxWidth: .infinity,
        minHeight: .finite(contentHeight),
        idealHeight: .finite(contentHeight),
        maxHeight: .finite(contentHeight),
        alignment: .topLeading
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .alert(
      "Reset gallery state?",
      isPresented: $isResetAlertPresented,
      actions: {
        Button("Reset", role: .destructive) {
          model.reset()
        }
        Button("Cancel", role: .cancel) {
          isResetAlertPresented = false
        }
      },
      message: {
        Text("Clears the interactive control and appearance samples?")
      }
    )
  }

  @ViewBuilder
  private var controlsPreview: some View {
    switch model.selectedControlDemo {
    case "inputs":
      Text("Inputs")
    case "values":
      Text("Values")
    default:
      VStack(alignment: .leading, spacing: 1) {
        HStack(alignment: .center, spacing: 1) {
          Button("Primary") {
            model.increment()
          }
          Button("Reset", role: .destructive) {
            isResetAlertPresented = true
          }
          Button("Plain") {
            model.increment()
            model.increment()
          }
          .buttonStyle(.plain)
        }
        Text("Pressed \(model.primaryCount) times")
          .foregroundStyle(.separator)
      }
    }
  }

  private func workbenchSurface<Content: View>(
    selection: Binding<String>,
    entries: [(String, String)],
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Picker("", selection: selection) {
        ForEach(entries, id: \.1) { entry in
          Text(entry.0).tag(entry.1)
        }
      }
      .pickerStyle(.segmented)
      .padding(.init(horizontal: 1, vertical: 0))

      Divider()
      previewPanel(
        title: title,
        subtitle: subtitle
      ) {
        content()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func previewPanel<Content: View>(
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .bold()
        Text(subtitle)
          .lineLimit(2)
          .truncationMode(.tail)
          .foregroundStyle(.separator)
      }
      Divider()
      content()
      Spacer(minLength: 0)
    }
    .padding(1)
    .frame(
      minWidth: .finite(24),
      maxWidth: .infinity,
      maxHeight: .infinity,
      alignment: .topLeading
    )
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

private struct GeometryReaderSelectionWorkbench: View {
  let model: Phase4SelectionModel

  var body: some View {
    GeometryReader { _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("Mode \(model.selection)")
          .id(testIdentity("SelectionHeader"))
        if model.selection == "browser" {
          Text("Browser Pane")
        } else {
          Text("Outline Pane")
        }
      }
    }
  }
}

private struct ObservableRowsView: View {
  let rows: [Phase4ObservableRow]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(rows) { row in
        Text(row.title)
      }

      Text("Stable sibling")
    }
  }
}

private struct Phase4OutlineNode: Identifiable {
  let id: Int
  let title: String
  let children: [Phase4OutlineNode]?
}

private func collectedInvalidatedIdentities(
  from invalidator: Phase4RecordingInvalidator
) -> Set<Identity> {
  invalidator.requests.reduce(into: Set<Identity>()) { partial, request in
    partial.formUnion(request)
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

@MainActor
private final class Phase4ScopeRecorder {
  var identity: Identity?
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
  private let scriptedEvents: [KeyPress]

  init(events: [KeyPress]) {
    scriptedEvents = events
  }

  convenience init(events: [KeyEvent]) {
    self.init(events: events.map { KeyPress($0) })
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class Phase4ScriptedTerminalInputReader: TerminalInputReading {
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

private final class Phase4EmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

@MainActor
private func runObservableRuntimeHarness<V: View>(
  rootIdentity: Identity,
  terminal: Phase4RecordingTerminalHost,
  events: [InputEvent],
  viewBuilder: @escaping () -> V
) async throws -> RunLoopResult<Int> {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = terminal.appearance
  environmentValues.terminalSize = terminal.surfaceSize

  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    terminalHost: terminal,
    terminalInputReader: Phase4ScriptedTerminalInputReader(events: events),
    signalReader: Phase4EmptySignalReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    ),
    focusTracker: FocusTracker(
      invalidationIdentities: [rootIdentity]
    ),
    environmentValues: environmentValues,
    proposal: .init(width: terminal.surfaceSize.width, height: terminal.surfaceSize.height),
    viewBuilder: { _, _ in
      viewBuilder()
    }
  )

  return try await runLoop.run()
}

@MainActor
private func interactionRect<V: View>(
  containingText text: String,
  in view: V,
  rootIdentity: Identity,
  terminalSize: Size
) -> Rect? {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalSize = terminalSize

  let artifacts = DefaultRenderer().render(
    view,
    context: .init(
      identity: rootIdentity,
      environmentValues: environmentValues,
      applyEnvironmentValues: true
    ),
    proposal: .init(width: terminalSize.width, height: terminalSize.height)
  )

  guard let textNode = artifacts.resolvedTree.descendant(withText: text) else {
    return nil
  }

  var candidate: Identity? = textNode.identity
  while let identity = candidate {
    if let rect = artifacts.semanticSnapshot.interactionRegions.first(where: {
      $0.identity == identity
    })?
    .rect {
      return rect
    }
    candidate = identity.parent
  }

  return nil
}

private func centerPoint(
  of rect: Rect
) -> Point {
  Point(
    x: rect.origin.x + max(0, rect.size.width - 1) / 2,
    y: rect.origin.y + max(0, rect.size.height - 1) / 2
  )
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
