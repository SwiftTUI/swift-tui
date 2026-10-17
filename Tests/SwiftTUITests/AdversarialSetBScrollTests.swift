import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Adversarial set B: collection and ScrollView scrolling geometry at combined
// boundaries. The Sept–Oct 2026 reports behind these probes: footer-only end
// windows that wheel/momentum could not reach or that PageUp skipped past
// (STUI-921, STUI-953, STUI-954), anchors collapsing after multi-line rows,
// reveal overshoot when a row is taller than the viewport, content-extent
// snap-back across heterogeneous rows, zero/diagonal wheel notches against an
// active fling (STUI-594, STUI-626, STUI-900), and reveal after resize (STUI-916).
@MainActor
@Suite("Adversarial set B: scroll geometry", .serialized)
struct AdversarialSetBScrollTests {
  @Test func setB001FooterOnlyEndThenPageUpVisitsTallFinalRow() throws {
    // Three-line final row, two-line footer, and a viewport shorter than the
    // row: End shows the footer alone; PageUp must land on the final row
    // before the row preceding it, in both directions.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScroll", "FooterOnlyTallFinalRow"),
      size: .init(width: 32, height: 8)
    ) {
      List {
        Section {
          ForEach(0..<4, id: \.self) { row in SetBRow(row: row, lines: row == 3 ? 3 : 1) }
        } header: {
          EmptyView()
        } footer: {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<2, id: \.self) { line in Text("footer:\(line)") }
          }
        }
      }
      .listStyle(SetBListStyle()).scrollIndicators(.hidden).focusable().frame(height: 2)
    }
    defer { harness.shutdown() }
    let registry = harness.runLoop.localScrollPositionRegistry
    let identity = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    try harness.focusText("«0»:0")

    try harness.pressKey(KeyPress(.end))
    #expect(harness.frame.contains("footer:0"), "\(harness.frame)")
    #expect(harness.frame.contains("footer:1"), "\(harness.frame)")
    #expect(!harness.frame.contains("«3»"), "End is a footer-only window:\n\(harness.frame)")
    #expect(registry.collectionScrollLayout(scopeIdentity: identity)?.anchor == .end)

    try harness.pressKey(KeyPress(.pageUp))
    #expect(harness.frame.contains("«3»:0"), "PageUp lands on the final row:\n\(harness.frame)")
    #expect(!harness.frame.contains("footer"), "\(harness.frame)")

    try harness.pressKey(KeyPress(.pageUp))
    #expect(harness.frame.contains("«2»:0"), "the second PageUp reaches row 2:\n\(harness.frame)")

    try harness.pressKey(KeyPress(.end))
    #expect(harness.frame.contains("footer:1"), "\(harness.frame)")
    #expect(registry.collectionScrollLayout(scopeIdentity: identity)?.anchor == .end)
  }

  @Test func setB002PageKeysOnOneLineViewportVisitEveryTallRow() throws {
    // A one-line viewport over three-line rows: every PageDown shows the next
    // row's first line; from the end, PageUp must still show a line of the
    // final row before it jumps to the row above it.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScroll", "OneLinePaging"),
      size: .init(width: 32, height: 8)
    ) {
      List(0..<12, id: \.self) { row in SetBRow(row: row, lines: 3) }
        .listStyle(SetBListStyle()).scrollIndicators(.hidden).focusable().frame(height: 1)
    }
    defer { harness.shutdown() }
    try harness.focusText("«0»:0")

    for row in 1..<12 {
      try harness.pressKey(KeyPress(.pageDown))
      try #require(harness.frame.contains("«\(row)»:0"), "row=\(row)\n\(harness.frame)")
      try #require(!harness.frame.contains("«\(row - 1)»"), "row=\(row)\n\(harness.frame)")
    }
    try harness.pressKey(KeyPress(.pageDown))
    withKnownIssue("paging moves by whole rows and never reveals a tall last row's tail") {
      #expect(harness.frame.contains("«11»:2"), "the end shows the final line:\n\(harness.frame)")

      try harness.pressKey(KeyPress(.pageUp))
      #expect(
        harness.frame.contains("«11»:"),
        "one PageUp from the end stays within the final row:\n\(harness.frame)")
      try harness.pressKey(KeyPress(.pageUp))
      #expect(harness.frame.contains("«10»:0"), "\(harness.frame)")
    }
  }

  @Test func setB003WheelReversalFromEndInsideTallLastRowRoundTrips() throws {
    // Two-line rows on a three-line viewport: the end window starts inside a
    // row. One notch up moves by a whole row; one notch down returns to the
    // identical End frame instead of stopping short of it.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScroll", "EndInsideTallRowWheel"),
      size: .init(width: 32, height: 8)
    ) {
      List(0..<20, id: \.self) { row in SetBRow(row: row, lines: 2) }
        .listStyle(SetBListStyle()).scrollIndicators(.hidden).focusable().frame(height: 3)
    }
    defer { harness.shutdown() }
    let registry = harness.runLoop.localScrollPositionRegistry
    let identity = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    try harness.focusText("«0»:0")

    try harness.pressKey(KeyPress(.end))
    try #require(harness.frame.contains("«19»:1"), "\(harness.frame)")
    let endFrame = harness.frame
    let point = try #require(harness.point(forText: "«19»:1"))

    try harness.scrollPointer(at: point, deltaY: -1)
    #expect(
      harness.frame.contains("«18»:0"), "one notch up shows the whole row 18:\n\(harness.frame)")
    #expect(!harness.frame.contains("«19»:1"), "\(harness.frame)")

    try harness.scrollPointer(at: point, deltaY: 1)
    #expect(
      harness.frame == endFrame, "one notch down returns to the End window:\n\(harness.frame)")
    withKnownIssue("the End window is republished as .row(19) after a wheel round trip") {
      #expect(registry.collectionScrollLayout(scopeIdentity: identity)?.anchor == .end)
    }
  }

  @Test func setB004BottomAnchorOnFirstRowPinsToStart() throws {
    // scrollTo(firstRow, anchor: .bottom) cannot scroll above the content:
    // the window clamps to the start, reports a change once, and is then a
    // no-op.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScroll", "FirstRowBottomAnchor"),
      size: .init(width: 32, height: 10)
    ) {
      SetBFirstRowBottomList()
    }
    defer { harness.shutdown() }
    let registry = harness.runLoop.localScrollPositionRegistry
    let identity = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    try harness.focusText("«0»")
    try harness.pressKey(KeyPress(.end))
    try #require(harness.frame.contains("«29»"), "\(harness.frame)")

    try harness.clickText("Jump")
    #expect(harness.frame.contains("jumped=true"), "\(harness.frame)")
    for row in 0..<5 {
      #expect(harness.frame.contains("«\(row)»"), "row=\(row)\n\(harness.frame)")
    }
    #expect(!harness.frame.contains("«29»"), "\(harness.frame)")
    #expect(registry.collectionScrollLayout(scopeIdentity: identity)?.anchor == .start)

    try harness.clickText("Jump")
    #expect(
      harness.frame.contains("jumped=false"), "a repeated command is a no-op:\n\(harness.frame)")
    for row in 0..<5 {
      #expect(harness.frame.contains("«\(row)»"), "row=\(row)\n\(harness.frame)")
    }
    #expect(!harness.frame.contains("«5»"), "a repeated command moves nothing:\n\(harness.frame)")
    #expect(registry.collectionScrollLayout(scopeIdentity: identity)?.anchor == .start)
  }

  @Test func setB005ExplicitAnchorsOnOversizedRowAlignItsStart() throws {
    // A five-line target on a three-line viewport cannot honor .center or
    // .bottom: every anchor shows the row from its first line.
    for anchor in [UnitPoint.top, .center, .bottom] {
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("SetBScroll", "OversizedAnchor", "\(anchor.y)"),
        size: .init(width: 32, height: 8)
      ) {
        SetBOversizedTargetList(anchor: anchor)
      }
      defer { harness.shutdown() }
      try harness.clickText("Jump")
      let viewport = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
      let top = viewport.viewportRect.origin.y
      let lines = harness.frame.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      try #require(lines.count > top + 2, "anchor=\(anchor.y)\n\(harness.frame)")
      #expect(lines[top].contains("«9»:0"), "anchor=\(anchor.y)\n\(harness.frame)")
      #expect(lines[top + 1].contains("«9»:1"), "anchor=\(anchor.y)\n\(harness.frame)")
      #expect(lines[top + 2].contains("«9»:2"), "anchor=\(anchor.y)\n\(harness.frame)")
      #expect(lines[0].contains("Jump"), "\(harness.frame)")
      #expect(lines[top + 3].contains("After list"), "\(harness.frame)")
    }
  }

  @Test func setB006ZeroDeltaNotchStopsFlingWithoutMoving() throws {
    // A wheel notch landing on a flinging route is touch-to-stop, even with
    // zero deltas; nothing moves, and a later real notch moves one row.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScroll", "ZeroDeltaNotch"),
      size: .init(width: 32, height: 8)
    ) {
      List(0..<200, id: \.self) { row in Text("«\(row)»") }
        .listStyle(SetBListStyle()).scrollIndicators(.hidden).frame(height: 6)
    }
    defer { harness.shutdown() }
    let point = try #require(harness.point(forText: "«0»"))
    let before = harness.frame
    let fling = try setBSeedFling(harness, velocity: 30)
    try #require(harness.runLoop.scrollMomentum.isActive(fling.identity))

    try harness.scrollPointer(at: point, deltaX: 0, deltaY: 0)
    #expect(!harness.runLoop.scrollMomentum.hasActiveMomentum, "a notch stops the fling")
    #expect(harness.frame == before, "a zero notch moves nothing:\n\(harness.frame)")

    try setBTick(harness, fling.clock)
    #expect(harness.frame == before, "no fling tick runs after the notch:\n\(harness.frame)")

    try harness.scrollPointer(at: point, deltaY: 1)
    #expect(harness.frame.contains("«1»"), "\(harness.frame)")
    #expect(!harness.frame.contains("«0»"), "one notch moves exactly one row:\n\(harness.frame)")
    #expect(harness.frame.contains("«6»"), "\(harness.frame)")
  }

  @Test func setB007KeyboardRevealDuringFlingKeepsSelectionVisible() throws {
    // A keyboard selection step is an explicit reposition. A fling that keeps
    // gliding afterward would scroll the just-selected row out of view.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScroll", "KeyboardRevealDuringFling"),
      size: .init(width: 32, height: 8)
    ) {
      SetBSelectableLongList()
    }
    defer { harness.shutdown() }
    try harness.focusText("«0»")
    let fling = try setBSeedFling(harness, velocity: 80)

    try harness.pressKey(KeyPress(.arrowDown))
    try #require(harness.frame.contains("sel=1"), "\(harness.frame)")
    try #require(harness.frame.contains("«1»"), "\(harness.frame)")

    for _ in 0..<10 {
      try setBTick(harness, fling.clock)
    }
    #expect(harness.frame.contains("sel=1"), "\(harness.frame)")
    withKnownIssue("keyboard reveal does not cancel momentum; the selection scrolls away") {
      #expect(
        harness.frame.contains("«1»"),
        "the selected row stays visible after the key press:\n\(harness.frame)")
    }
  }

  @Test func setB008OneLineViewportResizeKeepsSelectionReachable() throws {
    // Shrinking a selectable list to a one-line viewport (indicators cannot
    // fit) keeps the selected row visible, arrow keys keep moving one row,
    // and growing back plus Home/End move the window without the selection.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScroll", "OneLineViewportResize"),
      size: .init(width: 32, height: 10)
    ) {
      SetBResizableSelectableList()
    }
    defer { harness.shutdown() }
    let registry = harness.runLoop.localScrollPositionRegistry
    let identity = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    try harness.focusText("«0»")
    for _ in 0..<7 {
      try harness.pressKey(KeyPress(.arrowDown))
    }
    try #require(harness.frame.contains("sel=7"), "\(harness.frame)")
    try #require(harness.frame.contains("«7»"), "\(harness.frame)")

    try harness.pressKey(KeyPress(.character("h"), modifiers: .ctrl))
    #expect(harness.frame.contains("«7»"), "the selection survives the shrink:\n\(harness.frame)")
    #expect(registry.collectionScrollLayout(scopeIdentity: identity)?.visibleLines.count == 1)

    try harness.pressKey(KeyPress(.arrowDown))
    #expect(harness.frame.contains("sel=8"), "\(harness.frame)")
    #expect(harness.frame.contains("«8»"), "\(harness.frame)")
    #expect(!harness.frame.contains("«7»"), "a one-line window shows one row:\n\(harness.frame)")

    try harness.pressKey(KeyPress(.character("h"), modifiers: .ctrl))
    #expect(harness.frame.contains("«8»"), "the selection survives the growth:\n\(harness.frame)")
    #expect(harness.frame.contains("sel=8"), "\(harness.frame)")

    try harness.pressKey(KeyPress(.end))
    #expect(harness.frame.contains("«11»"), "\(harness.frame)")
    #expect(harness.frame.contains("sel=8"), "End scrolls without selecting:\n\(harness.frame)")

    try harness.pressKey(KeyPress(.home))
    #expect(harness.frame.contains("«0»"), "\(harness.frame)")
    #expect(harness.frame.contains("sel=8"), "Home scrolls without selecting:\n\(harness.frame)")
  }

  @Test func setB009FlingIntoFooterOnlyEndThenOneNotchUpShowsLastRow() throws {
    // Momentum must glide all the way into a footer-only end window and stop
    // there; reversing by one notch then shows the final row, not the row
    // before it.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScroll", "FlingIntoFooterOnlyEnd"),
      size: .init(width: 32, height: 8)
    ) {
      List {
        Section {
          ForEach(0..<20, id: \.self) { row in Text("«\(row)»") }
        } header: {
          EmptyView()
        } footer: {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<5, id: \.self) { line in Text("footer:\(line)") }
          }
        }
      }
      .listStyle(SetBListStyle()).scrollIndicators(.hidden).frame(height: 4)
    }
    defer { harness.shutdown() }
    let registry = harness.runLoop.localScrollPositionRegistry
    let point = try #require(harness.point(forText: "«0»"))
    let fling = try setBSeedFling(harness, velocity: 80)

    var steps = 0
    while harness.runLoop.scrollMomentum.hasActiveMomentum, steps < 600 {
      try setBTick(harness, fling.clock)
      steps += 1
    }
    #expect(steps < 600, "the fling settles")
    withKnownIssue("momentum stops one line short of the footer-only end") {
      #expect(
        harness.frame.contains("footer:4"), "the fling reaches the footer end:\n\(harness.frame)")
      #expect(!harness.frame.contains("«19»"), "the end window is footer-only:\n\(harness.frame)")
      #expect(registry.collectionScrollLayout(scopeIdentity: fling.identity)?.anchor == .end)

      try harness.scrollPointer(at: point, deltaY: -1)
      #expect(harness.frame.contains("«19»"), "one notch up shows the final row:\n\(harness.frame)")
      #expect(harness.frame.contains("footer:0"), "\(harness.frame)")
    }
  }

  @Test func setB010HeterogeneousRowsKeepExtentAcrossResizeAtEnd() throws {
    // Alternating one- and four-line rows scrolled to the end: shrinking and
    // growing the viewport keeps the measured content extent (no snap-back),
    // the window stays at the end, and one notch up moves a whole row.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBScroll", "HeterogeneousResizeAtEnd"),
      size: .init(width: 32, height: 10)
    ) {
      SetBHeterogeneousList()
    }
    defer { harness.shutdown() }
    let registry = harness.runLoop.localScrollPositionRegistry
    try harness.focusText("«0»:0")
    let point = try #require(harness.point(forText: "«0»:0"))

    func route() throws -> ScrollRoute {
      try #require(
        registry.routesWithCurrentOffsets(harness.runLoop.latestSemanticSnapshot.scrollRoutes)
          .first)
    }
    for _ in 0..<60 {
      let current = try route()
      let maximum = max(0, current.contentBounds.size.height - current.viewportRect.size.height)
      if current.contentOffset.y >= maximum { break }
      try harness.scrollPointer(at: point, deltaY: 1)
    }
    try #require(harness.frame.contains("«19»:3"), "the wheel reaches the end:\n\(harness.frame)")
    let identity = try route().identity
    let extent = try route().contentBounds.size.height
    #expect(extent >= 50, "ten four-line rows and ten one-line rows were measured: \(extent)")

    try harness.pressKey(KeyPress(.character("h"), modifiers: .ctrl))
    withKnownIssue("shrinking the viewport at the end drops the end anchor to row 18") {
      #expect(harness.frame.contains("«19»:3"), "the end survives the shrink:\n\(harness.frame)")
      let shrunkExtent = try route().contentBounds.size.height
      #expect(shrunkExtent == extent, "no snap-back on shrink: \(shrunkExtent) vs \(extent)")
      #expect(registry.collectionScrollLayout(scopeIdentity: identity)?.anchor == .end)
    }

    try harness.pressKey(KeyPress(.character("h"), modifiers: .ctrl))
    #expect(harness.frame.contains("«19»:3"), "the end survives the growth:\n\(harness.frame)")
    let grownExtent = try route().contentBounds.size.height
    #expect(grownExtent == extent, "no snap-back on growth: \(grownExtent) vs \(extent)")

    try harness.scrollPointer(at: point, deltaY: -1)
    #expect(harness.frame.contains("«18»:0"), "one notch up shows row 18:\n\(harness.frame)")
    let reversed = try route()
    let reversedMaximum = max(
      0, reversed.contentBounds.size.height - reversed.viewportRect.size.height)
    #expect(reversed.contentOffset.y > 0)
    #expect(reversed.contentOffset.y < reversedMaximum)
  }
}

