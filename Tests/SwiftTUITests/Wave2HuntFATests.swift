import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two, wave-2 regression hunt part FA (STUI-1165): forty pre-specified
// neighbours of the wave-2 repairs FW-A (92dc2e5a), FW-B (9f203f8b), FW-D
// (8236b3f2) and the STUI-1211 SPI (2fde3a6f). Contracts, inputs and
// predictions: docs/reports/evidence/2026-10-25-campaign-two-wave-2-hunt/fa/
// in the coordination root. Reproduced expectations are wrapped in
// `w2faKnown`; `SWIFTTUI_W2HUNT_UNMARKED=1` runs them as plain assertions.

@MainActor
func w2faKnown(_ comment: Comment, _ body: () -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_W2HUNT_UNMARKED"] == "1" {
    body()
  } else {
    withKnownIssue(comment) { body() }
  }
}

// MARK: - FW-A: scroll edges, table eligibility, editor keys, hidden separators

@MainActor
@Suite(.serialized)
struct Wave2HuntFAScrollTableTests {
  // w2fa001: a click on a visible row of a data-driven table whose separators
  // are hidden selects that row (Collections.md:39-43; StyleModifiers.swift:1616-1622).
  @Test func w2fa001HiddenSeparatorTableClickSelectsLowVisibleRow() throws {
    // Control: with separators drawn the lowest visible rows are clickable.
    let drawnBox = W2FASelection<String>(selected: W2FA.paddedID(100, prefix: "r"))
    let drawn = try W2FA.hiddenSeparatorTable("w2fa001-drawn", box: drawnBox, hidden: false)
    defer { drawn.shutdown() }
    let drawnVisible = W2FA.visibleIDs(in: drawn.frame, prefix: "r", digits: 3)
    try #require(drawnVisible.count >= 20, "\(drawn.frame)")
    _ = try drawn.clickText(drawnVisible[drawnVisible.count - 2])
    #expect(drawnBox.selected == drawnVisible[drawnVisible.count - 2])

    let box = W2FASelection<String>(selected: W2FA.paddedID(100, prefix: "r"))
    let h = try W2FA.hiddenSeparatorTable("w2fa001", box: box)
    defer { h.shutdown() }
    let visible = W2FA.visibleIDs(in: h.frame, prefix: "r", digits: 3)
    try #require(visible.count >= 40, "\(h.frame)")
    try #require(visible.first != "r000", "the window must sit away from the dataset start")
    let target = visible[visible.count - 2]
    _ = try h.clickText(target)
    // STUI-1239: the band counts the rows the window shows by their line span.
    #expect(
      box.selected == target, "clicked \(target); visible \(visible.first!)…\(visible.last!)")
    // Control: a row near the top of the same window is clickable.
    _ = try h.clickText(visible[3])
    #expect(box.selected == visible[3])
  }

  // w2fa002: the same row's assistive selection button activates it.
  @Test func w2fa002HiddenSeparatorTableActivatesLowVisibleRow() throws {
    let box = W2FASelection<String>(selected: W2FA.paddedID(100, prefix: "r"))
    let h = try W2FA.hiddenSeparatorTable("w2fa002", box: box)
    defer { h.shutdown() }
    let visible = W2FA.visibleIDs(in: h.frame, prefix: "r", digits: 3)
    try #require(visible.count >= 40, "\(h.frame)")
    try #require(visible.first != "r000")
    let target = visible[visible.count - 2]
    let rowNumber = try #require(Int(target.dropFirst())) + 1
    let node = try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Select row \(rowNumber)"
      })
    let actionTarget = try #require(node.actionTarget)
    let result = h.runLoop.handleAccessibilityAction(
      .init(target: actionTarget, action: .activate))
    _ = try h.render()
    // STUI-1239: the row action is registered for every visible row.
    #expect(result == .accepted, "\(String(describing: result))")
    #expect(box.selected == target)
  }

  // w2fa003: edge-specific hiding matches the static table on data-driven rows.
  @Test func w2fa003EdgeSpecificHiddenSeparatorsMatchStaticRows() {
    let data = W2FA.lines(
      Table(["a1", "b1", "c1", "d1"], id: \.self, columns: [TableColumn("Name")]) { row in
        if row == "b1" {
          Text(row).listRowSeparator(.hidden, edges: .bottom)
        } else if row == "d1" {
          Text(row).listRowSeparator(.hidden, edges: .top)
        } else {
          Text(row)
        }
      }, name: "w2fa003-data", width: 20, height: 16)
    let authored = W2FA.lines(
      Table(columns: [TableColumn("Name")]) {
        TableRow { Text("a1") }
        TableRow { Text("b1").listRowSeparator(.hidden, edges: .bottom) }
        TableRow { Text("c1") }
        TableRow { Text("d1").listRowSeparator(.hidden, edges: .top) }
      }, name: "w2fa003-static", width: 20, height: 16)
    let rows = W2FA.lineIndices(of: ["a1", "b1", "c1", "d1"], in: data)
    #expect(rows.count == 4, "\(data)")
    #expect(zip(rows.dropFirst(), rows).map { $0 - $1 } == [2, 1, 1], "\(data)")
    #expect(W2FA.nonBlank(data) == W2FA.nonBlank(authored), "data \(data) static \(authored)")
  }

  // w2fa004: tall rows with hidden separators stay contiguous through End.
  @Test func w2fa004TallRowsWithHiddenSeparatorsReachEnd() throws {
    let rows = (0..<20).map { W2FARow(id: "t\($0)") }
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa004"),
      size: .init(width: 20, height: 12)
    ) {
      Table(rows, columns: [TableColumn("Name")]) { row in
        VStack(alignment: .leading, spacing: 0) {
          Text(row.id)
          Text("u\(row.id.dropFirst())")
        }.listRowSeparator(.hidden)
      }.tableHeaders(.hidden).scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.tab))
    _ = try h.pressKey(.init(.end))
    let lines = h.frame.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(h.frame.contains("u19"), "\(h.frame)")
    let visible = W2FA.visibleIDs(in: h.frame, prefix: "t", digits: nil)
    try #require(visible.count >= 2, "\(h.frame)")
    for id in visible {
      let number = id.dropFirst()
      let first = W2FA.lineIndices(of: ["t\(number)"], in: lines)
      let second = W2FA.lineIndices(of: ["u\(number)"], in: lines)
      if let a = first.first, let b = second.first {
        #expect(b == a + 1, "row \(id) lines \(a), \(b)\n\(h.frame)")
      }
    }
    let starts = W2FA.lineIndices(of: visible, in: lines)
    #expect(zip(starts.dropFirst(), starts).allSatisfy { $0 - $1 == 2 }, "\(h.frame)")
  }

  // w2fa005: PageDown keeps one row of overlap when separators take no line.
  @Test func w2fa005HiddenSeparatorPageDownAdvancesVisibleRows() throws {
    let rows = (0..<60).map { W2FARow(id: W2FA.paddedID($0, prefix: "p", digits: 2)) }
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa005"),
      size: .init(width: 20, height: 12)
    ) {
      Table(rows, columns: [TableColumn("Name")]) { row in
        Text(row.id).listRowSeparator(.hidden)
      }.tableHeaders(.hidden).scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.tab))
    let before = W2FA.visibleIDs(in: h.frame, prefix: "p", digits: 2)
    try #require(before.first == "p00" && before.count >= 4, "\(h.frame)")
    _ = try h.pressKey(.init(.pageDown))
    let after = W2FA.visibleIDs(in: h.frame, prefix: "p", digits: 2)
    #expect(after.first == before.last, "before \(before) after \(after)")
  }

  // w2fa006: a disabled data-driven Table row's selection button is disabled
  // for assistive technology, as the List row's is (STUI-1172 claim).
  @Test func w2fa006DisabledTableRowSelectionButtonIsDisabled() throws {
    let tableBox = W2FASelection<Int>(selected: 1)
    let table = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa006-table"),
      size: .init(width: 20, height: 8)
    ) {
      Table(
        [1, 2, 3], id: \.self, selection: tableBox.binding,
        columns: [TableColumn("Name", width: 12)]
      ) { i in
        Text("row\(i)").disabled(i == 2)
      }.tableHeaders(.hidden)
    }
    defer { table.shutdown() }
    let listBox = W2FASelection<Int>(selected: 1)
    let list = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa006-list"),
      size: .init(width: 20, height: 8)
    ) {
      List([1, 2, 3], id: \.self, selection: listBox.binding) { i in
        Text("row\(i)").disabled(i == 2)
      }
    }
    defer { list.shutdown() }
    func button(_ h: StressRuntimeHarness<some View>, _ label: String) throws -> AccessibilityNode {
      try #require(
        h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == label })
    }
    #expect(try button(list, "Select row 2").isEnabled == false, "List control")
    #expect(try button(table, "Select row 1").isEnabled == true)
    let disabledRow = try button(table, "Select row 2")
    // STUI-1240: the selector follows the row's interaction availability.
    #expect(disabledRow.isEnabled == false)
  }

  // w2fa007: multi-select arrows skip the disabled row; Space toggles the cursor row.
  @Test func w2fa007MultiSelectArrowsSkipDisabledRow() throws {
    let box = W2FAMultiSelection()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa007"),
      size: .init(width: 20, height: 8)
    ) {
      Table(
        [1, 2, 3, 4], id: \.self, selection: box.binding,
        columns: [TableColumn("Name", width: 12)]
      ) { i in
        Text("row\(i)").disabled(i == 2)
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.focusText("row1")
    _ = try h.pressKey(.init(.arrowDown))
    _ = try h.pressKey(.init(.space))
    _ = try h.pressKey(.init(.arrowDown))
    _ = try h.pressKey(.init(.space))
    #expect(box.selected == [3, 4])
  }

  // w2fa008: the initial multi-select cursor on a disabled first row cannot toggle it.
  @Test func w2fa008MultiSelectInitialCursorOnDisabledRowDoesNotToggle() throws {
    let box = W2FAMultiSelection()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa008"),
      size: .init(width: 20, height: 8)
    ) {
      Table(
        [1, 2, 3], id: \.self, selection: box.binding,
        columns: [TableColumn("Name", width: 12)]
      ) { i in
        Text("row\(i)").disabled(i == 1)
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.focusText("row2")
    _ = try h.pressKey(.init(.space))
    #expect(box.selected.isEmpty)
    _ = try h.pressKey(.init(.arrowDown))
    _ = try h.pressKey(.init(.space))
    #expect(box.selected == [2])
  }

  // w2fa009: a static row whose every cell is disabled is skipped.
  @Test func w2fa009StaticRowWithAllCellsDisabledIsSkipped() throws {
    let box = W2FASelection<Int>(selected: 1)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa009"),
      size: .init(width: 24, height: 8)
    ) {
      Table(
        selection: box.binding,
        columns: [TableColumn("A", width: 6), TableColumn("B", width: 6)]
      ) {
        TableRow {
          Text("a1")
          Text("b1")
        }.tag(1)
        TableRow {
          Text("a2").disabled(true)
          Text("b2").disabled(true)
        }.tag(2)
        TableRow {
          Text("a3")
          Text("b3")
        }.tag(3)
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.focusText("a1")
    _ = try h.pressKey(.init(.arrowDown))
    #expect(box.selected == 3)
  }

  // w2fa010: End on a two-axis view whose content fits vertically leaves x alone.
  @Test func w2fa010TwoAxisEndWithoutVerticalOverflowKeepsHorizontalOffset() throws {
    let offset = W2FAOffset()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa010"),
      size: .init(width: 12, height: 6)
    ) {
      ScrollView([.horizontal, .vertical], position: offset.binding) {
        Text("wide").frame(width: 40, height: 4)
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    try #require(h.runLoop.focusTracker.currentFocusIdentity != nil)
    _ = try h.pressKey(.init(.arrowRight))
    try #require(offset.value == .init(x: 1, y: 0), "\(offset.value)")
    _ = try h.pressKey(.init(.end))
    #expect(offset.value == .init(x: 1, y: 0), "\(offset.value)")
  }

  // w2fa011: End on a horizontal variable-width lazy stack reaches the last item.
  @Test func w2fa011HorizontalLazyEndReachesLastVariableWidthItem() throws {
    let offset = W2FAOffset()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa011"),
      size: .init(width: 20, height: 3)
    ) {
      ScrollView(.horizontal, position: offset.binding) {
        LazyHStack(spacing: 0) {
          ForEach(0..<120, id: \.self) { i in
            Text(i == 119 ? "Z" : ".").frame(width: i < 40 ? 1 : 3)
          }
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.end))
    let route = try #require(h.runLoop.latestSemanticSnapshot.scrollRoutes.first)
    let maximum = max(0, route.contentBounds.size.width - route.viewportRect.size.width)
    #expect(h.frame.contains("Z"), "\(h.frame)")
    #expect(offset.value.x == maximum, "\(offset.value) of \(maximum)")
  }

  // w2fa012: the assistive "Scroll to bottom" command refines like End.
  @Test func w2fa012AccessibilityScrollToBottomReachesLastVariableRow() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa012"),
      size: .init(width: 20, height: 8)
    ) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<120, id: \.self) { i in Text("vrow \(i)").frame(height: i < 40 ? 1 : 3) }
        }
      }.scrollIndicators(.hidden).accessibilityLabel("Lazy rows")
    }
    defer { h.shutdown() }
    let target = try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Lazy rows"
      }?.actionTarget)
    let result = h.runLoop.handleAccessibilityAction(
      .init(target: target, action: .custom("Scroll to bottom")))
    _ = try h.render()
    #expect(result == .accepted)
    #expect(h.frame.contains("vrow 119"), "\(h.frame)")
  }

  // w2fa013: two pending far edges from one action both refine. The outcome
  // must not depend on which view the registry visits first: it visits
  // routes in frame order, so swapping the views (and the command order)
  // pins both orders.
  @Test(arguments: [false, true])
  func w2fa013TwoProxyBottomEdgesInOneActionBothRefine(swapped: Bool) throws {
    let proxies = W2FAProxies()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa013", swapped ? "swapped" : "ordered"),
      size: .init(width: 30, height: 9)
    ) {
      HStack(alignment: .top, spacing: 1) {
        ScrollViewReader { proxy in
          let _ = proxies.store(proxy, left: true)
          W2FA.variableLazy(prefix: swapped ? "b" : "a")
        }
        ScrollViewReader { proxy in
          let _ = proxies.store(proxy, left: false)
          W2FA.variableLazy(prefix: swapped ? "a" : "b")
        }
        Button("jump") {
          let order = swapped ? [proxies.right, proxies.left] : [proxies.left, proxies.right]
          for proxy in order { _ = proxy?.scrollTo(edge: .bottom) }
        }
      }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("a0") && h.frame.contains("b0"), "\(h.frame)")
    _ = try h.clickText("jump")
    // STUI-1243: sync refines every pending far edge in the same eager pass.
    #expect(h.frame.contains("a119") && h.frame.contains("b119"), "\(h.frame)")
  }

  // w2fa014: a focused field in a scroll-backed List owns a no-op End.
  @Test func w2fa014ListRowTextFieldOwnsNoOpEnd() throws {
    let text = W2FAText()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa014"),
      size: .init(width: 20, height: 8)
    ) {
      List(0..<40, id: \.self) { i in
        if i == 0 {
          TextField("Name", text: text.binding)
        } else {
          Text("item\(i)")
        }
      }
    }
    defer { h.shutdown() }
    let field = try h.focusIdentity(forText: "seed")
    _ = try h.focus(field)
    _ = try h.pressKey(.init(.end))
    _ = try h.pressKey(.init(.end))
    #expect(h.frame.contains("seed"), "\(h.frame)")
    #expect(!h.frame.contains("item39"), "\(h.frame)")
    #expect(h.runLoop.focusTracker.currentFocusIdentity == field)
    #expect(text.value == "seed")
  }
}

