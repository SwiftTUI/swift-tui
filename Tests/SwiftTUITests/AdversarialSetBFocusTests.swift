@_spi(Testing) import SwiftTUITestSupport
// Adversarial set B, pass 2: focus and modal restoration (121–130).
//
// Focus is reconciled every frame from three sources: the tracker's regions,
// the `@FocusState` binding registry, and the modal restoration stack that
// returns focus to a presentation's invoker. These probes put a request on
// one side of that reconciliation without a matching partner on the other:
// modals without focusable content, binding writes that name no live view,
// chained toasts sharing a source, item sheets that swap identity while open,
// a focused control that disappears, a request parked behind a collapsed
// disclosure, and the traversal ring with excluded members.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: focus and restoration", .serialized)
struct AdversarialSetBFocusTests {
  private func harness<V: View>(
    _ name: String, width: Int = 48, height: Int = 12, @ViewBuilder content: @escaping () -> V
  ) throws -> StressRuntimeHarness<V> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBFocus", name), size: .init(width: width, height: height),
      content: content)
  }

  // A modal whose content has no focusable control still returns focus to
  // its invoker when it closes.
  @Test func setB121ModalWithoutFocusableContentRestoresFocusToItsInvoker() throws {
    for usesCover in [false, true] {
      let kind = usesCover ? "cover" : "popover"
      let h = try harness("NoRegions-\(kind)") { SetBNoRegionsFixture(usesCover: usesCover) }
      defer { h.shutdown() }
      let opener = try h.focusIdentity(forText: "Open info")
      _ = try h.clickText("Open info")
      try #require(h.frame.contains("Details only"), "\(kind): \(h.frame)")
      _ = try h.pressKey(KeyPress(.escape))
      try #require(!h.frame.contains("Details only"), "\(kind): \(h.frame)")
      do {
        #expect(
          h.runLoop.focusTracker.currentFocusIdentity == opener,
          "\(kind): focus went to \(String(describing: h.runLoop.focusTracker.currentFocusIdentity))"
        )
      }
    }
  }

  // A `@FocusState` write naming a value no live view claims is dropped: the
  // binding resets to nil and keyboard focus is left where it was.
  @Test func setB122FocusStateWriteNamingNoLiveViewIsDropped() throws {
    let h = try harness("Ghost") { SetBGhostFocusFixture() }
    defer { h.shutdown() }
    let jump = try h.focusIdentity(forText: "Jump")
    let other = try h.focusIdentity(forText: "Other")
    _ = try h.clickText("Jump")
    do {
      #expect(h.frame.contains("field: nil"), "\(h.frame)")
      #expect(h.runLoop.focusTracker.currentFocusIdentity == jump, "\(h.frame)")
      _ = try h.pressKey(KeyPress(.tab))
      #expect(h.runLoop.focusTracker.currentFocusIdentity == other, "\(h.frame)")
      #expect(h.frame.contains("field: nil"), "\(h.frame)")
      _ = try h.pressKey(KeyPress(.tab))
      #expect(h.runLoop.focusTracker.currentFocusIdentity != nil, "Tab must keep traversing")
    }
  }

  // Two chained `.toast` modifiers dismiss independently: hiding the first
  // runs the first `onDismiss` only.
  @Test func setB123ChainedToastsDismissTheirOwnDeclaration() throws {
    let probe = SetBEventProbe()
    let h = try harness("Toasts") { SetBChainedToasts(probe: probe) }
    defer { h.shutdown() }
    _ = try h.clickText("Show both")
    try #require(h.frame.contains("Toast A") && h.frame.contains("Toast B"), "\(h.frame)")
    _ = try h.clickText("Hide A")
    #expect(!h.frame.contains("Toast A"), "\(h.frame)")
    #expect(h.frame.contains("Toast B"), "\(h.frame)")
    let afterA = probe.events
    _ = try h.clickText("Hide B")
    #expect(!h.frame.contains("Toast B"), "\(h.frame)")
    let afterB = probe.events
    do {
      #expect(afterA == ["A dismissed"], "\(afterA)")
      #expect(afterB == ["A dismissed", "B dismissed"], "\(afterB)")
    }
  }

  // Replacing a presented item with a different ID remounts the sheet; when
  // the replacement closes, focus returns to the original invoker. (The
  // modal-replacing-modal restoration class is STUI-779; this is the item
  // identity vector.)
  @Test func setB124ItemSheetIDSwapKeepsTheInvokerAsRestorationTarget() throws {
    let h = try harness("ItemSwap") { SetBItemSwapFixture() }
    defer { h.shutdown() }
    let opener = try h.focusIdentity(forText: "Open item")
    _ = try h.clickText("Open item")
    try #require(h.frame.contains("Item 1"), "\(h.frame)")
    _ = try h.clickText("Swap")
    try #require(h.frame.contains("Item 2"), "\(h.frame)")
    #expect(!h.frame.contains("Item 1"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.escape))
    try #require(!h.frame.contains("Item 2"), "\(h.frame)")
    do {
      #expect(
        h.runLoop.focusTracker.currentFocusIdentity == opener,
        "\(String(describing: h.runLoop.focusTracker.currentFocusIdentity))")
    }
  }

  // Removing the focused control from the tree resets the `@FocusState`
  // binding that named it.
  @Test func setB125RemovingTheFocusedControlResetsItsFocusState() throws {
    let h = try harness("Removed") { SetBRemovedFocusFixture() }
    defer { h.shutdown() }
    _ = try h.focus(SetBRemovedFocusFixture.fieldIdentity)
    try #require(h.frame.contains("field: name"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.character("r"), modifiers: .ctrl))
    try #require(!h.frame.contains("Name"), "the field is gone: \(h.frame)")
    #expect(h.runLoop.focusTracker.currentFocusIdentity != SetBRemovedFocusFixture.fieldIdentity)
    do {
      #expect(h.frame.contains("field: nil"), "\(h.frame)")
    }
  }

  // A finite but enormous popover anchor clamps into the host rect instead
  // of overflowing the cell conversion. (Non-finite anchors are STUI-773.)
  @Test func setB126HugeFinitePopoverAnchorsClampInsteadOfTrapping() async {
    await withKnownIssue(
      "scaledCellOffset converts extent × unit with Int(_:), which traps past 2^63"
    ) {
      await #expect(processExitsWith: .success) {
        let bounds = CellRect(origin: .zero, size: .init(width: 8, height: 1))
        let rect = PopoverAttachmentAnchor.point(UnitPoint(x: 1e300, y: 0)).attachmentRect(
          in: bounds)
        #expect(rect.origin.x >= 0 && rect.origin.x <= 8, "\(rect)")
      }
      await #expect(processExitsWith: .success) {
        let bounds = CellRect(origin: .zero, size: .init(width: 8, height: 3))
        let rect = PopoverAttachmentAnchor.point(UnitPoint(x: -1e300, y: 1e300)).attachmentRect(
          in: bounds)
        #expect(rect.origin.y >= 0 && rect.origin.y <= 3, "\(rect)")
      }
    }
    // A modest overshoot is representable; the presentation clamps it later.
    let modest = PopoverAttachmentAnchor.point(UnitPoint(x: 2, y: 2)).attachmentRect(
      in: CellRect(origin: .zero, size: .init(width: 8, height: 3)))
    #expect(modest.origin == CellPoint(x: 16, y: 6), "\(modest)")
  }

  // A focus request for a control that is not in the tree is dropped, not
  // parked: expanding the disclosure later does not steal focus.
  @Test func setB127PendingFocusRequestDoesNotStealFocusOnLaterExpansion() throws {
    let h = try harness("Collapsed") { SetBCollapsedRequestFixture() }
    defer { h.shutdown() }
    let expand = try h.focusIdentity(forText: "Expand")
    _ = try h.clickText("Request")
    let afterRequest = h.frame
    _ = try h.clickText("Expand")
    try #require(h.frame.contains("Inner") || h.frame.contains("_"), "\(h.frame)")
    do {
      #expect(afterRequest.contains("inner: false"), "\(afterRequest)")
      #expect(h.runLoop.focusTracker.currentFocusIdentity == expand, "\(h.frame)")
      #expect(h.frame.contains("inner: false"), "\(h.frame)")
    }
  }

  // Traversal wraps and skips disabled or explicitly unfocusable controls in
  // both directions.
  @Test func setB128TraversalWrapsAndSkipsExcludedControls() throws {
    let h = try harness("Ring") {
      VStack(alignment: .leading) {
        Button("Alpha") {}
        Button("Bravo") {}.disabled(true)
        Button("Charlie") {}.focusable(false)
        Button("Delta") {}
      }
    }
    defer { h.shutdown() }
    let alpha = try h.focusIdentity(forText: "Alpha")
    let delta = try h.focusIdentity(forText: "Delta")
    #expect(h.focusRegionCount == 2, "\(h.runLoop.focusTracker.focusRegions.map(\.identity))")
    _ = try h.focus(alpha)
    _ = try h.pressKey(KeyPress(.tab))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == delta)
    _ = try h.pressKey(KeyPress(.tab))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == alpha, "Tab wraps")
    _ = try h.pressKey(KeyPress(.tab, modifiers: .shift))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == delta, "Shift+Tab wraps backwards")
    _ = try h.pressKey(KeyPress(.tab, modifiers: .shift))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == alpha)
  }

  // Toggling an open sheet off and on inside one action is a net no-op: the
  // sheet keeps its state and `onDismiss` does not run.
  @Test func setB129NetNoOpToggleOfAnOpenSheetKeepsItsState() throws {
    let probe = SetBEventProbe()
    let h = try harness("Blip") { SetBNoOpToggleFixture(probe: probe) }
    defer { h.shutdown() }
    _ = try h.clickText("Open")
    _ = try h.clickText("S Increment")
    _ = try h.clickText("S Increment")
    try #require(h.frame.contains("S Count 2"), "\(h.frame)")
    _ = try h.focusText("S Increment")
    _ = try h.pressKey(KeyPress(.character("b"), modifiers: .ctrl))
    #expect(h.frame.contains("S Count 2"), "\(h.frame)")
    #expect(probe.events.isEmpty, "\(probe.events)")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!h.frame.contains("S Count"), "\(h.frame)")
    #expect(probe.events == ["dismissed"], "\(probe.events)")
  }

  // An alert that is queued behind a visible one and cancelled before it is
  // ever shown never runs its `onDismiss`.
  @Test func setB130CancellingAQueuedAlertRunsNoDismissal() throws {
    let probe = SetBEventProbe()
    let h = try harness("Queue") { SetBQueuedAlertFixture(probe: probe) }
    defer { h.shutdown() }
    _ = try h.clickText("Open both")
    try #require(h.frame.contains("Alert A"), "\(h.frame)")
    #expect(!h.frame.contains("Alert B"), "only the oldest prompt is visible: \(h.frame)")
    _ = try h.clickText("Cancel B")
    if h.frame.contains("Alert A") {
      _ = try h.clickText("Dismiss A")
    }
    #expect(!h.frame.contains("Alert A") && !h.frame.contains("Alert B"), "\(h.frame)")
    #expect(probe.events == ["A dismissed"], "\(probe.events)")
  }
}

