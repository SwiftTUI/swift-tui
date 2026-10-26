// Wave-3 regression hunt, part FB (STUI-1167): forty pre-specified neighbours
// of the wave-3 repairs FW3-E (d2458754: collection bands, row selectors,
// pending far edges), FW3-F (e827636d: snapshot capture flag, centre-rounding
// mode) and FW3-G (d751e650: trimmed paths, far segments, ellipse outlines,
// numbered direct xterms). This file holds every case except the raster ones
// (Tests/SwiftTUICoreTests/Wave3HuntFBRasterTests.swift). The brief and
// hypotheses live in the org root's
// docs/reports/evidence/2026-10-25-campaign-two-wave-3-hunt/fb/.
import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Keeps an unmarked reproduction path (`SWIFTTUI_W3HUNT_UNMARKED=1`) while
/// limiting each guard to its exact reproduced assertion.
private func w3fbKnown(_ comment: Comment, _ body: () throws -> Void) rethrows {
  if ProcessInfo.processInfo.environment["SWIFTTUI_W3HUNT_UNMARKED"] == "1" {
    try body()
  } else {
    withKnownIssue(comment) { try body() }
  }
}

private func w3fbKnown(_ comment: Comment, _ body: () async throws -> Void) async rethrows {
  if ProcessInfo.processInfo.environment["SWIFTTUI_W3HUNT_UNMARKED"] == "1" {
    try await body()
  } else {
    await withKnownIssue(comment) { try await body() }
  }
}

// MARK: - FW3-E: collection bands and review pages (STUI-1239)

@MainActor
@Suite(.serialized)
struct Wave3HuntFBCollectionTests {
  // w3fb001: two review pages dispatched before one frame on a drawn-separator
  // table move by the rows the window shows, less one row of overlap, each.
  @Test func w3fb001ReviewPagesBeforeOneFrameMoveByVisibleRowsOnDrawnTable() throws {
    let outcome = try W3FB.reviewTwoPagesBeforeOneFrame("w3fb001", hidden: false)
    w3fbKnown(
      "NEW-1: two review Next page actions before one frame on a drawn-separator table move 10 then 21 rows (position 32, expected 21, 11 rows visible); after reveal moves the stored anchor, CollectionScrollCurrency.visibleRowCount takes the one-line-per-row bound (CollectionScrollState.swift:126-135; CollectionAccessibilityNavigation.swift:112-115); contract: wave3e04, Accessibility.md:142-148; adjacent STUI-1239"
    ) {
      // Contract: wave3e04 (the repair's own), Accessibility.md:142-148.
      #expect(
        outcome.value == .number(Double(1 + 2 * (outcome.visible - 1))),
        "\(outcome.visible) visible rows; value \(String(describing: outcome.value))")
    }
  }

  // w3fb002: the same with hidden separators, where one line holds one row.
  @Test func w3fb002ReviewPagesBeforeOneFrameMoveByVisibleRowsOnHiddenTable() throws {
    let outcome = try W3FB.reviewTwoPagesBeforeOneFrame("w3fb002", hidden: true)
    #expect(
      outcome.value == .number(Double(1 + 2 * (outcome.visible - 1))),
      "\(outcome.visible) visible rows; value \(String(describing: outcome.value))")
  }

  // w3fb003: a viewport-backed plain List whose rows hide their separators
  // answers the assistive activation of its lowest visible row. (A pointer
  // click selects no List row in this harness, with or without separators;
  // corrections.md C1.)
  @Test func w3fb003HiddenSeparatorListLowestVisibleRowSelects() throws {
    let box = W3FBSelection<String>(selected: "r100")
    let rows = W3FB.rows(200)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb003"), size: .init(width: 30, height: 64)
    ) {
      List(rows, id: \.id, selection: box.binding) { row in
        Text(row.id).listRowSeparator(.hidden)
      }.listStyle(.plain).scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    let visible = W3FB.rowIDs(h.frame)
    try #require(visible.count >= 25 && visible.first != "r000", "\(h.frame)")
    let target = visible[visible.count - 1]
    let result = try W3FB.activateRow(h, id: target)
    #expect(result == .accepted, "\(target): \(result)")
    #expect(box.selected == target, "activated \(target); visible \(visible[0])…\(target)")
  }

  // w3fb004: on a List of two-line rows the review page moves by the rows the
  // window shows, less one.
  @Test func w3fb004TallRowListReviewPageMovesByVisibleRows() throws {
    let box = W3FBSelection<String>(selected: "r000")
    let rows = W3FB.rows(200)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb004"), size: .init(width: 30, height: 24)
    ) {
      List(rows, id: \.id, selection: box.binding) { row in
        VStack(alignment: .leading, spacing: 0) {
          Text(row.id)
          Text("·")
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    let visible = W3FB.rowIDs(h.frame)
    try #require(visible.first == "r000" && visible.count >= 4, "\(h.frame)")
    let target = try #require(try W3FB.review(h).actionTarget)
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .custom("Next page")))
        == .accepted)
    _ = try h.render()
    #expect(
      try W3FB.review(h).control?.value == .number(Double(visible.count)),
      "\(visible.count) visible rows")
  }

  // w3fb005: after one long wheel scroll on a hidden-separator table, the
  // lowest visible row selects.
  @Test func w3fb005HiddenSeparatorTableLowestRowSelectsAfterLongWheel() throws {
    let box = W3FBSelection<String>(selected: "r000")
    let h = try W3FB.bandTable("w3fb005", box: box, hidden: true, height: 64)
    defer { h.shutdown() }
    _ = try h.scrollPointer(at: Point(x: 2, y: 5), deltaY: 40)
    let visible = W3FB.rowIDs(h.frame)
    try #require(visible.count >= 40 && visible.first != "r000", "\(h.frame)")
    let target = visible[visible.count - 1]
    _ = try h.clickText(target)
    #expect(box.selected == target, "clicked \(target); visible \(visible[0])…\(target)")
  }

  // w3fb006: a data table hosted in a ScrollView answers a click on its lowest
  // visible row after the ScrollView scrolls far from the selection.
  @Test(arguments: [false, true])
  func w3fb006ScrollHostedTableRowsAnswerAfterScrollViewScroll(hidden: Bool) throws {
    let box = W3FBSelection<String>(selected: "r000")
    let rows = W3FB.rows(200)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb006", hidden ? "hidden" : "drawn"),
      size: .init(width: 30, height: 42)
    ) {
      ScrollViewReader { proxy in
        VStack(spacing: 0) {
          Button("jump") { _ = proxy.scrollTo(edge: .bottom) }
          ScrollView {
            Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
              if hidden {
                Text(row.id).listRowSeparator(.hidden)
              } else {
                Text(row.id)
              }
            }.tableHeaders(.hidden)
          }.scrollIndicators(.hidden).frame(height: 40)
        }
      }
    }
    defer { h.shutdown() }
    _ = try h.clickText("jump")
    let visible = W3FB.rowIDs(h.frame)
    try #require(visible.last == "r199" && visible.count >= 15, "\(h.frame)")
    let target = visible[visible.count - 2]
    _ = try h.clickText(target)
    #expect(
      box.selected == target,
      "\(hidden ? "hidden" : "drawn"): clicked \(target); visible \(visible[0])…r199")
  }
}

// MARK: - FW3-E: row selector eligibility (STUI-1240)