// MARK: - FW-B: retired state writes, initial change events, signal reader end

@MainActor
@Suite(.serialized)
struct Wave2HuntFAStateEventTests {
  // w2fa015: an imperative dispatch between two one-shot snapshot renders of the
  // same view value carries to the second render (State.swift:612-650), also
  // when the first renderer is gone.
  @Test func w2fa015SnapshotDispatchSurvivesReleasedRenderer() throws {
    let view = W2FASnapshotCounter()
    // Control: the first renderer stays alive across the dispatch.
    let liveRegistry = LocalActionRegistry()
    let liveRenderer = DefaultRenderer()
    defer { withExtendedLifetime(liveRenderer) {} }
    let live = liveRenderer.render(
      view,
      context: .init(
        identity: testIdentity("w2fa015-live"), localActionRegistry: liveRegistry,
        applyEnvironmentValues: true))
    try #require(live.rasterSurface.lines.contains { $0.contains("Count 0") })
    let liveAction = try #require(live.semanticSnapshot.focusRegions.first?.identity)
    #expect(liveRegistry.dispatch(identity: liveAction))
    let liveSecond = DefaultRenderer().render(
      view, context: .init(identity: testIdentity("w2fa015-live")))
    #expect(liveSecond.rasterSurface.lines.contains { $0.contains("Count 1") })

    let released = W2FASnapshotCounter()
    let registry = LocalActionRegistry()
    let action = try #require(
      W2FA.renderWithReleasedRenderer(released, registry: registry, name: "w2fa015"))
    W2FA.withRetiredWriteDiagnostics {
      #expect(registry.dispatch(identity: action))
    }
    let second = DefaultRenderer().render(
      released, context: .init(identity: testIdentity("w2fa015")))
    // STUI-1241: the capture records that its owner was a snapshot owner, so
    // the missed write keeps the seed mirror instead of being discarded.
    #expect(
      second.rasterSurface.lines.contains { $0.contains("Count 1") },
      "\(second.rasterSurface.lines)")
  }

  // w2fa016: a retired write after an `.id` change never seeds a later mount.
  @Test func w2fa016RetiredWriteAfterIdentityChangeDoesNotSeedRemount() throws {
    let log = W2FACaptureLog<Int>()
    let leaf = W2FACounterLeaf(log: log)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa016"),
      size: .init(width: 20, height: 3)
    ) {
      leaf.id(log.token)
    }
    defer { h.shutdown() }
    let retired = try #require(log.entries.first)
    retired.write(5)
    _ = try h.render()
    try #require(h.frame.contains("v5"), "\(h.frame)")
    log.token = 1
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("v0"), "\(h.frame)")
    W2FA.withRetiredWriteDiagnostics { retired.write(99) }
    log.token = 2
    _ = try h.renderAfterExternalMutation()
    #expect(h.frame.contains("v0"), "\(h.frame)")
    #expect(try #require(log.entries.last).read() == 0)
  }

  // w2fa017: a retired write through a composed DynamicProperty is discarded.
  @Test func w2fa017RetiredComposedWriteDoesNotSeedRemount() throws {
    let log = W2FACaptureLog<String>()
    let leaf = W2FAComposedLeaf(log: log)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa017"),
      size: .init(width: 20, height: 3)
    ) {
      if log.visible { leaf } else { Text("absent") }
    }
    defer { h.shutdown() }
    let retired = try #require(log.entries.first)
    retired.write("live")
    _ = try h.render()
    try #require(h.frame.contains("c:live"), "\(h.frame)")
    log.visible = false
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("absent"))
    W2FA.withRetiredWriteDiagnostics { retired.write("retired") }
    log.visible = true
    _ = try h.renderAfterExternalMutation()
    #expect(h.frame.contains("c:seed"), "\(h.frame)")
    #expect(try #require(log.entries.last).read() == "seed")
  }

  // w2fa018: a ForEach row removed from data and re-added starts from its seed.
  @Test func w2fa018RetiredRowWriteDoesNotSeedReaddedRow() throws {
    let rows = W2FARows(ids: ["a", "b", "c"])
    let logs = ["a", "b", "c"].reduce(into: [String: W2FACaptureLog<Int>]()) {
      $0[$1] = W2FACaptureLog<Int>(label: $1)
    }
    let leaves = logs.mapValues { W2FACounterLeaf(log: $0) }
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa018"),
      size: .init(width: 20, height: 5)
    ) {
      VStack(spacing: 0) {
        ForEach(rows.ids, id: \.self) { id in leaves[id]! }
      }
    }
    defer { h.shutdown() }
    let log = try #require(logs["b"])
    let retired = try #require(log.entries.first)
    retired.write(4)
    _ = try h.render()
    try #require(h.frame.contains("bv4"), "\(h.frame)")
    rows.ids = ["a", "c"]
    _ = try h.renderAfterExternalMutation()
    try #require(!h.frame.contains("bv"), "\(h.frame)")
    W2FA.withRetiredWriteDiagnostics { retired.write(9) }
    rows.ids = ["a", "b", "c"]
    _ = try h.renderAfterExternalMutation()
    #expect(h.frame.contains("bv0"), "\(h.frame)")
  }

  // w2fa019: optional content (`if let` without else) delivers its initial event.
  @Test func w2fa019OptionalContentDeliversInitialChange() throws {
    let log = W2FAChangeLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa019"),
      size: .init(width: 20, height: 3)
    ) {
      if let value = log.optional {
        Text("v").onChange(of: value, initial: true) { old, new in log.pairs.append([old, new]) }
      }
    }
    defer { h.shutdown() }
    #expect(log.pairs == [[1, 1]])
    _ = try h.renderAfterExternalMutation()
    #expect(log.pairs == [[1, 1]])
  }

  // w2fa020: conditional content in ForEach rows delivers each initial event once.
  @Test func w2fa020ForEachConditionalRowsDeliverInitialChanges() throws {
    let log = W2FAChangeLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa020"),
      size: .init(width: 20, height: 5)
    ) {
      VStack(spacing: 0) {
        ForEach(0..<3, id: \.self) { i in
          if i != 1 {
            Text("r\(i)").onChange(of: i, initial: true) { _, new in log.values.append(new) }
          } else {
            Text("skip")
          }
        }
      }
    }
    defer { h.shutdown() }
    #expect(log.values.sorted() == [0, 2], "\(log.values)")
  }

  // w2fa021: lazily realized conditional rows deliver their initial events once.
  @Test func w2fa021LazyConditionalRowsDeliverInitialChangesOnce() throws {
    let log = W2FAChangeLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa021"),
      size: .init(width: 20, height: 6)
    ) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<60, id: \.self) { i in
            if i.isMultiple(of: 2) {
              Text("e\(i)").onChange(of: i, initial: true) { _, new in log.values.append(new) }
            } else {
              Text("o\(i)")
            }
          }
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    func visibleEven() -> [Int] {
      W2FA.visibleIDs(in: h.frame, prefix: "e", digits: nil).compactMap { Int($0.dropFirst()) }
    }
    let top = visibleEven()
    try #require(!top.isEmpty, "\(h.frame)")
    for row in top {
      #expect(log.values.filter { $0 == row }.count == 1, "row \(row): \(log.values)")
    }
    _ = try h.pressKey(.init(.end))
    let bottom = visibleEven()
    try #require(bottom.contains(58), "\(h.frame)")
    for row in bottom {
      #expect(log.values.filter { $0 == row }.count == 1, "row \(row): \(log.values)")
    }
  }

  // w2fa022: an AnyView-erased conditional delivers its initial event.
  @Test func w2fa022AnyViewConditionalDeliversInitialChange() throws {
    let log = W2FAChangeLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa022"),
      size: .init(width: 20, height: 3)
    ) {
      AnyView(
        log.visible
          ? AnyView(
            Text("x").onChange(of: 1, initial: true) { old, new in log.pairs.append([old, new]) })
          : AnyView(Text("y")))
    }
    defer { h.shutdown() }
    #expect(log.pairs == [[1, 1]])
  }

  // w2fa023: a handler that reinstalls itself mid-flush sees each buffered signal once.
  @Test func w2fa023ReinstallDuringFlushDeliversEachSignalOnce() {
    let reader = InProcessSignalReader()
    let trace = Mutex<[String]>([])
    defer { reader.finish() }
    for value in ["A", "B", "C"] { reader.send(value) }
    @Sendable func install(_ tag: Int) {
      reader.installDirectHandler { value in
        trace.withLock { $0.append("\(tag):\(value)") }
        if value == "A" { install(tag + 1) }
      } onFinish: {
        trace.withLock { $0.append("\(tag):end") }
      }
    }
    install(1)
    reader.finish()
    #expect(trace.withLock { $0 } == ["1:A", "2:B", "2:C", "2:end"])
  }

  // w2fa024: a clear mid-flush leaves the remainder for the stream consumer.
  @Test func w2fa024ClearDuringFlushKeepsRemainderForStream() async {
    let reader = InProcessSignalReader()
    let trace = Mutex<[String]>([])
    for value in ["A", "B", "C"] { reader.send(value) }
    reader.installDirectHandler { [weak reader] value in
      trace.withLock { $0.append(value) }
      if value == "A" { reader?.clearDirectHandler() }
    } onFinish: {
      trace.withLock { $0.append("end") }
    }
    reader.send("D")
    let stream = reader.events()
    reader.finish()
    var streamed: [String] = []
    for await value in stream { streamed.append(value) }
    #expect(trace.withLock { $0 } == ["A"])
    #expect(streamed == ["B", "C", "D"])
  }
}

