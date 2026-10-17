@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth())
struct AdversarialSetAInteractionTests {
  @Test func setA201DisablingAPressedButtonRejectsItsPendingRelease() throws {
    // Hypothesis: a captured press retains an enabled action after its control becomes disabled.
    let log = SetAInteractionLog()
    let h = try make("201") { SetAPressLifetime(log: log) }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "Original"))
    try h.sendMouse(.down(.primary), at: point)
    try command("d", in: h)
    try h.sendMouse(.up(.primary), at: point)
    #expect(log.events.isEmpty)
    try command("d", in: h)
    try h.clickText("Original")
    #expect(log.events == ["original"])
  }

  @Test func setA202ReplacementControlCannotInheritARetiredPress() throws {
    // Hypothesis: release routing reuses the old structural position to activate a new owner.
    let log = SetAInteractionLog()
    let h = try make("202") { SetAPressLifetime(log: log) }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "Original"))
    try h.sendMouse(.down(.primary), at: point)
    try command("r", in: h)
    try #require(h.frame.contains("Replacement"))
    try h.sendMouse(.up(.primary), at: point)
    #expect(log.events.isEmpty)
    try h.clickText("Replacement")
    #expect(log.events == ["replacement"])
  }

  @Test func setA203RepeatedPointerCancellationLeavesKeyboardTraversalUsable() throws {
    // Hypothesis: cancellation clears or corrupts the keyboard traversal cursor along with capture.
    let log = SetAInteractionLog()
    let h = try make("203") { SetAPressLifetime(log: log) }
    defer { h.shutdown() }
    try h.focusText("Original")
    let point = try #require(h.point(forText: "Original"))
    try h.sendMouse(.down(.primary), at: point)
    try h.sendMouse(.cancelled, at: point)
    try h.sendMouse(.cancelled, at: point)
    try h.pressKey(.init(.tab))
    try h.pressKey(.init(.return))
    #expect(log.events == ["after"])
    #expect(h.runLoop.pressedIdentity == nil)
  }

  @Test func setA204SecondaryReleaseCannotCompleteAPrimaryPress() throws {
    // Hypothesis: release handling checks a pressed identity but forgets which button began it.
    let log = SetAInteractionLog()
    let h = try make("204") { SetAPressLifetime(log: log) }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "Original"))
    try h.sendMouse(.down(.primary), at: point)
    try h.sendMouse(.up(.secondary), at: point)
    #expect(log.events.isEmpty)
    try h.sendMouse(.cancelled, at: point)
    try h.clickText("Original")
    #expect(log.events == ["original"])
  }

  @Test func setA205RemovingHoveredContentCannotLeaveItsCallbackInstalled() throws {
    // Hypothesis: pruning the hovered subtree loses its exit or retains its move callback.
    let log = SetAInteractionLog()
    let h = try make("205") { SetAHoverLifetime(log: log) }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "Hover target"))
    try h.movePointer(to: point)
    try #require(log.events == ["entered"])
    try command("r", in: h)
    try h.movePointer(to: point)
    try h.movePointer(to: .init(x: 55, y: 18))
    #expect(log.events == ["entered", "exited"])
    #expect(h.pointerHoverHandlerCount == 0)
  }

  @Test func setA206NonHitTestingOverlayAllowsTheUnderlyingButtonToActivate() throws {
    // Hypothesis: an overlay's painted extent blocks hit testing even with allowsHitTesting(false).
    let log = SetAInteractionLog()
    let h = try make("206") {
      Button("Underlying") { log.events.append("under") }
        .overlay { Text("Cover").allowsHitTesting(false) }
    }
    defer { h.shutdown() }
    let region = try #require(h.runLoop.latestSemanticSnapshot.focusRegions.first)
    try h.click(Point(x: Double(region.rect.origin.x + 1), y: Double(region.rect.origin.y)))
    #expect(log.events == ["under"])
  }

  @Test func setA207OverlappingZStackTargetsOnlyTheFrontmostDeclaredControl() throws {
    // Hypothesis: pointer selection walks stacked children in paint order and selects the back layer.
    let log = SetAInteractionLog()
    let h = try make("207") {
      ZStack(alignment: .topLeading) {
        Button("Bottom layer") { log.events.append("bottom") }
        Button("Top layer") { log.events.append("top") }
      }
    }
    defer { h.shutdown() }
    try h.clickText("Top layer")
    #expect(log.events == ["top"])
  }

  @Test func setA208ExplicitContentShapeConstrainsAClippedButtonsOverflowHitBounds() throws {
    // Hypothesis: a child button's intrinsic hit bounds override its enclosing explicit content shape.
    let log = SetAInteractionLog()
    let h = try make("208") {
      Button("Long clipped action") { log.events.append("hit") }
        .frame(width: 20, alignment: .leading)
        .frame(width: 6, alignment: .leading)
        .clipped()
        .contentShape(CellRect(origin: .zero, size: .init(width: 6, height: 1)))
    }
    defer { h.shutdown() }
    try h.click(.init(x: 2, y: 0))
    try #require(log.events == ["hit"], "The point inside the explicit shape must activate")
    log.events.removeAll()
    try h.click(.init(x: 12, y: 0))
    let hitRects = h.runLoop.latestSemanticSnapshot.interactionRegions.map(\.rect)
    do {
      #expect(
        log.events.isEmpty,
        "Outside (12,0) must miss explicit (0,0,6,1); published interaction rects: \(hitRects)")
    }
  }

  @Test func setA209ChildEnableCannotOverrideAnAncestorsDisabledState() throws {
    // Hypothesis: the closest disabled(false) writer incorrectly revives an ancestor-disabled action.
    let log = SetAInteractionLog()
    let h = try make("209") {
      VStack {
        Button("Blocked") { log.events.append("hit") }.disabled(false)
      }.disabled(true)
    }
    defer { h.shutdown() }
    try h.clickText("Blocked")
    #expect(log.events.isEmpty)
    #expect(h.runLoop.focusTracker.currentFocusIdentity == nil)
  }

  @Test func setA210RemovingFocusedEditorRetiresItsPasteConsumer() throws {
    // Hypothesis: removing an editor leaves its paste closure reachable after focus moves elsewhere.
    let log = SetAInteractionLog()
    let h = try make("210") { SetAEditorLifetime(log: log) }
    defer { h.shutdown() }
    try h.focusText("First input")
    try h.paste("old")
    try #require(log.firstText == "old")
    try command("r", in: h)
    try #require(h.runLoop.latestSemanticSnapshot.focusRegions.count == 1)
    let survivor = try #require(h.runLoop.latestSemanticSnapshot.focusRegions.first)
    try h.focus(survivor.identity)
    try h.paste("new")
    #expect(log.firstText == "old")
    #expect(log.secondText == "new")
  }

  @Test func setA211TabTraversalSkipsANewlyDisabledMiddleControl() throws {
    // Hypothesis: traversal retains the previous enabled-region list after an ancestor state update.
    let log = SetAInteractionLog()
    let h = try make("211") { SetAFocusControls(log: log) }
    defer { h.shutdown() }
    try h.focusText("First control")
    try command("d", in: h)
    try h.pressKey(.init(.tab))
    try h.pressKey(.init(.return))
    #expect(log.events == ["last"])
  }

  @Test func setA212ClearingFocusBindingRemovesTheActiveKeyboardTarget() throws {
    // Hypothesis: a false FocusState request updates authored state but leaves the old action focused.
    let log = SetAInteractionLog()
    let h = try make("212") { SetAClearFocus(log: log) }
    defer { h.shutdown() }
    try h.focusText("Bound control")
    try #require(h.frame.contains("focused=true"))
    try command("u", in: h)
    #expect(h.frame.contains("focused=false"))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == nil)
    try h.pressKey(.init(.return))
    #expect(log.events.isEmpty)
  }

  @Test func setA213DismissalRestoresFocusAfterBackgroundStateChanges() throws {
    // Hypothesis: re-resolving the presenting tree while a sheet is open overwrites its restoration target.
    let log = SetAInteractionLog()
    let h = try make("213") { SetAModalFocus(log: log) }
    defer { h.shutdown() }
    try h.focusText("Restore here")
    let expected = h.runLoop.focusTracker.currentFocusIdentity
    try command("s", in: h)
    try #require(h.frame.contains("Sheet control"))
    try h.clickText("Refresh background")
    try #require(log.events == ["background:1"], "The sheet must permit the background update")
    try h.focusText("Sheet control")
    try h.pressKey(.init(.escape))
    #expect(!h.frame.contains("Sheet control"))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == expected)
    try h.pressKey(.init(.return))
    #expect(log.events == ["background:1", "restored"])
  }

  @Test func setA214RejectedPathDropFallsBackToTheEditorsOriginalPasteText() throws {
    // Hypothesis: a declined path drop consumes or rewrites the raw paste before the editor receives it.
    let log = SetAInteractionLog()
    let h = try make("214") {
      Panel(id: "set-a-editor-drop") {
        TextField("Path input", text: log.firstBinding).textFieldStyle(.plain)
      }.dropDestination { _ in
        log.events.append("declined")
        return false
      }
    }
    defer { h.shutdown() }
    try h.focusText("Path input")
    try h.paste("/tmp/a file.txt")
    #expect(log.firstText == "/tmp/a file.txt")
    #expect(log.events == ["declined"])
  }

  @Test func setA215PastedTabCannotMoveFocusAndRetargetTheRemainingCharacters() throws {
    // Hypothesis: synthesizing a tab during paste moves focus, delivering the suffix to another owner.
    let log = SetAInteractionLog()
    let h = try make("215") {
      VStack {
        Text("Console A").focusable().onKeyPress { key in
          log.recordKey("A", key)
          return .handled
        }
        Text("Console B").focusable().onKeyPress { key in
          log.recordKey("B", key)
          return .handled
        }
      }
    }
    defer { h.shutdown() }
    try h.focusText("Console A")
    let focus = h.runLoop.focusTracker.currentFocusIdentity
    try h.paste("ab\tcd")
    #expect(log.events == ["A:a", "A:b", "A:c", "A:d"])
    #expect(h.runLoop.focusTracker.currentFocusIdentity == focus)
  }

  @Test func setA216RemovedKeyInterceptorCannotConsumeItsReplacementInputs() throws {
    // Hypothesis: conditional handler retirement leaves the departed branch's interceptor in the bubble path.
    let log = SetAInteractionLog()
    let h = try make("216") { SetAKeyInterceptor(log: log) }
    defer { h.shutdown() }
    try h.focusText("Intercepted")
    try h.pressKey(.init(.character("x")))
    try #require(log.events == ["intercept"])
    try command("r", in: h)
    try h.focusText("Replacement leaf")
    try h.pressKey(.init(.character("x")))
    #expect(log.events == ["intercept", "replacement"])
  }

  @Test func setA217SiblingCommandsFollowTheCurrentFocusScope() throws {
    // Hypothesis: a cached scope path dispatches a shortcut into the previously focused sibling panel.
    let log = SetAInteractionLog()
    let h = try make("217") {
      VStack {
        Panel(id: "set-a-left") { Text("Left scope").focusable() }
          .keyCommand("Left", key: .character("k"), modifiers: .ctrl) { log.events.append("left") }
        Panel(id: "set-a-right") { Text("Right scope").focusable() }
          .keyCommand("Right", key: .character("k"), modifiers: .ctrl) {
            log.events.append("right")
          }
      }
    }
    defer { h.shutdown() }
    try h.focusText("Left scope")
    try command("k", in: h)
    try h.focusText("Right scope")
    try command("k", in: h)
    #expect(log.events == ["left", "right"])
  }

  @Test func setA218DisabledAncestorCommandConsumesItsBindingAfterALiveToggle() throws {
    // Hypothesis: disabled command refresh drops the ancestor registration and exposes a descendant binding.
    let log = SetAInteractionLog()
    let h = try make("218") { SetACommandLifetime(log: log) }
    defer { h.shutdown() }
    try h.focusText("Command leaf")
    try command("k", in: h)
    try #require(log.events == ["outer:0"])
    try command("d", in: h)
    try command("k", in: h)
    #expect(log.events == ["outer:0"])
    try command("d", in: h)
    try command("k", in: h)
    #expect(log.events == ["outer:0", "outer:0"])
  }

  @Test func setA219FunctionKeyCommandRefreshesItsCapturedPayload() throws {
    // Hypothesis: command registration reuse keeps the first closure despite a changed authored payload.
    let log = SetAInteractionLog()
    let h = try make("219") { SetACommandLifetime(log: log) }
    defer { h.shutdown() }
    try h.focusText("Command leaf")
    try h.pressKey(.init(.functionKey(5)))
    try #require(log.events == ["refresh:0"])
    try command("g", in: h)
    try h.pressKey(.init(.functionKey(5)))
    #expect(log.events == ["refresh:0", "refresh:1"])
  }

  @Test func setA220CommandModifierSupersetsDoNotMatchAWeakerBinding() throws {
    // Hypothesis: shortcut matching uses a modifier subset, turning Ctrl+Shift+K into Ctrl+K.
    let log = SetAInteractionLog()
    let h = try make("220") { SetACommandLifetime(log: log) }
    defer { h.shutdown() }
    try h.focusText("Command leaf")
    try h.pressKey(.init(.character("k"), modifiers: [.ctrl, .shift]))
    #expect(log.events.isEmpty)
    try command("k", in: h)
    #expect(log.events == ["outer:0"])
  }

  @Test func setA221SubmitScopeUpdatesItsBarrierWithoutRemountingTheEditor() throws {
    // Hypothesis: a retained editor keeps the old submit environment after the scope's blocking flag changes.
    let log = SetAInteractionLog()
    let h = try make("221") { SetASubmitLifetime(log: log) }
    defer { h.shutdown() }
    try h.focusText("Submit input")
    try h.pressKey(.init(.return))
    try #require(log.events == ["inner", "outer"])
    try command("b", in: h)
    try h.pressKey(.init(.return))
    #expect(log.events == ["inner", "outer", "inner"])
  }

  @Test func setA222TextEditorReplacementCannotInheritTheDepartedFieldsSubmitHandler() throws {
    // Hypothesis: replacing a single-line field with a multiline editor leaves Return registered as submit.
    let log = SetAInteractionLog()
    let h = try make("222") { SetASubmitLifetime(log: log) }
    defer { h.shutdown() }
    try command("r", in: h)
    try h.focusText("editor seed")
    try h.pressKey(.init(.return))
    #expect(log.firstText.contains("\n"))
    #expect(log.events.isEmpty)
  }

  @Test func setA223ChildGestureUpdatesReachTheirOwningGestureState() throws {
    // Hypothesis: a nested gesture writes its binding under the child route instead of the state owner.
    let log = SetAInteractionLog()
    let h = try make("223") { SetADragLifetime(log: log) }
    defer { h.shutdown() }
    let start = try #require(h.point(forText: "Drag pad"))
    try h.sendMouse(.down(.primary), at: start)
    try h.sendMouse(.dragged(.primary), at: .init(x: start.x + 3, y: start.y))
    try #require(log.gestureUpdates.contains(3), "The updater must receive the actual drag")
    do {
      #expect(
        h.frame.contains("drag=3"),
        "Updater values: \(log.gestureUpdates); stored: \(String(describing: log.gestureOwnerValue?())); frame:\n\(h.frame)"
      )
    }
    try h.sendMouse(.cancelled, at: start)
    #expect(h.frame.contains("drag=0"))
    #expect(log.events.isEmpty)
    #expect(!h.runLoop.pointerInteraction.isRouting)
  }

  @Test func setA224CapturedDragCompletesOutsideItsOriginalClippedBounds() throws {
    // Hypothesis: post-capture hit testing wrongly discards the final drag/release beyond its clip.
    let log = SetAInteractionLog()
    let h = try make("224") { SetADragLifetime(log: log) }
    defer { h.shutdown() }
    let start = try #require(h.point(forText: "Drag pad"))
    try h.drag(from: start, to: .init(x: start.x + 22, y: start.y + 3))
    #expect(log.events == ["end:22,3"])
    #expect(h.frame.contains("drag=0"))
  }

  @Test func setA225SpatialDropRoutesByLocationRatherThanTheKeyboardFocusedSibling() throws {
    // Hypothesis: a spatial drop incorrectly reuses keyboard focus scopes or drops its modifier context.
    let log = SetAInteractionLog()
    let h = try make("225") {
      VStack {
        Panel(id: "set-a-drop-left") { Text("Drop left").focusable() }
          .dropDestination { _, _ in
            log.events.append("left")
            return true
          }
        Panel(id: "set-a-drop-right") { Text("Drop right").focusable() }
          .dropDestination { paths, context in
            log.events.append("right:\(paths.count):\(context.modifiers == .shift)")
            return true
          }
      }
    }
    defer { h.shutdown() }
    try h.focusText("Drop left")
    let point = try #require(h.point(forText: "Drop right"))
    try h.drop(
      paths: [.init("/tmp/first"), .init("/tmp/second")],
      context: .init(location: point, modifiers: .shift))
    #expect(log.events == ["right:2:true"])
  }

  private func make<V: View>(_ name: String, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("AdversarialSetAInteraction", name),
      size: .init(width: 60, height: 20), content: content)
  }

  private func command<V: View>(_ key: Character, in h: StressRuntimeHarness<V>) throws {
    try h.pressKey(.init(.character(key), modifiers: .ctrl))
  }
}

