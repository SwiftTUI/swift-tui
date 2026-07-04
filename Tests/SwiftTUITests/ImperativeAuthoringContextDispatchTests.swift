import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct ImperativeAuthoringContextDispatchTests {
  @Test(
    "keyCommand mutates the graph that dispatched it when the same view instance is hosted twice")
  func keyCommandTargetsDispatchingGraph() throws {
    let sharedView = KeyCommandScopeFixture()
    let primary = makeRunLoop(rootName: "SharedKeyCommandPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedKeyCommandSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    _ = primary.runLoop.handleKeyPress(KeyPress(.character("m"), modifiers: .ctrl))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("mutated"))
    #expect(surfaceText(secondary.host).contains("idle"))
  }

  @Test(
    "paletteCommand action mutates the graph that exposed it when the same view instance is hosted twice"
  )
  func paletteCommandTargetsDispatchingGraph() throws {
    let sharedView = PaletteCommandScopeFixture()
    let primary = makeRunLoop(rootName: "SharedPalettePrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedPaletteSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    // Capture primary's command before secondary's render overwrites the static box.
    let command = try #require(
      PaletteCommandScopeFixture.absorbed.commands.first(where: { $0.name == "Mutate" })
    )
    try renderInitial(secondary.runLoop)

    command.action()
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("mutated"))
    #expect(surfaceText(secondary.host).contains("idle"))
  }

  @Test(
    "toolbarItem button mutates the graph that activated it when the same view instance is hosted twice"
  )
  func toolbarItemTargetsDispatchingGraph() throws {
    let sharedView = ToolbarScopeFixture()
    let primary = makeRunLoop(rootName: "SharedToolbarPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedToolbarSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)
    focusLeafmostFocusable(in: primary.runLoop)

    _ = primary.runLoop.handleKeyPress(KeyPress(.space, modifiers: []))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("mutated"))
    #expect(surfaceText(secondary.host).contains("idle"))
  }

  @Test(
    "toolbarItem config without a construction-time context uses its attachment context"
  )
  func toolbarItemWithoutConstructionContextTargetsAttachmentGraph() throws {
    let fixture = ToolbarNilConstructionContextFixture()
    let primary = makeRunLoop(rootName: "NilContextToolbarPrimary") { fixture }

    try renderInitial(primary.runLoop)
    focusLeafmostFocusable(in: primary.runLoop)

    _ = primary.runLoop.handleKeyPress(KeyPress(.space, modifiers: []))
    try renderPending(primary.runLoop)

    #expect(surfaceText(primary.host).contains("mutated"))
  }

  @Test(
    "dropDestination mutates the graph that handled the paste when the same view instance is hosted twice"
  )
  func dropDestinationTargetsDispatchingGraph() throws {
    let sharedView = DropDestinationScopeFixture()
    let primary = makeRunLoop(rootName: "SharedDropPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedDropSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)
    focusLeafmostFocusable(in: primary.runLoop)

    primary.runLoop.handlePaste(PasteEvent(content: "/tmp/file.txt"))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("mutated"))
    #expect(surfaceText(secondary.host).contains("idle"))
  }

  @Test(
    "gesture callbacks mutate only the graph that received the drag when the same view instance is hosted twice"
  )
  func gestureCallbacksTargetDispatchingGraph() throws {
    let sharedView = GestureCallbackScopeFixture()
    let primary = makeRunLoop(rootName: "SharedGesturePrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedGestureSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    let region = try #require(primary.runLoop.latestSemanticSnapshot.interactionRegions.first)
    let startCell = centerPoint(of: region.rect)
    let start = Point(startCell)
    let dragged = Point(CellPoint(x: startCell.x + 4, y: startCell.y + 1))

    _ = primary.runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: start))))
    try renderPending(primary.runLoop)

    _ = primary.runLoop.handle(.input(.mouse(.init(kind: .dragged(.primary), location: dragged))))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("changed"))
    #expect(surfaceText(primary.host).contains("offset:4.0,1.0"))
    #expect(surfaceText(secondary.host).contains("idle"))
    #expect(surfaceText(secondary.host).contains("offset:0.0,0.0"))

    _ = primary.runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: dragged))))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("ended"))
    #expect(surfaceText(primary.host).contains("offset:0.0,0.0"))
    #expect(surfaceText(primary.host).contains("commits:1"))
    #expect(surfaceText(secondary.host).contains("idle"))
    #expect(surfaceText(secondary.host).contains("commits:0"))
  }

  // F08 step-4 follow-up re-tests (2026-07-04). Both were documented as
  // dispatch-time imperative-context gaps; F10 slice 4 fixed the suspected
  // mechanism for the first (FocusState.makeLocation fell back to a detached
  // local box when the authoring context carried the owner by ID only) and
  // 5cdfde32 fixed the async-tail request clobber behind it.

  @Test("@FocusState write from a keyCommand action lands and moves focus")
  func keyCommandFocusStateWriteMovesFocus() throws {
    let fixture = KeyCommandFocusWriteFixture()
    let primary = makeRunLoop(rootName: "KeyCommandFocusWrite") { fixture }

    try renderInitial(primary.runLoop)
    #expect(surfaceText(primary.host).contains("focus:first"))

    _ = primary.runLoop.handleKeyPress(KeyPress(.character("m"), modifiers: .ctrl))
    try renderPending(primary.runLoop)

    #expect(surfaceText(primary.host).contains("focus:second"))
  }

  @Test("@Environment read from a keyCommand action sees the injected value")
  func keyCommandEnvironmentReadSeesInjectedValue() throws {
    let fixture = KeyCommandEnvironmentReadFixture()
    let primary = makeRunLoop(rootName: "KeyCommandEnvRead") { fixture }

    try renderInitial(primary.runLoop)
    // Body-time read renders the injected value.
    #expect(surfaceText(primary.host).contains("body:injected"))

    _ = primary.runLoop.handleKeyPress(KeyPress(.character("e"), modifiers: .ctrl))
    try renderPending(primary.runLoop)

    #expect(surfaceText(primary.host).contains("action:injected"))
  }

  @Test("@Environment read from a Button action sees the injected value")
  func buttonActionEnvironmentReadSeesInjectedValue() throws {
    let fixture = ButtonEnvironmentReadFixture()
    let primary = makeRunLoop(rootName: "ButtonEnvRead") { fixture }

    try renderInitial(primary.runLoop)
    focusLeafmostFocusable(in: primary.runLoop)

    _ = primary.runLoop.handleKeyPress(KeyPress(.space, modifiers: []))
    try renderPending(primary.runLoop)

    #expect(surfaceText(primary.host).contains("action:injected"))
  }

  @Test(
    "onAppear mutates the graph that revealed the child when the same view instance is hosted twice"
  )
  func appearLifecycleTargetsDispatchingGraph() async throws {
    let sharedView = AppearLifecycleScopeFixture()
    let primary = makeRunLoop(rootName: "SharedAppearPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedAppearSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    _ = primary.runLoop.handleKeyPress(KeyPress(.character("a"), modifiers: .ctrl))

    try await renderUntil("appear lifecycle mutation") {
      do {
        try renderPending(primary.runLoop)
        try renderPending(secondary.runLoop)
      } catch {
        return false
      }
      return surfaceText(primary.host).contains("appeared")
        || surfaceText(secondary.host).contains("appeared")
    }

    #expect(surfaceText(primary.host).contains("appeared"))
    #expect(surfaceText(secondary.host).contains("idle"))
  }

  @Test(
    "onDisappear mutates the graph that hid the child when the same view instance is hosted twice"
  )
  func disappearLifecycleTargetsDispatchingGraph() async throws {
    let sharedView = DisappearLifecycleScopeFixture()
    let primary = makeRunLoop(rootName: "SharedDisappearPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedDisappearSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    _ = primary.runLoop.handleKeyPress(KeyPress(.character("d"), modifiers: .ctrl))

    try await renderUntil("disappear lifecycle mutation") {
      do {
        try renderPending(primary.runLoop)
        try renderPending(secondary.runLoop)
      } catch {
        return false
      }
      return surfaceText(primary.host).contains("disappeared")
        || surfaceText(secondary.host).contains("disappeared")
    }

    #expect(surfaceText(primary.host).contains("disappeared"))
    #expect(surfaceText(secondary.host).contains("idle"))
  }

  @Test(
    "onChange mutates the graph whose value changed when the same view instance is hosted twice"
  )
  func changeLifecycleTargetsDispatchingGraph() async throws {
    let sharedView = ChangeLifecycleScopeFixture()
    let primary = makeRunLoop(rootName: "SharedChangePrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedChangeSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    _ = primary.runLoop.handleKeyPress(KeyPress(.character("c"), modifiers: .ctrl))

    try await renderUntil("change lifecycle mutation") {
      do {
        try renderPending(primary.runLoop)
        try renderPending(secondary.runLoop)
      } catch {
        return false
      }
      return surfaceText(primary.host).contains("changed")
        || surfaceText(secondary.host).contains("changed")
    }

    #expect(surfaceText(primary.host).contains("changed"))
    #expect(surfaceText(primary.host).contains("count:1"))
    #expect(surfaceText(secondary.host).contains("idle"))
    #expect(surfaceText(secondary.host).contains("count:0"))
  }

  @Test(
    "task mutates the graph that started it when the same view instance is hosted twice"
  )
  func taskLifecycleTargetsDispatchingGraph() async throws {
    let sharedView = TaskLifecycleScopeFixture()
    let primary = makeRunLoop(rootName: "SharedTaskPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedTaskSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    _ = primary.runLoop.handleKeyPress(KeyPress(.character("t"), modifiers: .ctrl))

    try await renderUntil("task lifecycle mutation") {
      do {
        try renderPending(primary.runLoop)
        try renderPending(secondary.runLoop)
      } catch {
        return false
      }
      return surfaceText(primary.host).contains("tasked")
        || surfaceText(secondary.host).contains("tasked")
    }

    #expect(surfaceText(primary.host).contains("tasked"))
    #expect(surfaceText(secondary.host).contains("idle"))
  }

  @Test(
    "menu action mutates the graph that activated it when the same view instance is hosted twice")
  func menuActionTargetsDispatchingGraph() throws {
    let sharedView = MenuScopeFixture()
    let primary = makeRunLoop(rootName: "SharedMenuPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedMenuSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    #expect(primary.runLoop.localActionRegistry.dispatch(identity: testIdentity("ScopedMenu")))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("Action 1"))
    #expect(!surfaceText(secondary.host).contains("Action 1"))
  }

  @Test(
    "toggle action mutates the graph that activated it when the same view instance is hosted twice")
  func toggleActionTargetsDispatchingGraph() throws {
    let sharedView = ToggleScopeFixture()
    let primary = makeRunLoop(rootName: "SharedTogglePrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedToggleSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    #expect(primary.runLoop.localActionRegistry.dispatch(identity: testIdentity("ScopedToggle")))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("on:true"))
    #expect(surfaceText(secondary.host).contains("on:false"))
  }

  @Test(
    "disclosure action mutates the graph that activated it when the same view instance is hosted twice"
  )
  func disclosureActionTargetsDispatchingGraph() throws {
    let sharedView = DisclosureScopeFixture()
    let primary = makeRunLoop(rootName: "SharedDisclosurePrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedDisclosureSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    #expect(
      primary.runLoop.localActionRegistry.dispatch(identity: testIdentity("ScopedDisclosure")))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("expanded:true"))
    #expect(surfaceText(secondary.host).contains("expanded:false"))
  }

  @Test(
    "text field key handling mutates the graph that received it when the same view instance is hosted twice"
  )
  func textFieldKeyHandlerTargetsDispatchingGraph() throws {
    let sharedView = TextFieldScopeFixture()
    let primary = makeRunLoop(rootName: "SharedTextFieldPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedTextFieldSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    #expect(
      primary.runLoop.localKeyHandlerRegistry.dispatch(
        identity: testIdentity("ScopedTextField"),
        event: .character("x")
      )
    )
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("value:x"))
    #expect(surfaceText(secondary.host).contains("value:-"))
  }

  @Test(
    "text field paste handling mutates the graph that received it when the same view instance is hosted twice"
  )
  func textFieldPasteHandlerTargetsDispatchingGraph() throws {
    let sharedView = TextFieldScopeFixture()
    let primary = makeRunLoop(rootName: "SharedTextFieldPastePrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedTextFieldPasteSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)
    _ = primary.runLoop.focusTracker.setFocus(to: testIdentity("ScopedTextField"))

    primary.runLoop.handlePaste(PasteEvent(content: "pasted"))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("value:pasted"))
    #expect(surfaceText(secondary.host).contains("value:-"))
  }

  @Test(
    "text editor key handling mutates the graph that received it when the same view instance is hosted twice"
  )
  func textEditorKeyHandlerTargetsDispatchingGraph() throws {
    let sharedView = TextEditorScopeFixture()
    let primary = makeRunLoop(rootName: "SharedTextEditorPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedTextEditorSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    #expect(
      primary.runLoop.localKeyHandlerRegistry.dispatch(
        identity: testIdentity("ScopedTextEditor"),
        event: .character("z")
      )
    )
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("count:1"))
    #expect(surfaceText(secondary.host).contains("count:0"))
  }

  @Test(
    "stepper key handling mutates the graph that received it when the same view instance is hosted twice"
  )
  func stepperKeyHandlerTargetsDispatchingGraph() throws {
    let sharedView = StepperScopeFixture()
    let primary = makeRunLoop(rootName: "SharedStepperPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedStepperSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    #expect(
      primary.runLoop.localKeyHandlerRegistry.dispatch(
        identity: testIdentity("ScopedStepper"),
        event: .arrowRight
      )
    )
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("value:1"))
    #expect(surfaceText(secondary.host).contains("value:0"))
  }

  @Test(
    "slider key handling mutates the graph that received it when the same view instance is hosted twice"
  )
  func sliderKeyHandlerTargetsDispatchingGraph() throws {
    let sharedView = SliderScopeFixture()
    let primary = makeRunLoop(rootName: "SharedSliderPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedSliderSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    #expect(
      primary.runLoop.localKeyHandlerRegistry.dispatch(
        identity: testIdentity("ScopedSlider"),
        event: .arrowRight
      )
    )
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("value:1"))
    #expect(surfaceText(secondary.host).contains("value:0"))
  }

  @Test(
    "picker key handling mutates the graph that received it when the same view instance is hosted twice"
  )
  func pickerKeyHandlerTargetsDispatchingGraph() throws {
    let sharedView = PickerScopeFixture()
    let primary = makeRunLoop(rootName: "SharedPickerPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedPickerSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    #expect(
      primary.runLoop.localKeyHandlerRegistry.dispatch(
        identity: testIdentity("ScopedPicker"),
        event: .arrowDown
      )
    )
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("selection:two"))
    #expect(surfaceText(secondary.host).contains("selection:one"))
  }

  @Test(
    "scroll view pointer handling mutates the graph that received it when the same view instance is hosted twice"
  )
  func scrollViewPointerHandlerTargetsDispatchingGraph() throws {
    let sharedView = ScrollViewScopeFixture()
    let primary = makeRunLoop(rootName: "SharedScrollPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedScrollSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    #expect(
      primary.runLoop.localPointerHandlerRegistry.dispatch(
        routeID: primaryRouteID(for: testIdentity("ScopedScrollView")),
        event: .init(
          kind: .scrolled(deltaX: 0, deltaY: 1),
          location: .zero,
          targetRect: .init(origin: .zero, size: .init(width: 10, height: 4))
        )
      )
    )
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("offset:1"))
    #expect(surfaceText(secondary.host).contains("offset:0"))
  }

  @Test(
    "link action mutates the graph that activated it when the same view instance is hosted twice")
  func linkActionTargetsDispatchingGraph() throws {
    let sharedView = LinkScopeFixture()
    let primary = makeRunLoop(rootName: "SharedLinkPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedLinkSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    #expect(primary.runLoop.localActionRegistry.dispatch(identity: testIdentity("ScopedLink")))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("opens:1"))
    #expect(surfaceText(secondary.host).contains("opens:0"))
  }
}

