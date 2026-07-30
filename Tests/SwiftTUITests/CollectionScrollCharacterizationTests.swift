import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Characterization suite for the scroll-currency program (root plan
/// `docs/plans/2026-07-28-007-collection-scroll-currency-plan.md`, Stage S0).
///
/// Every row here pins *current* behaviour — including the current defects the
/// program exists to fix — so a later stage flips a row deliberately rather
/// than discovering the change as fixture churn. The `C-nn` ids match the S0
/// table in the plan; the "flipped by" column names the stage that retires the
/// row.
@MainActor
@Suite(.serialized)
struct CollectionScrollCharacterizationTests {
  // MARK: - C-01 / C-02 / C-03 — the window IS the selection (D16)

  @Test("C-01: a viewport-backed List re-centres its window on every selection change")
  func windowRecentresOnSelectionChange() throws {
    // Flipped by S1: selection moves inside the window must not scroll, and a
    // move outside must scroll only far enough to reveal.
    let atTop = characterizationRows(
      renderingSelectableList(rowCount: 100, selection: 0, viewportHeight: 10)
    )
    let atMiddle = characterizationRows(
      renderingSelectableList(rowCount: 100, selection: 50, viewportHeight: 10)
    )

    #expect(atTop.contains(0))
    #expect(!atTop.contains(50))
    // The window is *centred* on the selection rather than minimally adjusted:
    // moving selection from 0 to 50 drags the whole viewport with it.
    #expect(atMiddle.contains(50))
    #expect(!atMiddle.contains(0))
    let middleLow = try #require(atMiddle.min())
    #expect(middleLow > 40, "window is centred on the selection, not merely revealing it")
  }

  @Test("C-02: a wheel tick over a selectable viewport-backed List steps the selection")
  func wheelStepsSelection() throws {
    // Flipped by S1: the wheel scrolls the window and leaves selection alone.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CharWheelSelection"),
      size: .init(width: 30, height: 14)
    ) {
      SelectableCharacterizationList()
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("sel=0"))
    let listPoint = try #require(harness.point(forText: "«0»"))
    _ = try harness.scrollPointer(at: listPoint, deltaY: 1)

    #expect(
      harness.frame.contains("sel=1"),
      "current behaviour: the wheel is wired to `policy.step`, so it moves the selection"
    )
  }

  @Test("C-03: a non-selectable indexed List is pinned to its first screenful")
  func nonSelectableListCannotScroll() throws {
    // Flipped by S1: wheel + PageDown/End reveal every row.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CharNonSelectable"),
      size: .init(width: 30, height: 12)
    ) {
      NonSelectableCharacterizationList()
    }
    defer { harness.shutdown() }

    let firstFrame = harness.frame
    #expect(firstFrame.contains("«0»"))
    let listPoint = try #require(harness.point(forText: "«0»"))

    for _ in 0..<5 {
      _ = try harness.scrollPointer(at: listPoint, deltaY: 1)
    }
    #expect(
      harness.frame.contains("«0»"),
      "current behaviour: no scroll registration exists for a non-selectable collection"
    )

    _ = try harness.pressKey(KeyPress(.pageDown))
    _ = try harness.pressKey(KeyPress(.end))
    #expect(
      harness.frame.contains("«0»"),
      "current behaviour: PageDown/End are unhandled over a collection"
    )
    #expect(!harness.frame.contains("«9999»"))
  }

  @Test("C-04: ScrollViewProxy.scrollTo(id) is a no-op over a viewport-backed List")
  func scrollToIsNoOpOverCollections() throws {
    // Flipped by S1: the collection registers a scroll position, so the
    // registry can find a route + registration for it.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CharScrollTo"),
      size: .init(width: 30, height: 12)
    ) {
      ScrollToCharacterizationList()
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("«0»"))
    _ = try harness.clickText("Jump")

    #expect(
      harness.frame.contains("result=false"),
      "current behaviour: `scrollToTarget` finds no registration for a collection identity"
    )
    #expect(!harness.frame.contains("«500»"))
  }

  // MARK: - C-05 — the fixed 64-row interaction band (D20)

  @Test("C-05: a visible row outside the fixed 64-index band registers no action")
  func rowsOutsideTheInteractionBandAreInert() {
    // Flipped by S4: the band is sized from live viewport geometry.
    let listIdentity = testIdentity("CharBand")
    let actions = LocalActionRegistry()
    let artifacts = DefaultRenderer().render(
      List(0..<500, id: \.self, selection: .constant(0 as Int?)) { row in
        Text("«\(row)»")
      },
      context: .init(
        identity: listIdentity,
        localActionRegistry: actions,
        applyEnvironmentValues: false
      ),
      proposal: .init(width: .finite(20), height: .finite(120))
    )

    // Row 100 is inside the drawn window on a 120-line viewport...
    let visible = characterizationRows(artifacts)
    #expect(visible.contains(100))
    // ...but outside `collectionInteractionIndices(count:anchor:capacity: 64)`, so
    // resolve never registers an action for it. Asserted against the registry's
    // published set rather than by dispatching: a real dispatch miss is a
    // soundness-trace signal, and this row pins a *registration* gap.
    let registered = Set(actions.snapshot().keys)
    #expect(registered.contains(listRowIdentity(for: listIdentity, rowIndex: 10)))
    #expect(
      !registered.contains(listRowIdentity(for: listIdentity, rowIndex: 100)),
      "current behaviour: resolve registers row handlers only for a 64-index band"
    )
  }

  // MARK: - C-06 — phase disagreement on tall rows (D19)

  @Test("C-06: a 2-line hosted row leaves the selection marker misaligned with its content")
  func tallRowChromeDisagreesWithContent() throws {
    // Flipped by S3: one carried, height-aware layout product for all phases.
    let artifacts = DefaultRenderer().render(
      List(0..<3, id: \.self, selection: .constant(1 as Int?)) { row in
        VStack(alignment: .leading, spacing: 0) {
          Text("«\(row)»a")
          Text("«\(row)»b")
        }
      },
      context: .init(identity: testIdentity("CharTallRow"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    let lines = artifacts.rasterSurface.lines
    let surface = lines.joined(separator: "\n")
    let markerLine = try #require(
      lines.firstIndex { $0.contains("▌") },
      "no selection marker in:\n\(surface)"
    )
    let firstRowLine = try #require(lines.firstIndex { $0.contains("«0»a") })
    let selectedRowLine = try #require(lines.firstIndex { $0.contains("«1»a") })

    // Placement advances hosted children by `additionalYOffset` so a 2-line
    // row really occupies 2 cells, but `ListDisplayLine` has no height concept:
    // draw paints the marker at `contentBounds.y + lineIndex` with height 1.
    // For the selected row 1 the two conventions differ by exactly the extra
    // cell row 0 consumed.
    #expect(selectedRowLine - firstRowLine == 2, "content advances 2 cells per 2-line row")
    #expect(
      markerLine == selectedRowLine - 1,
      """
      current behaviour: the marker for row 1 is painted one cell ABOVE its \
      content, because the line model counts row 0 as a single line. Surface:
      \(surface)
      """
    )
  }

  // MARK: - C-07 / C-09 — realization cliffs (D17, D22)

  @Test("C-07: ScrollView { List } collapses to full-dataset realization")
  func nonFiniteProposalRealizesEverything() {
    // Flipped by S2: the measure viewport hint bounds the window.
    IndexedChildRealizationProbe.reset()
    _ = DefaultRenderer().render(
      ScrollView {
        List(0..<2_000, id: \.self) { row in
          Text("«\(row)»")
        }
      },
      context: .init(identity: testIdentity("CharScrollViewList"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    #expect(
      IndexedChildRealizationProbe.realizedChildCount == 2_000,
      """
      current behaviour: `hostedCollectionWindow` returns `0..<count` for a \
      non-finite height proposal, realized \
      \(IndexedChildRealizationProbe.realizedChildCount) rows
      """
    )
  }

  @Test("C-09: List { ForEach(...) } silently takes the eager, unwindowed path")
  func builderSpelledListIsEager() {
    // Kept by S4, which adds an observability RuntimeIssue for the fork.
    IndexedChildRealizationProbe.reset()
    let artifacts = DefaultRenderer().render(
      List {
        ForEach(0..<2_000, id: \.self) { row in
          Text("«\(row)»")
        }
      },
      context: .init(identity: testIdentity("CharBuilderList"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    #expect(artifacts.resolvedTree.indexedChildSource == nil)
    #expect(
      IndexedChildRealizationProbe.realizedChildCount == 2_000,
      """
      current behaviour: `usesIndexedDataSource` is false for the builder \
      spelling, so recognition never runs; realized \
      \(IndexedChildRealizationProbe.realizedChildCount) rows
      """
    )
  }

  // MARK: - C-08 — the table column-width ratchet (D21)

  @Test("C-08: viewport-backed Table column widths never shrink for a stable id set")
  func tableColumnWidthsRatchet() throws {
    // Kept by S4, which documents the contract and removes the second
    // realize+measure pass.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CharTableRatchet"),
      size: .init(width: 60, height: 12)
    ) {
      RatchetCharacterizationTable()
    }
    defer { harness.shutdown() }

    let narrowWidth = try #require(characterizationTailColumn(harness.frame))
    _ = try harness.clickText("Widen")
    let wideWidth = try #require(characterizationTailColumn(harness.frame))
    #expect(wideWidth > narrowWidth, "a wide cell entering the window grows the column")

    _ = try harness.clickText("Narrow")
    let afterWidth = try #require(characterizationTailColumn(harness.frame))
    #expect(
      afterWidth == wideWidth,
      "current behaviour: `zip(retained, discovered).map(max)` is grow-only for a stable id set"
    )
  }
}

// MARK: - Fixtures

@MainActor
private struct SelectableCharacterizationList: View {
  @State private var selection: Int? = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("sel=\(selection ?? -1)")
      List(0..<100, id: \.self, selection: $selection) { row in
        Text("«\(row)»")
      }
      .frame(height: 10)
    }
  }
}

