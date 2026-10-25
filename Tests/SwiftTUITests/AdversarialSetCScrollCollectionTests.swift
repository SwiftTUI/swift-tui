@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCScrollCollectionTests {
  // Contracts and pre-run predictions: campaign-two F1 briefs, areas 05/08.
  @Test func setC041TwoAxisEndKeepsHorizontalOffset() throws {
    let box = SetCScrollBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC041"),
      size: .init(width: 12, height: 6)
    ) {
      ScrollView([.horizontal, .vertical], position: box.binding) {
        Text("grid").frame(width: 40, height: 30)
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    try #require(h.runLoop.focusTracker.currentFocusIdentity != nil)
    _ = try h.pressKey(.init(.end))
    // STUI-1170 (fixed in wave 2): End goes to the bottom only.
    #expect(box.offset == .init(x: 0, y: 24))
    _ = try h.pressKey(.init(.home))
    #expect(box.offset == .zero)
  }

  @Test func setC042InnerNonoverflowingWheelInterception() throws {
    let box = SetCScrollBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC042"),
      size: .init(width: 20, height: 6)
    ) {
      ScrollView(.vertical, position: box.binding) {
        VStack(alignment: .leading, spacing: 0) {
          ScrollView { Text("inner") }.frame(height: 2)
            .onScrollWheel { _ in
              box.calls += 1
              return .ignored
            }
          ForEach(0..<20) { i in Text("tail \(i)") }
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "inner"))
    _ = try h.scrollPointer(at: point, deltaY: 1)
    #expect(box.calls == 1)
    #expect(box.offset.y == 1)
  }

  @Test func setC044WheelRoutesRetireAcrossRemovalAndRekey() throws {
    let box = SetCScrollBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC044"),
      size: .init(width: 20, height: 5)
    ) {
      VStack {
        if box.show {
          Text("Row").onScrollWheel { _ in
            box.calls += 1
            return .handled
          }.id(box.token)
        } else {
          Text("absent")
        }
      }
    }
    defer { h.shutdown() }
    try #require(h.runLoop.localPointerHandlerRegistry.snapshotWheel().count == 1)
    box.show = false
    _ = try h.renderAfterExternalMutation()
    #expect(h.runLoop.localPointerHandlerRegistry.snapshotWheel().isEmpty)
    box.show = true
    _ = try h.renderAfterExternalMutation()
    #expect(h.runLoop.localPointerHandlerRegistry.snapshotWheel().count == 1)
    for _ in 0..<stressIterations(full: 24, hotPath: 6) {
      box.token += 1
      _ = try h.renderAfterExternalMutation()
      #expect(h.runLoop.localPointerHandlerRegistry.snapshotWheel().count == 1)
    }
    let point = try #require(h.point(forText: "Row"))
    _ = try h.scrollPointer(at: point, deltaY: 1)
    #expect(box.calls == 1)
  }

  @Test func setC048LazyEndReachesLastVariableHeightRow() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC048"),
      size: .init(width: 20, height: 8)
    ) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<120) { i in Text("vrow \(i)").frame(height: i < 40 ? 1 : 3) }
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("vrow 0"))
    _ = try h.pressKey(.init(.end))
    // STUI-1171 (fixed in wave 2): the edge command refines against the
    // extent the landing frame measured.
    #expect(h.frame.contains("vrow 119"), "\(h.frame)")
  }

  @Test func setC049PagingRespectsAuthoredAxis() throws {
    let box = SetCScrollBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC049"),
      size: .init(width: 12, height: 3)
    ) {
      ScrollView(.horizontal, position: box.binding) {
        Text("abcdefghijklmnopqrstuvwxyz01234567890123")
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.pageDown))
    #expect(box.offset == .init(x: 11, y: 0))
    _ = try h.pressKey(.init(.end))
    #expect(box.offset == .init(x: 28, y: 0))
  }

  @Test func setC071TableArrowsSkipDisabledRows() throws {
    let box = SetCScrollBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC071"),
      size: .init(width: 20, height: 6)
    ) {
      Table(
        [1, 2, 3], id: \.self, selection: box.selectionBinding,
        columns: [TableColumn("Name", width: 12)]
      ) { i in
        Text("row\(i)").disabled(i == 2)
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("row2"))
    _ = try h.focusText("row1")
    _ = try h.pressKey(.init(.arrowDown))
    // STUI-1172 (fixed in wave 2): navigation skips the disabled row.
    #expect(box.selection == 3)
  }

  @Test func setC072TablePointerSkipsDisabledRow() throws {
    let box = SetCScrollBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC072"),
      size: .init(width: 20, height: 6)
    ) {
      Table(
        [1, 2, 3], id: \.self, selection: box.selectionBinding,
        columns: [TableColumn("Name", width: 12)]
      ) { i in
        Text("row\(i)").disabled(i == 2)
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.clickText("row2")
    // STUI-1172 (fixed in wave 2): a disabled row has no pointer action.
    #expect(box.selection == 1)
  }

  // Wave 2 (STUI-1164) repair regressions and neighbors for STUI-1170,
  // STUI-1171 and STUI-1172; scenarios in the wave's repair-hypotheses.json.

  @Test func wave2a02TwoAxisHomeResetsBothAxes() throws {
    let box = SetCScrollBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave2a02"),
      size: .init(width: 12, height: 6)
    ) {
      ScrollView([.horizontal, .vertical], position: box.binding) {
        Text("grid").frame(width: 40, height: 30)
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    try #require(h.runLoop.focusTracker.currentFocusIdentity != nil)
    for _ in 0..<3 { _ = try h.pressKey(.init(.arrowRight)) }
    for _ in 0..<2 { _ = try h.pressKey(.init(.arrowDown)) }
    try #require(box.offset == .init(x: 3, y: 2))
    _ = try h.pressKey(.init(.home))
    #expect(box.offset == .zero)
  }

  @Test func wave2a04IndicatorEndDrivesOnlyItsAxis() throws {
    let box = SetCScrollBox()
    let scrollID = testIdentity("wave2a04", "scroll")
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave2a04"),
      size: .init(width: 12, height: 6)
    ) {
      ScrollView([.horizontal, .vertical], position: box.binding) {
        Text("grid").frame(width: 40, height: 30)
      }.id(scrollID)
    }
    defer { h.shutdown() }
    // Focusing an indicator may reveal it; only the End key's change is measured.
    _ = try h.focus(horizontalScrollIndicatorIdentity(for: scrollID))
    let beforeHorizontal = box.offset
    _ = try h.pressKey(.init(.end))
    #expect(
      box.offset.x > beforeHorizontal.x && box.offset.y == beforeHorizontal.y, "\(box.offset)")
    _ = try h.focus(verticalScrollIndicatorIdentity(for: scrollID))
    let beforeVertical = box.offset
    _ = try h.pressKey(.init(.end))
    #expect(
      box.offset.x == beforeVertical.x && box.offset.y > beforeVertical.y, "\(box.offset)")
  }

  @Test func wave2a07UniformLazyEndIsExact() throws {
    let box = SetCScrollBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave2a07"),
      size: .init(width: 20, height: 8)
    ) {
      ScrollView(.vertical, position: box.binding) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<120) { i in Text("urow \(i)") }
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.end))
    #expect(box.offset == .init(x: 0, y: 112))
    #expect(h.frame.contains("urow 119"), "\(h.frame)")
  }

  @Test func wave2a08LazyEndThenArrowUpIsNotRepinned() throws {
    let box = SetCScrollBox()
    let h = try SetCVariableLazy.harness("wave2a08", box: box)
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.end))
    let maximum = try SetCVariableLazy.maximumOffset(h)
    #expect(box.offset.y == maximum, "\(box.offset) of \(maximum)")
    #expect(h.frame.contains("vrow 119"), "\(h.frame)")
    _ = try h.pressKey(.init(.arrowUp))
    #expect(box.offset.y == maximum - 1, "\(box.offset)")
    _ = try h.renderAfterExternalMutation()
    #expect(box.offset.y == maximum - 1, "a later frame keeps the authored offset: \(box.offset)")
  }

  @Test func wave2a09ProxyBottomEdgeReachesLastVariableRow() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave2a09"),
      size: .init(width: 20, height: 9)
    ) {
      ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 0) {
          Button("jump") { _ = proxy.scrollTo(edge: .bottom) }
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(0..<120) { i in Text("vrow \(i)").frame(height: i < 40 ? 1 : 3) }
            }
          }.scrollIndicators(.hidden).frame(height: 8)
        }
      }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("vrow 0"))
    _ = try h.clickText("jump")
    #expect(h.frame.contains("vrow 119"), "\(h.frame)")
  }

  @Test func wave2a10LazyHomeAfterEndReturnsToStart() throws {
    let box = SetCScrollBox()
    let h = try SetCVariableLazy.harness("wave2a10", box: box)
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.end))
    try #require(box.offset.y > 0)
    _ = try h.pressKey(.init(.home))
    #expect(box.offset == .zero)
    #expect(h.frame.contains("vrow 0"), "\(h.frame)")
  }

  @Test func wave2a13EnabledTableRowClickSelects() throws {
    let box = SetCScrollBox()
    let h = try SetCDisabledRowTable.harness("wave2a13", box: box)
    defer { h.shutdown() }
    _ = try h.clickText("row3")
    #expect(box.selection == 3)
  }

  @Test func wave2a14StaticTableArrowsSkipDisabledRow() throws {
    let box = SetCScrollBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave2a14"),
      size: .init(width: 20, height: 6)
    ) {
      Table(selection: box.selectionBinding, columns: [TableColumn("Name", width: 12)]) {
        TableRow { Text("row1") }.tag(1)
        TableRow { Text("row2") }.tag(2).disabled(true)
        TableRow { Text("row3") }.tag(3)
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.focusText("row1")
    _ = try h.pressKey(.init(.arrowDown))
    #expect(box.selection == 3)
    _ = try h.pressKey(.init(.arrowUp))
    #expect(box.selection == 1)
    _ = try h.clickText("row2")
    #expect(box.selection == 1)
  }

  @Test func wave2a15DisabledSelectedRowStepsToNeighbors() throws {
    let box = SetCScrollBox()
    box.selection = 2
    let h = try SetCDisabledRowTable.harness("wave2a15", box: box)
    defer { h.shutdown() }
    _ = try h.focusText("row1")
    try #require(box.selection == 2, "focus keeps the externally selected disabled row")
    _ = try h.pressKey(.init(.arrowDown))
    #expect(box.selection == 3)
    box.selection = 2
    _ = try h.renderAfterExternalMutation()
    _ = try h.pressKey(.init(.arrowUp))
    #expect(box.selection == 1)
  }

  @Test func wave2a16OneDisabledCellKeepsRowSelectable() throws {
    let box = SetCScrollBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave2a16"),
      size: .init(width: 30, height: 6)
    ) {
      Table(
        [1, 2, 3], id: \.self, selection: box.selectionBinding,
        columns: [TableColumn("Name", width: 8), TableColumn("Act", width: 8)]
      ) { i in
        Text("row\(i)")
        Text("act\(i)").disabled(i == 2)
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.focusText("row1")
    _ = try h.pressKey(.init(.arrowDown))
    #expect(box.selection == 2)
  }

  @Test func wave2a17AssistiveActivateSkipsDisabledRow() throws {
    let box = SetCScrollBox()
    let h = try SetCDisabledRowTable.harness("wave2a17", box: box)
    defer { h.shutdown() }
    func activate(_ label: String) throws -> AccessibilityActionResult? {
      guard
        let target = h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first(where: {
          $0.label == label
        })?.actionTarget
      else { return nil }
      let result = h.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
      _ = try h.render()
      return result
    }
    let disabled = try activate("Select row 2")
    #expect(box.selection == 1, "disabled row activation result: \(String(describing: disabled))")
    let enabled = try activate("Select row 3")
    #expect(enabled == .accepted)
    #expect(box.selection == 3)
  }
}

@MainActor
private enum SetCVariableLazy {
  static func harness(_ name: String, box: SetCScrollBox) throws -> StressRuntimeHarness<
    some View
  > {
    try StressRuntimeHarness(
      rootIdentity: testIdentity(name),
      size: .init(width: 20, height: 8)
    ) {
      ScrollView(.vertical, position: box.binding) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<120) { i in Text("vrow \(i)").frame(height: i < 40 ? 1 : 3) }
        }
      }.scrollIndicators(.hidden)
    }
  }

  /// The committed route's own maximum offset (content minus viewport).
  static func maximumOffset<V: View>(_ h: StressRuntimeHarness<V>) throws -> Int {
    let route = try #require(h.runLoop.latestSemanticSnapshot.scrollRoutes.first)
    return max(0, route.contentBounds.size.height - route.viewportRect.size.height)
  }
}

@MainActor
private enum SetCDisabledRowTable {
  static func harness(_ name: String, box: SetCScrollBox) throws -> StressRuntimeHarness<
    some View
  > {
    try StressRuntimeHarness(
      rootIdentity: testIdentity(name),
      size: .init(width: 20, height: 8)
    ) {
      Table(
        [1, 2, 3], id: \.self, selection: box.selectionBinding,
        columns: [TableColumn("Name", width: 12)]
      ) { i in
        Text("row\(i)").disabled(i == 2)
      }.tableHeaders(.hidden)
    }
  }
}

@MainActor
private final class SetCScrollBox {
  var offset = ScrollCellOffset.zero
  var calls = 0
  var token = 0
  var show = true
  var selection: Int? = 1
  var binding: Binding<ScrollCellOffset> { .init(get: { self.offset }, set: { self.offset = $0 }) }
  var selectionBinding: Binding<Int?> {
    .init(get: { self.selection }, set: { self.selection = $0 })
  }
}
