import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage S1 of the scroll-currency program (root plan
/// `docs/plans/2026-07-28-007-collection-scroll-currency-plan.md`): the
/// collection's visible window is derived from a node-owned scroll anchor, and
/// selection *follows* that window instead of *being* it.
///
/// T-01..T-04 are the flipped forms of characterization rows C-01..C-04, which
/// this stage deletes. T-07 keeps the `nil`-anchor fallback pinned, because
/// `ListPayload` is public API and its behaviour must not change.
@MainActor
@Suite(.serialized)
struct CollectionScrollCurrencyTests {
  @Test("web chaining retains headroom until a tall materialized list reaches its measured end")
  func tallMaterializedListChaining() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TallMaterializedChaining"), size: .init(width: 26, height: 10)
    ) {
      List {
        ForEach(0..<20, id: \.self) { Text("«\($0)»a\n«\($0)»b\n«\($0)»c") }
      }.frame(height: 10)
    }
    defer { harness.shutdown() }
    let point = try #require(harness.point(forText: "«0»a"))
    for _ in 0..<40 {
      let route = try #require(
        harness.runLoop.localScrollPositionRegistry.routesWithCurrentOffsets(
          harness.runLoop.latestSemanticSnapshot.scrollRoutes
        ).first)
      let maximum = max(0, route.contentBounds.size.height - route.viewportRect.size.height)
      if route.contentOffset.y >= maximum { break }
      _ = try harness.scrollPointer(at: point, deltaY: 1)
    }
    #expect(
      harness.frame.contains("«19»c"), "web forwarding must reach the last row: \(harness.frame)")
  }

  @Test("section edges retain multi-cell headers and footers separately from their row")
  func sectionEdgesRemainReachableAroundTallRow() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MeasuredSectionEdges"),
      size: CellSize(width: 32, height: 12)
    ) {
      SectionEdgeCurrencyRows()
    }
    defer { harness.shutdown() }

    let listIdentity = try #require(
      harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    _ = try harness.focus(listIdentity)
    _ = try harness.pressKey(KeyPress(.home))
    for line in 0..<3 {
      #expect(harness.frame.contains("header:\(line)"), "\(harness.frame)")
    }
    _ = try harness.pressKey(KeyPress(.end))
    #expect(harness.frame.contains("footer:0"), "\(harness.frame)")
    #expect(harness.frame.contains("footer:1"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.home))
    for line in 0..<3 {
      #expect(harness.frame.contains("header:\(line)"), "\(harness.frame)")
    }

    _ = try harness.clickText("Reveal row")
    for line in 0..<3 {
      try #require(harness.frame.contains("«0»:\(line)"), "\(harness.frame)")
    }
    _ = try harness.clickText("«0»:0")
    try requireMeasuredCurrencyRow(0, lines: 3, collection: .sectionList, in: harness)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=0"), "\(harness.frame)")

    _ = try harness.pressKey(KeyPress(.end))
    #expect(harness.frame.contains("footer:0"), "\(harness.frame)")
    #expect(harness.frame.contains("footer:1"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.home))
    for line in 0..<3 {
      #expect(harness.frame.contains("header:\(line)"), "\(harness.frame)")
    }
  }

  @Test(
    "one proxy command aligns an unrealized tall row and subsequent wheel input wins",
    arguments: MeasuredCurrencyAnchor.allCases
  )
  private func proxyRevealsMeasuredTargetOnce(anchor: MeasuredCurrencyAnchor) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MeasuredCurrencyProxy", anchor.rawValue),
      size: CellSize(width: 32, height: 12)
    ) {
      MeasuredProxyCurrencyRows(anchor: anchor)
    }
    defer { harness.shutdown() }

    #expect(!harness.frame.contains("«50»:0"))
    _ = try harness.clickText("Jump")

    let expectedFirstCell: Int
    switch anchor {
    case .top: expectedFirstCell = 0
    case .center, .reveal: expectedFirstCell = 1
    case .bottom: expectedFirstCell = 2
    }

    func requireTarget(firstCell: Int) throws {
      let viewport = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
      let lines = harness.frame.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      let first = try #require(lines.firstIndex { $0.contains("«50»:0") })
      let last = try #require(lines.firstIndex { $0.contains("«50»:2") })
      #expect(first == viewport.viewportRect.origin.y + firstCell, "\(harness.frame)")
      #expect(last == first + 2, "all three target cells retain their placement")
    }

    try requireTarget(firstCell: expectedFirstCell)
    let point = try #require(harness.point(forText: "«50»:0"))
    _ = try harness.scrollPointer(at: point, deltaY: 1)
    if anchor == .top {
      #expect(!harness.frame.contains("«50»:0"), "one row down leaves the target above")
      #expect(harness.frame.contains("«51»:0"), "\(harness.frame)")
    } else {
      try requireTarget(firstCell: expectedFirstCell - 1)
    }
    _ = try harness.scrollPointer(at: point, deltaY: -1)
    try requireTarget(firstCell: expectedFirstCell)
  }

  @Test("paging three-cell rows preserves overlap and reverses to the first row")
  func pagingUsesMeasuredCells() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MeasuredCurrencyPaging"),
      size: CellSize(width: 32, height: 12)
    ) {
      List(0..<20, id: \.self) { row in
        MeasuredCurrencyRow(row: row, lines: 3)
      }
      .listStyle(CompactCurrencyListStyle())
      .scrollIndicators(.hidden)
      .frame(height: 9)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("«0»:0")
    _ = try harness.pressKey(KeyPress(.pageDown))
    #expect(scrollCurrencyRows(harness.frame).min() == 2, "\(harness.frame)")
    #expect(harness.frame.contains("«2»:2"), "the overlapping row remains complete")
    _ = try harness.pressKey(KeyPress(.pageUp))
    #expect(scrollCurrencyRows(harness.frame).min() == 0, "\(harness.frame)")
    #expect(harness.frame.contains("«0»:2"), "\(harness.frame)")
  }

  @Test("reverse reveal keeps a tall target visible after a taller predecessor")
  func reverseRevealKeepsTheWholeTargetVisible() throws {
    let rowHeights = [4, 3, 3, 3]
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ReverseMeasuredCurrencyReveal"),
      size: CellSize(width: 32, height: 12)
    ) {
      MeasuredCurrencyRows(
        collection: .indexedList, rowHeights: rowHeights, viewportHeight: 5)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("«0»:0")
    for row in 1..<4 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try requireMeasuredCurrencyRow(
        row, lines: rowHeights[row], collection: .indexedList, in: harness)
    }
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=3"), "\(harness.frame)")

    // Row 1 needs three cells; anchoring on its four-cell predecessor hides its end.
    for row in (0..<3).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try requireMeasuredCurrencyRow(
        row, lines: rowHeights[row], collection: .indexedList, in: harness)
    }
  }

  @Test(
    "mixed-height rows stay focused through overflow and section chrome",
    arguments: MeasuredCurrencyCollection.allCases
  )
  private func mixedRowsKeepNavigationAndActivation(collection: MeasuredCurrencyCollection) throws {
    let rowHeights = [1, 3, 2, 1, 3, 2, 1, 3, 2, 1, 3, 2]
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MixedCurrencyNavigation", collection.rawValue),
      size: CellSize(width: 32, height: 12)
    ) {
      MeasuredCurrencyRows(collection: collection, rowHeights: rowHeights)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("«0»:0")
    try requireMeasuredCurrencyRow(0, lines: 1, collection: collection, in: harness)
    for row in 1..<12 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try requireMeasuredCurrencyRow(
        row, lines: rowHeights[row], collection: collection, in: harness)
    }

    _ = try harness.pressKey(KeyPress(.return))
    let activation = collection == .indexedTable ? "checked=[11]" : "activated=11"
    #expect(harness.frame.contains(activation), "\(harness.frame)")
    if collection == .indexedTable {
      _ = try harness.pressKey(KeyPress(.space))
    }

    for row in (0..<11).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try requireMeasuredCurrencyRow(
        row, lines: rowHeights[row], collection: collection, in: harness)
    }
  }

  @Test(
    "an oversized row reveals its start and preserves successor and reverse navigation",
    arguments: [MeasuredCurrencyCollection.indexedList, .indexedTable]
  )
  private func oversizedRowsKeepTheirStartVisible(collection: MeasuredCurrencyCollection) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("OversizedCurrencyNavigation", collection.rawValue),
      size: CellSize(width: 32, height: 12)
    ) {
      MeasuredCurrencyRows(collection: collection, rowHeights: [1, 10, 1])
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("«0»:0")
    try requireMeasuredCurrencyRow(0, lines: 1, collection: collection, in: harness)
    _ = try harness.pressKey(KeyPress(.arrowDown))

    func requireOversizedStart() throws {
      try requireMeasuredCurrencyRow(1, lines: 1, collection: collection, in: harness)
      let lines = harness.frame.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      let firstCell = try #require(lines.firstIndex { $0.contains("«1»:0") })
      let viewport = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
      #expect(
        firstCell == viewport.viewportRect.origin.y,
        "a row taller than the viewport aligns its start with the body:\n\(harness.frame)"
      )
      #expect(!harness.frame.contains("«1»:9"), "the ten-cell row exceeds the viewport")
    }

    try requireOversizedStart()
    _ = try harness.pressKey(KeyPress(.arrowDown))
    try requireMeasuredCurrencyRow(2, lines: 1, collection: collection, in: harness)
    _ = try harness.pressKey(KeyPress(.return))
    let activation = collection == .indexedTable ? "checked=[2]" : "activated=2"
    #expect(harness.frame.contains(activation), "\(harness.frame)")
    if collection == .indexedTable {
      _ = try harness.pressKey(KeyPress(.space))
    }

    _ = try harness.pressKey(KeyPress(.arrowUp))
    try requireOversizedStart()
    _ = try harness.pressKey(KeyPress(.arrowUp))
    try requireMeasuredCurrencyRow(0, lines: 1, collection: collection, in: harness)
  }

  @Test("same-ID row height changes replace placement and navigation measurements")
  func rowHeightChangesPreserveNavigation() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ChangingCurrencyRowHeight"),
      size: CellSize(width: 32, height: 12)
    ) {
      ChangingCurrencyRows()
    }
    defer { harness.shutdown() }

    func requireSuccessor(after height: Int) throws {
      let lines = harness.frame.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      let first = try #require(lines.firstIndex { $0.contains("«0»:0") })
      let successor = try #require(lines.firstIndex { $0.contains("«1»:0") })
      #expect(successor == first + height, "the successor follows the current height")
    }

    try requireSuccessor(after: 1)
    for (phase, height) in [3, 1].enumerated() {
      _ = try harness.clickText("Change height")
      try requireSuccessor(after: height)
      _ = try harness.focusText("«0»:0")
      try requireMeasuredCurrencyRow(0, lines: height, collection: .indexedList, in: harness)

      for row in 1..<12 {
        _ = try harness.pressKey(KeyPress(.arrowDown))
        try requireMeasuredCurrencyRow(row, lines: 1, collection: .indexedList, in: harness)
      }
      _ = try harness.pressKey(KeyPress(.return))
      #expect(harness.frame.contains("activated=11"), "\(harness.frame)")
      #expect(harness.frame.contains("activations=\(phase + 1)"), "\(harness.frame)")
      for row in (0..<11).reversed() {
        _ = try harness.pressKey(KeyPress(.arrowUp))
        try requireMeasuredCurrencyRow(
          row, lines: row == 0 ? height : 1, collection: .indexedList, in: harness)
      }
    }
  }

  @Test("collection width changes remeasure wrapped rows and preserve navigation")
  func collectionWidthChangesPreserveNavigation() throws {
    final class WidthBox {
      var value = 32
    }
    let width = WidthBox()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("WrappingCurrencyRowWidth"),
      size: CellSize(width: 32, height: 12)
    ) {
      WrappingCurrencyRows(width: width.value)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("«0»:0")
    try requireWrappedCurrencyRow(0, height: 1, in: harness)
    try requireCompactCurrencySuccessor(after: 0, in: harness)
    for row in 1...8 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try requireWrappedCurrencyRow(row, height: 1, in: harness)
    }
    let selectedIdentity = harness.runLoop.focusTracker.currentFocusIdentity

    // The rows and text stay fixed; only the collection's available width changes.
    width.value = 10
    _ = try harness.renderAfterExternalMutation()
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == selectedIdentity)
    try requireWrappedCurrencyRow(8, height: 3, in: harness)
    for row in 9..<12 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try requireWrappedCurrencyRow(row, height: 3, in: harness)
    }
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=11"), "\(harness.frame)")
    #expect(harness.frame.contains("activations=1"), "\(harness.frame)")
    for row in (4..<11).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try requireWrappedCurrencyRow(row, height: 3, in: harness)
    }

    let reverseIdentity = harness.runLoop.focusTracker.currentFocusIdentity
    width.value = 32
    _ = try harness.renderAfterExternalMutation()
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == reverseIdentity)
    try requireWrappedCurrencyRow(4, height: 1, in: harness)
    try requireCompactCurrencySuccessor(after: 4, in: harness)
    #expect(harness.frame.contains("activated=11"), "\(harness.frame)")
    #expect(harness.frame.contains("activations=1"), "\(harness.frame)")
    for row in 5..<12 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try requireWrappedCurrencyRow(row, height: 1, in: harness)
    }
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=11"), "\(harness.frame)")
    #expect(harness.frame.contains("activations=2"), "\(harness.frame)")
    for row in (0..<11).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try requireWrappedCurrencyRow(row, height: 1, in: harness)
    }
  }

  @Test(
    "padded rows stay visible and focused down and back, including final-row activation",
    arguments: PaddedCurrencySelection.allCases
  )
  private func paddedRowsKeepNavigationAndActivation(selection: PaddedCurrencySelection) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PaddedCurrencyNavigation", selection.rawValue),
      size: CellSize(width: 32, height: 12)
    ) {
      PaddedCurrencyList(selection: selection)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("«0»")

    func requireFocusedRow(_ row: Int) throws {
      let identity = try harness.focusIdentity(forText: "«\(row)»")
      try #require(
        harness.runLoop.focusTracker.currentFocusIdentity == identity,
        "\(selection.rawValue): row \(row) must be painted inside the focused region:\n\(harness.frame)"
      )
      if selection == .automaticSingle {
        #expect(scrollCurrencySelection(harness.frame) == row, "\(harness.frame)")
      }
    }

    try requireFocusedRow(0)
    for row in 1..<12 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try requireFocusedRow(row)
    }

    _ = try harness.pressKey(KeyPress(.return))
    switch selection {
    case .automaticSingle:
      #expect(harness.frame.contains("activated=11"), "\(harness.frame)")
    case .automaticMultiple, .compactMultiple:
      #expect(harness.frame.contains("checked=[11]"), "\(harness.frame)")
    }

    for row in (0..<11).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try requireFocusedRow(row)
    }
  }

  @Test("reveal keeps the target row's anchor when visibleLineCount < rowSpan")
  func revealDoesNotOvershootAnchorPastTarget() throws {
    let identity = testIdentity("RevealOvershootDirect")
    let graph = ViewGraph()
    graph.beginFrame()
    let ownerNode = graph.beginEvaluation(identity: identity, invalidator: nil)

    let registry = LocalScrollPositionRegistry()
    let route = ScrollRoute(
      identity: identity,
      viewportRect: .init(origin: .zero, size: .init(width: 20, height: 6)),
      contentBounds: .init(origin: .zero, size: .init(width: 20, height: 19))
    )
    registry.updateGeometry(scrollRoutes: [route], scrollTargets: [])

    let currency = CollectionScrollCurrency(
      identity: identity,
      geometry: CollectionScrollGeometry(rowCount: 10, rowSpan: 2),
      ownerNode: ownerNode,
      registry: registry,
      windowMetrics: { _ in (offset: 0, visibleLineCount: 1) }
    )

    #expect(currency.effectiveAnchorRow == 0, "starts at the selection-centred fallback")

    // reveal(row: 5, margin: 1): the target occupies display lines 10–11; a
    // 1-line viewport must anchor on the target row (5) or earlier to keep it
    // visible. Overshooting to row 6 (lines 12–13) hides row 5 above the window.
    _ = currency.reveal(row: 5, margin: 1)

    #expect(
      currency.effectiveAnchorRow <= 5,
      "reveal must not anchor past the target row: observed \(currency.effectiveAnchorRow)"
    )
  }
  @Test("T-01: a selection move inside the window does not scroll; outside reveals minimally")
  func selectionFollowsTheWindow() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollCurrencySelectionFollow"),
      size: .init(width: 30, height: 14)
    ) {
      SelectableCurrencyList()
    }
    defer { harness.shutdown() }

    // Arrow keys are selection keys, so they need focus inside the list. A
    // click on a visible row is how a user gets there.
    _ = try harness.clickText("«0»")
    var previousRows = scrollCurrencyRows(harness.frame)
    #expect(previousRows.contains(0))
    #expect(previousRows.count > 3)

    // Stated as an invariant over the *observed* window rather than a step
    // count or a fixed height: the drawn row count varies by one as the
    // overflow indicators come and go. The contract is that the window follows
    // the selection minimally — one row at a time, only when it has to, and
    // never leaving the selection without a row of context to step onto.
    func checkStep(_ label: String) throws {
      let rows = scrollCurrencyRows(harness.frame)
      let selection = try #require(scrollCurrencySelection(harness.frame))
      let top = try #require(rows.min())
      let bottom = try #require(rows.max())
      let previousTop = try #require(previousRows.min())

      #expect(rows.contains(selection), "\(label): the selected row stays visible")
      if selection > 0 {
        #expect(top <= selection - 1, "\(label): a row of context above the selection")
      }
      if selection < 99 {
        #expect(bottom >= selection + 1, "\(label): a row of context below the selection")
      }
      #expect(
        abs(top - previousTop) <= 1,
        "\(label): one selection step scrolls at most one row:\n\(harness.frame)"
      )
      if previousRows.contains(selection - 1) && previousRows.contains(selection + 1) {
        #expect(
          top == previousTop,
          "\(label): a step well inside the window must not scroll:\n\(harness.frame)"
        )
      }
      previousRows = rows
    }

    for step in 0..<24 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try checkStep("down \(step)")
    }
    #expect(try #require(previousRows.min()) > 0, "the window followed the selection down")

    // And back up: the same contract against the top edge. This direction is
    // the one that regressed while `reveal` had no margin — focus walked out
    // of the collection entirely once the selection reached the window's top
    // row, because the row above it was never drawn.
    for step in 0..<40 {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try checkStep("up \(step)")
    }
    #expect(previousRows.min() == 0, "stepping back up returns the window to the top")
    #expect(scrollCurrencySelection(harness.frame) == 0, "and the selection to the first row")
  }

  @Test("compact checklist arrow navigation reaches every row and preserves focused activation")
  func compactChecklistKeepsRevealedRowsFocused() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CompactChecklistFocus"),
      size: CellSize(width: 32, height: 12)
    ) {
      CompactCurrencyChecklist()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("«0»")

    func expectFocusedRow(_ row: Int) throws {
      let identity = try harness.focusIdentity(forText: "«\(row)»")
      #expect(
        harness.runLoop.focusTracker.currentFocusIdentity == identity,
        "row \(row) must remain visible and focused:\n\(harness.frame)"
      )
    }

    // Eight lines leave six usable rows once both overflow indicators appear.
    // Generic focus clamping used the raw height and moved a valid anchor back,
    // hiding the requested row and falling back to the first visible row.
    for row in 1..<12 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try expectFocusedRow(row)
    }

    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("checked=[11]"))
    _ = try harness.pressKey(KeyPress(.space))
    #expect(harness.frame.contains("checked=[]"))

    for row in (0..<11).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try expectFocusedRow(row)
    }
  }

  @Test("T-02: the wheel moves the window and leaves the selection alone")
  func wheelScrollsWithoutChangingSelection() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollCurrencyWheel"),
      size: .init(width: 30, height: 14)
    ) {
      SelectableCurrencyList()
    }
    defer { harness.shutdown() }

    let listPoint = try #require(harness.point(forText: "«0»"))
    let firstTop = try #require(scrollCurrencyRows(harness.frame).min())

    for _ in 0..<5 {
      _ = try harness.scrollPointer(at: listPoint, deltaY: 1)
    }
    #expect(
      harness.frame.contains("sel=0"),
      "the wheel must not step the selection (flipped from C-02):\n\(harness.frame)"
    )
    let scrolledTop = try #require(scrollCurrencyRows(harness.frame).min())
    #expect(scrolledTop == firstTop + 5)

    // Clamped at the top: wheeling up past row 0 stops there.
    for _ in 0..<20 {
      _ = try harness.scrollPointer(at: listPoint, deltaY: -1)
    }
    #expect(scrollCurrencyRows(harness.frame).min() == 0)
    #expect(harness.frame.contains("sel=0"))

    // Clamped at the bottom: the last row is reachable and the window stops.
    for _ in 0..<200 {
      _ = try harness.scrollPointer(at: listPoint, deltaY: 1)
    }
    #expect(scrollCurrencyRows(harness.frame).contains(99))
    let bottomTop = try #require(scrollCurrencyRows(harness.frame).min())
    _ = try harness.scrollPointer(at: listPoint, deltaY: 1)
    #expect(scrollCurrencyRows(harness.frame).min() == bottomTop, "clamped at the bottom edge")
  }

  @Test("T-03: a non-selectable 10k List scrolls by wheel, PageDown/End, and back with Home")
  func nonSelectableListScrolls() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollCurrencyNonSelectable"),
      size: .init(width: 30, height: 12)
    ) {
      NonSelectableCurrencyList()
    }
    defer { harness.shutdown() }

    #expect(scrollCurrencyRows(harness.frame).contains(0))
    let listPoint = try #require(harness.point(forText: "«0»"))

    _ = try harness.scrollPointer(at: listPoint, deltaY: 1)
    #expect(
      !scrollCurrencyRows(harness.frame).contains(0),
      "flipped from C-03: a non-selectable indexed List now scrolls"
    )

    _ = try harness.pressKey(KeyPress(.end))
    #expect(
      scrollCurrencyRows(harness.frame).contains(9_999),
      "End must reach the last row of a 10k dataset:\n\(harness.frame)"
    )

    _ = try harness.pressKey(KeyPress(.home))
    #expect(scrollCurrencyRows(harness.frame).contains(0))

    let afterHome = try #require(scrollCurrencyRows(harness.frame).max())
    _ = try harness.pressKey(KeyPress(.pageDown))
    let afterPage = try #require(scrollCurrencyRows(harness.frame).min())
    #expect(afterPage > 0, "PageDown advances a screenful")
    #expect(afterPage <= afterHome + 1, "PageDown advances at most one screenful")
  }

  @Test("T-04: scrollTo(id) is a no-op in-window and reveals an out-of-window row")
  func scrollToReachesCollectionRows() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollCurrencyScrollTo"),
      size: .init(width: 30, height: 12)
    ) {
      ScrollToCurrencyList()
    }
    defer { harness.shutdown() }

    #expect(scrollCurrencyRows(harness.frame).contains(0))

    // In-window: the row is already visible, so the command reports no move.
    _ = try harness.clickText("Near")
    #expect(harness.frame.contains("result=false"))
    #expect(scrollCurrencyRows(harness.frame).contains(0))

    // Out-of-window: the row has no placed frame at all, so this exercises the
    // registration's own target resolver.
    _ = try harness.clickText("Far")
    #expect(
      harness.frame.contains("result=true"),
      "flipped from C-04: scrollTo now reaches a collection row:\n\(harness.frame)"
    )
    #expect(
      scrollCurrencyRows(harness.frame).contains(500),
      "row 500 must be revealed:\n\(harness.frame)"
    )
  }

  @Test("T-05: the anchor survives an unrelated invalidation")
  func anchorSurvivesUnrelatedInvalidation() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollCurrencyPersistence"),
      size: .init(width: 34, height: 14)
    ) {
      SelectableCurrencyList()
    }
    defer { harness.shutdown() }

    let listPoint = try #require(harness.point(forText: "«0»"))
    for _ in 0..<6 {
      _ = try harness.scrollPointer(at: listPoint, deltaY: 1)
    }
    let scrolledTop = try #require(scrollCurrencyRows(harness.frame).min())
    #expect(scrolledTop == 6)

    _ = try harness.clickText("Bump")
    #expect(harness.frame.contains("bump=1"))
    #expect(
      scrollCurrencyRows(harness.frame).min() == scrolledTop,
      "an unrelated state change must not reset the scroll position:\n\(harness.frame)"
    )
  }

  @Test("T-06: a Table scrolls by wheel and reaches its last row with End")
  func tableMirrorsListScrolling() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollCurrencyTable"),
      size: .init(width: 40, height: 14)
    ) {
      NonSelectableCurrencyTable()
    }
    defer { harness.shutdown() }

    #expect(scrollCurrencyRows(harness.frame).contains(0))
    let point = try #require(harness.point(forText: "«0»"))

    _ = try harness.scrollPointer(at: point, deltaY: 1)
    #expect(!scrollCurrencyRows(harness.frame).contains(0), "the table wheel scrolls the window")

    _ = try harness.pressKey(KeyPress(.end))
    #expect(
      scrollCurrencyRows(harness.frame).contains(499),
      "End must reach the table's last row:\n\(harness.frame)"
    )
  }

  @Test("T-07: a payload with no stored anchor keeps the selection-centred window")
  func payloadOnlyCallersKeepTheOldWindow() throws {
    // The `nil` fallback is the compatibility contract for `ListPayload`, which
    // is public API: a render with no interaction must still centre on the
    // selection exactly as it did before the anchor existed.
    let atTop = scrollCurrencyRows(renderingSelectableList(selection: 0))
    let atMiddle = scrollCurrencyRows(renderingSelectableList(selection: 50))

    #expect(atTop.contains(0))
    #expect(!atTop.contains(50))
    #expect(atMiddle.contains(50))
    #expect(!atMiddle.contains(0))
    let middleTop = try #require(atMiddle.min())
    #expect(middleTop > 40, "the fallback still centres the window on the selection")
  }

  @Test("T-08: the public ListPayload initializer is unchanged and leaves the anchor nil")
  func publicPayloadInitIsUnchanged() {
    // Compiles against the pre-S1 argument list; the new currency is `package`
    // and defaulted, so the public API baseline is untouched.
    let payload = ListPayload(
      items: [.init(kind: .row, text: "one")],
      selectedRowIndex: 0,
      style: .plain
    )
    #expect(payload.scrollAnchor == nil)
    #expect(!payload.isViewportBacked)
  }

  @Test("T-09: a non-selectable viewport-backed list is container-focusable; selectable is not")
  func containerFocusabilityFollowsSelectability() {
    let nonSelectable = DefaultRenderer().render(
      List(0..<50, id: \.self) { row in
        Text("«\(row)»")
      },
      context: .init(identity: testIdentity("FocusableNonSelectable")),
      proposal: .init(width: .finite(20), height: .finite(10))
    )
    let selectable = DefaultRenderer().render(
      List(0..<50, id: \.self, selection: .constant(0 as Int?)) { row in
        Text("«\(row)»")
      },
      context: .init(identity: testIdentity("FocusableSelectable")),
      proposal: .init(width: .finite(20), height: .finite(10))
    )

    #expect(
      nonSelectable.semanticSnapshot.focusRegions.contains {
        $0.identity == testIdentity("FocusableNonSelectable")
      },
      "the container must be focusable or its scroll keys are unreachable"
    )
    #expect(
      !selectable.semanticSnapshot.focusRegions.contains {
        $0.identity == testIdentity("FocusableSelectable")
      },
      "a selectable list keeps focus at the row layer — no double focus stop"
    )
  }

  @Test("T-10: an anchor write re-runs resolve and measure with the new window")
  func anchorWriteReRunsResolveAndMeasure() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollCurrencyInvalidation"),
      size: .init(width: 30, height: 12)
    ) {
      NonSelectableCurrencyList()
    }
    defer { harness.shutdown() }

    let listPoint = try #require(harness.point(forText: "«0»"))
    let before = scrollCurrencyRows(harness.frame)

    // The realization counter is the proof that MEASURE re-ran: a re-resolve
    // that reused the previous window would realize nothing new.
    IndexedChildRealizationProbe.reset()
    for _ in 0..<12 {
      _ = try harness.scrollPointer(at: listPoint, deltaY: 1)
    }
    let after = scrollCurrencyRows(harness.frame)

    #expect(IndexedChildRealizationProbe.realizedChildCount > 0, "rows were realized for the move")
    #expect(before.intersection(after).isEmpty, "the window advanced past the original screenful")
  }

  @Test(
    "T-11: two-line rows reach the bottom by scrollTo(edge:), End, and the wheel",
    arguments: [true, false], [TallRowBottomMove.scrollToEdge, .endKey, .wheel])
  func tallRowsReachTheBottom(isTable: Bool, move: TallRowBottomMove) throws {
    // The window and the scroll clamp counted one line per row, so rows that
    // render two lines ran out of viewport before the dataset ran out of rows:
    // the last rows and the table's closing border were unreachable.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TallRowBottom", isTable ? "Table" : "List", "\(move)"),
      size: .init(width: 30, height: 16)
    ) {
      TallRowCurrencyCollection(isTable: isTable, showsBottomButton: move == .scrollToEdge)
    }
    defer { harness.shutdown() }

    func publishedRoute() throws -> ScrollRoute {
      try #require(
        harness.runLoop.localScrollPositionRegistry.routesWithCurrentOffsets(
          harness.runLoop.latestSemanticSnapshot.scrollRoutes
        ).first)
    }
    #expect(try publishedRoute().contentOffset.y == 0, "the top must chain wheel-up")

    switch move {
    case .scrollToEdge:
      _ = try harness.clickText("Bottom")
    case .endKey:
      _ = try harness.pressKey(KeyPress(.end))
    case .wheel:
      let point = try #require(harness.point(forText: "«0»a"))
      for _ in 0..<60 {
        _ = try harness.scrollPointer(at: point, deltaY: 1)
      }
    }

    #expect(harness.frame.contains("«48»a"), "the second-to-last row is visible:\n\(harness.frame)")
    #expect(harness.frame.contains("«49»b"), "the last row is visible in full:\n\(harness.frame)")
    #expect(!harness.frame.contains("«0»a"), "the first row scrolled away:\n\(harness.frame)")
    if isTable {
      #expect(harness.frame.contains("╰"), "the closing border is visible:\n\(harness.frame)")
    }

    let bottomRoute = try publishedRoute()
    #expect(
      bottomRoute.contentOffset.y
        == max(
          0,
          bottomRoute.contentBounds.size.height - bottomRoute.viewportRect.size.height),
      "the browser must chain wheel-down at the last row")

    // Reversing moves one row at once: no spinning in place at the bottom, and
    // no jump past the rows the layout actually drew there.
    if move == .wheel {
      let point = try #require(harness.point(forText: "«49»a"))
      _ = try harness.scrollPointer(at: point, deltaY: -1)
      let reversedRoute = try publishedRoute()
      #expect(reversedRoute.contentOffset.y > 0)
      #expect(
        reversedRoute.contentOffset.y
          < max(
            0,
            reversedRoute.contentBounds.size.height - reversedRoute.viewportRect.size.height))
      #expect(!harness.frame.contains("«49»b"), "one notch up moves the window:\n\(harness.frame)")
      #expect(harness.frame.contains("«48»b"), "by one row:\n\(harness.frame)")
    }
  }
}