// MARK: - FW-D: one centre-rounding rule

@MainActor
@Suite(.serialized)
struct Wave2HuntFACentringTests {
  // w2fa025: an explicit centre guide equal to the default changes nothing.
  @Test func w2fa025IdentityCentreGuideKeepsStackSiblingOnSharedRow() {
    let guided = W2FA.raster(
      HStack(alignment: .center, spacing: 1) {
        Text("A").frame(width: 3, height: 2)
          .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] }
        Text("B")
      }, "w2fa025")
    // STUI-1242: the identity guide names the default centre.
    #expect(guided == [" A  B", ""], "\(guided)")
  }

  // w2fa026: a custom alignment whose default is the centre places like `.center`.
  @Test func w2fa026CustomCentreAlignmentMatchesBuiltinCentre() {
    let custom = W2FA.raster(
      HStack(alignment: .w2faMiddle, spacing: 1) {
        Text("A").frame(width: 3, height: 2)
        Text("B")
      }, "w2fa026")
    // STUI-1242: a default computed from the centre keeps the centre's half cell.
    #expect(custom == [" A  B", ""], "\(custom)")
  }

  // w2fa027: a Spacer child does not disturb centring by extent.
  @Test func w2fa027SpacerChildKeepsCentringByExtent() {
    let lines = W2FA.raster(
      HStack(alignment: .center, spacing: 0) {
        Text("A").frame(height: 2)
        Spacer()
        Text("B")
      }.frame(width: 6), "w2fa027")
    #expect(W2FA.position(of: "A", in: lines)?.row == 0, "\(lines)")
    #expect(W2FA.position(of: "B", in: lines)?.row == 0, "\(lines)")
  }

  // w2fa028: HStackLayout and VStackLayout place like HStack and VStack.
  @Test func w2fa028StackLayoutsMatchStacks() {
    let stack = W2FA.raster(
      HStack(alignment: .center, spacing: 1) {
        Text("A").frame(width: 3, height: 2)
        Text("B")
      }, "w2fa028-stack")
    let layout = W2FA.raster(
      HStackLayout(alignment: .center, spacing: 1) {
        Text("A").frame(width: 3, height: 2)
        Text("B")
      }, "w2fa028-layout")
    #expect(layout == stack, "layout \(layout) stack \(stack)")
    let column = W2FA.raster(
      VStack(alignment: .center, spacing: 0) {
        Text("A").frame(width: 2, height: 1)
        Text("B")
      }, "w2fa028-vstack")
    let columnLayout = W2FA.raster(
      VStackLayout(alignment: .center, spacing: 0) {
        Text("A").frame(width: 2, height: 1)
        Text("B")
      }, "w2fa028-vlayout")
    #expect(columnLayout == column, "layout \(columnLayout) stack \(column)")
  }

  // w2fa029: ZStackLayout places like ZStack on both axes.
  @Test func w2fa029ZStackLayoutMatchesZStack() {
    for (width, height) in [(1, 2), (2, 1)] {
      let filler = Rectangle().fill(Color.clear).frame(width: width, height: height)
      let stack = W2FA.raster(
        ZStack {
          filler
          Text("b")
        }, "w2fa029-stack-\(width)")
      let layout = W2FA.raster(
        ZStackLayout(alignment: .center) {
          filler
          Text("b")
        }, "w2fa029-layout-\(width)")
      #expect(layout == stack, "layout \(layout) stack \(stack)")
      #expect(W2FA.position(of: "b", in: layout).map { [$0.row, $0.column] } == [0, 0])
    }
  }

  // w2fa030: a windowed lazy stack centres rows like the eager stack.
  @Test func w2fa030WindowedLazyStackCentresLikeEagerStack() throws {
    func column(lazy: Bool) throws -> Int? {
      let h = try StressRuntimeHarness(
        rootIdentity: testIdentity("w2fa030", lazy ? "lazy" : "eager"),
        size: .init(width: 10, height: 8)
      ) {
        ScrollView {
          if lazy {
            LazyVStack(alignment: .center, spacing: 0) {
              ForEach(0..<200, id: \.self) { i in Text(i.isMultiple(of: 2) ? "abcd" : "x") }
            }
          } else {
            VStack(alignment: .center, spacing: 0) {
              ForEach(0..<200, id: \.self) { i in Text(i.isMultiple(of: 2) ? "abcd" : "x") }
            }
          }
        }.scrollIndicators(.hidden)
      }
      defer { h.shutdown() }
      return W2FA.position(of: "x", in: W2FA.frameLines(h.frame))?.column
    }
    let eager = try column(lazy: false)
    #expect(eager == 1)
    #expect(try column(lazy: true) == eager)
  }

  // w2fa031: a lazily windowed row's explicit centre guide does not move other rows.
  @Test func w2fa031WindowedGuidedRowDoesNotShiftOtherRows() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa031"),
      size: .init(width: 10, height: 8)
    ) {
      ScrollView {
        LazyVStack(alignment: .center, spacing: 0) {
          ForEach(0..<200, id: \.self) { i in
            if i == 197 {
              Text("abcd")
                .alignmentGuide(HorizontalAlignment.center) { $0[HorizontalAlignment.center] }
            } else {
              Text(i.isMultiple(of: 2) ? "abcd" : "x")
            }
          }
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    let top = W2FA.position(of: "x", in: W2FA.frameLines(h.frame))?.column
    try #require(top == 1, "\(h.frame)")
    _ = try h.pressKey(.init(.end))
    let lines = W2FA.frameLines(h.frame)
    try #require(h.frame.contains("x"), "\(h.frame)")
    let bottom = W2FA.position(of: "x", in: lines)?.column
    // STUI-1242: each row places against the measured line alone.
    #expect(bottom == top, "\(h.frame)")
  }

  // w2fa032: nested frame and stack centring compose.
  @Test func w2fa032NestedFrameAndStackCentringCompose() {
    let lines = W2FA.raster(
      HStack(alignment: .center, spacing: 0) {
        Text("A").frame(height: 3)
        VStack(spacing: 0) {
          Text("b")
          Text("c")
        }
      }.frame(height: 4), "w2fa032")
    #expect(W2FA.position(of: "A", in: lines)?.row == 1, "\(lines)")
    #expect(W2FA.position(of: "b", in: lines)?.row == 0, "\(lines)")
    #expect(W2FA.position(of: "c", in: lines)?.row == 1, "\(lines)")
  }

  // w2fa033: a flexible child sets an even extent; the odd sibling centres by it.
  @Test func w2fa033FlexibleChildEvenExtentCentresOddSibling() {
    let lines = W2FA.raster(
      HStack(alignment: .center, spacing: 0) {
        Rectangle().fill(Color.clear).frame(width: 1)
        Text("B")
      }, "w2fa033", width: 20, height: 6)
    #expect(W2FA.position(of: "B", in: lines)?.row == 2, "\(lines)")
  }

  // w2fa034: an explicit non-centre guide leaves centring by extent intact.
  @Test func w2fa034NonCentreExplicitGuideKeepsCentringByExtent() {
    let lines = W2FA.raster(
      HStack(alignment: .center, spacing: 1) {
        Text("A").frame(width: 3, height: 2).alignmentGuide(.top) { _ in 0 }
        Text("B")
      }, "w2fa034")
    #expect(lines == [" A  B", ""], "\(lines)")
  }
}

// MARK: - SPI: runtime focus identity

@MainActor
@Suite(.serialized)
struct Wave2HuntFAFocusIdentityTests {
  // w2fa035: every focus target exposes a node through runtimeFocusIdentity.
  @Test func w2fa035EveryFocusTargetHasRuntimeFocusNode() throws {
    let state = W2FAControls()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa035"),
      size: .init(width: 40, height: 30)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Button("Tap") {}
        Toggle("Flag", isOn: state.flag)
        TextField("Name", text: state.text)
        Stepper("Step", value: state.step)
        List(["l1", "l2", "l3"], id: \.self, selection: state.listSelection) { Text($0) }
          .frame(height: 5)
        Table(
          ["t1", "t2", "t3"], id: \.self, selection: state.tableSelection,
          columns: [TableColumn("Name", width: 8)]
        ) { Text($0) }.tableHeaders(.hidden)
      }
    }
    defer { h.shutdown() }
    var seen: Set<Identity> = []
    var missing: [String] = []
    for identity in h.runLoop.focusTracker.focusRegions.map(\.identity)
    where seen.insert(identity).inserted {
      _ = try h.focus(identity)
      let focused = try #require(h.runLoop.focusTracker.currentFocusIdentity)
      let matches = h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.filter {
        $0.runtimeFocusIdentity == focused
      }
      if matches.isEmpty { missing.append(focused.path) }
    }
    try #require(seen.count >= 6, "\(seen.count) focus regions")
    #expect(missing.isEmpty, "\(missing)")
  }

  // w2fa036: a List row with a nested button matches exactly its selection button.
  @Test func w2fa036ListRowWithNestedButtonHasOneRuntimeFocusNode() throws {
    let state = W2FAControls()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa036"),
      size: .init(width: 30, height: 8)
    ) {
      List(["alpha", "beta", "gamma"], id: \.self, selection: state.listSelection) { item in
        HStack {
          Text(item)
          Button("go") {}
        }
      }
    }
    defer { h.shutdown() }
    _ = try h.focusText("alpha")
    _ = try h.pressKey(.init(.arrowDown))
    let focused = try #require(h.runLoop.focusTracker.currentFocusIdentity)
    let matches = h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.filter {
      $0.runtimeFocusIdentity == focused
    }
    #expect(state.listSelectionValue == "beta")
    #expect(matches.map(\.label) == ["Select row 2"], "\(focused.path): \(matches.map(\.label))")
  }
}