@MainActor
private struct KeyCommandScopeFixture: View {
  @State private var value = "idle"

  var body: some View {
    Panel(id: "scope") {
      Text(value).focusable(true)
    }
    .keyCommand("Mutate", key: .character("m"), modifiers: .ctrl) {
      value = "mutated"
    }
  }
}

private enum DispatchContextProbeKey: EnvironmentKey {
  static let defaultValue = "default"
}

extension EnvironmentValues {
  fileprivate var dispatchContextProbe: String {
    get { self[DispatchContextProbeKey.self] }
    set { self[DispatchContextProbeKey.self] = newValue }
  }
}

private enum KeyCommandFocusField: Hashable {
  case first
  case second
}

private struct KeyCommandFocusWriteFixture: View {
  @FocusState private var focusedField: KeyCommandFocusField?

  var body: some View {
    Panel(id: "focus-scope") {
      VStack(alignment: .leading, spacing: 1) {
        Text("focus:\(focusLabel)")
        Button("First") {}
          .focused($focusedField, equals: .first)
        Button("Second") {}
          .focused($focusedField, equals: .second)
      }
    }
    .keyCommand("FocusSecond", key: .character("m"), modifiers: .ctrl) {
      focusedField = .second
    }
    .defaultFocus($focusedField, .first)
  }