enum TallRowBottomMove: CustomStringConvertible, Sendable {
  case scrollToEdge
  case endKey
  case wheel

  var description: String {
    switch self {
    case .scrollToEdge: "scrollToEdge"
    case .endKey: "endKey"
    case .wheel: "wheel"
    }
  }
}

// MARK: - Fixtures

@MainActor
private struct SectionEdgeCurrencyRows: View {
  @State private var selected: Int? = nil
  @State private var activated: Int? = nil

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("Reveal row") { _ = proxy.scrollTo("edge-row") }
        List(selection: $selected, onActivate: { activated = $0 }) {
          Section {
            MeasuredCurrencyRow(row: 0, lines: 3).tag(0).id("edge-row")
          } header: {
            VStack(alignment: .leading, spacing: 0) {
              Text("header:0")
              Text("header:1")
              Text("header:2")
            }
          } footer: {
            VStack(alignment: .leading, spacing: 0) {
              Text("footer:0")
              Text("footer:1")
            }
          }
        }
        .listStyle(CompactCurrencyListStyle())
        .scrollIndicators(.hidden)
        .focusable()
        .frame(height: 4)
        Text("sel=\(selected ?? -1)")
        Text("activated=\(activated ?? -1)")
      }
    }
  }
}

private enum MeasuredCurrencyAnchor: String, CaseIterable, Sendable {
  case top
  case center
  case bottom
  case reveal

