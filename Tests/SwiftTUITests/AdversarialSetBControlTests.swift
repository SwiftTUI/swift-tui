@_spi(Testing) import SwiftTUITestSupport
// Adversarial set B, pass 3: controls and their style seams (241–250).
//
// Value controls map pointer cells and keys onto their models, and the
// public style protocols document what each configuration field means.
// These probes press the slider's own marker, use a three-cell custom track,
// press Up on a stepper, watch `isPressed` under a keyboard activation, give
// a group box an empty label, feed the spinner empty frames, open a menu
// picker with Down, and pin the activation keys, empty style bodies, and
// the single-option segmented picker.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@_spi(StyleFixtures) @testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: controls and styles", .serialized)
struct AdversarialSetBControlTests {
  private func harness<V: View>(
    _ name: String, width: Int = 40, height: Int = 10, @ViewBuilder content: @escaping () -> V
  ) throws -> StressRuntimeHarness<V> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBControl", name), size: .init(width: width, height: height),
      content: content)
  }

  // Pressing the slider's own marker cell is a no-op: the drawn position maps
  // back to the value it displays.
  @Test func setB241PressingTheSliderMarkerKeepsItsValue() throws {
    let probe = SetBValueProbe(2)
    let h = try harness("Marker") {
      Slider("Level", value: probe.binding(), in: 0...10)
    }
    defer { h.shutdown() }
    let marker = try #require(h.point(forText: "●"), "\(h.frame)")
    _ = try h.click(marker)
    do {
      #expect(probe.value == 2, "\(probe.value)")
      #expect(probe.writes.isEmpty, "\(probe.writes)")
    }
  }

  // A custom three-cell track still reaches both bounds from the pointer.
  @Test func setB242ThreeCellCustomTrackReachesBothBounds() throws {
    let probe = SetBValueProbe(5)
    let h = try harness("Tiny") {
      Slider("Level", value: probe.binding(), in: 0...10).sliderStyle(SetBTinyTrackStyle())
    }
    defer { h.shutdown() }
    let track = try #require(h.point(forText: "[=]"), "\(h.frame)")
    let last = Point(x: track.x + 1, y: track.y)
    _ = try h.click(last)
    let afterLast = probe.value
    let first = Point(x: track.x - 1, y: track.y)
    _ = try h.click(first)
    let afterFirst = probe.value
    do {
      #expect(afterLast == 10, "last cell → \(afterLast)")
    }
    #expect(afterFirst == 0, "first cell → \(afterFirst)")
  }

  // Up and Down on a focused stepper adjust its value like AppKit's control.
  @Test func setB243UpAndDownAdjustAFocusedStepper() throws {
    let probe = SetBValueProbe(2)
    let h = try harness("Arrows") {
      VStack(alignment: .leading) {
        Button("A") {}
        Stepper("S", value: probe.binding(), in: 0...5)
        Button("B") {}
      }
    }
    defer { h.shutdown() }
    _ = try h.focusText("S")
    let stepper = h.runLoop.focusTracker.currentFocusIdentity
    _ = try h.pressKey(KeyPress(.arrowUp))
    let afterUp = probe.value
    _ = try h.pressKey(KeyPress(.arrowDown))
    let afterDown = probe.value
    do {
      #expect(afterUp == 3, "\(afterUp)")
      #expect(afterDown == 2, "\(afterDown)")
    }
    #expect(h.runLoop.focusTracker.currentFocusIdentity == stepper, "arrows never left the stepper")
    _ = try h.pressKey(KeyPress(.arrowRight))
    #expect(probe.value == afterDown + 1, "\(probe.value)")
  }

  // `isPressed` describes a pointer press: a keyboard activation never
  // resolves a stepper style with `isPressed == true`.
  @Test func setB244KeyboardActivationDoesNotReportAPointerPress() throws {
    let log = SetBPressLog()
    let probe = SetBValueProbe(0)
    let h = try harness("Pressed") {
      Stepper("S", value: probe.binding(), in: 0...5).stepperStyle(
        SetBPressRecordingStepperStyle(log: log))
    }
    defer { h.shutdown() }
    _ = try h.focusText("S")
    log.pressed.removeAll()
    _ = try h.pressKey(KeyPress(.return))
    #expect(probe.value == 1, "\(probe.value)")
    do {
      #expect(!log.pressed.contains(true), "\(log.pressed)")
    }
    log.pressed.removeAll()
    _ = try h.renderAfterExternalMutation()
    #expect(
      !log.pressed.contains(true), "the transient press is cleared after the frame: \(log.pressed)")
  }

  @Test func keyboardPulsePreservesAHeldPhysicalPress() throws {
    let log = SetBPressLog()
    let probe = SetBValueProbe(0)
    let h = try harness("HeldPress") {
      Stepper("S", value: probe.binding(), in: 0...10).stepperStyle(
        SetBPressRecordingStepperStyle(log: log))
    }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "+"))
    _ = try h.sendMouse(.down(.primary), at: point)
    let held = try #require(h.runLoop.pointerPressedIdentity)
    #expect(log.pressed.last == true)
    log.pressed.removeAll()
    _ = try h.pressKey(KeyPress(.return))
    #expect(h.runLoop.pointerPressedIdentity == held)
    #expect(h.runLoop.pressedIdentity == held)
    #expect(!log.pressed.contains(false))
    _ = try h.sendMouse(.up(.primary), at: point)
    #expect(h.runLoop.pointerPressedIdentity == nil)
    #expect(log.pressed.last == false)
  }

  // A group box whose authored label is empty reserves no label row.
  @Test func setB245EmptyGroupBoxLabelReservesNoRow() {
    let labelled = DefaultRenderer().render(
      GroupBox(content: { Text("V") }, label: { EmptyView() }),
      context: .init(identity: testIdentity("SetBControl", "emptyLabel")),
      proposal: .init(width: 10, height: 6))
    let unlabelled = DefaultRenderer().render(
      GroupBox { Text("V") },
      context: .init(identity: testIdentity("SetBControl", "noLabel")),
      proposal: .init(width: 10, height: 6))
    #expect(
      labelled.measuredTree.measuredSize.height == unlabelled.measuredTree.measuredSize.height,
      "labelled \(labelled.measuredTree.measuredSize) unlabelled \(unlabelled.measuredTree.measuredSize)"
    )
    #expect(
      unlabelled.measuredTree.measuredSize.height == 3, "\(unlabelled.measuredTree.measuredSize)")
  }

  // Empty spinner frames are an invalid presentation: the style reports it
  // and the automatic frames are shown instead of a blank cell.
  @Test func setB246EmptySpinnerFramesAreRejected() {
    let snapshot = DefaultRenderer().render(
      Spinner().spinnerStyle(GlyphSpinnerStyle(activeFrames: ["", ""])),
      context: .init(identity: testIdentity("SetBControl", "emptyFrames")),
      proposal: .init(width: 10, height: 1))
    let codes = snapshot.diagnostics.runtime.issues.map(\.code)
    let line = snapshot.rasterSurface.lines.first ?? ""
    do {
      #expect(codes.contains("style.invalidPresentation"), "\(codes)")
      #expect(!line.isEmpty, "\(snapshot.rasterSurface.lines)")
    }
    let mixed = DefaultRenderer().render(
      Spinner().spinnerStyle(GlyphSpinnerStyle(activeFrames: ["a", "界"])),
      context: .init(identity: testIdentity("SetBControl", "mixedFrames")),
      proposal: .init(width: 10, height: 1))
    #expect(mixed.diagnostics.runtime.issues.map(\.code).contains("style.invalidPresentation"))
  }

  // Down on a collapsed menu picker opens it without changing the selection.
  @Test func setB247DownOnACollapsedMenuPickerOpensWithoutSelecting() throws {
    let probe = SetBValueProbe(0)
    let h = try harness("MenuPicker") {
      Picker("Choice", selection: probe.binding()) {
        Text("Zero").tag(0)
        Text("One").tag(1)
        Text("Two").tag(2)
      }
      .pickerStyle(.menu)
    }
    defer { h.shutdown() }
    _ = try h.focusText("Choice")
    _ = try h.pressKey(KeyPress(.escape))
    try #require(!h.frame.contains("Two"), "collapsed: \(h.frame)")
    _ = try h.pressKey(KeyPress(.arrowDown))
    #expect(h.frame.contains("Two"), "expanded: \(h.frame)")
    do {
      #expect(probe.value == 0, "\(probe.value)")
      #expect(probe.writes.isEmpty, "\(probe.writes)")
    }
  }

  // Return and bare Space activate every button-like control; a modified
  // Return or Space activates nothing.
  @Test func setB248ReturnAndSpaceActivateModifiedKeysDoNot() throws {
    let counter = SetBValueProbe(0)
    let toggle = SetBValueProbe(false)
    let h = try harness("Activation") {
      VStack(alignment: .leading) {
        Button("Count") { counter.value += 1 }
        Toggle("Flag", isOn: toggle.binding())
      }
    }
    defer { h.shutdown() }
    _ = try h.focusText("Count")
    _ = try h.pressKey(KeyPress(.return, modifiers: .shift))
    _ = try h.pressKey(KeyPress(.space, modifiers: .ctrl))
    #expect(counter.value == 0, "\(counter.value)")
    _ = try h.pressKey(KeyPress(.return))
    _ = try h.pressKey(KeyPress(.space))
    #expect(counter.value == 2, "\(counter.value)")
    _ = try h.focusText("Flag")
    _ = try h.pressKey(KeyPress(.return))
    #expect(toggle.value == true)
    _ = try h.pressKey(KeyPress(.space))
    #expect(toggle.value == false)
    #expect(toggle.writes.count == 2, "\(toggle.writes)")
  }

  // A button style whose body omits the label keeps the focus stop and
  // keyboard activation; only the pointer region disappears.
  @Test func setB249EmptyButtonStyleBodyKeepsFocusAndKeyboardActivation() throws {
    let counter = SetBValueProbe(0)
    let identity = testIdentity("SetBControl", "EmptyBody")
    let h = try harness("EmptyStyle") {
      VStack(alignment: .leading) {
        Button("Save") { counter.value += 1 }.buttonStyle(SetBEmptyButtonStyle()).id(identity)
        Text("count \(counter.value)")
      }
    }
    defer { h.shutdown() }
    #expect(h.focusRegionCount == 1, "\(h.runLoop.focusTracker.focusRegions.map(\.identity))")
    #expect(
      h.runLoop.latestSemanticSnapshot.interactionRegions.isEmpty,
      "no pointer region for an empty body")
    _ = try h.focus(identity)
    _ = try h.pressKey(KeyPress(.return))
    #expect(counter.value == 1, "\(counter.value)")
    let node = h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
      $0.role == .button
    }
    #expect(node?.label == "Save", "\(String(describing: node))")
  }

  // A single-option segmented picker neither wraps nor moves focus on
  // Left/Right, and writes nothing.
  @Test func setB250SingleOptionSegmentedPickerAbsorbsArrows() throws {
    let probe = SetBValueProbe(0)
    let h = try harness("Segmented") {
      VStack(alignment: .leading) {
        Picker("Only", selection: probe.binding()) {
          Text("Solo").tag(0)
        }
        .pickerStyle(.segmented)
        Button("After") {}
      }
    }
    defer { h.shutdown() }
    _ = try h.focusText("Solo")
    let picker = h.runLoop.focusTracker.currentFocusIdentity
    _ = try h.pressKey(KeyPress(.arrowRight))
    _ = try h.pressKey(KeyPress(.arrowLeft))
    #expect(probe.value == 0)
    #expect(probe.writes.isEmpty, "\(probe.writes)")
    #expect(h.runLoop.focusTracker.currentFocusIdentity == picker)
  }
}

@MainActor
private final class SetBValueProbe<Value> {
  var value: Value
  var writes: [Value] = []

  init(_ value: Value) {
    self.value = value
  }

  func binding() -> Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writes.append($0)
      })
  }
}

@MainActor
private final class SetBPressLog {
  var pressed: [Bool] = []
}

private struct SetBTinyTrackStyle: SliderStyle {
  func makeBody(configuration: SliderStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      configuration.label
      configuration.track { Text("[=]") }
    }
  }
}

private struct SetBPressRecordingStepperStyle: StepperStyle {
  let log: SetBPressLog

  func makeBody(configuration: StepperStyleConfiguration) -> some View {
    let pressed = configuration.isPressed
    MainActor.assumeIsolated { log.pressed.append(pressed) }
    return HStack(spacing: 1) {
      configuration.decrement { Text("-") }
      configuration.label
      configuration.valueLabel
      configuration.increment { Text("+") }
    }
  }
}

private struct SetBEmptyButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    Text("")
  }
}
