import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F1 pass 3 (STUI-1282), area 6: table bands, eligibility and high-water
/// widths when the data changes between frames. Crosses STUI-1172/1209
/// (wave 2) and STUI-1230/1239/1240 (wave 3). Contracts:
/// `Collections.md:39-43, 133-138, 187-198`.
@MainActor
@Suite(.serialized)
struct AdversarialSetCTableDataTests {
  @Test func setC277HiddenSeparatorClickAfterTopInsertSelectsRow() throws {
    let model = SetCTDModel(count: 40)
    model.hideAll = true
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC277"), size: .init(width: 20, height: 12)
    ) { SetCTDTable(model: model) }
    defer { h.shutdown() }
    model.rows.insert(contentsOf: ["p0", "p1", "p2", "p3", "p4"], at: 0)
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("r003"), "\(h.frame)")
    _ = try h.clickText("r003")
    #expect(model.selection == "r003", "\(String(describing: model.selection))\n\(h.frame)")
  }

  @Test func setC278MixedSeparatorClickAfterWheelSelectsRow() throws {
    let model = SetCTDModel(count: 60)
    model.hideEven = true
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC278"), size: .init(width: 20, height: 12)
    ) { SetCTDTable(model: model) }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "r000"))
    _ = try h.scrollPointer(at: point, deltaY: 7)
    let visible = setCTDVisibleRows(h)
    try #require(visible.count >= 4, "\(h.frame)")
    for target in [visible[1], visible[visible.count - 2]] {
      _ = try h.clickText(target)
      #expect(model.selection == target, "clicked \(target)\n\(h.frame)")
    }
  }

  @Test func setC279DisabledRowSkippedAfterReverse() throws {
    let model = SetCTDModel(count: 0)
    model.rows = ["r001", "r002", "r003", "r004", "r005"]
    model.disabled = ["r002"]
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC279"), size: .init(width: 20, height: 12)
    ) { SetCTDTable(model: model) }
    defer { h.shutdown() }
    model.rows.reverse()
    model.selection = "r003"
    _ = try h.renderAfterExternalMutation()
    _ = try h.focusText("r003")
    _ = try h.pressKey(.init(.arrowDown))
    #expect(model.selection == "r001", "\(String(describing: model.selection))")
  }

  @Test func setC280SelectedRowDisabledStaysSelected() throws {
    let model = SetCTDModel(count: 0)
    model.rows = ["r001", "r002", "r003", "r004"]
    model.selection = "r002"
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC280"), size: .init(width: 20, height: 12)
    ) { SetCTDTable(model: model) }
    defer { h.shutdown() }
    _ = try h.focusText("r002")
    model.disabled = ["r002"]
    _ = try h.renderAfterExternalMutation()
    #expect(model.selection == "r002")
    _ = try h.pressKey(.init(.arrowDown))
    #expect(model.selection == "r003", "\(String(describing: model.selection))")
  }

  @Test func setC281SeparatorsHiddenAtRuntimeClickSelectsRow() throws {
    let model = SetCTDModel(count: 40)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC281"), size: .init(width: 20, height: 14)
    ) { SetCTDTable(model: model) }
    defer { h.shutdown() }
    model.hideAll = true
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("r007"), "\(h.frame)")
    _ = try h.clickText("r007")
    #expect(model.selection == "r007", "\(String(describing: model.selection))\n\(h.frame)")
  }

  @Test func setC282HighWaterSurvivesOtherRowEdit() throws {
    let model = SetCTDModel(count: 30)
    model.texts["r020"] = "r020-wide-cell"
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC282"), size: .init(width: 30, height: 10)
    ) { SetCTDHostedTable(model: model) }
    defer { h.shutdown() }
    let narrow = setCTDTableWidth(h)
    try setCTDWheelUntil("r020-wide-cell", h)
    let widened = setCTDTableWidth(h)
    try #require(widened > narrow, "\(narrow) -> \(widened)\n\(h.frame)")
    model.texts["r021"] = "r021*"
    _ = try h.renderAfterExternalMutation()
    #expect(setCTDTableWidth(h) == widened, "\(h.frame)")
  }

  @Test func setC283HighWaterSurvivesWideRowShrink() throws {
    let model = SetCTDModel(count: 30)
    model.texts["r020"] = "r020-wide-cell"
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC283"), size: .init(width: 30, height: 10)
    ) { SetCTDHostedTable(model: model) }
    defer { h.shutdown() }
    try setCTDWheelUntil("r020-wide-cell", h)
    let widened = setCTDTableWidth(h)
    try #require(widened > 0, "\(h.frame)")
    model.texts["r020"] = "r020"
    _ = try h.renderAfterExternalMutation()
    #expect(setCTDTableWidth(h) == widened, "\(widened)\n\(h.frame)")
  }

  @Test func setC284HiddenSeparatorEndThenClickLastRow() throws {
    let model = SetCTDModel(count: 40)
    model.hideAll = true
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC284"), size: .init(width: 20, height: 8)
    ) { SetCTDTable(model: model) }
    defer { h.shutdown() }
    _ = try h.focusText("r000")
    _ = try h.pressKey(.init(.end))
    try #require(h.frame.contains("r039"), "\(h.frame)")
    _ = try h.clickText("r039")
    #expect(model.selection == "r039", "\(String(describing: model.selection))")
  }

  @Test func setC285ListRowSelectorReenabledByData() throws {
    let model = SetCTDModel(count: 0)
    model.rows = ["r001", "r002", "r003"]
    model.disabled = ["r002"]
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC285"), size: .init(width: 20, height: 8)
    ) {
      List(model.rows, id: \.self, selection: model.selectionBinding) { r in
        Text(r).disabled(model.disabled.contains(r))
      }
    }
    defer { h.shutdown() }
    func selector(_ label: String) throws -> AccessibilityNode {
      try #require(
        h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == label })
    }
    try #require(try selector("Select row 2").isEnabled == false)
    model.disabled = []
    _ = try h.renderAfterExternalMutation()
    #expect(try selector("Select row 2").isEnabled == true)
  }

  @Test func setC286SelectionFollowsAuthoredItemAfterInsertAbove() throws {
    let model = SetCTDModel(count: 10)
    model.selection = "r005"
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC286"), size: .init(width: 20, height: 30)
    ) { SetCTDTable(model: model) }
    defer { h.shutdown() }
    _ = try h.focusText("r005")
    model.rows.insert(contentsOf: ["p0", "p1", "p2"], at: 0)
    _ = try h.renderAfterExternalMutation()
    _ = try h.pressKey(.init(.arrowDown))
    #expect(model.selection == "r006", "\(String(describing: model.selection))")
  }
}