  private var focusLabel: String {
    switch focusedField {
    case .first: "first"
    case .second: "second"
    case nil: "none"
    }
  }
}

private struct KeyCommandEnvironmentReadFixture: View {
  var body: some View {
    KeyCommandEnvironmentReadContent()
      .environment(\.dispatchContextProbe, "injected")
  }
}

private struct KeyCommandEnvironmentReadContent: View {
  @Environment(\.dispatchContextProbe) private var probe
  @State private var actionRead = "unread"

  var body: some View {
    Panel(id: "env-scope") {
      VStack(alignment: .leading, spacing: 1) {
        Text("body:\(probe)").focusable(true)
        Text("action:\(actionRead)")
      }
    }
    .keyCommand("ReadEnv", key: .character("e"), modifiers: .ctrl) {
      actionRead = probe
    }
  }
}

private struct ButtonEnvironmentReadFixture: View {
  var body: some View {
    ButtonEnvironmentReadContent()
      .environment(\.dispatchContextProbe, "injected")
  }
}

private struct ButtonEnvironmentReadContent: View {
  @Environment(\.dispatchContextProbe) private var probe
  @State private var actionRead = "unread"

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("action:\(actionRead)")
      Button("Read") {
        actionRead = probe
      }
    }
  }
}

@MainActor
private struct PaletteCommandScopeFixture: View {
  static let absorbed = PaletteCommandFixtureCaptureBox()