@MainActor
private final class SetAInteractionLog {
  var events: [String] = []
  var gestureUpdates: [Int] = []
  var gestureOwnerValue: (@MainActor () -> Int)?
  var firstText = ""
  var secondText = ""
  var firstBinding: Binding<String> {
    .init(get: { self.firstText }, set: { self.firstText = $0 })
  }
  var secondBinding: Binding<String> {
    .init(get: { self.secondText }, set: { self.secondText = $0 })
  }
  func recordKey(_ label: String, _ key: KeyPress) {
    if case .character(let character) = key.key {
      events.append("\(label):\(character)")
    } else {
      events.append("\(label):control")
    }
  }
}

@MainActor
private struct SetAPressLifetime: View {
  let log: SetAInteractionLog
  @State private var disabled = false
  @State private var replaced = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if replaced {
        Button("Replacement") { log.events.append("replacement") }
      } else {
        Button("Original") { log.events.append("original") }.disabled(disabled)
      }
      Button("After") { log.events.append("after") }
    }
    .onKeyPress(.character("d"), modifiers: .ctrl) { _ in
      disabled.toggle()
      return .handled
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      replaced.toggle()
      return .handled
    }
  }
}

@MainActor
private struct SetAHoverLifetime: View {
  let log: SetAInteractionLog
  @State private var removed = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Focus anchor") {}
      if removed {
        Text("Departed")
      } else {
        Text("Hover target").onPointerHover { phase in
          switch phase {
          case .entered: log.events.append("entered")
          case .moved: log.events.append("moved")
          case .exited: log.events.append("exited")
          }
        }
      }
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      removed.toggle()
      return .handled
    }
  }
}