// MARK: - Cross-group interactions

@MainActor
@Suite(.serialized)
struct Wave2HuntFACrossTests {
  // w2fa037: End on a table with a disabled last row; navigation still skips it.
  @Test func w2fa037EndThenArrowsSkipDisabledLastRow() throws {
    let box = W2FASelection<Int>(selected: 28)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa037"),
      size: .init(width: 20, height: 8)
    ) {
      Table(
        Array(0..<30), id: \.self, selection: box.binding,
        columns: [TableColumn("Name", width: 12)]
      ) { i in
        Text("t\(i)").disabled(i == 29)
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.focusText("t28")
    _ = try h.pressKey(.init(.end))
    #expect(h.frame.contains("t29"), "\(h.frame)")
    _ = try h.pressKey(.init(.arrowDown))
    #expect(box.selected == 28)
    _ = try h.pressKey(.init(.arrowUp))
    #expect(box.selected == 27)
  }

  // w2fa038: centring by extent holds inside a lazily refined End.
  @Test func w2fa038CentringHoldsAfterRefinedLazyEnd() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa038"),
      size: .init(width: 10, height: 8)
    ) {
      ScrollView {
        LazyVStack(alignment: .center, spacing: 0) {
          ForEach(0..<120, id: \.self) { i in
            Text(i == 119 ? "z" : (i.isMultiple(of: 2) ? "abcd" : "x"))
              .frame(height: i < 40 ? 1 : 3)
          }
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.end))
    let lines = W2FA.frameLines(h.frame)
    #expect(W2FA.position(of: "z", in: lines)?.column == 1, "\(h.frame)")
  }

