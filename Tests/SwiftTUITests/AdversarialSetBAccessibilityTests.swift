import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Published accessibility values and the typed assistive actions that write
// them back must agree with each other and with the authored model. The
// Sept-Oct 2026 reports in this class: STUI-903 (progress label vs clamped
// value), STUI-615 (stepper normalizing an out-of-range model), STUI-914 and
// STUI-904 (picker selection no-ops), STUI-628 (disabled state of non-control
// nodes), STUI-655 (expired action targets) and the newline caret geometry.
@MainActor
@Suite("Adversarial set B: accessibility values", .serialized)
struct AdversarialSetBAccessibilityTests {
  @Test func setB091ProgressSubTenthTotalsDescribePartialProgress() throws {
    for (value, total, fraction) in [
      (0.05, 0.1, 0.5), (0.04, 0.1, 0.4), (0.01, 0.02, 0.5), (0.25, 1.0, 0.25), (2.5, 5.0, 0.5),
    ] {
      let snapshot = setBRender(ProgressView(value: value, total: total))
      let node = try #require(snapshot.accessibilityNodes.first { $0.role == .progressBar })
      let published = try #require(node.control?.value)
      guard case .number(let publishedFraction) = published else {
        Issue.record("\(value)/\(total) published \(published)")
        continue
      }
      #expect(abs(publishedFraction - fraction) < 1e-9, "\(value)/\(total)")
      let description = try #require(node.properties?.valueDescription)
      let parts = description.split(separator: "/").map(String.init)
      try #require(parts.count == 2, "\(value)/\(total) reads \(description)")
      let shown = try #require(Double(parts[0]))
      let shownTotal = try #require(Double(parts[1]))
      // The description is the clamped progress in the authored unit, so the
      // ratio it reads must be the fraction the control publishes.
      withKnownIssue("one-decimal rounding misdescribes sub-tenth totals") {
        #expect(
          abs(shown / shownTotal - fraction) <= 0.051, "\(value)/\(total) reads \(description)")
        #expect(shown > 0 && shown < shownTotal, "\(value)/\(total) reads \(description)")
      } when: {
        total < 1
      }
    }
  }

  @Test func setB092ProgressClampEdgesAgreeWithDescriptions() throws {
    let cases: [(value: Double, total: Double, fraction: Double, description: String)] = [
      (1.5, 1.0, 1, "1/1"), (-0.0, 1, 0, "0/1"), (.leastNonzeroMagnitude, 0, 1, "100%"),
      (1e-9, 1, 1e-9, "0/1"), (0.5, .nan, 0, "0%"), (.nan, .nan, 0, "0%"),
    ]
    for entry in cases {
      let snapshot = setBRender(ProgressView(value: entry.value, total: entry.total))
      let node = try #require(snapshot.accessibilityNodes.first { $0.role == .progressBar })
      #expect(node.label == "Progress")
      withKnownIssue("a NaN total is treated as non-positive and publishes 100%") {
        #expect(node.control?.value == .number(entry.fraction), "\(entry.value)/\(entry.total)")
        #expect(
          node.properties?.valueDescription == entry.description, "\(entry.value)/\(entry.total)")
      } when: {
        entry.total.isNaN && entry.value > 0
      }
      #expect(node.control?.minimum == 0, "\(entry.value)/\(entry.total)")
      #expect(node.control?.maximum == 1, "\(entry.value)/\(entry.total)")
      #expect(node.control?.actions == [], "\(entry.value)/\(entry.total)")
    }
  }

  @Test func setB093StepperSetValueAroundTheClamp() throws {
    let bounded = SetBValueProbe(10)
    let whole = SetBValueProbe(2)
    let free = SetBValueProbe(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBAccessibility", "StepperSetValue"),
      size: .init(width: 40, height: 8)
    ) {
      VStack {
        Stepper("Bounded", value: bounded.binding(), in: 0...5)
        Stepper("Whole", value: whole.binding(), in: 0...5)
        Stepper("Free", value: free.binding())
      }
    }
    defer { harness.shutdown() }
    func node(_ label: String) throws -> AccessibilityNode {
      try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.role == .stepper && $0.label == label
        })
    }
    func send(_ label: String, _ value: Double) throws -> AccessibilityActionResult {
      let stepper = try node(label)
      let target = try #require(stepper.actionTarget)
      let result = harness.runLoop.handleAccessibilityAction(
        .init(target: target, action: .setValue(.number(value))))
      _ = try harness.renderAfterExternalMutation()
      return result
    }

    let published = try node("Bounded")
    #expect(published.control?.value == .number(5))
    #expect(published.control?.minimum == 0)
    #expect(published.control?.maximum == 5)
    // Setting the value the control already publishes is a no-op for the
    // host; it must not silently rewrite the out-of-range model.
    #expect(try send("Bounded", 5) == .accepted)
    withKnownIssue("setValue compares with the unclamped model and writes the clamp") {
      #expect(bounded.writes.isEmpty, "\(bounded.writes)")
      let overflowing = try send("Bounded", 10)
      #expect(overflowing == .invalidValue)
      let fractional = try send("Bounded", 5.5)
      #expect(fractional == .invalidValue)
      #expect(bounded.writes.isEmpty, "\(bounded.writes)")
      let inRange = try send("Bounded", 3)
      #expect(inRange == .accepted)
      #expect(bounded.writes == [3])
    }
    let updated = try node("Bounded")
    #expect(updated.control?.value == .number(3))

    #expect(try send("Whole", 2.5) == .invalidValue)
    #expect(try send("Whole", 2) == .accepted)
    #expect(whole.writes.isEmpty, "\(whole.writes)")

    let unbounded = try node("Free")
    #expect(unbounded.control?.minimum == nil)
    #expect(unbounded.control?.maximum == nil)
    #expect(try send("Free", 1e300) == .invalidValue)
    #expect(try send("Free", .infinity) == .invalidValue)
    #expect(try send("Free", -0.0) == .accepted)
    #expect(free.writes.isEmpty, "\(free.writes)")
    #expect(try send("Free", -7) == .accepted)
    #expect(free.writes == [-7])
  }

  @Test func setB094ToggleSetValueIsIdempotentAndTyped() throws {
    let enabled = SetBValueProbe(false)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBAccessibility", "ToggleSetValue"),
      size: .init(width: 30, height: 4)
    ) {
      Toggle("Enabled", isOn: enabled.binding())
    }
    defer { harness.shutdown() }
    func node() throws -> AccessibilityNode {
      try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.role == .toggle
        })
    }
    func send(_ action: AccessibilityAction) throws -> AccessibilityActionResult {
      let toggle = try node()
      let target = try #require(toggle.actionTarget)
      let result = harness.runLoop.handleAccessibilityAction(
        .init(target: target, action: action))
      _ = try harness.renderAfterExternalMutation()
      return result
    }

    let initial = try node()
    #expect(initial.control?.value == .boolean(false))
    var frames = 0
    try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    let settled = frames
    let target = try #require(initial.actionTarget)
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: target, action: .setValue(.boolean(false)))) == .accepted)
    try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    #expect(frames == settled)
    #expect(enabled.writes.isEmpty, "\(enabled.writes)")

    #expect(try send(.setValue(.number(1))) == .invalidValue)
    #expect(try send(.setValue(.text("true"))) == .invalidValue)
    #expect(enabled.writes.isEmpty, "\(enabled.writes)")

    #expect(try send(.setValue(.boolean(true))) == .accepted)
    #expect(enabled.writes == [true])
    let turnedOn = try node()
    #expect(turnedOn.control?.value == .boolean(true))
    #expect(try send(.setValue(.boolean(true))) == .accepted)
    #expect(enabled.writes == [true])

    #expect(try send(.activate) == .accepted)
    #expect(enabled.writes == [true, false])
    let turnedOff = try node()
    #expect(turnedOff.control?.value == .boolean(false))
  }

  @Test func setB095PickerRejectsTokenOfRemovedOption() throws {
    let selection = SetBValueProbe(1)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBAccessibility", "PickerRemoval"),
      size: .init(width: 40, height: 12)
    ) {
      SetBPickerRemovalFixture(selection: selection)
    }
    defer { harness.shutdown() }
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func picker() throws -> AccessibilityNode {
      try #require(nodes().first { $0.role == .picker })
    }
    func option(_ label: String) throws -> AccessibilitySelectionOption {
      let current = try picker()
      return try #require(current.control?.selection?.options.first { $0.label == label })
    }
    func toggleSecond() throws {
      let button = try #require(nodes().first { $0.label == "Toggle second" })
      let target = try #require(button.actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
          == .accepted)
      _ = try harness.render()
    }
    func select(_ token: String) throws -> AccessibilityActionResult {
      let current = try picker()
      let target = try #require(current.actionTarget)
      let result = harness.runLoop.handleAccessibilityAction(
        .init(target: target, action: .setValue(.text(token))))
      _ = try harness.renderAfterExternalMutation()
      return result
    }

    let stale = try option("Second").id
    try toggleSecond()
    let remaining = try picker().control?.selection?.options.map { $0.label }
    #expect(remaining == ["First", "Third"])
    // The removed option's token is dead: it must be rejected, not resolved to
    // a neighbour or to the picker itself.
    #expect(try select(stale) == .invalidValue)
    #expect(selection.writes.isEmpty, "\(selection.writes)")
    let firstID = try option("First").id
    let afterRemoval = try picker()
    #expect(afterRemoval.control?.value == .text(firstID))

    try toggleSecond()
    let restored = try option("Second")
    #expect(restored.id != stale)
    #expect(try select(stale) == .invalidValue)
    #expect(selection.writes.isEmpty, "\(selection.writes)")
    #expect(try select(restored.id) == .accepted)
    #expect(selection.writes == [2])
    let selected = try picker()
    #expect(selected.control?.value == .text(restored.id))
    #expect(selected.properties?.valueDescription == "Second")
  }

  @Test func setB096DisabledPropagatesToTextAndInlineLinkNodes() throws {
    let opened = SetBValueProbe(0)
    let pressed = SetBValueProbe(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBAccessibility", "DisabledText"),
      size: .init(width: 50, height: 10)
    ) {
      SetBDisabledFixture(opened: opened, pressed: pressed)
    }
    defer { harness.shutdown() }
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func send(_ node: AccessibilityNode, _ action: AccessibilityAction) throws
      -> AccessibilityActionResult
    {
      let target = try #require(node.actionTarget, "\(node.label ?? "?") has no target")
      let result = harness.runLoop.handleAccessibilityAction(
        .init(target: target, action: action))
      _ = try harness.render()
      return result
    }

    let note = try #require(nodes().first { $0.label == "Note" })
    #expect(note.isEnabled == false)
    let guide = try #require(nodes().first { $0.role == .link && $0.label == "Guide" })
    #expect(guide.isEnabled == false)
    #expect(try send(guide, .activate) == .disabled)
    #expect(opened.value == 0)

    let manual = try #require(nodes().first { $0.role == .link && $0.label == "Manual" })
    #expect(manual.isEnabled == true)
    #expect(try send(manual, .activate) == .accepted)
    #expect(opened.value == 1)

    // A disabled label does not disable the control that owns it.
    let go = try #require(nodes().first { $0.role == .button && $0.label == "Go" })
    #expect(go.isEnabled == true)
    #expect(try send(go, .activate) == .accepted)
    #expect(pressed.value == 1)
  }

  @Test func setB097TextEditorCaretGeometryAtNewlinesAndLineSeparators() throws {
    let text = SetBValueProbe("\n\n")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBAccessibility", "EditorCaret"),
      size: .init(width: 40, height: 10)
    ) {
      TextEditor(text: text.binding()).accessibilityLabel("Editor").frame(width: 30, height: 5)
    }
    defer { harness.shutdown() }
    func node() throws -> AccessibilityNode {
      try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.role == .textEditor && $0.label == "Editor"
        })
    }
    func send(_ action: AccessibilityAction) throws -> AccessibilityActionResult {
      let editor = try node()
      let target = try #require(editor.actionTarget)
      let result = harness.runLoop.handleAccessibilityAction(
        .init(target: target, action: action))
      _ = try harness.renderAfterExternalMutation()
      return result
    }

    #expect(try send(.focus) == .accepted)
    #expect(try send(.selectText(.init(text: "\n\n", anchor: 0, head: 0))) == .accepted)
    let atStart = try node()
    let leading = try #require(atStart.textInput)
    let origin = try #require(atStart.cursorAnchor)
    let ranges = leading.clusters.map { $0.range }
    #expect(ranges == [0..<1, 1..<2])
    #expect(leading.selection == 0..<0)
    #expect(leading.insertionOffset == 0)
    // The first newline shares the caret row (it may sit after a synthetic
    // caret cell); the second starts its own row; the end is the row after.
    #expect(leading.clusters[0].rect.origin.y == origin.y)
    #expect((origin.x...origin.x + 1).contains(leading.clusters[0].rect.origin.x))
    #expect(leading.clusters[1].rect.origin == CellPoint(x: origin.x, y: origin.y + 1))
    #expect(leading.endAnchor == CellPoint(x: origin.x, y: origin.y + 2))

    #expect(try send(.selectText(.init(text: "\n\n", anchor: 1, head: 1))) == .accepted)
    let atMiddle = try node()
    let middle = try #require(atMiddle.textInput)
    let caret = try #require(atMiddle.cursorAnchor)
    #expect(caret == CellPoint(x: origin.x, y: origin.y + 1))
    #expect(middle.selection == 1..<1)
    #expect(middle.clusters[0].rect.origin == origin)
    #expect(middle.clusters[1].rect.origin.y == origin.y + 1)
    #expect((origin.x...origin.x + 1).contains(middle.clusters[1].rect.origin.x))
    #expect(middle.endAnchor == CellPoint(x: origin.x, y: origin.y + 2))

    // NEL, LS, PS, VT and FF are ordinary graphemes for the caret map: the
    // end-of-text anchor stays on the rendered row, directly after the last
    // placed cluster, and the caret anchor agrees with it.
    for suffix in ["\u{85}", "\u{2028}", "\u{2029}", "\u{0B}", "\u{0C}"] {
      let code = suffix.unicodeScalars.map { String($0.value, radix: 16) }.joined()
      let content = "AB" + suffix
      #expect(try send(.editText(.init(text: content, anchor: 3, head: 3))) == .accepted, "\(code)")
      let atEnd = try node()
      let placed = try #require(atEnd.textInput, "\(code)")
      let endCaret = try #require(atEnd.cursorAnchor, "\(code)")
      let last = try #require(placed.clusters.last, "\(code)")
      #expect(placed.clusters.count == 3, "\(code)")
      #expect(placed.selection == 3..<3, "\(code)")
      #expect(placed.insertionOffset == 3, "\(code)")
      let rows = Set(placed.clusters.map { $0.rect.origin.y })
      #expect(rows == [endCaret.y], "\(code)")
      #expect(placed.endAnchor == endCaret, "\(code)")
      let afterLast = CellPoint(
        x: last.rect.origin.x + last.rect.size.width, y: last.rect.origin.y)
      #expect(placed.endAnchor == afterLast, "\(code)")
    }
  }

  @Test func setB098MultiSelectAnchorIgnoresSetOrder() throws {
    var forward: Set<Int> = []
    for id in [1, 2, 3] { forward.insert(id) }
    var shuffled: Set<Int> = []
    for id in [2, 3, 1] { shuffled.insert(id) }
    let runs: [(ids: [Int], seed: Set<Int>)] = [
      ([3, 1, 2], forward), ([3, 1, 2], shuffled), ([1, 2, 3], shuffled),
    ]

    // Keyboard: the active row starts at the first dataset row whatever the
    // membership set looks like, so space and return toggle in dataset order.
    for (index, run) in runs.enumerated() {
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("SetBAccessibility", "MultiTable\(index)"),
        size: .init(width: 30, height: 14)
      ) {
        SetBMultiSelectTableFixture(ids: run.ids, members: run.seed)
      }
      defer { harness.shutdown() }
      let table = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
      _ = try harness.focus(table)
      _ = try harness.pressKey(KeyPress(.space))
      let afterFirst = [run.ids[1], run.ids[2]].sorted()
      #expect(harness.frame.contains("members=\(afterFirst)"), "\(harness.frame)")
      _ = try harness.pressKey(KeyPress(.arrowDown))
      _ = try harness.pressKey(KeyPress(.return))
      #expect(harness.frame.contains("members=[\(run.ids[2])]"), "\(harness.frame)")
      _ = try harness.pressKey(KeyPress(.arrowDown))
      _ = try harness.pressKey(KeyPress(.space))
      #expect(harness.frame.contains("members=[]"), "\(harness.frame)")
      _ = try harness.pressKey(KeyPress(.space))
      #expect(harness.frame.contains("members=[\(run.ids[2])]"), "\(harness.frame)")
    }

    // Assistive row selectors toggle the row they name, in dataset order.
    for (index, run) in runs.enumerated() {
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("SetBAccessibility", "MultiList\(index)"),
        size: .init(width: 30, height: 12)
      ) {
        SetBMultiSelectListFixture(ids: run.ids, members: run.seed)
      }
      defer { harness.shutdown() }
      func selector(_ row: Int) throws -> AccessibilityNode {
        try #require(
          harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
            $0.label == "Select row \(row)"
          })
      }
      func toggle(_ row: Int) throws {
        let button = try selector(row)
        let target = try #require(button.actionTarget)
        #expect(
          harness.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
            == .accepted)
        _ = try harness.render()
      }
      let first = try selector(1)
      #expect(first.control?.value == .boolean(true))
      try toggle(1)
      let afterFirst = [run.ids[1], run.ids[2]].sorted()
      #expect(harness.frame.contains("members=\(afterFirst)"), "\(harness.frame)")
      let deselected = try selector(1)
      #expect(deselected.control?.value == .boolean(false))
      try toggle(3)
      #expect(harness.frame.contains("members=[\(run.ids[1])]"), "\(harness.frame)")
      try toggle(1)
      let reselected = [run.ids[0], run.ids[1]].sorted()
      #expect(harness.frame.contains("members=\(reselected)"), "\(harness.frame)")
    }
  }

  @Test func setB099TargetSurvivesValueChangeButNotRoleSwap() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBAccessibility", "RoleSwap"),
      size: .init(width: 40, height: 8)
    ) {
      SetBRoleSwapFixture()
    }
    defer { harness.shutdown() }
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func dispatch(_ target: String, _ action: AccessibilityAction) throws
      -> AccessibilityActionResult
    {
      let result = harness.runLoop.handleAccessibilityAction(
        .init(target: target, action: action))
      _ = try harness.render()
      return result
    }
    func swap() throws {
      let button = try #require(nodes().first { $0.role == .button && $0.label == "Swap" })
      let target = try #require(button.actionTarget)
      #expect(try dispatch(target, .activate) == .accepted)
    }

    let toggle = try #require(nodes().first { $0.role == .toggle })
    let original = try #require(toggle.actionTarget)
    #expect(try dispatch(original, .activate) == .accepted)
    #expect(harness.frame.contains("flag=true"), "\(harness.frame)")
    let changed = try #require(nodes().first { $0.role == .toggle })
    #expect(changed.actionTarget == original)
    #expect(changed.control?.value == .boolean(true))

    try swap()
    #expect(!nodes().contains { $0.role == .toggle })
    let button = try #require(nodes().first { $0.role == .button && $0.label == "Same" })
    #expect(button.actionTarget != original)
    #expect(try dispatch(original, .activate) == .staleTarget)
    #expect(harness.frame.contains("flag=true"), "\(harness.frame)")

    try swap()
    let returned = try #require(nodes().first { $0.role == .toggle })
    let renewed = try #require(returned.actionTarget)
    #expect(renewed != original)
    #expect(try dispatch(original, .activate) == .staleTarget)
    #expect(harness.frame.contains("flag=true"), "\(harness.frame)")
    #expect(try dispatch(renewed, .activate) == .accepted)
    #expect(harness.frame.contains("flag=false"), "\(harness.frame)")
  }

  @Test func setB100EmptyLinkDestinationPublishesAndActivates() throws {
    let seen = SetBValueProbe<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBAccessibility", "EmptyLink"),
      size: .init(width: 40, height: 6)
    ) {
      SetBEmptyLinkFixture(seen: seen)
    }
    defer { harness.shutdown() }
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func activate(_ node: AccessibilityNode) throws -> AccessibilityActionResult {
      let target = try #require(node.actionTarget, "\(node.label ?? "?") has no target")
      let result = harness.runLoop.handleAccessibilityAction(
        .init(target: target, action: .activate))
      _ = try harness.render()
      return result
    }

    let home = try #require(nodes().first { $0.role == .link && $0.label == "Home" })
    #expect(home.control?.value == .text(""))
    #expect(home.control?.opensLink == false)
    let homeActions = home.control?.actions ?? []
    #expect(homeActions.contains(.activate))
    #expect(try activate(home) == .accepted)
    #expect(seen.value == [""])

    let docs = try #require(nodes().first { $0.role == .link && $0.label == "Docs" })
    #expect(docs.control?.value == .text(""))
    #expect(docs.control?.opensLink == false)
    #expect(try activate(docs) == .accepted)
    #expect(seen.value == ["", ""])
  }
}