@MainActor
private struct SetAEditorLifetime: View {
  let log: SetAInteractionLog
  @State private var removed = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !removed { TextField("First input", text: log.firstBinding).textFieldStyle(.plain) }
      TextField("Second input", text: log.secondBinding).textFieldStyle(.plain)
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      removed.toggle()
      return .handled
    }
  }
}

@MainActor
private struct SetAFocusControls: View {
  let log: SetAInteractionLog
  @State private var disabled = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("First control") { log.events.append("first") }
      Button("Middle control") { log.events.append("middle") }.disabled(disabled)
      Button("Last control") { log.events.append("last") }
    }
    .onKeyPress(.character("d"), modifiers: .ctrl) { _ in
      disabled.toggle()
      return .handled
    }
  }
}

@MainActor
private struct SetAClearFocus: View {
  let log: SetAInteractionLog
  @FocusState private var focused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Bound control") { log.events.append("hit") }.focused($focused)
      Text("focused=\(focused)")
    }
    .onKeyPress(.character("u"), modifiers: .ctrl) { _ in
      focused = false
      return .handled
    }
  }
}

@MainActor
private struct SetAModalFocus: View {
  let log: SetAInteractionLog
  @State private var presented = false
  @State private var generation = 0
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Other control") { log.events.append("other") }
      Button("Restore here") { log.events.append("restored") }
      Text("generation=\(generation)")
    }
    .sheet("Focus sheet", isPresented: $presented) {
      VStack {
        Button("Sheet control") {}
        Button("Refresh background") {
          generation += 1
          log.events.append("background:\(generation)")
        }
      }
    }
    .onKeyPress(.character("s"), modifiers: .ctrl) { _ in
      presented = true
      return .handled
    }
  }
}

