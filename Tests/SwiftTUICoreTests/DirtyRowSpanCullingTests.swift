import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// D70: the incremental raster culls paint work on the *exact* dirty-row set,
/// not on its convex hull.
///
/// The hull is the only span-shaped question a `Set<Int>` answers cheaply, so
/// the paint walk historically skipped a subtree only when it missed
/// `(dirtyRows.min(), dirtyRows.max())`. A one-cell clock in the top row plus a
/// spinner in the bottom row therefore produced a hull covering the screen, and
/// every command on it ran text layout and per-cluster style resolution to
/// write two cells — the writes were dropped by the exact-set clamp in `write`
/// only after the compute had happened. `DirtyRowSpans` restores the exact set
/// as a span-testable shape so the compute is skipped too.
@MainActor
@Suite("Dirty-row span culling")
struct DirtyRowSpanCullingTests {

  // MARK: - The span structure itself

  @Test("coalesces contiguous rows into disjoint half-open spans")
  func coalescesContiguousRows() {
    let spans = DirtyRowSpans(dirtyRows: [0, 1, 2, 7, 9, 10])
    #expect(spans?.spans == [0..<3, 7..<8, 9..<11])
    #expect(spans?.hull == 0..<11)
  }

  @Test("a single dirty row is one unit span equal to its own hull")
  func singleRow() {
    let spans = DirtyRowSpans(dirtyRows: [4])
    #expect(spans?.spans == [4..<5])
    #expect(spans?.hull == 4..<5)
  }

  @Test("an empty dirty set has no spans")
  func emptySetIsNil() {
    #expect(DirtyRowSpans(dirtyRows: []) == nil)
  }

  @Test("intersects answers membership for the gap between two disjoint bands")
  func intersectsSkipsTheGap() {
    let spans = DirtyRowSpans(dirtyRows: [0, 23])!

    // The band rows themselves.
    #expect(spans.intersects(rows: 0..<1))
    #expect(spans.intersects(rows: 23..<24))
    // Every row strictly between the bands — the whole point of D70.
    #expect(!spans.intersects(rows: 1..<23))
    #expect(!spans.intersects(rows: 5..<6))
    // Ranges that straddle a band still intersect.
    #expect(spans.intersects(rows: 0..<24))
    #expect(spans.intersects(rows: 20..<30))
    // Outside the hull entirely.
    #expect(!spans.intersects(rows: 24..<40))
    #expect(!spans.intersects(rows: -5..<0))
    // Degenerate ranges never intersect.
    #expect(!spans.intersects(rows: 3..<3))
  }

