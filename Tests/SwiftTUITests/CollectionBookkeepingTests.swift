import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage S4 of the scroll-currency program (root plan
/// `docs/plans/2026-07-28-007-collection-scroll-currency-plan.md`): retire the
/// O(dataset) resolve-side bookkeeping (register item D18), size the
/// interaction band from live viewport geometry (D20), and make the eager
/// builder fork observable (D22).
@MainActor
@Suite(.serialized)
struct CollectionBookkeepingTests {
  @Test("T-40: every row visible on a tall viewport is registered")
  func tallViewportRegistersEveryVisibleRow() throws {
    // Flipped from C-05, which pinned rows plainly on screen having no
    // registered handler because the band was a fixed 64 indices.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BandFromGeometry"),
      size: .init(width: 24, height: 120)
    ) {
      TallViewportList()
    }
    defer { harness.shutdown() }

    // Scroll geometry is published from the committed frame, so the band can
    // only be sized from it on a LATER resolve. One wheel tick both syncs the
    // geometry and forces that resolve.
    let listPoint = try #require(harness.point(forText: "«1»"))
    _ = try harness.scrollPointer(at: listPoint, deltaY: 1)
    let listIdentity = try #require(
      harness.runLoop.latestSemanticSnapshot.scrollRoutes
        .map(\.identity)
        .first { $0.description.contains("BandFromGeometry") }
    )
    let registered = Set(harness.runLoop.localActionRegistry.snapshot().keys)
    let visibleRows = bookkeepingRows(harness.frame)
    #expect(visibleRows.count > 64, "the fixture must exceed the old fixed band")

    for row in visibleRows {
      #expect(
        registered.contains(listRowIdentity(for: listIdentity, rowIndex: row)),
        "row \(row) is on screen but has no registered action"
      )
    }
  }

  @Test("T-41: locating the focused row mints no identities")
  func focusedRowLookupMintsNothing() {
    // The focused row used to be found by minting a row identity per index
    // until one matched the focused identity — `explicitID` runs
    // `String(reflecting:)` plus per-character escaping every call.
    let container = testIdentity("MintFree")
    let identity = listRowIdentity(for: container, rowIndex: 4_321)

    #expect(listRowIndex(parsedFrom: identity, container: container) == 4_321)
    #expect(listRowIndex(parsedFrom: container, container: container) == nil)
    #expect(
      listRowIndex(parsedFrom: identity, container: testIdentity("Other")) == nil,
      "a row of a different collection must not resolve"
    )
  }

  @Test("T-43: the parsed row index round-trips its identity")
  func rowIndexRoundTrips() {
    let container = testIdentity("RoundTrip", "Inner")
    for row in [0, 1, 7, 63, 64, 999, 10_000] {
      let identity = listRowIdentity(for: container, rowIndex: row)
      #expect(listRowIndex(parsedFrom: identity, container: container) == row)
    }
    for row in [0, 5, 512] {
      let identity = tableRowIdentity(for: container, rowIndex: row)
      #expect(tableRowIndex(parsedFrom: identity, container: container) == row)
      #expect(
        listRowIndex(parsedFrom: identity, container: container) == nil,
        "a table row must not parse as a list row"
      )
    }
  }

  @Test("T-42: locating the selected row does not consult every row")
  func selectedRowLookupIsIndexed() {
    // The selected row used to be found by asking the policy about each row's
    // tag in turn — a dynamic cast plus a binding read per row, on the resolve
    // path of every frame. It is now one hash lookup in the source's id index,
    // which the narrowed `SelectionValue: Hashable & Sendable` made possible.
    CollectionSelectionProbe.reset()
    _ = DefaultRenderer().render(
      List(0..<2_000, id: \.self, selection: .constant(1_900 as Int?)) { row in
        Text("row \(row)")
      },
      context: .init(identity: testIdentity("IndexedSelection"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(10))
    )
    let windowed = CollectionSelectionProbe.membershipTests

    // The eager spelling of the same collection has no id index to consult,
    // so it still asks about every row — the contrast is the measurement.
    CollectionSelectionProbe.reset()
    _ = DefaultRenderer().render(
      List(selection: .constant(1_900 as Int?)) {
        ForEach(0..<2_000, id: \.self) { row in
          Text("row \(row)").tag(row)
        }
      },
      context: .init(identity: testIdentity("EagerSelection"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(10))
    )
    let eager = CollectionSelectionProbe.membershipTests

    #expect(eager > 1_000, "the eager path scans until it matches, as it always has: \(eager)")
    #expect(
      windowed == 0,
      """
      the windowed path locates the selection by id and asks about no row at       all, but asked about \(windowed) (eager asked about \(eager))
      """
    )
  }

  @Test("T-45: an eagerly-resolved large collection reports the fork")
  func eagerLargeCollectionIsReported() {
    let large = DefaultRenderer().render(
      List {
        ForEach(0..<300, id: \.self) { row in
          Text("row \(row)").tag(row)
        }
      },
      context: .init(identity: testIdentity("EagerLarge"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(10))
    )
    let small = DefaultRenderer().render(
      List {
        ForEach(0..<100, id: \.self) { row in
          Text("row \(row)").tag(row)
        }
      },
      context: .init(identity: testIdentity("EagerSmall"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(10))
    )
    let windowed = DefaultRenderer().render(
      List(0..<300, id: \.self) { row in
        Text("row \(row)")
      },
      context: .init(identity: testIdentity("WindowedLarge"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(10))
    )

    func reportsFork(_ artifacts: RenderSnapshot) -> Bool {
      artifacts.diagnostics.runtime.issues.map(\.code).contains("collection.eagerLargeCollection")
    }
    #expect(reportsFork(large))
    #expect(!reportsFork(small), "below the threshold the fork is not worth reporting")
    #expect(!reportsFork(windowed), "the data-source spelling is already windowed")
  }

  @Test("T-46: with no synced geometry the band falls back to a fixed 64")
  func bandFallsBackWithoutGeometry() {
    let listIdentity = testIdentity("BandFallback")
    let actions = LocalActionRegistry()
    _ = DefaultRenderer().render(
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

    // A one-shot render publishes no scroll route, so there is no viewport to
    // size against and the historical capacity stands. One frame of
    // imprecision, self-correcting.
    let registered = Set(actions.snapshot().keys)
    let rowIdentities = (0..<500).map { listRowIdentity(for: listIdentity, rowIndex: $0) }
    let registeredRowCount = rowIdentities.filter(registered.contains).count
    #expect(registeredRowCount == collectionInteractionFallbackCapacity)
  }
}

@MainActor
private struct TallViewportList: View {
  @State private var selection: Int? = 0

  var body: some View {
    List(0..<500, id: \.self, selection: $selection) { row in
      Text("«\(row)»")
    }
    .frame(height: 118)
  }
}

private func bookkeepingRows(_ surface: String) -> Set<Int> {
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