@MainActor
private struct SetAKeyInterceptor: View {
  let log: SetAInteractionLog
  @State private var replaced = false
  var body: some View {
    Group {
      if replaced {
        Text("Replacement leaf").focusable().onKeyPress(.character("x")) { _ in
          log.events.append("replacement")
          return .handled
        }
      } else {
        Text("Intercepted").focusable().onKeyPress(.character("x")) { _ in
          log.events.append("intercept")
          return .handled
        }
      }
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      replaced.toggle()
      return .handled
    }
  }
}

@MainActor
private struct SetACommandLifetime: View {
  let log: SetAInteractionLog
  @State private var enabled = true
  @State private var generation = 0
  var body: some View {
    let current = generation
    Panel(id: "set-a-command-outer") {
      Panel(id: "set-a-command-inner") { Text("Command leaf").focusable() }
        .keyCommand("Inner", key: .character("k"), modifiers: .ctrl) {
          log.events.append("inner")
        }
    }
    .keyCommand("Outer", key: .character("k"), modifiers: .ctrl, isEnabled: enabled) {
      log.events.append("outer:\(current)")
    }
    .keyCommand("Refresh", key: .functionKey(5), modifiers: []) {
      log.events.append("refresh:\(current)")
    }
    .onKeyPress(.character("d"), modifiers: .ctrl) { _ in
      enabled.toggle()
      return .handled
    }
    .onKeyPress(.character("g"), modifiers: .ctrl) { _ in
      generation += 1
      return .handled
    }
  }
}