  var point: UnitPoint? {
    switch self {
    case .top: .top
    case .center: .center
    case .bottom: .bottom
    case .reveal: nil
    }
  }
}

@MainActor
private struct MeasuredProxyCurrencyRows: View {
  let anchor: MeasuredCurrencyAnchor

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("Jump") { _ = proxy.scrollTo(50, anchor: anchor.point) }
        List(0..<100, id: \.self) { row in
          MeasuredCurrencyRow(row: row, lines: row == 50 ? 3 : 1)
        }
        .listStyle(CompactCurrencyListStyle())
        .scrollIndicators(.hidden)
        .frame(height: 5)
      }
    }
  }
}

private enum MeasuredCurrencyCollection: String, CaseIterable, Sendable {
  case indexedList
  case indexedTable
  case sectionList
}

@MainActor
private struct MeasuredCurrencyRows: View {
  let collection: MeasuredCurrencyCollection
  let rowHeights: [Int]
  let viewportHeight: Int
  @State private var selected: Int? = 0
  @State private var checked: Set<Int> = []
  @State private var activated: Int? = nil

  init(
    collection: MeasuredCurrencyCollection, rowHeights: [Int], viewportHeight: Int = 8
  ) {
    self.collection = collection
    self.rowHeights = rowHeights
    self.viewportHeight = viewportHeight
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      switch collection {
      case .indexedList:
        List(0..<rowHeights.count, id: \.self, selection: $selected, onActivate: { activated = $0 })
        {
          row in
          MeasuredCurrencyRow(row: row, lines: rowHeights[row])
        }
        .listStyle(CompactCurrencyListStyle())
        .scrollIndicators(.hidden)
        .frame(height: viewportHeight)
      case .indexedTable:
        Table(
          0..<rowHeights.count, id: \.self, selection: $checked,
          columns: [TableColumn("Value", width: 20)]
        ) { row in
          MeasuredCurrencyRow(row: row, lines: rowHeights[row])
        }
        .tableHeaders(.hidden)
        .scrollIndicators(.hidden)
        .frame(height: viewportHeight)
      case .sectionList:
        List(selection: $selected, onActivate: { activated = $0 }) {
          Section {
            ForEach(0..<6, id: \.self) { row in
              MeasuredCurrencyRow(row: row, lines: rowHeights[row]).tag(row)
            }
          } header: {
            Text("First header")
          } footer: {
            Text("First footer")
          }
          Section {
            ForEach(6..<12, id: \.self) { row in
              MeasuredCurrencyRow(row: row, lines: rowHeights[row]).tag(row)
            }
          } header: {
            Text("Second header")
          } footer: {
            Text("Second footer")
          }
        }
        .listStyle(CompactCurrencyListStyle())
        .frame(height: viewportHeight)
      }
      Text("sel=\(selected ?? -1)")
      Text("activated=\(activated ?? -1)")
      Text("checked=\(checked.sorted())")
    }
  }
}