  // w2fa039: conditional rows of a data-driven Table deliver initial events once.
  @Test func w2fa039DataTableConditionalRowsDeliverInitialChanges() throws {
    let log = W2FAChangeLog()
    let flagged: Set<String> = ["a", "c", "e"]
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa039"),
      size: .init(width: 20, height: 14)
    ) {
      Table(["a", "b", "c", "d", "e"], id: \.self, columns: [TableColumn("Name")]) { id in
        if flagged.contains(id) {
          Text(id).onChange(of: id, initial: true) { _, new in log.strings.append(new) }
        } else {
          Text(id)
        }
      }
    }
    defer { h.shutdown() }
    #expect(log.strings.sorted() == ["a", "c", "e"], "\(log.strings)")
  }

  // w2fa040: a proxy bottom edge over a scroll-hosted hidden-separator table.
  @Test func w2fa040ProxyBottomOverScrollHostedHiddenSeparatorTable() throws {
    let rows = (0..<40).map { W2FARow(id: W2FA.paddedID($0, prefix: "row", digits: 2)) }
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fa040"),
      size: .init(width: 24, height: 11)
    ) {
      ScrollViewReader { proxy in
        VStack(spacing: 0) {
          Button("jump") { _ = proxy.scrollTo(edge: .bottom) }
          ScrollView {
            Table(rows, columns: [TableColumn("Name")]) { row in
              Text(row.id).listRowSeparator(.hidden)
            }
          }.scrollIndicators(.hidden).frame(height: 9)
        }
      }
    }
    defer { h.shutdown() }
    _ = try h.clickText("jump")
    let visible = W2FA.visibleIDs(in: h.frame, prefix: "row", digits: 2)
    #expect(visible.last == "row39", "\(h.frame)")
    let starts = W2FA.lineIndices(of: visible, in: W2FA.frameLines(h.frame))
    #expect(zip(starts.dropFirst(), starts).allSatisfy { $0 - $1 == 1 }, "\(h.frame)")
  }
}