@MainActor
@Suite(.serialized)
struct Wave3HuntFBSelectorTests {
  // w3fb007: a multiple-selection table's disabled row has a disabled selector
  // whose activation is refused.
  @Test func w3fb007MultiSelectDisabledRowSelectorIsDisabled() throws {
    let box = W3FBMultiSelection()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb007"), size: .init(width: 24, height: 10)
    ) {
      Table(
        [1, 2, 3], id: \.self, selection: box.binding,
        columns: [TableColumn("Name", width: 12)]
      ) { i in
        Text("row\(i)").disabled(i == 2)
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    #expect(try W3FB.selector(h, 1).isEnabled)
    #expect(try W3FB.selector(h, 3).isEnabled)
    let disabled = try W3FB.selector(h, 2)
    #expect(!disabled.isEnabled)
    let result = h.runLoop.handleAccessibilityAction(
      .init(target: try #require(disabled.actionTarget), action: .activate))
    _ = try h.render()
    #expect(result == .disabled, "\(String(describing: result))")
    #expect(box.selected.isEmpty)
    let enabled = try #require(try W3FB.selector(h, 3).actionTarget)
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: enabled, action: .activate)) == .accepted)
    _ = try h.render()
    #expect(box.selected == [3])
  }

  // w3fb008: one disabled cell beside an enabled one leaves the row, and so its
  // selector, enabled.
  @Test func w3fb008OneDisabledCellKeepsRowSelectorEnabled() throws {
    let box = W3FBSelection<Int>(selected: 1)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb008"), size: .init(width: 24, height: 10)
    ) {
      Table(
        [1, 2, 3], id: \.self, selection: box.binding,
        columns: [TableColumn("A", width: 6), TableColumn("B", width: 6)]
      ) { i in
        Text("a\(i)").disabled(i == 2)
        Text("b\(i)")
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    let selector = try W3FB.selector(h, 2)
    #expect(selector.isEnabled)
    let result = h.runLoop.handleAccessibilityAction(
      .init(target: try #require(selector.actionTarget), action: .activate))
    _ = try h.render()
    #expect(result == .accepted, "\(String(describing: result))")
    #expect(box.selected == 2)
  }

  // w3fb009: the selector follows the row's eligibility as it toggles.
  @Test func w3fb009SelectorFollowsRuntimeEligibilityToggle() throws {
    let box = W3FBSelection<Int>(selected: 1)
    let model = W3FBToggle()
    model.disabled = true
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb009"), size: .init(width: 24, height: 10)
    ) {
      Table(
        [1, 2, 3], id: \.self, selection: box.binding,
        columns: [TableColumn("Name", width: 12)]
      ) { i in
        Text("row\(i)").disabled(i == 2 && model.disabled)
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    var observed: [Bool] = []
    var results: [String] = []
    for disabled in [true, false, true] {
      model.disabled = disabled
      _ = try h.renderAfterExternalMutation()
      box.selected = 1
      _ = try h.renderAfterExternalMutation()
      let selector = try W3FB.selector(h, 2)
      observed.append(selector.isEnabled)
      let result = h.runLoop.handleAccessibilityAction(
        .init(target: try #require(selector.actionTarget), action: .activate))
      _ = try h.render()
      results.append("\(String(describing: result)):\(String(describing: box.selected))")
    }
    #expect(observed == [false, true, false], "\(observed)")
    #expect(
      results == [
        "\(AccessibilityActionResult.disabled):Optional(1)",
        "\(AccessibilityActionResult.accepted):Optional(2)",
        "\(AccessibilityActionResult.disabled):Optional(1)",
      ], "\(results)")
  }

  // w3fb010: a disabled outline branch row leaves its children's selectors
  // enabled.
  @Test func w3fb010OutlineDisabledParentKeepsChildSelectorsEnabled() throws {
    let box = W3FBSelection<Int>(selected: nil)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb010"), size: .init(width: 24, height: 10)
    ) {
      List(
        [W3FBOutlineRecord(id: 1, children: [.init(id: 2), .init(id: 3)])], id: \.id,
        selection: box.binding, children: \.children
      ) { record in
        Text("row\(record.id)").disabled(record.id == 1)
      }
    }
    defer { h.shutdown() }
    #expect(!(try W3FB.selector(h, 1).isEnabled))
    #expect(try W3FB.selector(h, 2).isEnabled)
    #expect(try W3FB.selector(h, 3).isEnabled)
    let target = try #require(try W3FB.selector(h, 2).actionTarget)
    let result = h.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
    _ = try h.render()
    #expect(result == .accepted, "\(String(describing: result))")
    #expect(box.selected == 2)
  }
}

// MARK: - FW3-E: pending far edges (STUI-1243)

@MainActor
@Suite(.serialized)
struct Wave3HuntFBScrollEdgeTests {
  // w3fb011: bottom and trailing commands on one two-axis lazy view in one
  // action reach both edges, in either order.
  @Test(arguments: [true, false])
  func w3fb011BottomThenTrailingOnOneViewReachesBothEdges(bottomFirst: Bool) throws {
    let proxies = W3FBProxies()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb011", bottomFirst ? "bottomFirst" : "trailingFirst"),
      size: .init(width: 24, height: 10)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Button("jump") {
          let edges: [Edge] = bottomFirst ? [.bottom, .trailing] : [.trailing, .bottom]
          for edge in edges { _ = proxies.first?.scrollTo(edge: edge) }
        }
        ScrollViewReader { proxy in
          let _ = proxies.store(proxy, at: 0)
          ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(0..<120, id: \.self) { i in
                Text("a\(i)").frame(width: 40, height: i < 40 ? 1 : 3, alignment: .topTrailing)
              }
            }
          }.scrollIndicators(.hidden).frame(width: 20, height: 8)
        }
      }
    }
    defer { h.shutdown() }
    try #require(!h.frame.contains("a119"), "\(h.frame)")
    _ = try h.clickText("jump")
    func reachedBottom() {
      // Contract: Scrolling.md:139-150, 206-210; Divergences-And-Gaps.md:398-407.
      #expect(
        h.frame.contains("a119"), "\(bottomFirst ? "bottom first" : "trailing first"):\n\(h.frame)")
    }
    if bottomFirst {
      w3fbKnown(
        "NEW-2: proxy bottom then trailing on one two-axis lazy view in one action stops at a111-a113; the trailing command overwrites the route's pending far edge, so only x is refined (LocalScrollPositionRegistry.swift:519-547); contract: Scrolling.md:139-150, 206-210; adjacent STUI-1243"
      ) { reachedBottom() }
    } else {
      reachedBottom()
    }
  }

  // w3fb012: three bottom edges in one action all refine.
  @Test func w3fb012ThreeBottomEdgesInOneActionAllRefine() throws {
    let proxies = W3FBProxies()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb012"), size: .init(width: 30, height: 10)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Button("jump") {
          for index in 0..<3 { _ = proxies.proxy(at: index)?.scrollTo(edge: .bottom) }
        }
        HStack(alignment: .top, spacing: 1) {
          ForEach(Array(["a", "b", "c"].enumerated()), id: \.offset) { index, prefix in
            ScrollViewReader { proxy in
              let _ = proxies.store(proxy, at: index)
              W3FB.variableLazy(prefix: prefix)
            }
          }
        }
      }
    }
    defer { h.shutdown() }
    _ = try h.clickText("jump")
    #expect(
      h.frame.contains("a119") && h.frame.contains("b119") && h.frame.contains("c119"),
      "\(h.frame)")
  }

  // w3fb013: one action sends view a to the bottom and view b, already at its
  // bottom, to the top.
  @Test func w3fb013MixedTopAndBottomEdgesInOneAction() throws {
    let proxies = W3FBProxies()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb013"), size: .init(width: 30, height: 10)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
          Button("prep") { _ = proxies.proxy(at: 1)?.scrollTo(edge: .bottom) }
          Button("mix") {
            _ = proxies.proxy(at: 0)?.scrollTo(edge: .bottom)
            _ = proxies.proxy(at: 1)?.scrollTo(edge: .top)
          }
        }
        HStack(alignment: .top, spacing: 1) {
          ScrollViewReader { proxy in
            let _ = proxies.store(proxy, at: 0)
            W3FB.variableLazy(prefix: "a")
          }
          ScrollViewReader { proxy in
            let _ = proxies.store(proxy, at: 1)
            W3FB.variableLazy(prefix: "b")
          }
        }
      }
    }
    defer { h.shutdown() }
    _ = try h.clickText("prep")
    try #require(h.frame.contains("b119") && h.frame.contains("a0"), "\(h.frame)")
    _ = try h.clickText("mix")
    let tokens = Set(W3FB.lines(h.frame).flatMap { $0.split(separator: " ").map(String.init) })
    #expect(tokens.contains("a119") && tokens.contains("b0"), "\(h.frame)")
  }

  // w3fb014: a far edge on view a and a lazy scrollTo(id) on view b in one
  // action both land.
  // Control (`estimatedTarget` false, added after the first run): a target
  // the frame has already placed leaves no pending lazy target, and the far
  // edge lands.
  @Test(arguments: [true, false])
  func w3fb014FarEdgeAndLazyTargetInOneActionBothLand(estimatedTarget: Bool) throws {
    let proxies = W3FBProxies()
    let target = estimatedTarget ? 110 : 3
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb014", estimatedTarget ? "estimated" : "placed"),
      size: .init(width: 30, height: 10)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Button("jump") {
          _ = proxies.proxy(at: 0)?.scrollTo(edge: .bottom)
          _ = proxies.proxy(at: 1)?.scrollTo(target, anchor: .top)
        }
        HStack(alignment: .top, spacing: 1) {
          ScrollViewReader { proxy in
            let _ = proxies.store(proxy, at: 0)
            W3FB.variableLazy(prefix: "a")
          }
          ScrollViewReader { proxy in
            let _ = proxies.store(proxy, at: 1)
            W3FB.variableLazy(prefix: "b")
          }
        }
      }
    }
    defer { h.shutdown() }
    _ = try h.clickText("jump")
    #expect(h.frame.contains("b\(target)"), "\(h.frame)")
    func reachedBottom() {
      #expect(h.frame.contains("a119"), "\(estimatedTarget ? "estimated" : "placed"):\n\(h.frame)")
    }
    if estimatedTarget {
      w3fbKnown(
        "NEW-3: a far edge on lazy view a and a scrollTo(id) to an unplaced row of view b in one action leave a at a111/a112; the lazy-target loop refines and returns before refineFarEdges, and anchor preservation then supersedes a's pending edge (LocalScrollPositionRegistry.swift:708-737); contract: Scrolling.md:139-150, Divergences-And-Gaps.md:398-407; adjacent STUI-1243"
      ) { reachedBottom() }
    } else {
      reachedBottom()
    }
  }
}