@MainActor
private struct ChangingCurrencyRows: View {
  @State private var isTall = false
  @State private var selected: Int? = 0
  @State private var activated: Int? = nil
  @State private var activations = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Change height") { isTall.toggle() }
      List(
        0..<12, id: \.self, selection: $selected,
        onActivate: { row in
          activated = row
          activations += 1
        }
      ) { row in
        MeasuredCurrencyRow(row: row, lines: row == 0 && isTall ? 3 : 1)
      }
      .listStyle(CompactCurrencyListStyle())
      .scrollIndicators(.hidden)
      .frame(height: 8)
      Text("sel=\(selected ?? -1)")
      Text("activated=\(activated ?? -1)")
      Text("activations=\(activations)")
    }
  }
}

@MainActor
private struct WrappingCurrencyRows: View {
  let width: Int
  @State private var selected: Int? = 0
  @State private var activated: Int? = nil
  @State private var activations = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(
        0..<12, id: \.self, selection: $selected,
        onActivate: { row in
          activated = row
          activations += 1
        }
      ) { row in
        Text("«\(row)»:0 «\(row)»:1 «\(row)»:2").lineLimit(3)
      }
      .listStyle(CompactCurrencyListStyle())
      .scrollIndicators(.hidden)
      .frame(width: width, height: 8)
      Text("sel=\(selected ?? -1)")
      Text("activated=\(activated ?? -1)")
      Text("activations=\(activations)")
    }
  }
}

