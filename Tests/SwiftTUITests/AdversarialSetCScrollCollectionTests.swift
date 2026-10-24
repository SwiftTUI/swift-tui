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
    setCKnown("STUI-1170: End changes both axes") {
      #expect(box.offset == .init(x: 0, y: 24))
    }
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
    setCKnown("STUI-1171: lazy End stops before the last variable-height row") {
      #expect(h.frame.contains("vrow 119"), "\(h.frame)")
    }
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
    setCKnown("STUI-1172: Table arrow navigation includes disabled rows") {
      #expect(box.selection == 3)
    }
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
    setCKnown("STUI-1172: Table pointer selection includes disabled rows") {
      #expect(box.selection == 1)
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
