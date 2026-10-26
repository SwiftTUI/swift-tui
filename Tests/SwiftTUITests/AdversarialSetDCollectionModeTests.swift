import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two, F2 pass 2 (STUI-1283), setD101–setD130: viewport-backed
// tables and lists under a live resize, external data and selection
// mutation, and one input batch. Briefs 01–03 in the coordination root's
// docs/reports/evidence/2026-10-26-campaign-two-f2-pass-2/.

@MainActor
private enum SetDTables {
  static let small = CellSize(width: 30, height: 10)

  static func selectable(
    _ name: String, box: SetDSelection<String?>, hidden: Bool,
    rows: [SetDRow] = setDRows(200), size: CellSize = small
  ) throws -> SetDLiveHarness<some View> {
    try SetDLiveHarness(name, size: size) {
      Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
        Text(row.id).listRowSeparator(hidden ? .hidden : .automatic)
      }.tableHeaders(.hidden).scrollIndicators(.hidden)
    }
  }

  static func plain(
    _ name: String, hidden: Bool, size: CellSize = .init(width: 30, height: 12)
  ) throws -> SetDLiveHarness<some View> {
    let rows = setDRows(200)
    return try SetDLiveHarness(name, size: size) {
      Table(rows, columns: [TableColumn("Name")]) { row in
        Text(row.id).listRowSeparator(hidden ? .hidden : .automatic)
      }.tableHeaders(.hidden).scrollIndicators(.hidden)
    }
  }

  static func list(
    _ name: String, box: SetDSelection<String?>, size: CellSize = small
  ) throws -> SetDLiveHarness<some View> {
    let rows = setDRows(200)
    return try SetDLiveHarness(name, size: size) {
      List(rows, selection: box.binding) { row in Text(row.id) }.scrollIndicators(.hidden)
    }
  }
}

@MainActor
@Suite("Campaign F2 pass 2: collections under a live resize", .serialized)
struct AdversarialSetDCollectionResizeTests {
  @Test("setD101: a grown drawn-separator table routes a click on a low visible row")
  func setD101GrownDrawnTableRoutesLowRow() throws {
    let box = SetDSelection<String?>("r100")
    let h = try SetDTables.selectable("101", box: box, hidden: false)
    defer { h.shutdown() }
    try h.resize(.init(width: 30, height: 120))
    let visible = h.tokens(prefix: "r")
    try #require(visible.count >= 50, "\(h.frame)")
    let target = visible[visible.count - 2]
    try h.clickText(target)
    setDKnown(
      "NEW-1: after a grow resize the first frame's row actions and pointer routes cover only the previous viewport's band, so a low visible row ignores its click or selector; the band reads the previous frame's published layout and viewport (CollectionScrollState.swift:103-135, CollectionSupport.swift:239-253); contract: Collections.md:133-135, CollectionSupport.swift:204-207; adjacent STUI-1239"
    ) {
      #expect(box.value == target, "clicked \(target); visible \(visible.first!)…\(visible.last!)")
    }
  }

  @Test("setD102: a grown hidden-separator table routes a click on a low visible row")
  func setD102GrownHiddenTableRoutesLowRow() throws {
    let box = SetDSelection<String?>("r100")
    let h = try SetDTables.selectable("102", box: box, hidden: true)
    defer { h.shutdown() }
    try h.resize(.init(width: 30, height: 64))
    let visible = h.tokens(prefix: "r")
    try #require(visible.count >= 60, "\(h.frame)")
    let target = visible[visible.count - 2]
    try h.clickText(target)
    setDKnown(
      "NEW-1: after a grow resize the first frame's row actions and pointer routes cover only the previous viewport's band, so a low visible row ignores its click or selector; the band reads the previous frame's published layout and viewport (CollectionScrollState.swift:103-135, CollectionSupport.swift:239-253); contract: Collections.md:133-135, CollectionSupport.swift:204-207; adjacent STUI-1239"
    ) {
      #expect(box.value == target, "clicked \(target); visible \(visible.first!)…\(visible.last!)")
    }
  }