@MainActor
private struct MeasuredCurrencyRow: View {
  let row: Int
  let lines: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<lines, id: \.self) { line in
        Text("«\(row)»:\(line)")
      }
    }
  }
}

private enum PaddedCurrencySelection: String, CaseIterable, Sendable {
  case automaticSingle
  case automaticMultiple
  case compactMultiple
}

@MainActor
private struct PaddedCurrencyList: View {
  let selection: PaddedCurrencySelection
  @State private var selected: Int? = 0
  @State private var checked: Set<Int> = []
  @State private var activated: Int? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      switch selection {
      case .automaticSingle:
        List(0..<12, id: \.self, selection: $selected, onActivate: { activated = $0 }) { row in
          Text("«\(row)»").padding(.vertical, 1)
        }
        .focusable()
        .frame(height: 8)
      case .automaticMultiple:
        multipleList
      case .compactMultiple:
        multipleList.listStyle(CompactCurrencyListStyle())
      }
      Text("sel=\(selected ?? -1)")
      Text("activated=\(activated ?? -1)")
      Text("checked=\(checked.sorted())")
    }
  }

  private var multipleList: some View {
    List(0..<12, id: \.self, selection: $checked) { row in
      Text("«\(row)»").padding(.vertical, 1)
    }
    .focusable(false)
    .frame(height: 8)
  }
}