  @State private var value = "idle"

  var body: some View {
    Panel(id: "scope") {
      Text(value).focusable(true)
    }
    .paletteCommand(name: "Mutate") {
      value = "mutated"
    }
    .backgroundPreferenceValue(PaletteCommandsPreferenceKey.self) { commands in
      Self.absorbed.commands = commands
      return EmptyView()
    }
  }
}

@MainActor
private final class PaletteCommandFixtureCaptureBox {
  var commands: [ActivePaletteCommand] = []
}

@MainActor
private struct ToolbarScopeFixture: View {
  @State private var value = "idle"

  var body: some View {
    Panel(id: "scope") {
      Text(value)
        .toolbarItem(
          .init(
            title: "Mutate",
            action: { value = "mutated" }
          )
        )
    }
    .toolbar(style: DefaultBottomToolbarStyle())
  }
}

@MainActor
private struct ToolbarNilConstructionContextFixture: View {
  @State private var value = "idle"

  var body: some View {
    let config = withAuthoringContext(nil) {
      ToolbarItemConfig(
        title: "Mutate",
        action: { value = "mutated" }
      )
    }

    Panel(id: "scope") {
      Text(value)
        .toolbarItem(config)
    }
    .toolbar(style: DefaultBottomToolbarStyle())
  }
}

