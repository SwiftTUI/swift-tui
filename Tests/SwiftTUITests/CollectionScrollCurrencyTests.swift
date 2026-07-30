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
    #expect(payload.scrollAnchorRowIndex == nil)
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
}

// MARK: - Fixtures

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