@MainActor
private struct CompactCurrencyChecklist: View {
  @State private var selection: Set<Int> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(0..<12, id: \.self, selection: $selection) { row in
        Text("«\(row)»")
      }
      .listStyle(CompactCurrencyListStyle())
      .focusable(false)
      .frame(height: 8)
      Text("checked=\(selection.sorted())")
    }
  }
}

private struct CompactCurrencyListStyle: ListStyle, Equatable {
  @MainActor
  func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    ListStylePresentation(
      contentInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
      showsRowSeparators: false,
      showsSectionSeparators: false
    )
  }
}

@MainActor
private struct TallRowCurrencyCollection: View {
  let isTable: Bool
  let showsBottomButton: Bool

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        if showsBottomButton {
          Button("Bottom") { _ = proxy.scrollTo(edge: .bottom) }
        }
        if isTable {
          Table(0..<50, id: \.self, columns: [.init("Value", width: 20)]) { row in
            TwoLineCurrencyRow(row: row)
          }
          .tableHeaders(.hidden)
        } else {
          List(0..<50, id: \.self) { row in
            TwoLineCurrencyRow(row: row)
          }
        }
      }
    }
  }
}

@MainActor
private struct TwoLineCurrencyRow: View {
  let row: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("«\(row)»a")
      Text("«\(row)»b")
    }
  }
}