  // Correction C8 (input): a pointer press on a lower List row reveals and
  // scrolls the list before the release (wave-3 FB observation O2), so a
  // click cannot test the band. The list's own row selector is used instead.
  @Test("setD103: a grown data list keeps a low visible row's selector")
  func setD103GrownListRoutesLowRow() throws {
    let box = SetDSelection<String?>("r100")
    let h = try SetDTables.list("103", box: box)
    defer { h.shutdown() }
    try h.resize(.init(width: 30, height: 120))
    let visible = h.tokens(prefix: "r")
    try #require(visible.count >= 50, "\(h.frame)")
    let target = visible[visible.count - 2]
    let rowNumber = try #require(Int(target.dropFirst())) + 1
    let result = try h.activate(label: "Select row \(rowNumber)")
    setDKnown(
      "NEW-1: after a grow resize the first frame's row actions and pointer routes cover only the previous viewport's band, so a low visible row ignores its click or selector; the band reads the previous frame's published layout and viewport (CollectionScrollState.swift:103-135, CollectionSupport.swift:239-253); contract: Collections.md:133-135, CollectionSupport.swift:204-207; adjacent STUI-1239"
    ) {
      #expect(result == .accepted, "\(String(describing: result)) for \(target)")
    }
    setDKnown(
      "NEW-1: after a grow resize the first frame's row actions and pointer routes cover only the previous viewport's band, so a low visible row ignores its click or selector; the band reads the previous frame's published layout and viewport (CollectionScrollState.swift:103-135, CollectionSupport.swift:239-253); contract: Collections.md:133-135, CollectionSupport.swift:204-207; adjacent STUI-1239"
    ) {
      #expect(box.value == target, "selected \(target); visible \(visible.first!)…\(visible.last!)")
    }
  }

  @Test("setD104: a grown table's low visible row keeps its assistive selector")
  func setD104GrownTableKeepsLowRowSelector() throws {
    let box = SetDSelection<String?>("r100")
    let h = try SetDTables.selectable("104", box: box, hidden: false)
    defer { h.shutdown() }
    try h.resize(.init(width: 30, height: 120))
    let visible = h.tokens(prefix: "r")
    try #require(visible.count >= 50, "\(h.frame)")
    let target = visible[visible.count - 2]
    let rowNumber = try #require(Int(target.dropFirst())) + 1
    let result = try h.activate(label: "Select row \(rowNumber)")
    setDKnown(
      "NEW-1: after a grow resize the first frame's row actions and pointer routes cover only the previous viewport's band, so a low visible row ignores its click or selector; the band reads the previous frame's published layout and viewport (CollectionScrollState.swift:103-135, CollectionSupport.swift:239-253); contract: Collections.md:133-135, CollectionSupport.swift:204-207; adjacent STUI-1239"
    ) {
      #expect(result == .accepted, "\(String(describing: result)) for \(target)")
    }
    setDKnown(
      "NEW-1: after a grow resize the first frame's row actions and pointer routes cover only the previous viewport's band, so a low visible row ignores its click or selector; the band reads the previous frame's published layout and viewport (CollectionScrollState.swift:103-135, CollectionSupport.swift:239-253); contract: Collections.md:133-135, CollectionSupport.swift:204-207; adjacent STUI-1239"
    ) {
      #expect(box.value == target)
    }
  }

  @Test("setD105: one more root frame after the grow restores the low row's route")
  func setD105ExtraFrameRestoresBand() throws {
    let box = SetDSelection<String?>("r100")
    let h = try SetDTables.selectable("105", box: box, hidden: true)
    defer { h.shutdown() }
    try h.resize(.init(width: 30, height: 64))
    try h.renderRoot()
    let visible = h.tokens(prefix: "r")
    try #require(visible.count >= 60, "\(h.frame)")
    let target = visible[visible.count - 2]
    try h.clickText(target)
    #expect(box.value == target)
  }

  @Test("setD106: an end window stays attached to the last row through a grow")
  func setD106EndAnchorSurvivesGrow() throws {
    let h = try SetDTables.plain("106", hidden: true, size: SetDTables.small)
    defer { h.shutdown() }
    try h.key(.tab)
    try h.key(.end)
    try #require(h.tokens(prefix: "r").last == "r199", "\(h.frame)")
    try h.resize(.init(width: 30, height: 64))
    let visible = h.tokens(prefix: "r")
    #expect(visible.last == "r199", "\(h.frame)")
    #expect(visible.count >= 60, "the grown end window is full: \(visible.count) rows")
  }

