import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Scroll-latency R4-A: the hosted-collection resolve reuses — the
/// integer-range id-space witness (O(1) artifact verification for
/// `Range`-shaped `ForEach` sources) and the retained row-selection snapshot
/// (the `List` route's previously O(dataset)-per-resolve rows array).
///
/// The probes only count in DEBUG, so the engagement oracles are
/// DEBUG-conditional; the behavioral pins (scrolling, selection stepping,
/// bounds-change refresh) run everywhere.
@MainActor
@Suite(.serialized)
struct CollectionResolveReuseTests {
  @Test("witness detection: range shapes with the identity keypath, nothing else")
  func integerRangeWitnessDetection() {
    #expect(
      integerRangeIDWitness(data: 3..<10, id: \Int.self)
        == IntegerRangeIDWitness(lowerBound: 3, count: 7)
    )
    #expect(
      integerRangeIDWitness(data: 0...4, id: \Int.self)
        == IntegerRangeIDWitness(lowerBound: 0, count: 5)
    )
    // `\Int.hashValue` is also `KeyPath<Int, Int>` — the identity-keypath
    // equality check must reject it, or ids would be "verified" against a
    // different id derivation.
    #expect(integerRangeIDWitness(data: 0..<5, id: \Int.hashValue) == nil)
    // Materialized arrays carry no bounds proof: element-wise stays.
    #expect(integerRangeIDWitness(data: Array(0..<5), id: \Int.self) == nil)
    // Non-integer elements cannot match the `KeyPath<Int, Int>` cast.
    #expect(integerRangeIDWitness(data: ["a", "b"], id: \String.self) == nil)
  }

  @Test("wheel notches over a range-backed List adopt through the witness")
  func rangeWitnessAdoptionEngagesOnWheelNotches() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ResolveReuseNotch"),
      size: .init(width: 30, height: 12)
    ) {
      ReuseProbeList()
    }
    defer { harness.shutdown() }

    let listPoint = try #require(harness.point(forText: "«0»"))
    // Warm the artifacts (first resolve fresh-mints), then measure notches.
    _ = try harness.scrollPointer(at: listPoint, deltaY: 1)
    IndexedChildSourceArtifactsProbe.reset()

    for _ in 0..<3 {
      _ = try harness.scrollPointer(at: listPoint, deltaY: 1)
    }
    #expect(
      scrollCurrencyRowMarkers(harness.frame).contains(4),
      "the wheel really scrolled the window:\n\(harness.frame)"
    )
    #if DEBUG
      #expect(
        IndexedChildSourceArtifactsProbe.rangeWitnessAdoptionCount > 0,
        "per-notch List body re-resolves must adopt via the O(1) range witness"
      )
      #expect(
        IndexedChildSourceArtifactsProbe.freshMintCount == 0,
        "unchanged range data must never fresh-mint identity artifacts mid-scroll"
      )
      #expect(
        IndexedChildSourceArtifactsProbe.rowSelectionReuseCount > 0,
        "the List row-selection snapshot must be served from the retained artifacts"
      )
    #endif
  }

  @Test("a range bounds change refreshes the artifacts and the visible rows")
  func rangeBoundsChangeRefreshesArtifacts() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ResolveReuseBoundsChange"),
      size: .init(width: 30, height: 12)
    ) {
      ShiftingRangeList()
    }
    defer { harness.shutdown() }

    #expect(scrollCurrencyRowMarkers(harness.frame).contains(0))
    IndexedChildSourceArtifactsProbe.reset()

    _ = try harness.clickText("Shift")
    let shifted = scrollCurrencyRowMarkers(harness.frame)
    #expect(
      !shifted.contains(0) && shifted.contains(5),
      "shifting the range to 5..<55 must re-derive rows from the new bounds:\n\(harness.frame)"
    )
    #if DEBUG
      #expect(
        IndexedChildSourceArtifactsProbe.freshMintCount > 0,
        "changed range bounds must invalidate the retained identity artifacts"
      )
    #endif

    IndexedChildSourceArtifactsProbe.reset()
    _ = try harness.clickText("Shrink")
    let shrunk = scrollCurrencyRowMarkers(harness.frame)
    #expect(
      shrunk.contains(5),
      "the shrunk range keeps its lower bound:\n\(harness.frame)"
    )
    #if DEBUG
      #expect(
        IndexedChildSourceArtifactsProbe.freshMintCount > 0,
        "a shrunk range (same lower bound, changed count) must also re-mint"
      )
    #endif
  }

  @Test("selection steps against the reused row snapshot")
  func selectionStepsAgainstReusedRowSnapshot() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ResolveReuseSelection"),
      size: .init(width: 30, height: 14)
    ) {
      SelectableReuseList()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("«0»")
    #expect(harness.frame.contains("sel=0"))

    // Arrow stepping indexes the (reused) rows array by row and hands its
    // tags to the policy — the exact consumer the cache must not corrupt.
    // The click frame minted/adopted the artifacts; these re-resolves reuse.
    IndexedChildSourceArtifactsProbe.reset()
    _ = try harness.pressKey(KeyPress(.arrowDown))
    #expect(
      harness.frame.contains("sel=1"),
      "selection stepping must work against the reused snapshot:\n\(harness.frame)"
    )
    _ = try harness.pressKey(KeyPress(.arrowDown))
    #expect(harness.frame.contains("sel=2"))
    #if DEBUG
      #expect(
        IndexedChildSourceArtifactsProbe.rowSelectionReuseCount > 0,
        "a selectable list's row snapshot must also reuse (tags included)"
      )
      #expect(
        IndexedChildSourceArtifactsProbe.freshMintCount == 0,
        "selection stepping must not re-mint identity artifacts"
      )
    #endif

    // The wheel moves the window and leaves the (reused) selection alone.
    let listPoint = try #require(harness.point(forText: "«3»"))
    for _ in 0..<4 {
      _ = try harness.scrollPointer(at: listPoint, deltaY: 1)
    }
    #expect(
      harness.frame.contains("sel=2"),
      "the wheel leaves the selection alone:\n\(harness.frame)"
    )
  }
}

@MainActor
private struct ReuseProbeList: View {
  var body: some View {
    List(0..<200, id: \.self) { row in
      Text("«\(row)»")
    }
    .frame(height: 10)
  }
}

@MainActor
private struct ShiftingRangeList: View {
  @State private var lowerBound = 0
  @State private var count = 50

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Shift") { lowerBound += 5 }
      Button("Shrink") { count -= 10 }
      List(lowerBound..<(lowerBound + count), id: \.self) { row in
        Text("«\(row)»")
      }
      .frame(height: 8)
    }
  }
}

@MainActor
private struct SelectableReuseList: View {
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

/// The `«n»`-delimited row indices visible in a rendered surface (local copy —
/// the currency suite's helper is fileprivate there).
private func scrollCurrencyRowMarkers(
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
      digits.append(character)
    }
  }
  return rows
}
