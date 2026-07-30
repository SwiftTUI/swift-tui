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

  // MARK: - C-09 — the eager builder fork (D22)

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