  @Test("setD107: an end window stays attached to the last row through a shrink")
  func setD107EndAnchorSurvivesShrink() throws {
    let h = try SetDTables.plain("107", hidden: true, size: .init(width: 30, height: 64))
    defer { h.shutdown() }
    try h.key(.tab)
    try h.key(.end)
    try #require(h.tokens(prefix: "r").last == "r199", "\(h.frame)")
    try h.resize(SetDTables.small)
    #expect(h.tokens(prefix: "r").last == "r199", "\(h.frame)")
  }

  @Test("setD108: a wheel notch over a low row of a grown table scrolls its window")
  func setD108GrownTableWheelScrolls() throws {
    let box = SetDSelection<String?>("r100")
    let h = try SetDTables.selectable("108", box: box, hidden: false)
    defer { h.shutdown() }
    try h.resize(.init(width: 30, height: 120))
    let before = h.tokens(prefix: "r")
    let beforeLines = h.lines
    try #require(before.count >= 50, "\(h.frame)")
    let low = try #require(h.cell(of: before[before.count - 2]))
    // Correction C2: the unanchored window can start on a separator line, so
    // the first notch moves it to the next row boundary without changing the
    // first visible row; the window itself must move.
    try h.wheel(at: low, deltaY: 1)
    #expect(h.lines != beforeLines, "the first notch moves the window")
    try h.wheel(at: low, deltaY: 1)
    let after = h.tokens(prefix: "r")
    #expect(after.first != before.first, "before \(before.first!) after \(after.first ?? "-")")
    #expect(box.value == "r100", "the wheel leaves the selection alone")
  }

  @Test("setD109: a grown multi-select table toggles a low visible row on click")
  func setD109GrownMultiSelectTableTogglesLowRow() throws {
    let box = SetDSelection<Set<String>>([])
    let rows = setDRows(200)
    let h = try SetDLiveHarness("109", size: SetDTables.small) {
      Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
        Text(row.id).listRowSeparator(.hidden)
      }.tableHeaders(.hidden).scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    try h.resize(.init(width: 30, height: 64))
    let visible = h.tokens(prefix: "r")
    try #require(visible.count >= 60, "\(h.frame)")
    let target = visible[visible.count - 2]
    try h.clickText(target)
    setDKnown(
      "NEW-1: after a grow resize the first frame's row actions and pointer routes cover only the previous viewport's band, so a low visible row ignores its click or selector; the band reads the previous frame's published layout and viewport (CollectionScrollState.swift:103-135, CollectionSupport.swift:239-253); contract: Collections.md:133-135, CollectionSupport.swift:204-207; adjacent STUI-1239"
    ) {
      #expect(
        box.value == [target], "clicked \(target); visible \(visible.first!)…\(visible.last!)")
    }
  }

  @Test("setD110: a grown end window routes a click on its first visible row")
  func setD110GrownEndWindowRoutesTopRow() throws {
    let box = SetDSelection<String?>(nil)
    let h = try SetDTables.selectable("110", box: box, hidden: true)
    defer { h.shutdown() }
    try h.key(.tab)
    try h.key(.end)
    try #require(h.tokens(prefix: "r").last == "r199", "\(h.frame)")
    try h.resize(.init(width: 30, height: 64))
    let visible = h.tokens(prefix: "r")
    try #require(visible.count >= 60 && visible.last == "r199", "\(h.frame)")
    let target = visible[1]
    try h.clickText(target)
    setDKnown(
      "NEW-1: after a grow resize the first frame's row actions and pointer routes cover only the previous viewport's band, so a low visible row ignores its click or selector; the band reads the previous frame's published layout and viewport (CollectionScrollState.swift:103-135, CollectionSupport.swift:239-253); contract: Collections.md:133-135, CollectionSupport.swift:204-207; adjacent STUI-1239"
    ) {
      #expect(box.value == target, "clicked \(target); visible \(visible.first!)…\(visible.last!)")
    }
  }
}