// MARK: - Fixtures

@MainActor
private final class SetCTDModel {
  var rows: [String]
  var texts: [String: String] = [:]
  var selection: String?
  var hideAll = false
  var hideEven = false
  var disabled: Set<String> = []

  init(count: Int) {
    rows = (0..<count).map { $0 < 10 ? "r00\($0)" : $0 < 100 ? "r0\($0)" : "r\($0)" }
  }

  var selectionBinding: Binding<String?> {
    Binding(get: { self.selection }, set: { self.selection = $0 })
  }

  func hides(_ row: String) -> Bool {
    if hideAll { return true }
    guard hideEven, let index = rows.firstIndex(of: row) else { return false }
    return index.isMultiple(of: 2)
  }
}

private struct SetCTDTable: View {
  let model: SetCTDModel

  var body: some View {
    Table(
      model.rows, id: \.self, selection: model.selectionBinding,
      columns: [TableColumn("Name", width: 12)]
    ) { r in
      Text(model.texts[r] ?? r)
        .disabled(model.disabled.contains(r))
        .listRowSeparator(model.hides(r) ? .hidden : .automatic)
    }.tableHeaders(.hidden)
  }
}

private struct SetCTDHostedTable: View {
  let model: SetCTDModel

  var body: some View {
    ScrollView {
      Table(model.rows, id: \.self, columns: [TableColumn("Name")]) { r in
        Text(model.texts[r] ?? r)
      }
    }.scrollIndicators(.hidden)
  }
}

@MainActor
private func setCTDVisibleRows<V: View>(_ h: StressRuntimeHarness<V>) -> [String] {
  h.frame.split(separator: "\n").compactMap { line in
    line.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
      .first { $0.hasPrefix("r") && $0.count == 4 }
  }
}

@MainActor
private func setCTDTableWidth<V: View>(_ h: StressRuntimeHarness<V>) -> Int {
  // Correction C3: the top border scrolls away; measure a row separator.
  h.frame.split(separator: "\n").first { $0.contains("├") }
    .map { $0.trimmingCharacters(in: .whitespaces).count } ?? -1
}

@MainActor
private func setCTDWheelUntil<V: View>(_ text: String, _ h: StressRuntimeHarness<V>) throws {
  let point = Point(x: 3.5, y: 3.5)
  var turns = 0
  while !h.frame.contains(text), turns < 30 {
    _ = try h.scrollPointer(at: point, deltaY: 3)
    turns += 1
  }
  try #require(h.frame.contains(text), "\(h.frame)")
}
