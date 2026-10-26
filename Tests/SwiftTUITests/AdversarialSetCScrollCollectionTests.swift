import Foundation
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

  // Wave 3 (FW3-E, STUI-1240): an ineligible row's assistive selector is
  // published disabled in every collection shape, as the List row's is
  // (Collections.md:39-43; Accessibility.md:117-123). The browser projection
  // serializes the framework node's enabled state.
  @Test(arguments: SetCDisabledRowShape.allCases)
  func wave3e10DisabledRowSelectorIsPublishedDisabled(_ shape: SetCDisabledRowShape) throws {
    let box = SetCScrollBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave3e10", shape.description), size: .init(width: 24, height: 10)
    ) {
      SetCDisabledRowHost(shape: shape, selection: box.selectionBinding)
    }
    defer { h.shutdown() }
    func selector(_ row: Int) throws -> AccessibilityNode {
      try #require(
        h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == "Select row \(row)"
        }, "\(shape): \(h.frame)")
    }
    #expect(try selector(1).isEnabled, "\(shape)")
    #expect(try selector(3).isEnabled, "\(shape)")
    let disabled = try selector(2)
    #expect(!disabled.isEnabled, "\(shape)")
    let wire = try SetCWire.accessibilityEntries(h.runLoop.publishedAccessibilitySnapshot, h.frame)
    let entry = try #require(wire.first { $0["label"] as? String == "Select row 2" }, "\(shape)")
    #expect(entry["isEnabled"] as? Bool == false, "\(shape): \(entry)")
    let target = try #require(disabled.actionTarget)
    let result = h.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
    _ = try h.render()
    #expect(result == .disabled, "\(shape): \(String(describing: result))")
    #expect(box.selection == 1, "\(shape)")
  }

  // Wave 3 (FW3-E, STUI-1243): every far-edge command of one action
  // refines, whichever view the registry visits first. The registry visits
  // routes in frame order, so swapping the views pins both orders
  // (Scrolling.md:206-209; Divergences-And-Gaps.md:398-405: explicit scroll
  // commands take precedence over anchor preservation).
  @Test(arguments: [false, true])
  func wave3e20TwoTrailingEdgesInOneActionBothRefine(swapped: Bool) throws {
    let proxies = SetCProxies()
    let names = swapped ? ["Y", "Z"] : ["Z", "Y"]
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave3e20", swapped ? "swapped" : "ordered"),
      size: .init(width: 24, height: 9)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        ScrollViewReader { proxy in
          let _ = proxies.store(proxy, first: true)
          SetCVariableLazy.horizontal(last: names[0])
        }
        ScrollViewReader { proxy in
          let _ = proxies.store(proxy, first: false)
          SetCVariableLazy.horizontal(last: names[1])
        }
        Button("jump") {
          for proxy in proxies.ordered(reversed: swapped) { _ = proxy.scrollTo(edge: .trailing) }
        }
      }
    }
    defer { h.shutdown() }
    try #require(!h.frame.contains("Z") && !h.frame.contains("Y"), "\(h.frame)")
    _ = try h.clickText("jump")
    #expect(h.frame.contains("Z") && h.frame.contains("Y"), "\(h.frame)")
  }

  // Two assistive "Scroll to bottom" commands before one frame both refine.
  @Test(arguments: [false, true])
  func wave3e21TwoAssistiveBottomEdgesBeforeOneFrameBothRefine(swapped: Bool) throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave3e21", swapped ? "swapped" : "ordered"),
      size: .init(width: 30, height: 9)
    ) {
      HStack(alignment: .top, spacing: 1) {
        SetCVariableLazy.vertical(prefix: "a", label: "Left rows")
        SetCVariableLazy.vertical(prefix: "b", label: "Right rows")
      }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("a0") && h.frame.contains("b0"), "\(h.frame)")
    let labels = swapped ? ["Right rows", "Left rows"] : ["Left rows", "Right rows"]
    let targets = try labels.map { label in
      try #require(
        h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == label
        }?.actionTarget)
    }
    for target in targets {
      #expect(
        h.runLoop.handleAccessibilityAction(
          .init(target: target, action: .custom("Scroll to bottom"))) == .accepted)
    }
    _ = try h.render()
    #expect(h.frame.contains("a119") && h.frame.contains("b119"), "\(h.frame)")
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