@MainActor
private struct NonSelectableCharacterizationList: View {
  var body: some View {
    List(0..<10_000, id: \.self) { row in
      Text("«\(row)»")
    }
    .frame(height: 10)
  }
}

@MainActor
private struct ScrollToCharacterizationList: View {
  @State private var result = "none"

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Text("result=\(result)")
        Button("Jump") {
          result = proxy.scrollTo(500) ? "true" : "false"
        }
        List(0..<1_000, id: \.self) { row in
          Text("«\(row)»")
        }
        .frame(height: 8)
      }
    }
  }
}

@MainActor
private struct RatchetCharacterizationTable: View {
  @State private var selection: Int? = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Widen") { selection = 30 }
      Button("Narrow") { selection = 0 }
      Table(
        0..<40,
        id: \.self,
        selection: $selection,
        columns: [.init("Value"), .init("Tail")]
      ) { index in
        Text(index == 30 ? "wide-value-0000000" : "x")
        Text("t\(index)")
      }
      .frame(height: 6)
    }
  }
}

// MARK: - Support

/// The `«n»`-delimited row indices visible in a rendered surface. The
/// delimiters keep `«5»` from matching inside `«50»`.
@MainActor
private func characterizationRows(
  _ artifacts: RenderSnapshot
) -> Set<Int> {
  characterizationRows(artifacts.rasterSurface.lines.joined(separator: "\n"))
}