@MainActor
private final class SetDRowModel {
  var rows = setDRows(200)
  var disabled: Set<String> = []
}

@MainActor
@Suite("Campaign F2 pass 2: collections under external data and selection mutation", .serialized)
struct AdversarialSetDCollectionMutationTests {
  // Correction C1 (setD111–setD115): an external selection write does not
  // move the window (Collections.md:182-183: the window is owned separately
  // from the selection), so the original "the window follows the selection"
  // precondition was invalid. The corrected cells pin that the unmoved window
  // keeps every visible row routed after the jump or reorder.
  @Test("setD111: after a programmatic selection jump a visible row is clickable")
  func setD111SelectionJumpKeepsVisibleRowsClickable() throws {
    let box = SetDSelection<String?>("r010")
    let h = try SetDTables.selectable(
      "111", box: box, hidden: false, size: .init(width: 30, height: 24))
    defer { h.shutdown() }
    let before = h.tokens(prefix: "r")
    box.value = "r160"
    try h.renderRoot()
    let visible = h.tokens(prefix: "r")
    try #require(visible == before, "the window stays: \(h.frame)")
    let target = visible[visible.count - 2]
    try h.clickText(target)
    #expect(box.value == target, "clicked \(target); visible \(visible.first!)…\(visible.last!)")
  }

  @Test("setD112: after a programmatic selection jump a visible row's selector is accepted")
  func setD112SelectionJumpKeepsSelectors() throws {
    let box = SetDSelection<String?>("r010")
    let h = try SetDTables.selectable(
      "112", box: box, hidden: false, size: .init(width: 30, height: 24))
    defer { h.shutdown() }
    box.value = "r160"
    try h.renderRoot()
    let visible = h.tokens(prefix: "r")
    let target = visible[visible.count - 2]
    let rowNumber = try #require(Int(target.dropFirst())) + 1
    let result = try h.activate(label: "Select row \(rowNumber)")
    #expect(result == .accepted, "\(String(describing: result)) for \(target)")
    #expect(box.value == target)
  }