// MARK: - Fixtures

private struct W2FARow: Identifiable, Hashable, Sendable {
  var id: String
}

@MainActor
private final class W2FASelection<Value: Hashable & Sendable> {
  var selected: Value?
  init(selected: Value?) { self.selected = selected }
  var binding: Binding<Value?> { .init(get: { self.selected }, set: { self.selected = $0 }) }
}

@MainActor
private final class W2FAMultiSelection {
  var selected: Set<Int> = []
  var binding: Binding<Set<Int>> { .init(get: { self.selected }, set: { self.selected = $0 }) }
}

@MainActor
private final class W2FAOffset {
  var value = ScrollCellOffset.zero
  var binding: Binding<ScrollCellOffset> { .init(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
private final class W2FAText {
  var value = "seed"
  var binding: Binding<String> { .init(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
private final class W2FAProxies {
  var left: ScrollViewProxy?
  var right: ScrollViewProxy?
  func store(_ proxy: ScrollViewProxy, left isLeft: Bool) {
    if isLeft { left = proxy } else { right = proxy }
  }
}

@MainActor
private final class W2FAControls {
  var flagValue = false
  var textValue = "name"
  var stepValue = 0
  var listSelectionValue: String? = "l1"
  var tableSelectionValue: String? = "t1"
  var flag: Binding<Bool> { .init(get: { self.flagValue }, set: { self.flagValue = $0 }) }
  var text: Binding<String> { .init(get: { self.textValue }, set: { self.textValue = $0 }) }
  var step: Binding<Int> { .init(get: { self.stepValue }, set: { self.stepValue = $0 }) }
  var listSelection: Binding<String?> {
    .init(get: { self.listSelectionValue }, set: { self.listSelectionValue = $0 })
  }
  var tableSelection: Binding<String?> {
    .init(get: { self.tableSelectionValue }, set: { self.tableSelectionValue = $0 })
  }
}

@MainActor
private final class W2FAChangeLog {
  var pairs: [[Int]] = []
  var values: [Int] = []
  var strings: [String] = []
  var visible = true
  var optional: Int? = 1
}

@MainActor
private final class W2FARows {
  var ids: [String]
  init(ids: [String]) { self.ids = ids }
}

@MainActor
private final class W2FACaptureLog<Value> {
  struct Entry {
    var read: () -> Value
    var write: (Value) -> Void
  }
  let label: String
  var entries: [Entry] = []
  var visible = true
  var token = 0
  init(label: String = "") { self.label = label }
}

private struct W2FACounterLeaf: View {
  @State private var value = 0
  let log: W2FACaptureLog<Int>
  var body: some View {
    log.entries.append(.init(read: { value }, write: { value = $0 }))
    return Text("\(log.label)v\(value)")
  }
}

@MainActor
private struct W2FAComposedStorage: DynamicProperty {
  @State private var storage = "seed"
  var value: String {
    get { storage }
    nonmutating set { storage = newValue }
  }
}

private struct W2FAComposedLeaf: View {
  private var composed = W2FAComposedStorage()
  let log: W2FACaptureLog<String>
  init(log: W2FACaptureLog<String>) { self.log = log }
  var body: some View {
    log.entries.append(.init(read: { composed.value }, write: { composed.value = $0 }))
    return Text("c:\(composed.value)")
  }
}

private struct W2FASnapshotCounter: View {
  @State private var count = 0
  var body: some View {
    Button("Count \(count)") { count += 1 }
  }
}

private enum W2FAMiddle: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int {
    context[VerticalAlignment.center]
  }
}

extension VerticalAlignment {
  fileprivate static let w2faMiddle = VerticalAlignment(W2FAMiddle.self)
}

@MainActor
private enum W2FA {
  static func paddedID(_ value: Int, prefix: String, digits: Int = 3) -> String {
    let text = String(value)
    return prefix + String(repeating: "0", count: max(0, digits - text.count)) + text
  }

  /// Tokens `<prefix><digits>` in frame order; `digits == nil` accepts any count.
  static func visibleIDs(in frame: String, prefix: String, digits: Int?) -> [String] {
    var result: [String] = []
    for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
      for token in line.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
        guard token.hasPrefix(prefix) else { continue }
        let rest = token.dropFirst(prefix.count)
        guard !rest.isEmpty, rest.allSatisfy(\.isNumber) else { continue }
        if let digits, rest.count != digits { continue }
        result.append(String(token))
      }
    }
    return result
  }

  static func frameLines(_ frame: String) -> [String] {
    frame.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }

  /// The first line index containing each token as a whole word, in token order.
  static func lineIndices(of tokens: [String], in lines: [String]) -> [Int] {
    tokens.compactMap { token in
      lines.firstIndex { line in
        line.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0 == token }
      }
    }
  }

  static func nonBlank(_ lines: [String]) -> [String] {
    lines.map { String($0.reversed().drop(while: \.isWhitespace).reversed()) }
      .filter { !$0.isEmpty }
  }

  static func position(of glyph: Character, in lines: [String]) -> (row: Int, column: Int)? {
    for (row, line) in lines.enumerated() {
      if let index = line.firstIndex(of: glyph) {
        return (row, line.distance(from: line.startIndex, to: index))
      }
    }
    return nil
  }

  static func raster<V: View>(_ view: V, _ name: String) -> [String] {
    DefaultRenderer().render(view, context: .init(identity: testIdentity("W2FA", name)))
      .rasterSurface.lines
  }

  static func raster<V: View>(_ view: V, _ name: String, width: Int, height: Int) -> [String] {
    lines(view, name: name, width: width, height: height)
  }

  static func lines<V: View>(_ view: V, name: String, width: Int, height: Int) -> [String] {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("W2FA", name)),
      proposal: .init(width: width, height: height)
    ).rasterSurface.lines
  }