@MainActor
private struct SetASubmitLifetime: View {
  let log: SetAInteractionLog
  @State private var blocked = false
  @State private var multiline = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if multiline {
        TextEditor(text: log.firstBinding).frame(width: 40, height: 4)
      } else {
        TextField("Submit input", text: log.firstBinding).textFieldStyle(.plain)
          .onSubmit { log.events.append("inner") }
          .submitScope(blocked)
      }
    }
    .onSubmit { log.events.append("outer") }
    .onKeyPress(.character("b"), modifiers: .ctrl) { _ in
      blocked.toggle()
      return .handled
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      log.firstText = "editor seed"
      multiline = true
      return .handled
    }
  }
}

@MainActor
private struct SetADragLifetime: View {
  let log: SetAInteractionLog
  @GestureState private var offset = Vector(dx: 0, dy: 0)
  var body: some View {
    let ownerContext = currentImperativeAuthoringContextSnapshot()
    let ownerBinding = $offset
    log.gestureOwnerValue = {
      withImperativeAuthoringContext(ownerContext) { Int(ownerBinding.box.currentValue().dx) }
    }
    return VStack(alignment: .leading, spacing: 0) {
      Text("Drag pad").frame(width: 12, height: 2, alignment: .topLeading)
        .gesture(
          DragGesture(minimumDistance: 0)
            .updating($offset) { value, state, _ in
              state = value.translation
              log.gestureUpdates.append(Int(state.dx))
            }
            .onEnded { value in
              log.events.append("end:\(Int(value.translation.dx)),\(Int(value.translation.dy))")
            }
        )
        .clipped()
      Text("drag=\(Int(offset.dx))")
    }
  }
}