@MainActor
private struct SelectableCurrencyList: View {
  @State private var selection: Int? = 0
  @State private var bump = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("sel=\(selection ?? -1) bump=\(bump)")
      Button("Bump") { bump += 1 }
      List(0..<100, id: \.self, selection: $selection) { row in
        Text("«\(row)»")
      }
      .frame(height: 10)
    }
  }
}

@MainActor
private struct NonSelectableCurrencyList: View {
  var body: some View {
    List(0..<10_000, id: \.self) { row in
      Text("«\(row)»")
    }
    .frame(height: 10)
  }
}

@MainActor
private struct NonSelectableCurrencyTable: View {
  var body: some View {
    Table(0..<500, id: \.self, columns: [.init("Value", width: 10)]) { row in
      Text("«\(row)»")
    }
    .frame(height: 12)
  }
}

@MainActor
private struct ScrollToCurrencyList: View {
  @State private var result = "none"

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Text("result=\(result)")
        Button("Near") { result = proxy.scrollTo(0) ? "true" : "false" }
        Button("Far") { result = proxy.scrollTo(500) ? "true" : "false" }
        List(0..<1_000, id: \.self) { row in
          Text("«\(row)»")
        }
        .frame(height: 8)
      }
    }
  }
}

// MARK: - Support

@MainActor
private func requireWrappedCurrencyRow<Content: View>(
  _ row: Int,
  height: Int,
  in harness: StressRuntimeHarness<Content>
) throws {
  try requireMeasuredCurrencyRow(row, lines: height, collection: .indexedList, in: harness)
  let lines = harness.frame.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
  let firstIndex = lines.firstIndex { $0.contains("«\(row)»:0") }
  let first = try #require(firstIndex)
  for token in 1..<3 {
    let tokenIndex = lines.firstIndex { $0.contains("«\(row)»:\(token)") }
    let actualLine = try #require(tokenIndex)
    let expectedLine = height == 1 ? first : first + token
    #expect(actualLine == expectedLine, "\(harness.frame)")
  }
}

