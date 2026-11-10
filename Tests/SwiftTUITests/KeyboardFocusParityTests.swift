import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct KeyboardFocusParityTests {
  @Test("Tab visits every counter control through a composed tab and toolbar shell")
  func counterTraversal() throws {
    let state = KeyboardParityState()
    let h = try harness(state)
    defer { h.shutdown() }
    let tracker = h.runLoop.focusTracker
    _ = try h.focus(testIdentity("Minus"))
    for name in ["Plus", "Step", "Reset", "Toolbar"] {
      _ = try h.pressKey(KeyPress(.tab))
      #expect(tracker.currentFocusIdentity == testIdentity(name))
    }
    for name in ["Reset", "Step", "Plus", "Minus"] {
      _ = try h.pressKey(KeyPress(.tab, modifiers: .shift))
      #expect(tracker.currentFocusIdentity == testIdentity(name))
    }
    _ = try h.pressKey(KeyPress(.tab))
    _ = try h.pressKey(KeyPress(.space))
    #expect(state.count == 1)
  }

  @Test(
    "content keys cannot change an enclosing TabView's strip state",
    arguments: [
      KeyPress(.arrowLeft), KeyPress(.arrowRight), KeyPress(.home), KeyPress(.end),
      KeyPress(.arrowDown), KeyPress(.arrowUp), KeyPress(.tab),
      KeyPress(.tab, modifiers: .shift), KeyPress(.escape),
    ])
  func contentDoesNotOwnStrip(key: KeyPress) throws {
    let state = KeyboardParityState()
    let h = try harness(state)
    defer { h.shutdown() }
    let owner = try #require(h.runLoop.renderer.viewGraph.nodeForIdentity(testIdentity("Tabs")))
    let tags = (0..<3).map { SelectionTag(value: $0) }
    // Keep a hidden cursor so declined descendant keys cannot pass by only
    // preserving selection while still mutating tab state (STUI-1524).
    TabSelectionState.setStoredFocusedTabIndex(1, tags: tags, in: owner)
    _ = try h.focus(testIdentity("Minus"))
    let before = TabSelectionState.storedFocusedTabIndex(in: owner, tags: tags)
    let expanded = TabSelectionState.storedTabOverflowMenuExpanded(in: owner)
    _ = try h.pressKey(key)
    #expect(state.selection == 0)
    #expect(TabSelectionState.storedFocusedTabIndex(in: owner, tags: tags) == before)
    #expect(TabSelectionState.storedTabOverflowMenuExpanded(in: owner) == expanded)
    if key.key != .tab {
      #expect(h.runLoop.focusTracker.currentFocusIdentity == testIdentity("Minus"))
    }
  }

  @Test("a live focus change before a frame prevents stale TabView ownership")
  func batchedOwnership() throws {
    let state = KeyboardParityState()
    let h = try harness(state)
    defer { h.shutdown() }
    _ = try h.focus(testIdentity("Tabs"))
    let owner = try #require(h.runLoop.renderer.viewGraph.nodeForIdentity(testIdentity("Tabs")))
    let tags = (0..<3).map { SelectionTag(value: $0) }
    let before = TabSelectionState.storedFocusedTabIndex(in: owner, tags: tags)
    #expect(h.runLoop.handleKeyPress(KeyPress(.tab)) == nil)
    #expect(h.runLoop.focusTracker.currentFocusIdentity == testIdentity("Minus"))
    #expect(h.runLoop.handleKeyPress(KeyPress(.arrowRight)) == nil)
    _ = try h.render()
    #expect(state.selection == 0)
    #expect(TabSelectionState.storedFocusedTabIndex(in: owner, tags: tags) == before)
  }

  @Test("nested authored sections keep every member after reorder and hidden children")
  func nestedSections() throws {
    let state = KeyboardParityState()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedSections"), size: .init(width: 60, height: 20)
    ) {
      VStack {
        if state.reversed { Button("Outside") {}.id(testIdentity("Outside")) }
        VStack {
          Button("First") {}.id(testIdentity("First"))
          HStack {
            Button("Second") {}.id(testIdentity("Second"))
            Button("Disabled") {}.disabled(true)
            if state.showHidden { Button("Hidden") {} }
            Button("Third") {}.id(testIdentity("Third"))
          }.focusSection()
          EmptyView().focusSection()
          Button("Fourth") {}.id(testIdentity("Fourth"))
        }.focusSection()
        if !state.reversed { Button("Outside") {}.id(testIdentity("Outside")) }
      }
    }
    defer { h.shutdown() }
    for reversed in [false, true, false] {
      state.reversed = reversed
      _ = try h.renderAfterExternalMutation()
      _ = try h.focus(testIdentity("First"))
      for name in ["Second", "Third", "Fourth", "Outside", "First"] {
        _ = try h.pressKey(KeyPress(.tab))
        #expect(h.runLoop.focusTracker.currentFocusIdentity == testIdentity(name))
      }
    }
  }

  @Test("Lists inside one authored section retain separate active-row entry and exit")
  func listTraversal() throws {
    let state = KeyboardParityState()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("ListSectionParity"), size: .init(width: 60, height: 24)
    ) {
      VStack {
        Button("Before") {}.id(testIdentity("Before"))
        VStack {
          List(
            0..<3, id: \.self,
            selection: Binding(get: { state.firstRow }, set: { state.firstRow = $0 })
          ) { row in Text("A\(row)") }.frame(height: 5)
          Button("Peer") {}.id(testIdentity("Peer"))
          List(
            0..<3, id: \.self,
            selection: Binding(get: { state.secondRow }, set: { state.secondRow = $0 })
          ) { row in Text("B\(row)") }.frame(height: 5)
        }.focusSection()
        Button("After") {}.id(testIdentity("After"))
      }
    }
    defer { h.shutdown() }
    let expected = try [
      testIdentity("Before"), h.focusIdentity(forText: "A1"), testIdentity("Peer"),
      h.focusIdentity(forText: "B2"), testIdentity("After"),
    ]
    _ = try h.focus(expected[0])
    for target in expected.dropFirst() {
      _ = try h.pressKey(KeyPress(.tab))
      #expect(h.runLoop.focusTracker.currentFocusIdentity == target)
    }
    for target in expected.dropLast().reversed() {
      _ = try h.pressKey(KeyPress(.tab, modifiers: .shift))
      #expect(h.runLoop.focusTracker.currentFocusIdentity == target)
    }
    #expect(state.firstRow == 1)
    #expect(state.secondRow == 2)
  }

  @Test(
    "native strip cursor wraps and survives a Tab round trip without selecting",
    arguments: [
      AnyTabViewStyle.automatic, .underline, .literalTabs, .powerline,
      AnyTabViewStyle(KeyboardParityTabStyle()),
    ])
  func nativeStripCursor(style: AnyTabViewStyle) throws {
    let state = KeyboardParityState()
    let h = try harness(state, style: style)
    defer { h.shutdown() }
    _ = try h.focus(testIdentity("Tabs"))
    _ = try h.pressKey(KeyPress(.arrowLeft))
    #expect(state.selection == 0)
    _ = try h.pressKey(KeyPress(.home))
    _ = try h.pressKey(KeyPress(.end))
    _ = try h.pressKey(KeyPress(.return))
    #expect(state.selection == 0, "Return does not activate a native tab-strip item")
    _ = try h.pressKey(KeyPress(.tab))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == testIdentity("Minus"))
    _ = try h.pressKey(KeyPress(.tab, modifiers: .shift))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == testIdentity("Tabs"))
    _ = try h.pressKey(KeyPress(.space))
    #expect(state.selection == 2)
    _ = try h.pressKey(KeyPress(.arrowRight))
    #expect(state.selection == 2)
    _ = try h.pressKey(KeyPress(.space))
    #expect(state.selection == 0)
  }

  @Test("slider editing consumes arrows without moving the enclosing strip")
  func sliderOwnership() throws {
    let state = KeyboardParityState()
    let h = try harness(state)
    defer { h.shutdown() }
    _ = try h.focus(testIdentity("Step"))
    _ = try h.pressKey(KeyPress(.arrowRight))
    #expect(state.step == 2)
    #expect(state.selection == 0)
    #expect(h.runLoop.focusTracker.currentFocusIdentity == testIdentity("Step"))
  }

  @Test("nested tab strips and editors cannot mutate outer strip state")
  func nestedOwnership() throws {
    let state = KeyboardParityState()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedOwnership"), size: .init(width: 60, height: 20)
    ) {
      TabView(selection: Binding(get: { state.selection }, set: { state.selection = $0 })) {
        Tab("Outer first", value: 0) {
          TabView(selection: Binding(get: { state.innerTab }, set: { state.innerTab = $0 })) {
            Tab("Inner first", value: 0) {
              TextField("Editor", text: Binding(get: { state.text }, set: { state.text = $0 }))
                .id(testIdentity("Editor"))
            }
            Tab("Inner second", value: 1) { Text("Other") }
          }.id(testIdentity("InnerTabs"))
        }
        Tab("Outer second", value: 1) { Text("Other") }
      }.id(testIdentity("OuterTabs"))
        .onKeyPress(.arrowRight) { _ in
          state.interceptions += 1
          return state.intercept ? .handled : .ignored
        }
    }
    defer { h.shutdown() }
    let outer = try #require(
      h.runLoop.renderer.viewGraph.nodeForIdentity(testIdentity("OuterTabs")))
    let tags = [SelectionTag(value: 0), SelectionTag(value: 1)]
    _ = try h.focus(testIdentity("Editor"))
    for key in [KeyPress(.arrowRight), KeyPress(.end), KeyPress(.arrowRight)] {
      _ = try h.pressKey(key)
      #expect(h.runLoop.focusTracker.currentFocusIdentity == testIdentity("Editor"))
      #expect(TabSelectionState.storedFocusedTabIndex(in: outer, tags: tags) == nil)
    }
    _ = try h.focus(testIdentity("InnerTabs"))
    state.intercept = true
    _ = try h.pressKey(KeyPress(.arrowRight))
    _ = try h.pressKey(KeyPress(.space))
    #expect(state.innerTab == 0)
    state.intercept = false
    _ = try h.pressKey(KeyPress(.arrowLeft))
    _ = try h.pressKey(KeyPress(.space))
    #expect(state.innerTab == 1)
    #expect(state.selection == 0)
    #expect(state.interceptions == 3)
    #expect(TabSelectionState.storedFocusedTabIndex(in: outer, tags: tags) == nil)
  }

  @Test("overflow navigation stays owned and Tab dismisses without losing its cursor")
  func overflowOwnership() throws {
    let state = KeyboardParityState()
    let h = try harness(state, style: .literalTabs, width: 20)
    defer { h.shutdown() }
    let owner = try #require(h.runLoop.renderer.viewGraph.nodeForIdentity(testIdentity("Tabs")))
    let tags = (0..<3).map { SelectionTag(value: $0) }
    _ = try h.focus(testIdentity("Tabs"))
    _ = try h.pressKey(KeyPress(.arrowLeft))
    _ = try h.pressKey(KeyPress(.arrowDown))
    #expect(TabSelectionState.storedTabOverflowMenuExpanded(in: owner))
    _ = try h.pressKey(KeyPress(.tab))
    #expect(!TabSelectionState.storedTabOverflowMenuExpanded(in: owner))
    let cursor = TabSelectionState.storedFocusedTabIndex(in: owner, tags: tags)
    _ = try h.pressKey(KeyPress(.arrowDown))
    #expect(!TabSelectionState.storedTabOverflowMenuExpanded(in: owner))
    #expect(TabSelectionState.storedFocusedTabIndex(in: owner, tags: tags) == cursor)
    _ = try h.pressKey(KeyPress(.tab, modifiers: .shift))
    _ = try h.pressKey(KeyPress(.arrowDown))
    #expect(TabSelectionState.storedTabOverflowMenuExpanded(in: owner))
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!TabSelectionState.storedTabOverflowMenuExpanded(in: owner))
  }

  private func harness(
    _ state: KeyboardParityState, style: AnyTabViewStyle = .automatic,
    width: Int = 70
  ) throws
    -> StressRuntimeHarness<some View>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("KeyboardParity"), size: .init(width: width, height: 24)
    ) {
      VStack {
        TabView(selection: Binding(get: { state.selection }, set: { state.selection = $0 })) {
          Tab("Counter", value: 0) {
            VStack {
              HStack {
                Button("Minus") { state.count -= 1 }.id(testIdentity("Minus"))
                Button("Plus") { state.count += 1 }.id(testIdentity("Plus"))
              }.focusSection()
              HStack {
                Slider(
                  "Step", value: Binding(get: { state.step }, set: { state.step = $0 }),
                  in: 1...9, step: 1
                ).id(testIdentity("Step"))
                Button("Reset") { state.count = 0 }.id(testIdentity("Reset"))
              }.focusSection()
            }.id(testIdentity("CounterIsland")).frame(maxWidth: .infinity)
          }
          Tab("Other", value: 1) { Text("Other content") }
          Tab("Third", value: 2) { Text("Third content") }
        }.tabViewStyle(style).id(testIdentity("Tabs"))
        Button("Toolbar") {}.id(testIdentity("Toolbar"))
      }
    }
  }
}

@MainActor
private final class KeyboardParityState {
  var text = "abc"
  var innerTab = 0
  var intercept = false
  var interceptions = 0
  var selection = 0
  var count = 0
  var step = 1
  var reversed = false
  var showHidden = false
  var firstRow: Int? = 1
  var secondRow: Int? = 2
}

private struct KeyboardParityTabStyle: TabViewStyle {
  var snapshotLabel: String { "KeyboardParityTabStyle" }

  @MainActor
  func presentation(for configuration: TabViewStyleConfiguration) -> TabViewStylePresentation {
    .init(
      stripHeight: 1, visibleOptionIndices: Array(configuration.options.indices), overflowMenu: nil)
  }

  @MainActor
  func makeBody(configuration: TabViewStyleBodyConfiguration) -> some View {
    VStack {
      HStack {
        ForEach(Array(configuration.items.indices), id: \.self) { index in
          let item = configuration.items[index]
          item.route { Text(item.label.displayText) }
        }
      }
      configuration.content
    }
  }
}