extension SetCVariableLazy {
  /// 120 items: 0-39 one cell wide, 40-119 three; the last reads `last`.
  @ViewBuilder
  static func horizontal(last: String) -> some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 0) {
        ForEach(0..<120, id: \.self) { i in
          Text(i == 119 ? last : ".").frame(width: i < 40 ? 1 : 3)
        }
      }
    }.scrollIndicators(.hidden).frame(width: 20, height: 3)
  }

  /// 120 rows `<prefix>0`…`<prefix>119`: 0-39 one cell tall, 40-119 three.
  @ViewBuilder
  static func vertical(prefix: String, label: String) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<120, id: \.self) { i in
          Text("\(prefix)\(i)").frame(height: i < 40 ? 1 : 3)
        }
      }
    }.scrollIndicators(.hidden).accessibilityLabel(label).frame(width: 8, height: 8)
  }
}

@MainActor
private final class SetCProxies {
  var first: ScrollViewProxy?
  var second: ScrollViewProxy?
  func store(_ proxy: ScrollViewProxy, first isFirst: Bool) {
    if isFirst { first = proxy } else { second = proxy }
  }
  func ordered(reversed: Bool) -> [ScrollViewProxy] {
    let proxies = [first, second].compactMap { $0 }
    return reversed ? proxies.reversed() : proxies
  }
}

/// Collection shapes whose second row is ineligible for selection.
enum SetCDisabledRowShape: String, CaseIterable, Sendable, CustomStringConvertible {
  case list, listTaggedChild, outline, staticTableRow, staticTableCells, dataTable
  var description: String { rawValue }
}

private struct SetCOutlineRecord: Identifiable, Hashable, Sendable {
  let id: Int
  var children: [SetCOutlineRecord]?
}

private struct SetCDisabledRowHost: View {
  let shape: SetCDisabledRowShape
  let selection: Binding<Int?>

  var body: some View {
    switch shape {
    case .list:
      List([1, 2, 3], id: \.self, selection: selection) { i in
        Text("row\(i)").disabled(i == 2)
      }
    case .listTaggedChild:
      // The row wrapper stays enabled; its tagged content is disabled.
      List(selection: selection) {
        ForEach([1, 2, 3], id: \.self) { i in
          HStack(spacing: 1) {
            Text("row\(i)").tag(i).disabled(i == 2)
            Text("·")
          }
        }
      }
    case .outline:
      List(
        [SetCOutlineRecord(id: 1, children: [.init(id: 2), .init(id: 3)])], id: \.id,
        selection: selection, children: \.children
      ) { record in
        Text("row\(record.id)").disabled(record.id == 2)
      }
    case .staticTableRow:
      Table(selection: selection, columns: [TableColumn("Name", width: 12)]) {
        TableRow { Text("row1") }.tag(1)
        TableRow { Text("row2") }.tag(2).disabled(true)
        TableRow { Text("row3") }.tag(3)
      }.tableHeaders(.hidden)
    case .staticTableCells:
      Table(
        selection: selection, columns: [TableColumn("A", width: 6), TableColumn("B", width: 6)]
      ) {
        TableRow {
          Text("row1")
          Text("b1")
        }.tag(1)
        TableRow {
          Text("row2").disabled(true)
          Text("b2").disabled(true)
        }.tag(2)
        TableRow {
          Text("row3")
          Text("b3")
        }.tag(3)
      }.tableHeaders(.hidden)
    case .dataTable:
      Table(
        [1, 2, 3], id: \.self, selection: selection, columns: [TableColumn("Name", width: 12)]
      ) { i in
        Text("row\(i)").disabled(i == 2)
      }.tableHeaders(.hidden)
    }
  }
}

@MainActor
private enum SetCWire {
  /// The browser projection's accessibility records for a published snapshot.
  static func accessibilityEntries(
    _ snapshot: SemanticSnapshot, _ frame: String
  ) throws -> [[String: Any]] {
    let lines = frame.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let width = lines.map { layoutText(for: $0, width: nil).size.width }.max() ?? 1
    var state = HostWireCapabilities(acceptsDeltaFrames: true, styleAppend: true)
      .negotiatedEncodingState(epochID: 1)
    let encoded = WebSurfaceFrameEncoder.encode(
      RasterSurface(size: .init(width: max(1, width), height: lines.count), lines: lines),
      sequence: 1, semanticSnapshot: snapshot, focusedIdentity: nil,
      damage: .init(textRows: [.init(row: 0)]), state: &state)
    let prefix = "\u{1E}surface:"
    try #require(encoded.hasPrefix(prefix))
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(encoded.dropFirst(prefix.count).utf8))
        as? [String: Any])
    return try #require(object["accessibilityTree"] as? [[String: Any]])
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