// MARK: - Fling helpers

private final class SetBClock {
  var now: MonotonicInstant

  init(_ now: MonotonicInstant) {
    self.now = now
  }
}

/// Seeds a vertical fling on the first scroll route, pins the run loop clock,
/// and arms the first 33 ms momentum deadline the way a pan release does.
@MainActor
private func setBSeedFling<Content: View>(
  _ harness: StressRuntimeHarness<Content>,
  velocity: Double
) throws -> (identity: Identity, clock: SetBClock) {
  let identity = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
  let clock = SetBClock(.now())
  harness.runLoop.frameClock = { [clock] in clock.now }
  let started = harness.runLoop.scrollMomentum.begin(
    identity: identity,
    offsetVelocity: Vector(dx: 0, dy: velocity),
    canScrollX: false,
    canScrollY: true,
    now: clock.now
  )
  try #require(started, "the fling must start")
  harness.runLoop.scheduler.requestDeadline(clock.now.advanced(by: .milliseconds(33)))
  return (identity, clock)
}

/// Advances the pinned clock by one momentum tick and renders the deadline frame.
@MainActor
private func setBTick<Content: View>(
  _ harness: StressRuntimeHarness<Content>,
  _ clock: SetBClock
) throws {
  clock.now = clock.now.advanced(by: .milliseconds(33))
  try harness.render()
}