// MARK: - FW3-F: snapshot state continuity (STUI-1241)

@MainActor
@Suite(.serialized)
struct Wave3HuntFBStateTests {
  // w3fb015: a child Button writing the parent's state through @Binding
  // between two one-shot snapshots reaches the second snapshot, also after the
  // first renderer is released.
  @Test func w3fb015SnapshotBindingWriteSurvivesReleasedRenderer() throws {
    // Control: the first renderer stays alive across the dispatch.
    let alive = W3FBBindingParent()
    let aliveRegistry = LocalActionRegistry()
    let aliveRenderer = DefaultRenderer()
    defer { withExtendedLifetime(aliveRenderer) {} }
    let first = aliveRenderer.render(
      alive,
      context: .init(
        identity: testIdentity("w3fb015-alive"), localActionRegistry: aliveRegistry,
        applyEnvironmentValues: true))
    try #require(first.rasterSurface.lines.contains { $0.contains("Count 0") })
    let aliveAction = try #require(first.semanticSnapshot.focusRegions.first?.identity)
    #expect(aliveRegistry.dispatch(identity: aliveAction))
    let aliveSecond = DefaultRenderer().render(
      alive, context: .init(identity: testIdentity("w3fb015-alive")))
    #expect(
      aliveSecond.rasterSurface.lines.contains { $0.contains("Count 1") },
      "alive: \(aliveSecond.rasterSurface.lines)")

    let released = W3FBBindingParent()
    let registry = LocalActionRegistry()
    let action = try #require(
      W3FB.renderWithReleasedRenderer(released, registry: registry, name: "w3fb015"))
    W3FB.withRetiredWriteDiagnostics { #expect(registry.dispatch(identity: action)) }
    let second = DefaultRenderer().render(
      released, context: .init(identity: testIdentity("w3fb015")))
    w3fbKnown(
      "NEW-4: a child Button writing the parent's @State through @Binding between two snapshots is lost once the first renderer is released (second snapshot Count 0); the graph-backed binding's setter keeps only an owner-retained value when the graph is gone and never the seed mirror (State.swift:617-657); contract: State-Keying.md:156-166, State.swift:240-247; adjacent STUI-1241"
    ) {
      // Contract: State-Keying.md:156-166; State.swift:240-247.
      #expect(
        second.rasterSurface.lines.contains { $0.contains("Count 1") },
        "released: \(second.rasterSurface.lines)")
    }
  }

  // w3fb016: a Button with @State in a LazyVStack row keeps a dispatch between
  // two snapshots after the first renderer is released.
  @Test func w3fb016SnapshotLazyRowDispatchSurvivesReleasedRenderer() throws {
    // Control: the first renderer stays alive across the dispatch.
    let alive = W3FBLazyCounters()
    let aliveRegistry = LocalActionRegistry()
    let aliveRenderer = DefaultRenderer()
    defer { withExtendedLifetime(aliveRenderer) {} }
    let first = aliveRenderer.render(
      alive,
      context: .init(
        identity: testIdentity("w3fb016-alive"), localActionRegistry: aliveRegistry,
        applyEnvironmentValues: true))
    #expect(
      first.semanticSnapshot.focusRegions.map(\.identity).contains {
        aliveRegistry.dispatch(identity: $0)
      })
    let aliveSecond = DefaultRenderer().render(
      alive, context: .init(identity: testIdentity("w3fb016-alive")),
      proposal: .init(width: 20, height: 6))
    #expect(
      aliveSecond.rasterSurface.lines.contains { $0.contains("Count 1") },
      "alive: \(aliveSecond.rasterSurface.lines)")

    let view = W3FBLazyCounters()
    let registry = LocalActionRegistry()
    let regions = W3FB.focusRegionsWithReleasedRenderer(
      view, registry: registry, name: "w3fb016")
    try #require(!regions.isEmpty)
    // The first focus region is the ScrollView; dispatch the first button.
    W3FB.withRetiredWriteDiagnostics {
      #expect(regions.contains { registry.dispatch(identity: $0) })
    }
    let second = DefaultRenderer().render(
      view, context: .init(identity: testIdentity("w3fb016")),
      proposal: .init(width: 20, height: 6))
    #expect(
      second.rasterSurface.lines.contains { $0.contains("Count 1") },
      "\(second.rasterSurface.lines)")
  }

  // w3fb017: a snapshot write does not seed a later live mount of the same view
  // value, whether or not the snapshot's renderer is still alive.
  @Test(arguments: [false, true])
  func w3fb017SnapshotWriteDoesNotSeedLaterLiveMount(rendererAlive: Bool) throws {
    let view = W3FBSnapshotCounter()
    let registry = LocalActionRegistry()
    let name = "w3fb017-\(rendererAlive ? "alive" : "released")"
    var keeper: DefaultRenderer?
    let action: Identity
    if rendererAlive {
      let renderer = DefaultRenderer()
      keeper = renderer
      let artifacts = renderer.render(
        view,
        context: .init(
          identity: testIdentity(name), localActionRegistry: registry,
          applyEnvironmentValues: true))
      action = try #require(artifacts.semanticSnapshot.focusRegions.first?.identity)
    } else {
      action = try #require(
        W3FB.renderWithReleasedRenderer(view, registry: registry, name: name))
    }
    W3FB.withRetiredWriteDiagnostics { #expect(registry.dispatch(identity: action)) }
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity(name, "live"), size: .init(width: 20, height: 3)
    ) { view }
    defer { h.shutdown() }
    withExtendedLifetime(keeper) {}
    let route =
      rendererAlive
      ? "while the renderer lives, the graph-slot setter's mirror (State.swift:651-653, before wave 3 too)"
      : "after release, the capture-miss mirror e827636d kept (State.swift:362, 381)"
    w3fbKnown(
      "NEW-5: a snapshot's write seeds a later live mount of the same view value (the mount shows Count 1); \(route) writes the box seed that the mount's fresh slot reads (State.swift:580-615); contract: State-Keying.md:156-166, State.swift:240-247; adjacent STUI-1241, STUI-1173"
    ) {
      // Contract: State-Keying.md:156-166 (writes never leak between runtimes
      // through the view value; snapshot continuity is to a later snapshot).
      #expect(h.frame.contains("Count 0"), "\(rendererAlive ? "alive" : "released"): \(h.frame)")
    }
  }

  // w3fb018: a live data-driven List row's retired write never seeds the row
  // when its ID returns.
  @Test func w3fb018LiveIndexedListRowRetiredWriteDoesNotSeedReaddedRow() throws {
    let rows = W3FBRows(ids: ["a", "b", "c"])
    let logs = ["a", "b", "c"].reduce(into: [String: W3FBCaptureLog<Int>]()) {
      $0[$1] = W3FBCaptureLog<Int>(label: $1)
    }
    let leaves = logs.mapValues { W3FBCounterLeaf(log: $0) }
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb018"), size: .init(width: 20, height: 8)
    ) {
      List(rows.ids, id: \.self) { id in leaves[id]! }
    }
    defer { h.shutdown() }
    let log = try #require(logs["b"])
    let retired = try #require(log.entries.last)
    retired.write(4)
    _ = try h.render()
    try #require(h.frame.contains("bv4"), "\(h.frame)")
    rows.ids = ["a", "c"]
    _ = try h.renderAfterExternalMutation()
    try #require(!h.frame.contains("bv"), "\(h.frame)")
    W3FB.withRetiredWriteDiagnostics { retired.write(9) }
    rows.ids = ["a", "b", "c"]
    _ = try h.renderAfterExternalMutation()
    #expect(h.frame.contains("bv0"), "\(h.frame)")
  }
}