@MainActor
private struct DropDestinationScopeFixture: View {
  @State private var value = "idle"

  var body: some View {
    Panel(id: "scope") {
      Text(value).focusable(true)
    }
    .dropDestination { _ in
      value = "mutated"
      return true
    }
  }
}

@MainActor
private struct GestureCallbackScopeFixture: View {
  @State private var status = "idle"
  @State private var commits = 0
  @GestureState private var dragOffset = Vector.zero

  var body: some View {
    Text("status:\(status)|offset:\(dragOffset.dx),\(dragOffset.dy)|commits:\(commits)")
      .frame(minWidth: 48, maxWidth: 48, minHeight: 1, maxHeight: 1)
      .gesture(
        DragGesture()
          .updating($dragOffset) { value, state, _ in
            state = value.translation
          }
          .onChanged { _ in
            status = "changed"
          }
          .onEnded { _ in
            status = "ended"
            commits += 1
          }
      )
  }
}

@MainActor
private struct AppearLifecycleScopeFixture: View {
  @State private var showsChild = false
  @State private var status = "idle"

  var body: some View {
    Panel(id: "scope") {
      VStack(alignment: .leading, spacing: 1) {
        Text(status).focusable(true)
        if showsChild {
          Text("child").onAppear {
            status = "appeared"
          }
        }
      }
    }
    .keyCommand("Toggle child", key: .character("a"), modifiers: .ctrl) {
      showsChild.toggle()
    }
  }
}