@MainActor
private func requireCompactCurrencySuccessor<Content: View>(
  after row: Int,
  in harness: StressRuntimeHarness<Content>
) throws {
  let lines = harness.frame.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
  let firstIndex = lines.firstIndex { $0.contains("«\(row)»:0") }
  let successorIndex = lines.firstIndex { $0.contains("«\(row + 1)»:0") }
  let first = try #require(firstIndex)
  let successor = try #require(successorIndex)
  #expect(successor == first + 1, "one-cell rows place their successor on the next line")
}

@MainActor
private func requireMeasuredCurrencyRow<Content: View>(
  _ row: Int,
  lines: Int,
  collection: MeasuredCurrencyCollection,
  in harness: StressRuntimeHarness<Content>
) throws {
  let firstLabel = "«\(row)»:0"
  let identity = try harness.focusIdentity(forText: firstLabel)
  try #require(
    harness.runLoop.focusTracker.currentFocusIdentity == identity,
    "row \(row) remains visible inside the focused region:\n\(harness.frame)"
  )
  #expect(harness.frame.contains("«\(row)»:\(lines - 1)"), "\(harness.frame)")

  switch collection {
  case .indexedList, .sectionList:
    #expect(scrollCurrencySelection(harness.frame) == row, "\(harness.frame)")
  case .indexedTable:
    // Table keeps container focus; activation independently identifies its active row.
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("checked=[\(row)]"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.space))
    #expect(harness.frame.contains("checked=[]"), "\(harness.frame)")
  }
}

@MainActor
private func renderingSelectableList(
  selection: Int
) -> RenderSnapshot {
  DefaultRenderer().render(
    List(0..<100, id: \.self, selection: .constant(selection as Int?)) { row in
      Text("«\(row)»")
    },
    context: .init(
      identity: testIdentity("CurrencyFallbackList", "\(selection)"),
      applyEnvironmentValues: false
    ),
    proposal: .init(width: .finite(20), height: .finite(10))
  )
}

@MainActor
private func scrollCurrencyRows(
  _ artifacts: RenderSnapshot
) -> Set<Int> {
  scrollCurrencyRows(artifacts.rasterSurface.lines.joined(separator: "\n"))
}

/// The selected row index a fixture reports as `sel=N`.
private func scrollCurrencySelection(
  _ surface: String
) -> Int? {
  let marker = Array("sel=")
  let characters = Array(surface)
  guard characters.count > marker.count else {
    return nil
  }
  for start in 0...(characters.count - marker.count)
  where Array(characters[start..<(start + marker.count)]) == marker {
    let digits = characters[(start + marker.count)...].prefix { $0.isNumber }
    return Int(String(digits))
  }
  return nil
}

/// The `«n»`-delimited row indices visible in a rendered surface. The
/// delimiters keep `«5»` from matching inside `«50»`.
private func scrollCurrencyRows(
  _ surface: String
) -> Set<Int> {
  var rows: Set<Int> = []
  var digits = ""
  var isInside = false
  for character in surface {
    if character == "«" {
      isInside = true
      digits = ""
    } else if character == "»" {
      if isInside, let value = Int(digits) {
        rows.insert(value)
      }
      isInside = false
    } else if isInside {
      if character.isNumber {
        digits.append(character)
      } else {
        isInside = false
      }
    }
  }
  return rows
}