// MARK: - FW3-F: centre-rounding mode (STUI-1242)

@MainActor
@Suite(.serialized)
struct Wave3HuntFBCentringTests {
  // w3fb019: a custom alignment whose default reads the centre, as a lazy
  // stack's alignment, places like the eager centred stack.
  @Test func w3fb019CustomCentreAlignmentLazyStackMatchesEager() throws {
    let proxies = W3FBProxies()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb019"), size: .init(width: 10, height: 9)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Button("end") { _ = proxies.first?.scrollTo(edge: .bottom) }
        ScrollViewReader { proxy in
          let _ = proxies.store(proxy, at: 0)
          ScrollView {
            LazyVStack(alignment: .w3fbMidX, spacing: 0) {
              ForEach(0..<200, id: \.self) { i in Text(i.isMultiple(of: 2) ? "abcd" : "x") }
            }
          }.scrollIndicators(.hidden).frame(width: 10, height: 8)
        }
      }
    }
    defer { h.shutdown() }
    let eager = W3FB.raster(
      VStack(alignment: .center, spacing: 0) {
        Text("abcd")
        Text("x")
      }, "w3fb019-eager", width: 10, height: 2)
    let eagerOffset = try #require(W3FB.relativeColumn(of: "x", to: "abcd", in: eager))
    let top = W3FB.relativeColumn(of: "x", to: "abcd", in: W3FB.lines(h.frame))
    _ = try h.clickText("end")
    let end = W3FB.relativeColumn(of: "x", to: "abcd", in: W3FB.lines(h.frame))
    #expect(
      top == eagerOffset && end == eagerOffset,
      "eager \(eagerOffset) top \(String(describing: top)) end \(String(describing: end))\n\(h.frame)"
    )
  }

  // w3fb020: a guide computed as height minus centre, exactly the centre in
  // SwiftUI, places like the default.
  @Test func w3fb020GuideComputedAsHeightMinusCentrePlacesLikeDefault() throws {
    let unguided = W3FB.raster(
      HStack(alignment: .center, spacing: 1) {
        Text("A").frame(width: 3, height: 3)
        Text("B")
      }, "w3fb020-default")
    let guided = W3FB.raster(
      HStack(alignment: .center, spacing: 1) {
        Text("A").frame(width: 3, height: 3)
        Text("B").alignmentGuide(VerticalAlignment.center) {
          $0.height - $0[VerticalAlignment.center]
        }
      }, "w3fb020-guided")
    try #require(W3FB.position(of: "B", in: unguided)?.row == 1, "\(unguided)")
    w3fbKnown(
      "NEW-6: the guide { $0.height - $0[.center] } (exactly the centre in SwiftUI) puts a one-cell child beside a three-cell sibling on row 0 instead of the default row 1; halfCellPosition calls a guide half-cell only when it moves by +1 between the rounding modes, and this one moves by -1 (GeometryTypes.swift:440-470); contract: Authoring-Views.md:94-99, FW3-F residual (only a dependence not +-1 per mode degrades); adjacent STUI-1242"
    ) {
      // Contract: Authoring-Views.md:94-99; FW3-F residual ("not ±1 cell per mode").
      #expect(guided == unguided, "guided \(guided) default \(unguided)")
    }
  }

  // w3fb021: a custom Layout whose explicit centre forwards its subview's
  // centre places like the unwrapped subview.
  @Test func w3fb021CustomLayoutForwardingCentreKeepsHalfCell() throws {
    let unwrapped = W3FB.raster(
      HStack(alignment: .center, spacing: 1) {
        Text("A").frame(width: 3, height: 2)
        Text("B")
      }, "w3fb021-unwrapped")
    let forwarded = W3FB.raster(
      HStack(alignment: .center, spacing: 1) {
        Text("A").frame(width: 3, height: 2)
        W3FBForwardingLayout { Text("B") }
      }, "w3fb021-forwarded")
    let identity = W3FB.raster(
      HStack(alignment: .center, spacing: 1) {
        Text("A").frame(width: 3, height: 2)
        Text("B").alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] }
      }, "w3fb021-identity")
    try #require(identity == unwrapped, "identity \(identity) unwrapped \(unwrapped)")
    w3fbKnown(
      "NEW-7: a custom Layout whose explicitAlignment forwards its subview's centre puts the one-cell subview beside a two-cell sibling on row 1 instead of row 0; ownDimensions installs the layout's answers through the mode-blind overridingVerticalGuides(with:), and LayoutSubview.dimensions(in:) answers in the normal mode, so the forwarded centre is an integer guide (LayoutEngine+Alignment.swift:232-265; CustomLayout.swift:143-148); contract: CustomLayout.swift:355-368, Authoring-Views.md:94-99; adjacent STUI-1242"
    ) {
      // Contract: CustomLayout.swift:355-368 (answer "exactly as an
      // alignmentGuide closure does"); Authoring-Views.md:94-99.
      #expect(forwarded == unwrapped, "forwarded \(forwarded) unwrapped \(unwrapped)")
    }
  }

  // w3fb022: an identity guide propagated through padding keeps its half cell:
  // the padded child's exact centre (2.5) sets the line.
  @Test func w3fb022IdentityGuideThroughPaddingPlacesLikeDefault() {
    let lines = W3FB.raster(
      HStack(alignment: .center, spacing: 1) {
        Text("A").frame(width: 3, height: 3)
        Text("B").alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] }
          .padding(.top, 2)
      }, "w3fb022", height: 6)
    // SwiftUI: the padded guide is 2 + 0.5 = 2.5 and A's centre is 1.5, so A's
    // top is 1 and B (the padded wrapper's top 0, plus 2) is on row 2.
    #expect(W3FB.position(of: "A", in: lines)?.row == 2, "\(lines)")
    #expect(W3FB.position(of: "B", in: lines)?.row == 2, "\(lines)")
  }

  // w3fb023: an identity guide on a child inside a frame wrapper leaves the
  // frame's centre, and so its siblings, where the unguided frame puts them.
  @Test(arguments: [false, true])
  func w3fb023IdentityGuideInsideFrameKeepsSiblingPlacement(oddFrame: Bool) {
    func row(_ guided: Bool) -> [String] {
      W3FB.raster(
        HStack(alignment: .center, spacing: 1) {
          Text("A").frame(width: 3, height: 3)
          Group {
            if guided {
              W3FB.frameChild(oddFrame: oddFrame)
                .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] }
                .frame(width: 1, height: oddFrame ? 5 : 4)
            } else {
              W3FB.frameChild(oddFrame: oddFrame).frame(width: 1, height: oddFrame ? 5 : 4)
            }
          }
          Text("C").frame(width: 1, height: oddFrame ? 1 : 2)
        }, "w3fb023-\(oddFrame)-\(guided)", height: 6)
    }
    let unguided = row(false)
    let guided = row(true)
    w3fbKnown(
      "NEW-8: an identity centre guide on a child inside .frame(height: \(oddFrame ? 5 : 4)) moves the stack's other children by one row (\(oddFrame ? "A and C up" : "C up")); frame propagation adds the child's already-rounded integer origin to its guide, so the frame reports \(oddFrame ? "2 instead of its exact centre 2.5" : "1.5 instead of its exact centre 2.0") (LayoutEngine+Alignment.swift:436-447); contract: Authoring-Views.md:86-99; adjacent STUI-1242"
    ) {
      // Contract: Authoring-Views.md:86-99 (guides propagate through nested
      // frames; an identity guide places exactly like the built-in centre).
      #expect(
        guided == unguided,
        "\(oddFrame ? "odd" : "even") frame: guided \(guided) unguided \(unguided)")
    }
  }

  // w3fb024: a centre-derived guided row outside the lazy window moves the line
  // once measured (register), and then the lazy rows place like the eager stack.
  @Test func w3fb024CentreDerivedGuidedRowMovesLazyLineOnlyWhenMeasured() throws {
    let proxies = W3FBProxies()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb024"), size: .init(width: 10, height: 9)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Button("end") { _ = proxies.first?.scrollTo(edge: .bottom) }
        ScrollViewReader { proxy in
          let _ = proxies.store(proxy, at: 0)
          ScrollView {
            LazyVStack(alignment: .center, spacing: 0) {
              ForEach(0..<200, id: \.self) { i in
                if i == 197 {
                  Text("abc").alignmentGuide(HorizontalAlignment.center) {
                    $0[HorizontalAlignment.center] + 1
                  }
                } else {
                  Text(i.isMultiple(of: 2) ? "abcd" : "x")
                }
              }
            }
          }.scrollIndicators(.hidden).frame(width: 10, height: 8)
        }
      }
    }
    defer { h.shutdown() }
    let eager = W3FB.raster(
      VStack(alignment: .center, spacing: 0) {
        Text("abcd")
        Text("x")
        Text("abc").alignmentGuide(HorizontalAlignment.center) {
          $0[HorizontalAlignment.center] + 1
        }
      }, "w3fb024-eager", width: 10, height: 3)
    let eagerOffset = try #require(W3FB.relativeColumn(of: "x", to: "abcd", in: eager))
    let top = W3FB.relativeColumn(of: "x", to: "abcd", in: W3FB.lines(h.frame))
    _ = try h.clickText("end")
    let end = W3FB.relativeColumn(of: "x", to: "abcd", in: W3FB.lines(h.frame))
    // Divergences-And-Gaps.md:398-404: the unmeasured row may move the line.
    #expect(top == 1, "top \(String(describing: top))\n\(h.frame)")
    #expect(end == eagerOffset, "eager \(eagerOffset) end \(String(describing: end))\n\(h.frame)")
  }

  // w3fb025: identity guides on an overlay decoration, its primary or both
  // place the decoration like the unguided overlay.
  @Test(arguments: [3, 4])
  func w3fb025OverlayIdentityGuidesPlaceLikeDefault(width: Int) {
    let label = String("abcd".prefix(width))
    let unguided = W3FB.raster(Text(label).overlay { Text("x") }, "w3fb025-\(width)-none")
    let onDecoration = W3FB.raster(
      Text(label).overlay {
        Text("x").alignmentGuide(HorizontalAlignment.center) { $0[HorizontalAlignment.center] }
      }, "w3fb025-\(width)-decoration")
    let onPrimary = W3FB.raster(
      Text(label).alignmentGuide(HorizontalAlignment.center) { $0[HorizontalAlignment.center] }
        .overlay { Text("x") }, "w3fb025-\(width)-primary")
    let both = W3FB.raster(
      Text(label).alignmentGuide(HorizontalAlignment.center) { $0[HorizontalAlignment.center] }
        .overlay {
          Text("x").alignmentGuide(HorizontalAlignment.center) { $0[HorizontalAlignment.center] }
        }, "w3fb025-\(width)-both")
    #expect(
      onDecoration == unguided && onPrimary == unguided && both == unguided,
      "\(unguided) \(onDecoration) \(onPrimary) \(both)")
  }

  // w3fb026: an alignment guide closure sees only public ViewDimensions values,
  // and a closure valid for them does not trap.
  @Test func w3fb026GuideClosureSeesOnlyPublicCentreValues() async {
    let observed = LockedBox<Set<Int>>([])
    await MainActor.run {
      _ = W3FB.raster(
        HStack(alignment: .center, spacing: 1) {
          Text("A").frame(width: 1, height: 2)
          Text("B").frame(width: 1, height: 3).alignmentGuide(VerticalAlignment.center) { d in
            observed.withLock { _ = $0.insert(d[VerticalAlignment.center]) }
            return d[VerticalAlignment.center]
          }
        }, "w3fb026")
    }
    let comment: Comment =
      "NEW-9: an alignment guide closure on a three-cell view reads d[.center] == 2 as well as the public 1, and a closure indexing a two-element array by d[.center] traps (SIGTRAP); explicit guide closures are evaluated a second time with the centre default rounded up (LayoutMetadata.swift:151-165, GeometryTypes.swift:440-470); contract: FW3-F report (public ViewDimensions values unchanged), GeometryTypes.swift:382-389; adjacent STUI-1242"
    w3fbKnown(comment) {
      // Contract: FW3-F report ("public ViewDimensions values ... unchanged");
      // GeometryTypes.swift:382-389 (the public centre is length / 2 truncated).
      #expect(observed.value == [1], "observed \(observed.value.sorted())")
    }
    await w3fbKnown(comment) {
      await w3fbExpectGuideClosureDoesNotTrap()
    }
  }

  // w3fb039 (FW3-F x FW3-G): an identity-guided trimmed fill places like the
  // unguided one.
  @Test func w3fb039IdentityGuidedTrimmedFillPlacesLikeUnguided() {
    let unguided = W3FB.raster(
      HStack(alignment: .center, spacing: 1) {
        Circle().trim(from: 0, to: 0.5).fill().frame(width: 6, height: 3)
        Text("x").frame(height: 2)
      }, "w3fb039-unguided", height: 4)
    let guided = W3FB.raster(
      HStack(alignment: .center, spacing: 1) {
        Circle().trim(from: 0, to: 0.5).fill().frame(width: 6, height: 3)
          .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] }
        Text("x").frame(height: 2)
      }, "w3fb039-guided", height: 4)
    #expect(guided == unguided, "guided \(guided) unguided \(unguided)")
  }
}