// MARK: - Wave 4 (W4-FB): pending scroll commands

/// Wave-4 repair group W4-FB (STUI-1169): proxy and key scroll commands that
/// the content of the same action decides (STUI-1263, STUI-1264, STUI-1305,
/// STUI-1306). Extensions below add a reader whose first scroll view is
/// disabled (STUI-1317) and centre anchors (STUI-1322). Contracts:
/// `Scrolling.md:132-171, 206-210`, `Collections.md:193-194`,
/// `ScrollViewReader.swift:45-51`. The brief and hypotheses are in the
/// coordination root's
/// docs/reports/evidence/2026-10-26-campaign-two-wave-4/fw-b/.
@MainActor
@Suite(.serialized)
struct Wave4ScrollCommandRepairTests {
  // A far-edge command that moves nothing, issued outside any action,
  // resolves at the next layout and does not apply to a later growth.
  @Test func wave4b01NoOpEdgeDoesNotStickToLaterGrowth() throws {
    let model = W4ScrollModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave4b01"), size: .init(width: 24, height: 8)
    ) { W4ModelRows(model: model) }
    defer { h.shutdown() }
    model.offset = .init(x: 0, y: 14)
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("row 19"), "\(h.frame)")
    #expect(try #require(model.proxy).scrollTo(edge: .bottom) == false)
    _ = try h.render()
    model.count = 25
    _ = try h.renderAfterExternalMutation()
    _ = try h.render()
    #expect(model.offset.y == 14, "\(model.offset)")
    #expect(!h.frame.contains("row 24"), "\(h.frame)")
  }

  // The edge command may precede the append in the action.
  @Test func wave4b02EdgeBeforeAppendInOneActionRevealsNewRows() throws {
    let model = W4ScrollModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave4b02"), size: .init(width: 24, height: 8)
    ) { W4AppendRoot(model: model, edgeFirst: true) }
    defer { h.shutdown() }
    #expect(try #require(model.proxy).scrollTo(edge: .bottom))
    _ = try h.render()
    try #require(h.frame.contains("row 19") && model.offset.y == 14, "\(h.frame)")
    _ = try h.clickText("Append")
    _ = try h.render()
    #expect(h.frame.contains("row 24"), "\(h.frame)")
    #expect(model.offset.y == 19, "\(model.offset)")
  }

  // End at the bottom moves nothing; a later growth does not jump.
  @Test func wave4b03EndKeyAtBottomDoesNotStickToLaterGrowth() throws {
    let model = W4ScrollModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave4b03"), size: .init(width: 24, height: 8)
    ) { W4ModelRows(model: model) }
    defer { h.shutdown() }
    let route = try #require(h.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    _ = try h.focus(route)
    model.offset = .init(x: 0, y: 14)
    _ = try h.renderAfterExternalMutation()
    _ = try h.pressKey(.init(.end))
    try #require(model.offset.y == 14, "\(model.offset)")
    model.count = 25
    _ = try h.renderAfterExternalMutation()
    _ = try h.render()
    #expect(model.offset.y == 14, "\(model.offset)")
  }

  // `scrollTo(_:)` for an ID nothing shows, outside any action, does not
  // reveal a row that gains the ID in a later frame.
  @Test func wave4b04UnresolvedIDDoesNotStickToLaterInsertion() throws {
    let model = W4ScrollModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave4b04"), size: .init(width: 24, height: 8)
    ) { W4ModelRows(model: model, identified: true) }
    defer { h.shutdown() }
    #expect(try #require(model.proxy).scrollTo(28, anchor: .top) == false)
    _ = try h.render()
    model.count = 30
    _ = try h.renderAfterExternalMutation()
    _ = try h.render()
    #expect(model.offset.y == 0, "\(model.offset)")
  }

  // Bottom and then leading on one two-axis view: the vertical edge still
  // refines (one pending edge per axis).
  @Test func wave4b05BottomThenLeadingOnOneRouteKeepsTheBottom() throws {
    let model = W4ScrollModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave4b05"), size: .init(width: 24, height: 10)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
          Button("right") { _ = model.proxy?.scrollTo(edge: .trailing) }
          Button("mix") {
            _ = model.proxy?.scrollTo(edge: .bottom)
            _ = model.proxy?.scrollTo(edge: .leading)
          }
        }
        W4TwoAxisLazy(model: model)
      }
    }
    defer { h.shutdown() }
    _ = try h.clickText("right")
    _ = try h.render()
    try #require(model.offset.x == 20 && !h.frame.contains("a0"), "\(model.offset)\n\(h.frame)")
    _ = try h.clickText("mix")
    #expect(model.offset.x == 0, "\(model.offset)")
    #expect(h.frame.contains("a119"), "\(model.offset)\n\(h.frame)")
  }

  // Control: a later top edge in the same action wins over a bottom edge.
  @Test func wave4b06BottomThenTopInOneActionEndsAtTop() throws {
    let model = W4ScrollModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave4b06"), size: .init(width: 24, height: 10)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Button("mix") {
          _ = model.proxy?.scrollTo(edge: .bottom)
          _ = model.proxy?.scrollTo(edge: .top)
        }
        W4VariableLazy(model: model)
      }
    }
    defer { h.shutdown() }
    _ = try h.clickText("mix")
    #expect(model.offset.y == 0, "\(model.offset)")
    #expect(h.frame.contains("a0"), "\(h.frame)")
  }

  // Control: an ID command after an edge command on the same view wins.
  @Test func wave4b07EdgeThenIDOnOneViewLaterCommandWins() throws {
    let model = W4ScrollModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave4b07"), size: .init(width: 24, height: 10)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Button("mix") {
          _ = model.proxy?.scrollTo(edge: .bottom)
          _ = model.proxy?.scrollTo(5, anchor: .top)
        }
        W4VariableLazy(model: model)
      }
    }
    defer { h.shutdown() }
    _ = try h.clickText("mix")
    _ = try h.render()
    #expect(model.offset.y == 5, "\(model.offset)")
    #expect(!h.frame.contains("a119"), "\(h.frame)")
  }

  // A data `Table` reveals a row the same action appended (STUI-1306's Table
  // twin; `Collections.md:193-194`).
  @Test(arguments: [false, true])
  func wave4b08TableScrollToAppendedIDRevealsRow(existing: Bool) throws {
    let model = W4ScrollModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave4b08", existing ? "existing" : "appended"),
      size: .init(width: 24, height: 10)
    ) { W4TableAppendRoot(model: model, appends: !existing) }
    defer { h.shutdown() }
    try #require(h.frame.contains("t00") && !h.frame.contains("t19"), "\(h.frame)")
    _ = try h.clickText("Go")
    _ = try h.render()
    let target = existing ? "t19" : "t20"
    #expect(h.frame.contains(target), "\(h.frame)")
  }

  // A lazy stack reveals an identified row the same action appended.
  @Test func wave4b09LazyScrollToAppendedIDRevealsRow() throws {
    let model = W4ScrollModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave4b09"), size: .init(width: 24, height: 8)
    ) { W4AppendRoot(model: model, edgeFirst: false, lazyTarget: true) }
    defer { h.shutdown() }
    try #require(h.frame.contains("row 00"), "\(h.frame)")
    _ = try h.clickText("Append")
    _ = try h.render()
    #expect(
      h.frame.contains("row 24"), "result \(String(describing: model.lastResult))\n\(h.frame)")
  }

  // A body that issues an edge command on every evaluation converges: the
  // command resolves in the frame that issued it and requests no frame.
  @Test func wave4b10BodyIssuedEdgeCommandSettles() throws {
    let model = W4ScrollModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave4b10"), size: .init(width: 24, height: 8)
    ) { W4BodyEdgeRoot(model: model) }
    defer { h.shutdown() }
    _ = try h.renderAfterExternalMutation()
    _ = try h.render()
    #expect(!h.runLoop.scheduler.hasPendingFrame(at: .now()), "\(model.evaluations) evaluations")
    let settled = model.evaluations
    _ = try h.render()
    #expect(model.evaluations == settled)
  }
}