@MainActor
private final class SetBEventProbe {
  var events: [String] = []
}

private struct SetBItem: Identifiable, Sendable {
  var id: String
}

private struct SetBNoRegionsFixture: View {
  let usesCover: Bool
  @State private var show = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("First") {}
      if usesCover {
        Button("Open info") { show = true }
          .fullScreenCover(isPresented: $show) { Text("Details only") }
      } else {
        Button("Open info") { show = true }
          .popover(isPresented: $show) { Text("Details only") }
      }
    }
  }
}

private struct SetBGhostFocusFixture: View {
  enum Field: Hashable { case name, ghost }
  @FocusState private var field: Field?
  @State private var text = ""

  var body: some View {
    VStack(alignment: .leading) {
      TextField("Name", text: $text).focused($field, equals: .name).textFieldStyle(.plain)
      Button("Jump") { field = .ghost }
      Button("Other") {}
      Text("field: \(field.map { "\($0)" } ?? "nil")")
    }
  }
}

private struct SetBChainedToasts: View {
  let probe: SetBEventProbe
  @State private var a = false
  @State private var b = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Show both") {
        a = true
        b = true
      }
      Button("Hide A") { a = false }
      Button("Hide B") { b = false }
    }
    .toast(
      "Toast A", isPresented: $a, duration: nil, onDismiss: { probe.events.append("A dismissed") }
    )
    .toast(
      "Toast B", isPresented: $b, duration: nil, onDismiss: { probe.events.append("B dismissed") })
  }
}

