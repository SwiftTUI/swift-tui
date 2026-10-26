import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two, F2 pass 2 (STUI-1283), setD161–setD170: modal presentations
// over tables, lists and scroll views, under resize, item replacement and
// one input batch. Brief 07.

@MainActor
private final class SetDSheetModel {
  var presented = false
  var sheetTaps = 0
  var baseTaps = 0
  var invoker: String?
  var binding: Binding<Bool> { .init(get: { self.presented }, set: { self.presented = $0 }) }
}

private struct SetDSheetItem: Identifiable, Sendable {
  var id: Int
}

private struct SetDItemPresenter: View {
  @State private var item: SetDSheetItem?
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("first") {}
      Button("open") { item = SetDSheetItem(id: 1) }
    }
    .sheet(item: $item) { current in
      Button("replace \(current.id)") { item = SetDSheetItem(id: current.id + 1) }
    }
  }
}

@MainActor
@Suite("Campaign F2 pass 2: modal presentation over collections and scrolling", .serialized)
struct AdversarialSetDPresentationModeTests {
  private func tableUnderSheet(
    _ name: String, box: SetDSelection<String?>, model: SetDSheetModel
  ) throws -> SetDLiveHarness<some View> {
    let rows = setDRows(200)
    return try SetDLiveHarness(name, size: .init(width: 60, height: 20)) {
      Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in Text(row.id) }
        .tableHeaders(.hidden)
        .scrollIndicators(.hidden)
        .sheet(isPresented: model.binding) { Button("sheet action") { model.sheetTaps += 1 } }
    }
  }

  private func present(_ h: SetDLiveHarness<some View>, _ model: SetDSheetModel) throws {
    model.presented = true
    try h.renderRoot()
    try #require(h.frame.contains("sheet action"), "\(h.frame)")
  }

  @Test("setD161: a wheel over a base table row beside a sheet leaves the table window")
  func setD161WheelBesideSheetIsBlocked() throws {
    let box = SetDSelection<String?>("r005")
    let model = SetDSheetModel()
    let h = try tableUnderSheet("161", box: box, model: model)
    defer { h.shutdown() }
    try present(h, model)
    let before = h.tokens(prefix: "r")
    // Correction C3: the sheet card covers the base rows (the base table shows
    // only its outer border column beside the card), so the wheel and the
    // click target the visible base border cell on a row line.
    let cell = CellPoint(x: 0, y: 7)
    try #require(h.raster?.cells[cell.y][cell.x].character != " ", "\(h.frame)")
    try h.wheel(at: cell, deltaY: 3)
    #expect(h.tokens(prefix: "r") == before, "\(h.frame)")
  }

  @Test("setD162: a click on a base table row beside a sheet leaves the selection")
  func setD162ClickBesideSheetIsBlocked() throws {
    let box = SetDSelection<String?>("r005")
    let model = SetDSheetModel()
    let h = try tableUnderSheet("162", box: box, model: model)
    defer { h.shutdown() }
    let row = try #require(h.cell(of: "r003"), "\(h.frame)")
    try present(h, model)
    // Correction C3: the card covers the row's text; press its border cell.
    try h.click(CellPoint(x: 0, y: row.y))
    #expect(box.value == "r005")
    #expect(model.presented)
  }

  @Test("setD163: paging and arrow keys under a sheet leave the base table")
  func setD163KeysUnderSheetLeaveBaseTable() throws {
    let box = SetDSelection<String?>("r005")
    let model = SetDSheetModel()
    let h = try tableUnderSheet("163", box: box, model: model)
    defer { h.shutdown() }
    try h.focusText("r005")
    try present(h, model)
    let before = h.tokens(prefix: "r")
    for key in [KeyEvent.pageDown, .end, .arrowDown] { try h.key(key) }
    #expect(box.value == "r005")
    #expect(h.tokens(prefix: "r") == before, "\(h.frame)")
  }

  @Test("setD164: a base table row selector is refused while a sheet is up")
  func setD164BaseSelectorRefusedUnderSheet() throws {
    let box = SetDSelection<String?>("r005")
    let model = SetDSheetModel()
    let h = try tableUnderSheet("164", box: box, model: model)
    defer { h.shutdown() }
    let target = try #require(h.accessibilityNode(label: "Select row 4")?.actionTarget)
    try present(h, model)
    let result = h.runLoop.withRuntimeRegistrationScope {
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
    }
    try h.render()
    #expect(result != .accepted, "\(String(describing: result))")
    #expect(box.value == "r005")
  }

  @Test("setD165: Escape returns focus to the invoking button of a scrolled list row")
  func setD165FocusReturnsToScrolledListRowButton() throws {
    let model = SetDSheetModel()
    let rows = setDRows(60)
    let h = try SetDLiveHarness("165", size: .init(width: 40, height: 12)) {
      ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 0) {
          Button("jump") { _ = proxy.scrollTo("r025", anchor: .top) }
          List(rows) { row in
            HStack(spacing: 1) {
              Text(row.id)
              Button("open") {
                model.invoker = row.id
                model.presented = true
              }
            }
          }
          .frame(height: 10)
          .sheet(isPresented: model.binding) { Button("sheet action") { model.sheetTaps += 1 } }
        }
      }
    }
    defer { h.shutdown() }
    try h.clickText("jump")
    let rowCell = try #require(h.cell(of: "r025"), "\(h.frame)")
    let line = h.lines[rowCell.y]
    let openColumn = try #require(line.range(of: "open")).lowerBound
    let x = line.distance(from: line.startIndex, to: openColumn)
    let region = try #require(
      h.runLoop.focusTracker.focusRegions.last {
        $0.rect.contains(CellPoint(x: x, y: rowCell.y))
      }, "no focus region on r025's button")
    try h.focus(region.identity)
    try h.key(.return)
    try #require(model.presented && model.invoker == "r025", "\(h.frame)")
    try h.key(.escape)
    #expect(!model.presented)
    #expect(h.runLoop.focusTracker.currentFocusIdentity == region.identity)
    model.invoker = nil
    try h.key(.return)
    #expect(model.invoker == "r025" && model.presented)
  }

  @Test("setD166: a hidden-separator table inside a sheet routes a click on a low row")
  func setD166TableInsideSheetRoutesLowRow() throws {
    let model = SetDSheetModel()
    let box = SetDSelection<String?>(nil)
    let rows = setDRows(200, prefix: "s")
    let h = try SetDLiveHarness("166", size: .init(width: 40, height: 24)) {
      Text("base").sheet(isPresented: model.binding) {
        Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
          Text(row.id).listRowSeparator(.hidden)
        }
        .tableHeaders(.hidden)
        .scrollIndicators(.hidden)
        .frame(width: 20, height: 16)
      }
    }
    defer { h.shutdown() }
    model.presented = true
    try h.renderRoot()
    let visible = h.tokens(prefix: "s")
    try #require(visible.count >= 10, "\(h.frame)")
    let target = visible[visible.count - 2]
    try h.clickText(target)
    #expect(box.value == target, "clicked \(target); visible \(visible)")
  }

  @Test("setD167: End in a sheet's scroll view scrolls it and not the base")
  func setD167EndScrollsSheetScrollViewOnly() throws {
    let model = SetDSheetModel()
    let base = SetDOffsetBox()
    let inner = SetDOffsetBox()
    let h = try SetDLiveHarness("167", size: .init(width: 40, height: 16)) {
      ScrollView(.vertical, position: base.binding) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<40, id: \.self) { Text("b\($0)") }
        }
      }
      .scrollIndicators(.hidden)
      .sheet(isPresented: model.binding) {
        ScrollView(.vertical, position: inner.binding) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<20, id: \.self) { Text("s\($0)") }
          }
        }
        .scrollIndicators(.hidden)
        .frame(width: 10, height: 5)
      }
    }
    defer { h.shutdown() }
    model.presented = true
    try h.renderRoot()
    let s0 = try #require(h.cell(of: "s0"), "\(h.frame)")
    // Correction C4: the base route's viewport also contains s0; take the
    // innermost (smallest) route.
    let route = try #require(
      h.runLoop.latestSemanticSnapshot.scrollRoutes.filter { $0.viewportRect.contains(s0) }
        .min { $0.viewportRect.size.height < $1.viewportRect.size.height })
    try h.focus(route.identity)
    try h.key(.end)
    #expect(inner.value.y == 15, "\(inner.value)")
    #expect(base.value == .zero, "\(base.value)")
  }

  @Test("setD168: an alert re-centres across a live resize and keeps focus")
  func setD168AlertAcrossResize() throws {
    let model = SetDSheetModel()
    let h = try SetDLiveHarness("168", size: .init(width: 40, height: 12)) {
      Text("base").alert("Confirm", isPresented: model.binding) {
        Button("OK") { model.sheetTaps += 1 }
      } message: {
        Text("Proceed?")
      }
    }
    defer { h.shutdown() }
    model.presented = true
    try h.renderRoot()
    let focused = h.runLoop.focusTracker.currentFocusIdentity
    try #require(focused != nil)
    for size in [CellSize(width: 41, height: 13), CellSize(width: 40, height: 12)] {
      try h.resize(size)
      let raster = try #require(h.raster)
      var corners: [CellPoint] = []
      for (y, row) in raster.cells.enumerated() {
        for (x, cell) in row.enumerated() where "┌╭┏╔┘╯┛╝".contains(cell.character) {
          corners.append(CellPoint(x: x, y: y))
        }
      }
      let first = try #require(corners.first, "\(h.frame)")
      let last = try #require(corners.last)
      let width = last.x - first.x + 1
      let height = last.y - first.y + 1
      #expect(
        first.x == (size.width - width) / 2, "\(size): \(first) \(width)x\(height)\n\(h.frame)")
      #expect(
        first.y == (size.height - height) / 2, "\(size): \(first) \(width)x\(height)\n\(h.frame)")
      #expect(h.runLoop.focusTracker.currentFocusIdentity == focused)
    }
  }

  // Correction C5: the item lives in observed @State; the original fixture's
  // unobserved class model never re-resolved the presenter after the
  // in-sheet write.
  @Test("setD169: replacing a presented item's ID keeps the original return target")
  func setD169ItemReplacementKeepsReturnTarget() throws {
    let h = try SetDLiveHarness("169", size: .init(width: 40, height: 12)) { SetDItemPresenter() }
    defer { h.shutdown() }
    try h.focusText("open")
    let invoker = try #require(h.runLoop.focusTracker.currentFocusIdentity)
    try h.key(.return)
    try #require(h.frame.contains("replace 1"), "\(h.frame)")
    try h.focusText("replace 1")
    try h.key(.return)
    try #require(h.frame.contains("replace 2"), "\(h.frame)")
    try h.key(.escape)
    #expect(!h.frame.contains("replace"), "\(h.frame)")
    #expect(h.runLoop.focusTracker.currentFocusIdentity == invoker)
  }

  @Test("setD170: probe — Escape and Return in one batch with a sheet button focused")
  func setD170EscapeThenReturnInOneBatch() throws {
    let model = SetDSheetModel()
    let h = try SetDLiveHarness("170", size: .init(width: 40, height: 12)) {
      Button("base") {
        model.baseTaps += 1
        model.presented = true
      }
      .sheet(isPresented: model.binding) { Button("sheet action") { model.sheetTaps += 1 } }
    }
    defer { h.shutdown() }
    try h.focusText("base")
    try h.key(.return)
    try #require(model.presented && model.baseTaps == 1, "\(h.frame)")
    try h.focusText("sheet action")
    try h.keys([.escape, .return])
    print(
      "setD170 observation: presented \(model.presented), base taps \(model.baseTaps), "
        + "sheet taps \(model.sheetTaps)")
    #expect(model.baseTaps + model.sheetTaps >= 1)
  }
}