  @Test("setD113: after a same-count reorder a visible row is clickable")
  func setD113ReorderKeepsVisibleRowsClickable() throws {
    let box = SetDSelection<String?>("r010")
    let model = SetDRowModel()
    let h = try SetDLiveHarness("113", size: .init(width: 30, height: 24)) {
      Table(model.rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
        Text(row.id)
      }.tableHeaders(.hidden).scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    model.rows.reverse()
    try h.renderRoot()
    let visible = h.tokens(prefix: "r")
    try #require(visible.count >= 8, "\(h.frame)")
    let target = visible[1]
    try h.clickText(target)
    #expect(box.value == target, "clicked \(target); visible \(visible.first!)…\(visible.last!)")
  }

  @Test("setD114: after a programmatic selection jump a visible list row's selector is accepted")
  func setD114ListSelectionJumpKeepsRowsClickable() throws {
    let box = SetDSelection<String?>("r010")
    let h = try SetDTables.list("114", box: box, size: .init(width: 30, height: 24))
    defer { h.shutdown() }
    box.value = "r160"
    try h.renderRoot()
    let visible = h.tokens(prefix: "r")
    let target = visible[visible.count - 2]
    // Correction C8: the row selector, not a click (wave-3 FB observation O2).
    let rowNumber = try #require(Int(target.dropFirst())) + 1
    let result = try h.activate(label: "Select row \(rowNumber)")
    #expect(result == .accepted, "\(String(describing: result)) for \(target)")
    #expect(box.value == target, "selected \(target); visible \(visible.first!)…\(visible.last!)")
  }

  @Test("setD115: one more root frame after the jump keeps the band")
  func setD115ExtraFrameAfterJumpRestoresBand() throws {
    let box = SetDSelection<String?>("r010")
    let h = try SetDTables.selectable(
      "115", box: box, hidden: false, size: .init(width: 30, height: 24))
    defer { h.shutdown() }
    box.value = "r160"
    try h.renderRoot()
    try h.renderRoot()
    let visible = h.tokens(prefix: "r")
    let target = visible[visible.count - 2]
    try h.clickText(target)
    #expect(box.value == target)
  }

  @Test("setD116: a data-driven plain list honours hidden row separators")
  func setD116DataListHonoursHiddenSeparators() throws {
    let rows = setDRows(6)
    let staticList = try SetDLiveHarness("116-static", size: .init(width: 20, height: 16)) {
      List {
        ForEach(rows) { row in Text(row.id).listRowSeparator(.hidden) }
      }.listStyle(.plain)
    }
    defer { staticList.shutdown() }
    try #require(!staticList.frame.contains("─"), "control: \(staticList.frame)")
    let h = try SetDLiveHarness("116", size: .init(width: 20, height: 16)) {
      List(rows) { row in Text(row.id).listRowSeparator(.hidden) }.listStyle(.plain)
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("r000") && h.frame.contains("r005"), "\(h.frame)")
    setDKnown(
      "duplicate of wave-3 hunt FB observation O1 (filed within STUI-1261-1295): a viewport-backed plain List draws separators its rows hide; the line builder emits a separator at every odd position (CollectionStylePresentationLayout.swift:843-851); contract: StyleModifiers.swift:1616-1647; adjacent STUI-1209"
    ) {
      #expect(!h.frame.contains("─"), "\(h.frame)")
    }
    let first = try #require(h.cell(of: "r000")).y
    let second = try #require(h.cell(of: "r001")).y
    setDKnown(
      "duplicate of wave-3 hunt FB observation O1 (filed within STUI-1261-1295): a viewport-backed plain List draws separators its rows hide; the line builder emits a separator at every odd position (CollectionStylePresentationLayout.swift:843-851); contract: StyleModifiers.swift:1616-1647; adjacent STUI-1209"
    ) {
      #expect(second - first == 1, "rows \(first), \(second)\n\(h.frame)")
    }
  }

  @Test("setD117: a data-driven plain list hides only the named row's separator")
  func setD117DataListHidesOneSeparator() throws {
    let rows = setDRows(4)
    let h = try SetDLiveHarness("117", size: .init(width: 20, height: 16)) {
      List(rows) { row in
        if row.id == "r001" {
          Text(row.id).listRowSeparator(.hidden, edges: .bottom)
        } else {
          Text(row.id)
        }
      }.listStyle(.plain)
    }
    defer { h.shutdown() }
    let y = try ["r000", "r001", "r002", "r003"].map {
      try #require(h.cell(of: $0), "\(h.frame)").y
    }
    setDKnown(
      "duplicate of wave-3 hunt FB observation O1 (filed within STUI-1261-1295): a viewport-backed plain List draws separators its rows hide; the line builder emits a separator at every odd position (CollectionStylePresentationLayout.swift:843-851); contract: StyleModifiers.swift:1616-1647; adjacent STUI-1209"
    ) {
      #expect(zip(y.dropFirst(), y).map { $0 - $1 } == [2, 1, 2], "rows \(y)\n\(h.frame)")
    }
  }

  @Test("setD118: a scroll-hosted 2000-row table registers a bounded number of row actions")
  func setD118ScrollHostedTableBoundsRowActions() throws {
    let box = SetDSelection<String?>(nil)
    let rows = setDRows(2000, digits: 4)
    let h = try SetDLiveHarness("118", size: .init(width: 30, height: 20)) {
      ScrollView {
        Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
          Text(row.id)
        }.tableHeaders(.hidden)
      }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("r0000"), "\(h.frame)")
    setDKnown(
      "NEW-8: a ScrollView-hosted 2000-row data table registers 2001 row actions; the line model publishes the whole body as visible, so the band spans the dataset (DrawExtractor+Tables.swift:784-800, CollectionSupport.swift:239-253); contract: Collections.md:154-161; adjacent STUI-1273"
    ) {
      #expect(h.actionRegistrationCount < 150, "\(h.actionRegistrationCount) action registrations")
    }
  }

  @Test("setD119: an unhosted 2000-row table registers a bounded number of row actions")
  func setD119UnhostedTableBoundsRowActions() throws {
    let box = SetDSelection<String?>(nil)
    let rows = setDRows(2000, digits: 4)
    let h = try SetDLiveHarness("119", size: .init(width: 30, height: 20)) {
      Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
        Text(row.id)
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("r0000"), "\(h.frame)")
    #expect(h.actionRegistrationCount < 150, "\(h.actionRegistrationCount) action registrations")
  }