  @Test(
    "intersects agrees with brute-force set membership across many span shapes",
    arguments: [
      [0, 1, 2, 3, 4] as Set<Int>,
      [0, 5, 10, 15],
      [7],
      [0, 1, 3, 4, 6, 7, 9],
      [2, 3, 4, 40, 41, 99],
    ]
  )
  func intersectsMatchesBruteForce(dirtyRows: Set<Int>) {
    let spans = DirtyRowSpans(dirtyRows: dirtyRows)!

    for lower in -2...101 {
      for length in 0...6 {
        let range = lower..<(lower + length)
        let expected = dirtyRows.contains { range.contains($0) }
        #expect(
          spans.intersects(rows: range) == expected,
          "range \(range) over \(dirtyRows.sorted())"
        )
      }
    }
  }

  @Test("the hull pre-reject never disagrees with the span search")
  func hullNeverContradictsSpans() {
    let spans = DirtyRowSpans(dirtyRows: [3, 4, 100])!
    // Anything the old hull test rejected must still be rejected: culling can
    // only ever become sharper, never looser.
    for lower in -10...120 {
      let range = lower..<(lower + 3)
      if !(range.lowerBound < spans.hull.upperBound && range.upperBound > spans.hull.lowerBound) {
        #expect(!spans.intersects(rows: range))
      }
    }
  }

  // MARK: - Compute culling in the paint walk

  /// A foreign-surface payload that records every read of `grid`.
  ///
  /// `paint(commands:)` reads `payload.grid` as the first thing it does for a
  /// `.foreignSurface` command, so an unread grid is direct evidence that the
  /// command was rejected before any per-command work ran. Unlike
  /// `TextLayoutCache` metrics this probe is per-instance, so it stays
  /// deterministic under parallel test execution.
  private final class CountingForeignSurface: ForeignSurfacePayload {
    private let reads = Mutex<Int>(0)
    let backing: ForeignGrid

    init(width: Int, height: Int, character: Character) {
      backing = ForeignGrid(
        size: CellSize(width: width, height: height),
        cells: Array(
          repeating: Array(
            repeating: RasterCell(character: character, spanWidth: 1),
            count: width
          ),
          count: height
        )
      )
    }

    var grid: ForeignGrid {
      reads.withLock { $0 += 1 }
      return backing
    }

    var readCount: Int {
      reads.withLock { $0 }
    }
  }

  private func bandTree(
    top: CellRect,
    middle: CellRect,
    bottom: CellRect,
    middlePayload: CountingForeignSurface,
    topCharacter: Character
  ) -> DrawNode {
    DrawNode(
      identity: testIdentity("bands"),
      bounds: CellRect(origin: .init(x: 0, y: 0), size: .init(width: 8, height: 24)),
      children: [
        DrawNode(
          identity: testIdentity("bands", "top"),
          bounds: top,
          commands: [
            .text(
              bounds: top,
              content: String(topCharacter),
              style: .init(),
              lineLimit: nil,
              truncationMode: .tail,
              wrappingStrategy: .wordBoundary
            )
          ]
        ),
        DrawNode(
          identity: testIdentity("bands", "middle"),
          bounds: middle,
          commands: [.foreignSurface(bounds: middle, payload: middlePayload)]
        ),
        DrawNode(
          identity: testIdentity("bands", "bottom"),
          bounds: bottom,
          commands: [
            .text(
              bounds: bottom,
              content: "B",
              style: .init(),
              lineLimit: nil,
              truncationMode: .tail,
              wrappingStrategy: .wordBoundary
            )
          ]
        ),
      ]
    )
  }

  @Test("content between two disjoint damage bands is not computed at all")
  func middleContentIsSkippedBetweenDisjointBands() {
    // `.trustSoundDamage` mirrors release: no fresh-raster fallback that would
    // re-read the middle payload and mask the cull.
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let top = CellRect(origin: .init(x: 0, y: 0), size: .init(width: 8, height: 1))
    let middle = CellRect(origin: .init(x: 0, y: 1), size: .init(width: 8, height: 22))
    let bottom = CellRect(origin: .init(x: 0, y: 23), size: .init(width: 8, height: 1))

    let firstPayload = CountingForeignSurface(width: 8, height: 22, character: "#")
    let previousSurface = rasterizer.rasterize(
      bandTree(
        top: top,
        middle: middle,
        bottom: bottom,
        middlePayload: firstPayload,
        topCharacter: "0"
      )
    )
    #expect(firstPayload.readCount == 1, "the fresh raster must paint the middle band")

    // Damage is exactly the two one-row bands; the hull spans all 24 rows.
    let secondPayload = CountingForeignSurface(width: 8, height: 22, character: "#")
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      bandTree(
        top: top,
        middle: middle,
        bottom: bottom,
        middlePayload: secondPayload,
        topCharacter: "1"
      ),
      minimumSize: .zero,
      previousSurface: previousSurface,
      damage: .init(
        textRows: [
          .init(row: 0, columnRanges: [0..<8]),
          .init(row: 23, columnRanges: [0..<8]),
        ]
      )
    )

    #expect(
      secondPayload.readCount == 0,
      "the middle band spans only clean rows, so its command must never be entered"
    )
    // The damaged rows still repainted correctly.
    #expect(result.surface.lines[0].hasPrefix("1"))
    #expect(result.surface.lines[23].hasPrefix("B"))
    // And the untouched middle rows kept their previous content.
    #expect(result.surface.lines[10] == previousSurface.lines[10])
  }

  // MARK: - Per-line culling inside a straddling command

  /// One full-height text command covering every row, so the whole-command cull
  /// cannot fire: the command genuinely intersects the damage. Only the
  /// per-line guard can avoid resolving styles for the clean rows between the
  /// bands, and the surface must stay identical to a fresh raster either way.
  private func fullHeightTextTree(rows: Int, marker: Character) -> DrawNode {
    let bounds = CellRect(origin: .init(x: 0, y: 0), size: .init(width: 6, height: rows))
    // Only the first and last lines carry the marker, so the declared damage
    // `{0, rows - 1}` is genuinely complete — the rows between are byte-identical
    // across frames. Declaring less damage than the content actually changes
    // would be an unsound-damage input, which the F13 oracle rejects on its own
    // terms and would say nothing about the per-line cull.
    let content = (0..<rows)
      .map { row in
        row == 0 || row == rows - 1 ? "\(marker)\(row)" : "mid\(row)"
      }
      .joined(separator: "\n")
    return DrawNode(
      identity: testIdentity("straddle"),
      bounds: bounds,
      commands: [
        .text(
          bounds: bounds,
          content: content,
          style: .init(),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        )
      ]
    )
  }

  @Test("a command straddling two bands repaints exactly the damaged lines")
  func straddlingCommandRepaintsOnlyDamagedLines() {
    // `.verifySoundDamage` forces the F13 oracle to diff this incremental
    // surface against a fresh raster, so a per-line guard that skipped a line
    // it should have painted fails here rather than shipping as corruption.
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let rows = 12

    let previousSurface = rasterizer.rasterize(fullHeightTextTree(rows: rows, marker: "a"))
    #expect(previousSurface.lines[0] == "a0")
    #expect(previousSurface.lines[5] == "mid5")

    let updated = fullHeightTextTree(rows: rows, marker: "b")
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      updated,
      minimumSize: .zero,
      previousSurface: previousSurface,
      damage: .init(
        textRows: [
          .init(row: 0, columnRanges: [0..<6]),
          .init(row: rows - 1, columnRanges: [0..<6]),
        ]
      )
    )

    // No oracle mismatch: the incremental surface agrees with a fresh raster on
    // every row it claims to own.
    #expect(result.incrementalMismatch == nil)
    // Damaged lines took the new content...
    #expect(result.surface.lines[0] == "b0")
    #expect(result.surface.lines[rows - 1] == "b\(rows - 1)")
    // ...and the clean lines between the bands are intact, whether the per-line
    // guard skipped them or `write` clamped them.
    for row in 1..<(rows - 1) {
      #expect(result.surface.lines[row] == "mid\(row)", "row \(row)")
    }
  }

  @Test("an incremental raster over disjoint bands matches a fresh raster")
  func disjointBandIncrementalEqualsFresh() {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let top = CellRect(origin: .init(x: 0, y: 0), size: .init(width: 8, height: 1))
    let middle = CellRect(origin: .init(x: 0, y: 1), size: .init(width: 8, height: 22))
    let bottom = CellRect(origin: .init(x: 0, y: 23), size: .init(width: 8, height: 1))

    let previousSurface = rasterizer.rasterize(
      bandTree(
        top: top,
        middle: middle,
        bottom: bottom,
        middlePayload: CountingForeignSurface(width: 8, height: 22, character: "#"),
        topCharacter: "0"
      )
    )

    let updatedTree = bandTree(
      top: top,
      middle: middle,
      bottom: bottom,
      middlePayload: CountingForeignSurface(width: 8, height: 22, character: "#"),
      topCharacter: "1"
    )
    let incremental = rasterizer.rasterizeCollectingVisibleIdentities(
      updatedTree,
      minimumSize: .zero,
      previousSurface: previousSurface,
      damage: .init(
        textRows: [
          .init(row: 0, columnRanges: [0..<8]),
          .init(row: 23, columnRanges: [0..<8]),
        ]
      )
    )
    let fresh = rasterizer.rasterize(updatedTree)

    #expect(incremental.surface.cells == fresh.cells)
  }
}