private struct SetBItemSwapFixture: View {
  @State private var item: SetBItem?

  var body: some View {
    VStack(alignment: .leading) {
      Button("First") {}
      Button("Open item") { item = SetBItem(id: "1") }
        .sheet(item: $item) { presented in
          VStack(alignment: .leading) {
            Text("Item \(presented.id)")
            Button("Swap") { item = SetBItem(id: "2") }
          }
        }
    }
  }
}

private struct SetBRemovedFocusFixture: View {
  static let fieldIdentity = testIdentity("SetBFocus", "RemovedField")
  enum Field: Hashable { case name }
  @FocusState private var field: Field?
  @State private var show = true
  @State private var text = ""

  var body: some View {
    Panel(id: "removal") {
      VStack(alignment: .leading) {
        if show {
          TextField("Name", text: $text).focused($field, equals: .name).textFieldStyle(.plain)
            .id(Self.fieldIdentity)
        }
        Button("Other") {}
        Text("field: \(field.map { "\($0)" } ?? "nil")")
      }
    }
    .keyCommand("Remove", key: .character("r"), modifiers: .ctrl) { show = false }
  }
}

private struct SetBCollapsedRequestFixture: View {
  @FocusState private var inner: Bool
  @State private var expanded = false
  @State private var text = ""