  @Test("setD120: the multi-select cursor row's eligibility flips off and back on")
  func setD120CursorEligibilityFlip() throws {
    let box = SetDSelection<Set<String>>([])
    let model = SetDRowModel()
    let h = try SetDLiveHarness("120", size: .init(width: 30, height: 12)) {
      Table(model.rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
        Text(row.id).disabled(model.disabled.contains(row.id))
      }.tableHeaders(.hidden).scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    try h.focusText("r000")
    try h.key(.arrowDown)
    model.disabled = ["r001"]
    try h.renderRoot()
    try h.key(.space)
    #expect(box.value.isEmpty, "a disabled cursor row does not toggle: \(box.value)")
    model.disabled = []
    try h.renderRoot()
    try h.key(.space)
    #expect(box.value == ["r001"], "\(box.value)")
  }
}

@MainActor
@Suite("Campaign F2 pass 2: collection paging and selection in one input batch", .serialized)
struct AdversarialSetDCollectionBatchTests {
  /// Applies `keys` one frame at a time to one fresh table and in one batch
  /// to another, and returns both windows' first visible rows.
  private func pagedFirstRows(
    _ name: String, hidden: Bool, keys: [KeyEvent]
  ) throws -> (sequential: String?, batched: String?, batchedFrame: String) {
    let sequential = try SetDTables.plain(name + "-seq", hidden: hidden)
    defer { sequential.shutdown() }
    try sequential.key(.tab)
    for key in keys { try sequential.key(key) }
    let batched = try SetDTables.plain(name, hidden: hidden)
    defer { batched.shutdown() }
    try batched.key(.tab)
    try batched.keys(keys)
    return (
      sequential.tokens(prefix: "r").first, batched.tokens(prefix: "r").first, batched.frame
    )
  }

  // STUI-1316 (repaired in wave 4), setD121 and setD123–setD125: keys applied
  // before a frame estimate unmeasured rows like the measured window's.
  @Test(
    "setD121: two PageDowns in one batch land where two separate pages land (hidden separators)")
  func setD121BatchedPagesHiddenSeparators() throws {
    let result = try pagedFirstRows("121", hidden: true, keys: [.pageDown, .pageDown])
    try #require(result.sequential != nil && result.sequential != "r000")
    #expect(
      result.batched == result.sequential,
      "batched \(result.batched ?? "-") sequential \(result.sequential ?? "-")")
  }