// MARK: - FW3-G: far paths, trims and capability detection

@MainActor
@Suite(.serialized)
struct Wave3HuntFBShapeTests {
  // w3fb027: a stroke of a finite unit path whose far point overflows the
  // subpixel scale still draws its in-frame part.
  @Test func w3fb027FarUnitPathStrokeDrawsItsInFramePart() throws {
    let near = W3FB.dotRows(
      W3FBPathShape(pathValue: W3FB.polyline([(0, 0.5), (1, 0.5), (2e307, 0.5)])).stroke(),
      "w3fb027-near")
    try #require(near == [[0, 0, 0, 0], [2, 2, 2, 2]], "\(near)")
    let far = W3FB.dotRows(
      W3FBPathShape(pathValue: W3FB.polyline([(0, 0.5), (1, 0.5), (3e307, 0.5)])).stroke(),
      "w3fb027-far")
    // STUI-1268 (repaired). Contract: the FW-E brief (a stroke draws the
    // visible part of any finite path), adopted by FW3-G for STUI-1245;
    // Path.swift:11-17.
    #expect(far == near, "far \(far)")
  }

  // w3fb028: a fill of a finite unit triangle with a far vertex paints the
  // cells its own Path contains.
  @Test func w3fb028FarUnitPathFillPaintsAndHitTestAgree() throws {
    func check(_ far: Double, _ name: String) -> (painted: Set<[Int]>, contained: Set<[Int]>) {
      var path = W3FB.polyline([(0, 0), (1, 0), (1, far)])
      path.closeSubpath()
      let painted = W3FB.paintedCells(W3FBPathShape(pathValue: path).fill(), name)
      let placed = path.scaledBy(sx: 4, sy: 2)
      var contained: Set<[Int]> = []
      for y in 0..<2 {
        for x in 0..<4 where placed.contains(Point(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
          contained.insert([x, y])
        }
      }
      return (painted, contained)
    }
    let near = check(2e307, "w3fb028-near")
    try #require(!near.painted.isEmpty && near.painted == near.contained, "\(near)")
    let far = check(3e307, "w3fb028-far")
    // STUI-1268 (repaired). Contract: Path.swift:11-17 (one Path for hit
    // testing and rendering); the FW-E brief (a finite path paints its
    // visible part).
    #expect(far.painted == far.contained && far.painted == near.painted, "\(far)")
  }

  // w3fb029 (STUI-1244 x STUI-1248): a far custom shape's trimmed public path
  // describes the outline its trimmed fill paints.
  @Test func w3fb029TrimmedFarCustomFillMatchesItsPublicPath() throws {
    let shape = W3FBPathShape(pathValue: W3FB.polyline([(0, 0), (1, 0), (1, 2e307)]))
    let path = shape.trim(from: 0, to: 0.5).path(
      in: Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 5)))
    var covered: Set<[Int]> = []
    for y in 0..<5 {
      for x in 0..<10 where path.contains(Point(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
        covered.insert([x, y])
      }
    }
    try #require(!covered.isEmpty, "the public path covers no cell")
    let painted = W3FB.paintedCells(
      shape.trim(from: 0, to: 0.5).fill(), "w3fb029", width: 10, height: 5)
    // STUI-1268 (repaired). Contract: ShapePayload.swift:130-134.
    #expect(painted == covered, "painted \(painted.count) covered \(covered.count)")
  }