private func setBFlag(_ value: Bool?) -> String {
  value.map { $0 ? "true" : "false" } ?? "nil"
}

// MARK: - Fixtures

@MainActor
private struct SetBRow: View {
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

private struct SetBListStyle: ListStyle, Equatable {
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
private struct SetBFirstRowBottomList: View {
  @State private var jumped: Bool? = nil

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("Jump") { jumped = proxy.scrollTo(0, anchor: .bottom) }
        List(0..<30, id: \.self) { row in Text("«\(row)»") }
          .listStyle(SetBListStyle()).scrollIndicators(.hidden).focusable().frame(height: 5)
        Text("jumped=\(setBFlag(jumped))")
      }
    }
  }
}

@MainActor
private struct SetBOversizedTargetList: View {
  let anchor: UnitPoint

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("Jump") { _ = proxy.scrollTo(9, anchor: anchor) }
        List(0..<10, id: \.self) { row in SetBRow(row: row, lines: row == 9 ? 5 : 1) }
          .listStyle(SetBListStyle()).scrollIndicators(.hidden).frame(height: 3)
        Text("After list")
      }
    }
  }
}

@MainActor
private struct SetBSelectableLongList: View {
  @State private var selected: Int? = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(0..<200, id: \.self, selection: $selected) { row in Text("«\(row)»") }
        .listStyle(SetBListStyle()).scrollIndicators(.hidden).frame(height: 5)
      Text("sel=\(selected ?? -1)")
    }
  }
}

@MainActor
private struct SetBResizableSelectableList: View {
  @State private var selected: Int? = 0
  @State private var short = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(0..<12, id: \.self, selection: $selected) { row in Text("«\(row)»") }
        .listStyle(SetBListStyle())
        .frame(height: short ? 1 : 6)
      Text("sel=\(selected ?? -1)")
    }
    .onKeyPress(.character("h"), modifiers: .ctrl) { _ in
      short.toggle()
      return .handled
    }
  }
}

@MainActor
private struct SetBHeterogeneousList: View {
  @State private var short = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(0..<20, id: \.self) { row in
        SetBRow(row: row, lines: row.isMultiple(of: 2) ? 1 : 4)
      }
      .listStyle(SetBListStyle())
      .scrollIndicators(.hidden)
      .focusable()
      .frame(height: short ? 3 : 6)
    }
    .onKeyPress(.character("h"), modifiers: .ctrl) { _ in
      short.toggle()
      return .handled
    }
  }
}