private func characterizationRows(
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

/// The rendered width of the ratchet table's second ("Tail") column, measured
/// from the header line's leading run of the first column.
private func characterizationTailColumn(
  _ surface: String
) -> Int? {
  guard
    let header = surface.split(separator: "\n", omittingEmptySubsequences: false)
      .first(where: { $0.contains("Value") && $0.contains("Tail") })
  else {
    return nil
  }
  let characters = Array(header)
  guard let valueStart = characterizationOffset(of: "Value", in: characters),
    let tailStart = characterizationOffset(of: "Tail", in: characters)
  else {
    return nil
  }
  return tailStart - valueStart
}

private func characterizationOffset(
  of needle: String,
  in characters: [Character]
) -> Int? {
  let target = Array(needle)
  guard !target.isEmpty, characters.count >= target.count else {
    return nil
  }
  for start in 0...(characters.count - target.count)
  where Array(characters[start..<(start + target.count)]) == target {
    return start
  }
  return nil
}

@MainActor
private func renderingSelectableList(
  rowCount: Int,
  selection: Int,
  viewportHeight: Int
) -> RenderSnapshot {
  DefaultRenderer().render(
    List(0..<rowCount, id: \.self, selection: .constant(selection as Int?)) { row in
      Text("«\(row)»")
    },
    context: .init(
      identity: testIdentity("CharSelectableList", "\(selection)"),
      applyEnvironmentValues: false
    ),
    proposal: .init(width: .finite(20), height: .finite(viewportHeight))
  )
}