  static func hiddenSeparatorTable(
    _ name: String, box: W2FASelection<String>, hidden: Bool = true
  ) throws -> StressRuntimeHarness<some View> {
    let rows = (0..<200).map { W2FARow(id: paddedID($0, prefix: "r")) }
    return try StressRuntimeHarness(
      rootIdentity: testIdentity(name),
      size: .init(width: 30, height: 64)
    ) {
      Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
        Text(row.id).listRowSeparator(hidden ? .hidden : .automatic)
      }.tableHeaders(.hidden).scrollIndicators(.hidden)
    }
  }

  @ViewBuilder
  static func variableLazy(prefix: String) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<120, id: \.self) { i in
          Text("\(prefix)\(i)").frame(height: i < 40 ? 1 : 3)
        }
      }
    }.scrollIndicators(.hidden).frame(width: 8, height: 8)
  }

  /// Renders once through a renderer that is released before this returns,
  /// and answers the first focus region (the button's action identity).
  static func renderWithReleasedRenderer<V: View>(
    _ view: V, registry: LocalActionRegistry, name: String
  ) -> Identity? {
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity(name), localActionRegistry: registry,
        applyEnvironmentValues: true))
    return artifacts.semanticSnapshot.focusRegions.first?.identity
  }

  /// A retired write reports its seed-fallback diagnostics deliberately; keep
  /// them out of the soundness gate, as setC006 does.
  static func withRetiredWriteDiagnostics(_ body: () -> Void) {
    let savedTrace = SoundnessProbeConfiguration.isTraceEnabled
    let savedSeed = SoundnessProbeConfiguration.stateSeedFallbackViolationCount
    let savedMiss = SoundnessProbeConfiguration.stateCaptureMissViolationCount
    SoundnessProbeConfiguration.isTraceEnabled = false
    defer {
      SoundnessProbeConfiguration.isTraceEnabled = savedTrace
      SoundnessProbeConfiguration.stateSeedFallbackViolationCount = savedSeed
      SoundnessProbeConfiguration.stateCaptureMissViolationCount = savedMiss
    }
    body()
    _ = ImperativeRuntimeIssueQueue.drain()
  }
}