  // w3fb030: the physical trim of a far quadratic curve keeps its outline.
  @Test func w3fb030PhysicalTrimOfFarCurveKeepsOutline() throws {
    let trimmed = W3FBFarCurveShape().trim(from: 0, to: 0.5).path(
      in: Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10)))
    let points = trimmed.flattened(tolerance: 0.5).flatMap { $0 }
    try #require(!points.isEmpty, "empty trim")
    #expect(points.first == Point(x: 0, y: 0), "\(points.prefix(3))")
    #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
  }

  // w3fb036: inset and nested analytic trims equal the painted route.
  @Test func w3fb036InsetAndNestedAnalyticTrimsMatchThePaintedRoute() {
    let aspect = RectangleStrokeTrack.snappedAspectRatio(CellPixelMetrics.estimated.aspectRatio)
    let rect = Rect(origin: Point(x: 1, y: 2), size: Size(width: 12, height: 5))
    let ellipse = Ellipse().inset(by: -1).trim(from: 0.2, to: 0.9).path(in: rect)
    let ellipseRoute = ShapeGeometry.trimmed(.ellipse, from: 0.2, to: 0.9).path(
      in: Rect(origin: Point(x: 0, y: 1), size: Size(width: 14, height: 7)),
      stretchingCircle: true, trimAspectRatio: aspect)
    #expect(ellipse == ellipseRoute)
    let wide = Rect(origin: Point(x: 0, y: 0), size: Size(width: 20, height: 6))
    let capsule = Capsule().trim(from: 0.25, to: 0.75).trim(from: 0, to: 0.5).path(in: wide)
    let capsuleRoute = ShapeGeometry.trimmed(.capsule, from: 0.25, to: 0.5).path(
      in: wide, stretchingCircle: true, trimAspectRatio: aspect)
    #expect(capsule == capsuleRoute)
  }
}

@Suite(.serialized)
struct Wave3HuntFBCapabilityTests {
  // w3fb034: an upper-case numbered direct xterm is generic, and a nonempty
  // TERM_PROGRAM outranks inherited markers.
  @Test func w3fb034NumberedDirectXtermUppercaseAndMultiplexerMarkers() {
    let upper = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "XTERM-DIRECT256", "WT_SESSION": "1"], isTTY: true)
    #expect(upper.supportsHyperlinks)
    #expect(upper.colorLevel == .trueColor)
    let tmux = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "xterm-direct16", "TERM_PROGRAM": "tmux", "VTE_VERSION": "7600"],
      isTTY: true)
    #expect(!tmux.supportsHyperlinks)
    #expect(tmux.colorLevel == .trueColor)
  }

  // w3fb035: a numbered direct xterm under iTerm2 is refined to iTerm2.
  @Test func w3fb035NumberedDirectXtermITermRefinement() {
    let profile = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "xterm-direct256", "TERM_PROGRAM": "iTerm.app"], isTTY: true)
    #expect(profile.supportsHyperlinks)
    #expect(profile.supportsSynchronizedOutput)
    #expect(profile.colorLevel == .trueColor)
  }
}

// MARK: - Cross-group