@MainActor
private struct DisappearLifecycleScopeFixture: View {
  @State private var showsChild = true
  @State private var status = "idle"

  var body: some View {
    Panel(id: "scope") {
      VStack(alignment: .leading, spacing: 1) {
        Text(status).focusable(true)
        if showsChild {
          Text("child").onDisappear {
            status = "disappeared"
          }
        }
      }
    }
    .keyCommand("Toggle child", key: .character("d"), modifiers: .ctrl) {
      showsChild.toggle()
    }
  }
}

@MainActor
private struct ChangeLifecycleScopeFixture: View {
  @State private var count = 0
  @State private var status = "idle"

  var body: some View {
    Panel(id: "scope") {
      Text("status:\(status)|count:\(count)").focusable(true)
    }
    .keyCommand("Increment", key: .character("c"), modifiers: .ctrl) {
      count += 1
    }
    .onChange(of: count) {
      status = "changed"
    }
  }
}

@MainActor
private struct TaskLifecycleScopeFixture: View {
  @State private var showsChild = false
  @State private var status = "idle"

  var body: some View {
    Panel(id: "scope") {
      VStack(alignment: .leading, spacing: 1) {
        Text(status).focusable(true)
        if showsChild {
          Text("child")
            .task(id: "load") {
              status = "tasked"
            }
        }
      }
    }
    .keyCommand("Toggle child", key: .character("t"), modifiers: .ctrl) {
      showsChild.toggle()
    }
  }
}

@MainActor
private struct MenuScopeFixture: View {
  var body: some View {
    Menu("Actions") {
      Text("Action 1")
    }
    .id(testIdentity("ScopedMenu"))
  }
}

@MainActor
private struct ToggleScopeFixture: View {
  @State private var isOn = false

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("on:\(isOn)")
      Toggle("Enabled", isOn: $isOn)
        .id(testIdentity("ScopedToggle"))
    }
  }
}

@MainActor
private struct DisclosureScopeFixture: View {
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("expanded:\(isExpanded)")
      DisclosureGroup("More", isExpanded: $isExpanded) {
        Text("Details")
      }
      .id(testIdentity("ScopedDisclosure"))
    }
  }
}

@MainActor
private struct TextFieldScopeFixture: View {
  @State private var value = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("value:\(value.isEmpty ? "-" : value)")
      TextField("Name", text: $value)
        .id(testIdentity("ScopedTextField"))
    }
  }
}

@MainActor
private struct TextEditorScopeFixture: View {
  @State private var value = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("count:\(value.count)")
      TextEditor(text: $value)
        .id(testIdentity("ScopedTextEditor"))
        .frame(width: 16, height: 3, alignment: .topLeading)
    }
  }
}

@MainActor
private struct StepperScopeFixture: View {
  @State private var value = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("value:\(value)")
      Stepper("Count", value: $value, in: 0...3)
        .id(testIdentity("ScopedStepper"))
    }
  }
}

@MainActor
private struct SliderScopeFixture: View {
  @State private var value = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("value:\(value)")
      Slider("Value", value: $value, in: 0...4)
        .id(testIdentity("ScopedSlider"))
    }
  }
}

@MainActor
private struct PickerScopeFixture: View {
  @State private var selection = "one"

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("selection:\(selection)")
      Picker("Mode", selection: $selection) {
        Text("One").tag("one")
        Text("Two").tag("two")
      }
      .id(testIdentity("ScopedPicker"))
    }
  }
}

@MainActor
private struct ScrollViewScopeFixture: View {
  @State private var position = ScrollPosition.zero

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("offset:\(position.y)")
      ScrollView(.vertical, position: $position) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<12) { index in
            Text("Row \(index)")
          }
        }
      }
      .id(testIdentity("ScopedScrollView"))
      .frame(width: 12, height: 4, alignment: .topLeading)
    }
  }
}