// MARK: Wave 4 fixtures: pending scroll commands

@MainActor
private final class W4ScrollModel {
  var offset = ScrollCellOffset.zero
  var proxy: ScrollViewProxy?
  var count = 20
  var lastResult: Bool?
  var selection: String?
  var evaluations = 0
  var binding: Binding<ScrollCellOffset> { .init(get: { self.offset }, set: { self.offset = $0 }) }
  var selectionBinding: Binding<String?> {
    .init(get: { self.selection }, set: { self.selection = $0 })
  }
  func capture(_ proxy: ScrollViewProxy) -> Bool {
    self.proxy = proxy
    return true
  }
}

private struct W4ModelRows: View {
  let model: W4ScrollModel
  var identified = false
  var body: some View {
    ScrollViewReader { proxy in
      let _ = model.capture(proxy)
      ScrollView(.vertical, position: model.binding) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<model.count, id: \.self) { i in
            if identified {
              Text(setCRowLabel(i)).id(i)
            } else {
              Text(setCRowLabel(i))
            }
          }
        }
      }.scrollIndicators(.hidden).frame(width: 20, height: 6)
    }
  }
}

private struct W4AppendRoot: View {
  let model: W4ScrollModel
  let edgeFirst: Bool
  var lazyTarget = false
  @State private var count = 20