  var body: some View {
    VStack(alignment: .leading) {
      Button("Request") { inner = true }
      Button("Expand") { expanded = true }
      DisclosureGroup("Group", isExpanded: $expanded) {
        TextField("Inner", text: $text).focused($inner).textFieldStyle(.plain)
      }
      Text("inner: \(inner)")
    }
  }
}

private struct SetBCounterPane: View {
  let label: String
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(label) Count \(count)")
      Button("\(label) Increment") { count += 1 }
    }
  }
}

private struct SetBNoOpToggleFixture: View {
  let probe: SetBEventProbe
  @State private var show = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Open") { show = true }
    }
    .sheet("Sheet", isPresented: $show, onDismiss: { probe.events.append("dismissed") }) {
      Panel(id: "sheet") {
        SetBCounterPane(label: "S")
      }
      .keyCommand("Blip", key: .character("b"), modifiers: .ctrl) {
        show = false
        show = true
      }
    }
  }
}

private struct SetBQueuedAlertFixture: View {
  let probe: SetBEventProbe
  @State private var a = false
  @State private var b = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Open both") {
        a = true
        b = true
      }
    }
    .alert("Alert A", isPresented: $a, onDismiss: { probe.events.append("A dismissed") }) {
      Button("Cancel B") { b = false }
      Button("Dismiss A") { a = false }
    } message: {
      Text("A body")
    }
    .alert("Alert B", isPresented: $b, onDismiss: { probe.events.append("B dismissed") })
  }
}