@MainActor
@Suite(.serialized)
struct Wave3HuntFBCrossTests {
  // w3fb037 (FW3-E x FW3-F): centre-guided three-line rows in a hidden-separator
  // List select by a click on the guided text.
  @Test func w3fb037GuidedTallRowsInHiddenSeparatorListSelect() throws {
    let box = W3FBSelection<String>(selected: "r050")
    let rows = W3FB.rows(100)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb037"), size: .init(width: 30, height: 40)
    ) {
      List(rows, id: \.id, selection: box.binding) { row in
        HStack(alignment: .center, spacing: 1) {
          Text("|").frame(height: 3)
          Text(row.id).alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] }
        }.listRowSeparator(.hidden)
      }.listStyle(.plain).scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    let lines = W3FB.lines(h.frame)
    let visible = W3FB.rowIDs(h.frame)
    try #require(visible.count >= 8, "\(h.frame)")
    let target = visible[visible.count - 2]
    let label = try #require(W3FB.position(of: target, in: lines))
    // The one-line bar is centred in its three-cell frame, on the middle line;
    // the guided label shares that line (corrections.md C3).
    #expect(lines[label.row].contains("|"), "\(h.frame)")
    let result = try W3FB.activateRow(h, id: target)
    #expect(result == .accepted, "\(target): \(result)")
    #expect(box.selected == target, "activated \(target)")
  }

  // w3fb038 (FW3-E x FW3-G): labelled List rows carry a trimmed-ellipse fill
  // whose trimmed path is its content shape, with a tap gesture. The disabled
  // row's selector is disabled and a click on its painted cell delivers no tap;
  // an enabled row's painted cell delivers one. (Shape-only rows publish no
  // list item, and a click selects no List row here: corrections.md C4.)
  @Test func w3fb038TrimmedContentShapeOnDisabledAndEnabledRows() throws {
    let box = W3FBSelection<Int>(selected: 1)
    let taps = W3FBTaps()
    let shapeRect = Rect(origin: Point(x: 0, y: 0), size: Size(width: 12, height: 2))
    let shapePath = Ellipse().trim(from: 0, to: 0.5).path(in: shapeRect)
    let painted = W3FB.paintedCells(
      Ellipse().trim(from: 0, to: 0.5).fill(), "w3fb038-shape", width: 12, height: 2)
    let cell = try #require(
      painted.filter { shapePath.contains(Point(x: Double($0[0]) + 0.5, y: Double($0[1]) + 0.5)) }
        .min { abs($0[0] - 6) + 4 * abs($0[1] - 1) < abs($1[0] - 6) + 4 * abs($1[1] - 1) })
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb038"), size: .init(width: 24, height: 10)
    ) {
      List([1, 2, 3], id: \.self, selection: box.binding) { i in
        HStack(spacing: 1) {
          Text("row\(i)")
          Ellipse().trim(from: 0, to: 0.5).fill()
            .contentShape(Ellipse().trim(from: 0, to: 0.5).path(in: shapeRect))
            .onTapGesture { taps.values.append(i) }
            .frame(width: 12, height: 2)
        }.disabled(i == 2)
      }
    }
    defer { h.shutdown() }
    let disabled = try W3FB.selector(h, 2)
    #expect(!disabled.isEnabled)
    #expect(try W3FB.selector(h, 3).isEnabled)
    func click(row: Int) throws {
      // The row content starts two cells after its selector; the shape follows
      // the four-cell label and one cell of spacing.
      let selector = try W3FB.selector(h, row)
      _ = try h.click(
        Point(
          x: Double(selector.rect.origin.x + 2 + 5 + cell[0]) + 0.5,
          y: Double(selector.rect.origin.y + cell[1]) + 0.5))
    }
    try click(row: 2)
    #expect(taps.values.isEmpty, "disabled row tapped: \(taps.values)")
    try click(row: 3)
    #expect(taps.values == [3], "painted cell \(cell): \(taps.values)\n\(h.frame)")
  }

  // w3fb040 (FW3-E x FW3-F): two centred lazy stacks sent to the bottom in one
  // action show their last rows and keep the eager column.
  @Test func w3fb040TwoCentredLazyStacksToBottomKeepEagerColumn() throws {
    let proxies = W3FBProxies()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w3fb040"), size: .init(width: 24, height: 9)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Button("jump") {
          for index in 0..<2 { _ = proxies.proxy(at: index)?.scrollTo(edge: .bottom) }
        }
        HStack(alignment: .top, spacing: 2) {
          ForEach(0..<2, id: \.self) { index in
            ScrollViewReader { proxy in
              let _ = proxies.store(proxy, at: index)
              ScrollView {
                LazyVStack(alignment: .center, spacing: 0) {
                  ForEach(0..<200, id: \.self) { i in
                    Text(i == 199 ? "e" : (i.isMultiple(of: 2) ? "abcd" : "x"))
                      .frame(height: i < 100 ? 1 : 2)
                  }
                }
              }.scrollIndicators(.hidden).frame(width: 10, height: 8)
            }
          }
        }
      }
    }
    defer { h.shutdown() }
    _ = try h.clickText("jump")
    let lines = W3FB.lines(h.frame)
    let halves = [lines.map { String($0.prefix(10)) }, lines.map { String($0.dropFirst(12)) }]
    for (index, half) in halves.enumerated() {
      #expect(half.contains { $0.contains("e") }, "view \(index):\n\(h.frame)")
      #expect(
        W3FB.relativeColumn(of: "x", to: "abcd", in: half) == 1, "view \(index):\n\(h.frame)")
    }
  }
}

/// w3fb026's exit test: a guide closure that indexes a two-element array by
/// `d[.center]`, valid for every public centre of a one- to three-cell view.
private func w3fbExpectGuideClosureDoesNotTrap() async {
  await #expect(processExitsWith: .success) {
    await MainActor.run {
      let offsets = [0, 1]
      _ = DefaultRenderer().render(
        HStack(alignment: .center, spacing: 1) {
          Text("A").frame(width: 1, height: 2)
          Text("B").frame(width: 1, height: 3).alignmentGuide(VerticalAlignment.center) { d in
            offsets[d[VerticalAlignment.center]]
          }
        }, context: .init(identity: testIdentity("w3fb026-exit")),
        proposal: .init(width: 10, height: 4))
    }
  }
}

// MARK: - Fixtures

private struct W3FBRow: Identifiable, Hashable, Sendable {
  var id: String
}

@MainActor
private final class W3FBSelection<Value: Hashable & Sendable> {
  var selected: Value?
  init(selected: Value?) { self.selected = selected }
  var binding: Binding<Value?> { .init(get: { self.selected }, set: { self.selected = $0 }) }
}

@MainActor
private final class W3FBMultiSelection {
  var selected: Set<Int> = []
  var binding: Binding<Set<Int>> { .init(get: { self.selected }, set: { self.selected = $0 }) }
}

@MainActor
private final class W3FBTaps {
  var values: [Int] = []
}

@MainActor
private final class W3FBToggle {
  var disabled = false
}

@MainActor
private final class W3FBRows {
  var ids: [String]
  init(ids: [String]) { self.ids = ids }
}

private struct W3FBOutlineRecord: Identifiable, Hashable, Sendable {
  let id: Int
  var children: [W3FBOutlineRecord]?
}

@MainActor
private final class W3FBProxies {
  private var proxies: [Int: ScrollViewProxy] = [:]
  func store(_ proxy: ScrollViewProxy, at index: Int) { proxies[index] = proxy }
  func proxy(at index: Int) -> ScrollViewProxy? { proxies[index] }
  var first: ScrollViewProxy? { proxies[0] }
}

@MainActor
private final class W3FBCaptureLog<Value> {
  struct Entry {
    var read: () -> Value
    var write: (Value) -> Void
  }
  let label: String
  var entries: [Entry] = []
  init(label: String = "") { self.label = label }
}

private struct W3FBCounterLeaf: View {
  @State private var value = 0
  let log: W3FBCaptureLog<Int>
  var body: some View {
    log.entries.append(.init(read: { value }, write: { value = $0 }))
    return Text("\(log.label)v\(value)")
  }
}

private struct W3FBSnapshotCounter: View {
  @State private var count = 0
  var body: some View {
    Button("Count \(count)") { count += 1 }
  }
}

private struct W3FBBindingParent: View {
  @State private var count = 0
  var body: some View {
    W3FBBindingChild(count: $count)
  }
}

private struct W3FBBindingChild: View {
  @Binding var count: Int
  var body: some View {
    Button("Count \(count)") { count += 1 }
  }
}

/// Lazy rows that reuse the same counter view instances, so each row's state
/// box is the same across snapshots (State-Keying.md:160-163: continuity is
/// for "reusing one view instance").
private struct W3FBLazyCounters: View {
  let counters = [W3FBSnapshotCounter(), W3FBSnapshotCounter(), W3FBSnapshotCounter()]
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<3, id: \.self) { index in counters[index] }
      }
    }.frame(width: 20, height: 5)
  }
}