  @Test("setD122: two PageDowns in one batch land where two separate pages land (drawn separators)")
  func setD122BatchedPagesDrawnSeparators() throws {
    let result = try pagedFirstRows("122", hidden: false, keys: [.pageDown, .pageDown])
    try #require(result.sequential != nil && result.sequential != "r000")
    #expect(
      result.batched == result.sequential,
      "batched \(result.batched ?? "-") sequential \(result.sequential ?? "-")")
  }

  @Test("setD123: three PageDowns in one batch land where three separate pages land")
  func setD123BatchedThreePages() throws {
    let result = try pagedFirstRows("123", hidden: true, keys: [.pageDown, .pageDown, .pageDown])
    try #require(result.sequential != nil && result.sequential != "r000")
    #expect(
      result.batched == result.sequential,
      "batched \(result.batched ?? "-") sequential \(result.sequential ?? "-")")
  }

  @Test("setD124: End then PageUp in one batch lands where the separate keys land")
  func setD124BatchedEndThenPageUp() throws {
    let result = try pagedFirstRows("124", hidden: true, keys: [.end, .pageUp])
    try #require(result.sequential != nil)
    #expect(
      result.batched == result.sequential,
      "batched \(result.batched ?? "-") sequential \(result.sequential ?? "-")")
  }

  @Test("setD125: twelve Downs in one batch reveal the selection as twelve separate Downs do")
  func setD125BatchedDownsRevealSelection() throws {
    let keys = Array(repeating: KeyEvent.arrowDown, count: 12)
    let sequentialBox = SetDSelection<String?>("r000")
    let sequential = try SetDTables.selectable(
      "125-seq", box: sequentialBox, hidden: true, size: .init(width: 30, height: 12))
    defer { sequential.shutdown() }
    try sequential.focusText("r000")
    for key in keys { try sequential.key(key) }
    try #require(sequentialBox.value == "r012")
    let box = SetDSelection<String?>("r000")
    let h = try SetDTables.selectable(
      "125", box: box, hidden: true, size: .init(width: 30, height: 12))
    defer { h.shutdown() }
    try h.focusText("r000")
    try h.keys(keys)
    #expect(box.value == "r012")
    let visible = h.tokens(prefix: "r")
    #expect(visible.contains("r012") && visible.contains("r013"), "\(h.frame)")
    #expect(
      visible.first == sequential.tokens(prefix: "r").first, "\(h.frame)\n--\n\(sequential.frame)"
    )
  }

  @Test("setD126: PageDown then Down in one batch reveals the selection's new row")
  func setD126BatchedPageThenDown() throws {
    let box = SetDSelection<String?>("r000")
    let h = try SetDTables.selectable(
      "126", box: box, hidden: true, size: .init(width: 30, height: 12))
    defer { h.shutdown() }
    try h.focusText("r000")
    try h.keys([.pageDown, .arrowDown])
    #expect(box.value == "r001")
    #expect(h.tokens(prefix: "r").first == "r000", "\(h.frame)")
  }

  @Test("setD127: Space, Down, Down, Space in one batch selects the first and third rows")
  func setD127BatchedMultiSelect() throws {
    let box = SetDSelection<Set<String>>([])
    let rows = setDRows(20)
    let h = try SetDLiveHarness("127", size: .init(width: 30, height: 12)) {
      Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in Text(row.id) }
        .tableHeaders(.hidden).scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    try h.focusText("r000")
    try h.keys([.space, .arrowDown, .arrowDown, .space])
    #expect(box.value == ["r000", "r002"], "\(box.value)")
  }

  @Test("setD128: Down in one batch skips a disabled row")
  func setD128BatchedDownSkipsDisabledRow() throws {
    let box = SetDSelection<String?>("r000")
    let rows = setDRows(20)
    let h = try SetDLiveHarness("128", size: .init(width: 30, height: 12)) {
      Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
        Text(row.id).disabled(row.id == "r001")
      }.tableHeaders(.hidden).scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    try h.focusText("r000")
    try h.keys([.arrowDown])
    #expect(box.value == "r002")
  }

  @Test("setD129: two list PageDowns in one batch land where two separate pages land")
  func setD129BatchedListPages() throws {
    let sequentialBox = SetDSelection<String?>(nil)
    let sequential = try SetDTables.list(
      "129-seq", box: sequentialBox, size: .init(width: 30, height: 12))
    defer { sequential.shutdown() }
    try sequential.key(.tab)
    try sequential.key(.pageDown)
    try sequential.key(.pageDown)
    let box = SetDSelection<String?>(nil)
    let h = try SetDTables.list("129", box: box, size: .init(width: 30, height: 12))
    defer { h.shutdown() }
    try h.key(.tab)
    try h.keys([.pageDown, .pageDown])
    let expected = sequential.tokens(prefix: "r").first
    try #require(expected != nil && expected != "r000", "\(sequential.frame)")
    #expect(h.tokens(prefix: "r").first == expected, "\(h.frame)")
  }

  @Test("setD130: two wheel notches in one batch equal two separate notches")
  func setD130BatchedWheelNotches() throws {
    let sequential = try SetDTables.plain("130-seq", hidden: true)
    defer { sequential.shutdown() }
    let cell = try #require(sequential.cell(of: "r002"))
    try sequential.wheel(at: cell, deltaY: 1)
    try sequential.wheel(at: cell, deltaY: 1)
    let h = try SetDTables.plain("130", hidden: true)
    defer { h.shutdown() }
    for _ in 0..<2 {
      h.dispatch(.mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: Point(cell))))
    }
    try h.render()
    let expected = sequential.tokens(prefix: "r").first
    try #require(expected == "r002", "\(sequential.frame)")
    #expect(h.tokens(prefix: "r").first == expected, "\(h.frame)")
  }
}