  var body: some View {
    ScrollViewReader { proxy in
      let _ = model.capture(proxy)
      VStack(alignment: .leading, spacing: 0) {
        Button("Append") {
          if lazyTarget {
            count += 5
            model.lastResult = proxy.scrollTo(24, anchor: .bottom)
          } else if edgeFirst {
            model.lastResult = proxy.scrollTo(edge: .bottom)
            count += 5
          } else {
            count += 5
            model.lastResult = proxy.scrollTo(edge: .bottom)
          }
        }
        ScrollView(.vertical, position: model.binding) {
          if lazyTarget {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(0..<count, id: \.self) { i in Text(setCRowLabel(i)).id(i) }
            }
          } else {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<count, id: \.self) { i in Text(setCRowLabel(i)) }
            }
          }
        }.scrollIndicators(.hidden).frame(width: 20, height: 6)
      }
    }
  }
}

private struct W4TwoAxisLazy: View {
  let model: W4ScrollModel
  var body: some View {
    ScrollViewReader { proxy in
      let _ = model.capture(proxy)
      ScrollView([.horizontal, .vertical], position: model.binding) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<120, id: \.self) { i in
            Text("a\(i)").frame(width: 40, height: i < 40 ? 1 : 3, alignment: .topLeading)
          }
        }
      }.scrollIndicators(.hidden).frame(width: 20, height: 8)
    }
  }
}

private struct W4VariableLazy: View {
  let model: W4ScrollModel
  var body: some View {
    ScrollViewReader { proxy in
      let _ = model.capture(proxy)
      ScrollView(.vertical, position: model.binding) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<120, id: \.self) { i in
            Text("a\(i)").frame(height: i < 40 ? 1 : 3, alignment: .topLeading).id(i)
          }
        }
      }.scrollIndicators(.hidden).frame(width: 20, height: 8)
    }
  }
}

private struct W4TableRow: Identifiable, Hashable, Sendable {
  let id: Int
  var label: String { id < 10 ? "t0\(id)" : "t\(id)" }
}

private struct W4TableAppendRoot: View {
  let model: W4ScrollModel
  let appends: Bool
  @State private var rows = (0..<20).map { W4TableRow(id: $0) }

  var body: some View {
    ScrollViewReader { proxy in
      let _ = model.capture(proxy)
      VStack(alignment: .leading, spacing: 0) {
        Button("Go") {
          if appends {
            let next = rows.count
            rows.append(W4TableRow(id: next))
            model.lastResult = proxy.scrollTo(next)
          } else {
            model.lastResult = proxy.scrollTo(19)
          }
        }
        Table(rows, columns: [TableColumn("Name")]) { row in Text(row.label) }
          .tableHeaders(.hidden).scrollIndicators(.hidden).frame(height: 8)
      }
    }
  }
}

private struct W4BodyEdgeRoot: View {
  let model: W4ScrollModel
  var body: some View {
    ScrollViewReader { proxy in
      let _ = model.capture(proxy)
      ScrollView(.vertical, position: model.binding) {
        VStack(alignment: .leading, spacing: 0) {
          let _ = model.record(proxy.scrollTo(edge: .bottom))
          ForEach(0..<20, id: \.self) { i in Text(setCRowLabel(i)) }
        }
      }.scrollIndicators(.hidden).frame(width: 20, height: 6)
    }
  }
}

extension W4ScrollModel {
  fileprivate func record(_ result: Bool) -> Bool {
    evaluations += 1
    lastResult = result
    return result
  }
}