@MainActor
private func setBRender<V: View>(_ view: V) -> SemanticSnapshot {
  DefaultRenderer().render(
    view,
    context: .init(identity: testIdentity("SetBAccessibility", "Progress")),
    proposal: .init(width: 80, height: 30)
  ).semanticSnapshot
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
      }
    )
  }
}

private struct SetBPickerRemovalFixture: View {
  let selection: SetBValueProbe<Int>
  @State private var showSecond = true

  var body: some View {
    VStack {
      Picker("Mode", selection: selection.binding()) {
        PickerOption("First", value: 1)
        if showSecond {
          PickerOption("Second", value: 2)
        }
        PickerOption("Third", value: 3)
      }.pickerStyle(.inline)
      Button("Toggle second") { showSecond.toggle() }
    }
  }
}

private struct SetBDisabledFixture: View {
  let opened: SetBValueProbe<Int>
  let pressed: SetBValueProbe<Int>

  var body: some View {
    VStack {
      VStack {
        Text("Note")
        Text("See \(Link("Guide", destination: "https://example.com/guide")) now")
      }.disabled(true)
      Text("Read \(Link("Manual", destination: "https://example.com/manual")) too")
      Button {
        pressed.value += 1
      } label: {
        Text("Go").disabled(true)
      }
    }.openLinkAction(
      OpenLinkAction { _ in
        opened.value += 1
        return true
      })
  }
}

private struct SetBMultiSelectTableFixture: View {
  let ids: [Int]
  @State private var members: Set<Int>

  init(ids: [Int], members: Set<Int>) {
    self.ids = ids
    _members = State(initialValue: members)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Table(ids, id: \.self, selection: $members, columns: [TableColumn("Value", width: 12)]) {
        id in
        Text("Row \(id)")
      }
      .tableHeaders(.hidden)
      .frame(height: 9)
      Text("members=\(members.sorted())")
    }
  }
}

private struct SetBMultiSelectListFixture: View {
  let ids: [Int]
  @State private var members: Set<Int>

  init(ids: [Int], members: Set<Int>) {
    self.ids = ids
    _members = State(initialValue: members)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(ids, id: \.self, selection: $members) { id in
        Text("Record \(id)")
      }
      .frame(height: 7)
      Text("members=\(members.sorted())")
    }
  }
}

private struct SetBRoleSwapFixture: View {
  @State private var useToggle = true
  @State private var flag = false

  var body: some View {
    VStack {
      if useToggle {
        Toggle("Same", isOn: $flag).id(testIdentity("SetBAccessibility", "Same"))
      } else {
        Button("Same") { flag.toggle() }.id(testIdentity("SetBAccessibility", "Same"))
      }
      Button("Swap") { useToggle.toggle() }
      Text("flag=\(flag)")
    }
  }
}

private struct SetBEmptyLinkFixture: View {
  let seen: SetBValueProbe<[String]>

  var body: some View {
    VStack {
      Link("Home", destination: "")
      Text("Inline \(Link("Docs", destination: "")) link")
    }.openLinkAction(
      OpenLinkAction { destination in
        seen.value.append(destination.rawValue)
        return true
      })
  }
}