@MainActor
private struct LinkScopeFixture: View {
  @State private var opens = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("opens:\(opens)")
      Link("Docs", destination: "https://example.com")
        .id(testIdentity("ScopedLink"))
    }
    .openLinkAction(
      OpenLinkAction { _ in
        opens += 1
        return true
      }
    )
  }
}

@MainActor
private func makeRunLoop<V: View>(
  rootName: String,
  @ViewBuilder content: @escaping () -> V
) -> (runLoop: RunLoop<Int, V>, host: ImperativeScopeTerminalHost) {
  let terminalSize = CellSize(width: 60, height: 8)
  let host = ImperativeScopeTerminalHost(surfaceSizeProvider: { terminalSize })
  let rootIdentity = testIdentity(rootName)
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = host.appearance
  environmentValues.terminalSize = terminalSize
  let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: host,
    terminalInputReader: ImperativeScopeInputReader(),
    signalReader: ImperativeScopeSignalReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
    focusTracker: focusTracker,
    environmentValues: environmentValues,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in content() }
  )
  focusTracker.invalidator = runLoop.scheduler
  return (runLoop, host)
}

@MainActor
private func renderInitial<State, V: View>(_ runLoop: RunLoop<State, V>) throws {
  runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  runLoop.renderer.enableSelectiveEvaluation()
}

@MainActor
private func renderPending<State, V: View>(_ runLoop: RunLoop<State, V>) throws {
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
}

@MainActor
private func focusLeafmostFocusable<State, V: View>(
  in runLoop: RunLoop<State, V>
) {
  if let actionable = runLoop.latestSemanticSnapshot.focusRegions
    .filter({ runLoop.localActionRegistry.hasHandler(identity: $0.identity) })
    .max(by: { $0.scopePath.count < $1.scopePath.count })
  {
    _ = runLoop.focusTracker.setFocus(to: actionable.identity)
    return
  }
  guard
    let leafmost = runLoop.latestSemanticSnapshot.focusRegions
      .max(by: { $0.scopePath.count < $1.scopePath.count })
  else { return }
  _ = runLoop.focusTracker.setFocus(to: leafmost.identity)
}

private func centerPoint(of rect: CellRect) -> CellPoint {
  CellPoint(
    x: rect.origin.x + rect.size.width / 2,
    y: rect.origin.y + rect.size.height / 2
  )
}

private struct ImperativeDispatchTimeout: Error, CustomStringConvertible {
  let label: String

  var description: String {
    "Ran out of render attempts waiting for \(label)"
  }
}

/// Pumps `condition` — which itself drives a render cycle — until it holds.
///
/// The bound is a count of *render attempts*, not a wall-clock interval, so
/// it is identical on a fast laptop and a starved CI core and never times out
/// spuriously. `Task.yield()` between attempts lets an asynchronous lifecycle
/// effect (a `.task`) make progress before the next render.
@MainActor
private func renderUntil(
  _ label: String,
  maxRenderAttempts: Int = 1000,
  condition: @escaping @MainActor () -> Bool
) async throws {
  for _ in 0..<maxRenderAttempts {
    if condition() {
      return
    }
    await Task.yield()
  }
  throw ImperativeDispatchTimeout(label: label)
}

@MainActor
private func surfaceText(_ host: ImperativeScopeTerminalHost) -> String {
  host.latestSurface?.lines.joined(separator: "\n") ?? ""
}

private final class ImperativeScopeTerminalHost: PresentationSurface {
  var surfaceSize: CellSize { surfaceSizeProvider() }
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }
  private(set) var latestSurface: RasterSurface?
  private let surfaceSizeProvider: () -> CellSize

  init(
    surfaceSizeProvider: @escaping () -> CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSizeProvider = surfaceSizeProvider
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    latestSurface = surface
    return TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: surface.lines.count,
      cellsChanged: 0
    )
  }
}

extension ImperativeScopeTerminalHost: DamageAwarePresentationSurface {
  func present(_ surface: RasterSurface, damage: PresentationDamage?) throws
    -> TerminalPresentationMetrics
  {
    try present(surface)
  }
}

private final class ImperativeScopeInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class ImperativeScopeSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