private enum W3FBMidX: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int {
    context[HorizontalAlignment.center]
  }
}

extension HorizontalAlignment {
  fileprivate static let w3fbMidX = HorizontalAlignment(W3FBMidX.self)
}

/// Sizes to its single subview and forwards the subview's guides, as a
/// SwiftUI container that wraps one view without moving it would.
private struct W3FBForwardingLayout: Layout {
  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    subviews.first?.sizeThatFits(proposal) ?? .zero
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    for subview in subviews {
      subview.place(at: bounds.origin, proposal: proposal)
    }
  }

  func explicitAlignment(
    of guide: VerticalAlignment,
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> Int? {
    subviews.first.map { bounds.origin.y + $0.dimensions(in: proposal)[guide] }
  }
}

/// A custom shape defined only by normalized unit-rect geometry.
private struct W3FBPathShape: InsettableShape {
  var pathValue: Path
  var geometry: ShapeGeometry { .path(BoxedPath(pathValue), .nonZero) }
}

/// A custom shape whose own `path(in:)` holds a far quadratic curve.
private struct W3FBFarCurveShape: Shape {
  func path(in rect: Rect) -> Path {
    var path = Path()
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: rect.origin.x + 10, y: rect.origin.y))
    path.addQuadCurve(to: Point(x: rect.origin.x + 10, y: 1e308), control: Point(x: 0, y: 1e308))
    return path
  }
}

@MainActor
private enum W3FB {
  static func paddedID(_ index: Int) -> String {
    let digits = String(index)
    return "r" + String(repeating: "0", count: max(0, 3 - digits.count)) + digits
  }

  static func rows(_ count: Int) -> [W3FBRow] {
    (0..<count).map { W3FBRow(id: paddedID($0)) }
  }

  static func bandTable(
    _ name: String, box: W3FBSelection<String>, hidden: Bool, height: Int
  ) throws -> StressRuntimeHarness<some View> {
    let rows = rows(200)
    return try StressRuntimeHarness(
      rootIdentity: testIdentity(name), size: .init(width: 30, height: height)
    ) {
      Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
        if hidden {
          Text(row.id).listRowSeparator(.hidden)
        } else {
          Text(row.id)
        }
      }.tableHeaders(.hidden).scrollIndicators(.hidden)
    }
  }

  /// Two review pages before one frame: the rows the first frame showed and
  /// the review position after the pages.
  static func reviewTwoPagesBeforeOneFrame(_ name: String, hidden: Bool) throws -> (
    visible: Int, value: AccessibilityValue?
  ) {
    let box = W3FBSelection<String>(selected: "r000")
    let h = try bandTable(name, box: box, hidden: hidden, height: 24)
    defer { h.shutdown() }
    let visible = rowIDs(h.frame)
    try #require(visible.first == "r000" && visible.count >= 8, "\(h.frame)")
    let target = try #require(try review(h).actionTarget)
    for _ in 0..<2 {
      #expect(
        h.runLoop.handleAccessibilityAction(.init(target: target, action: .custom("Next page")))
          == .accepted)
    }
    _ = try h.render()
    return (visible.count, try review(h).control?.value)
  }

  static func review<V: View>(_ h: StressRuntimeHarness<V>) throws -> AccessibilityNode {
    try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Review items"
      })
  }

  static func selector<V: View>(_ h: StressRuntimeHarness<V>, _ row: Int) throws
    -> AccessibilityNode
  {
    try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Select row \(row)"
      }, "\(h.frame)")
  }

  /// Row ids `r000`…`r199` in frame order.
  static func rowIDs(_ frame: String) -> [String] {
    var ids: [String] = []
    for line in frame.split(separator: "\n") {
      let tokens = line.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      if let token = tokens.first(where: { token in
        token.count == 4 && token.first == "r" && token.dropFirst().allSatisfy(\.isNumber)
      }) {
        ids.append(String(token))
      }
    }
    return ids
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

  static func focusRegionsWithReleasedRenderer<V: View>(
    _ view: V, registry: LocalActionRegistry, name: String
  ) -> [Identity] {
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity(name), localActionRegistry: registry,
        applyEnvironmentValues: true))
    return artifacts.semanticSnapshot.focusRegions.map(\.identity)
  }

  /// Activates `Select row N` for the row id `rNNN` through the assistive path.
  static func activateRow<V: View>(_ h: StressRuntimeHarness<V>, id: String) throws
    -> AccessibilityActionResult
  {
    let row = try #require(Int(id.dropFirst())) + 1
    let target = try #require(try selector(h, row).actionTarget)
    let result = h.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
    _ = try h.render()
    return result
  }

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

  static func raster<V: View>(_ view: V, _ name: String, width: Int = 10, height: Int = 5)
    -> [String]
  {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("W3FB", name)),
      proposal: .init(width: width, height: height)
    ).rasterSurface.lines.map { line in
      var trimmed = line
      while trimmed.last == " " { trimmed.removeLast() }
      return trimmed
    }
  }

  static func lines(_ frame: String) -> [String] {
    frame.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }

  static func position(of text: String, in lines: [String]) -> (row: Int, column: Int)? {
    for (row, line) in lines.enumerated() {
      if let range = line.range(of: text) {
        return (row, line.distance(from: line.startIndex, to: range.lowerBound))
      }
    }
    return nil
  }

  /// The column of `text` minus the column of `reference`, each the first line
  /// whose trimmed content is exactly that text.
  static func relativeColumn(of text: String, to reference: String, in lines: [String]) -> Int? {
    func column(_ token: String) -> Int? {
      for line in lines where line.trimmingCharacters(in: .whitespaces) == token {
        return line.distance(
          from: line.startIndex, to: line.firstIndex { $0 != " " } ?? line.startIndex)
      }
      return nil
    }
    guard let a = column(text), let b = column(reference) else { return nil }
    return a - b
  }

  @ViewBuilder
  static func frameChild(oddFrame: Bool) -> some View {
    if oddFrame {
      Text("B").frame(width: 1, height: 2)
    } else {
      Text("B")
    }
  }

  static func polyline(_ points: [(Double, Double)]) -> Path {
    var path = Path()
    for (index, point) in points.enumerated() {
      let p = Point(x: point.0, y: point.1)
      if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    return path
  }

  static func brailleDots(_ cell: RasterCell) -> Int {
    guard let scalar = cell.character.unicodeScalars.first?.value, scalar >= 0x2800,
      scalar <= 0x28FF
    else {
      return 0
    }
    return Int(scalar - 0x2800).nonzeroBitCount
  }

  /// Renders a 4 x 2 cell frame and returns the Braille dot count of each cell.
  static func dotRows(_ view: some View, _ name: String) -> [[Int]] {
    let snapshot = DefaultRenderer().render(
      view.frame(width: 4, height: 2), context: .init(identity: testIdentity("W3FB", name)))
    return snapshot.rasterSurface.cells.map { $0.map(brailleDots) }
  }

  /// The cells of a `width` x `height` frame that hold any glyph.
  static func paintedCells(_ view: some View, _ name: String, width: Int = 4, height: Int = 2)
    -> Set<[Int]>
  {
    let snapshot = DefaultRenderer().render(
      view.frame(width: width, height: height),
      context: .init(identity: testIdentity("W3FB", name)),
      proposal: .init(width: width, height: height))
    var painted: Set<[Int]> = []
    for (y, row) in snapshot.rasterSurface.cells.enumerated() where y < height {
      for (x, cell) in row.enumerated() where x < width && cell.character != " " {
        painted.insert([x, y])
      }
    }
    return painted
  }
}
