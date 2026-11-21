import SwiftTUI
import Testing
import TransitionConsumer

/// The six demonstrations at a fixed progress (STUI-1546).
///
/// A demonstration is built on one `progress`, so what it draws is a
/// function of that number. These tests render the panel under the
/// demonstration's modifier or shape at 0, 0.25, 0.5, 0.75 and 1, with no
/// transition, no animation and no clock, and compare the cells that show a
/// glyph with the cells its description gives.
@MainActor
@Suite("Demonstration transitions at a fixed progress")
struct DemonstrationFrameTests {
  static let steps = [0.0, 0.25, 0.5, 0.75, 1.0]

  @Test("each demonstration shows the cells of its description", arguments: Demonstration.allCases)
  func cellsAtFixedProgress(demonstration: Demonstration) {
    for progress in Self.steps {
      let snapshot = DefaultRenderer().render(demonstration.panel(at: progress))
      let reading = snapshot.panel(rowsDown: demonstration.rowsDown(at: progress))
      let expected = demonstration.cells(at: progress)
      #expect(reading.problems.isEmpty, "\(progress): \(reading.problems.prefix(4))")
      #expect(
        reading.visible.isSuperset(of: expected.must),
        "\(progress): missing \(expected.must.subtracting(reading.visible).sorted().prefix(8))")
      #expect(
        reading.visible.isSubset(of: expected.may),
        "\(progress): extra \(reading.visible.subtracting(expected.may).sorted().prefix(8))")
      #expect(snapshot.issues.isEmpty, "\(progress): \(snapshot.issues)")
    }
    // Nothing at 0 and the whole panel at 1, whatever lies between.
    #expect(demonstration.cells(at: 0).may.isEmpty)
    #expect(demonstration.cells(at: 1).must == Panel.allCells)
  }

  /// The numbers the description of each demonstration gives, by hand, so a
  /// mistake in the expectations above cannot hide behind the same mistake
  /// in the code.
  @Test("the expected cells are the counts worked out by hand")
  func expectedCounts() {
    func counts(_ demonstration: Demonstration) -> [Int] {
      Self.steps.map { demonstration.cells(at: $0).must.count }
    }
    // The wipe: 48 columns for a unit of progress, cut at the panel's 40.
    #expect(counts(.wipe) == [0, 12 * 10, 24 * 10, 36 * 10, 400])
    // Ten slats, one column of each for a quarter.
    #expect(counts(.blinds) == [0, 10 * 10, 20 * 10, 30 * 10, 400])
    // 100 cells for a quarter.
    #expect(counts(.typewriter) == [0, 100, 200, 300, 400])
    // The panel moves down four rows, less one for each quarter, and is
    // transparent at 0.
    #expect(counts(.rise) == [0, 7 * 40, 8 * 40, 9 * 40, 400])
    // SplitMix64 with seed 1 over 400 cells, counted with another
    // implementation of the same published function.
    #expect(counts(.dissolve) == [0, 101, 216, 309, 400])
    // The ellipse: the cells that are inside whatever the flattening does,
    // and how many more it may add.
    #expect(counts(.iris) == [0, 56, 196, 376, 400])
    let undecided = Self.steps.map { progress in
      let cells = Demonstration.iris.cells(at: progress)
      return cells.may.count - cells.must.count
    }
    #expect(undecided == [0, 0, 12, 4, 0])
  }

  @Test("the wipe fades the ink in a straight line before its front")
  func wipeFadesBeforeItsFront() {
    // At 0.5 the front is at column 24 and the fade is 8 columns wide. The
    // ink of a cell is sampled at its centre.
    let reading = DefaultRenderer().render(Demonstration.wipe.panel(at: 0.5)).panel()
    #expect(reading.visible.count == 240)
    for cell in reading.visible.sorted() {
      let expected = min(1, max(0, (24 - (Double(cell.column) + 0.5)) / 8))
      let alpha = reading.inks[cell]?.alpha ?? -1
      #expect(abs(alpha - expected) < 1e-9, "\(cell): \(alpha), expected \(expected)")
    }
    // By hand: opaque up to column 15, then sixteenths from 15 down to 1.
    let firstRow = (0..<24).map { column in
      Int(((reading.inks[PanelCell(column: column, row: 0)]?.alpha ?? -1) * 16).rounded())
    }
    #expect(firstRow == Array(repeating: 16, count: 16) + [15, 13, 11, 9, 7, 5, 3, 1])
    // At 1 every cell has the whole ink.
    let whole = DefaultRenderer().render(Demonstration.wipe.panel(at: 1)).panel()
    #expect(whole.inks.count == 400)
    #expect(whole.inks.values.allSatisfy { abs($0.alpha - 1) < 1e-9 })
  }

  @Test("the rise fades the ink with its progress")
  func riseFadesTheInk() {
    // White ink over black. The opacity mixes the ink with what is behind
    // it in Oklab, where lightness is linear in the amount and luminance is
    // its cube: an opacity of 0.5 gives a luminance of 0.125, which is
    // 0.3886 in sRGB (1.055 * 0.125^(1/2.4) - 0.055).
    func gray(at progress: Double) -> [Double] {
      let snapshot = DefaultRenderer().render(
        Demonstration.rise.panel(at: progress)
          .foregroundStyle(Color.white)
          .background(Color.black))
      let reading = snapshot.panel(rowsDown: Demonstration.rise.rowsDown(at: progress))
      let reds = Set(reading.inks.values.map { ($0.red * 10000).rounded() / 10000 })
      #expect(reds.count == 1, "\(progress): \(reds)")
      #expect(
        reading.inks.values.allSatisfy {
          abs($0.red - $0.green) < 1e-4 && abs($0.red - $0.blue) < 1e-4
        })
      return reds.sorted()
    }
    #expect(gray(at: 0.5) == [0.3886])
    #expect(gray(at: 1) == [1])
    #expect(gray(at: 0.25).first ?? 1 < 0.2)
    #expect(gray(at: 0.75).first ?? 0 > 0.6)
  }

  @Test("progress outside 0...1 draws what the nearer end draws", arguments: Demonstration.allCases)
  func progressOutsideTheRange(demonstration: Demonstration) {
    // A spring delivers such values. Below 0 nothing shows, and above 1 the
    // whole panel shows, in place.
    for progress in [-0.4, -0.01] {
      let reading = DefaultRenderer().render(demonstration.panel(at: progress)).panel()
      #expect(reading.visible.isEmpty, "\(progress): \(reading.visible.count)")
      #expect(reading.problems.isEmpty, "\(progress): \(reading.problems.prefix(4))")
    }
    for progress in [1.01, 1.4] {
      let reading = DefaultRenderer().render(demonstration.panel(at: progress)).panel()
      #expect(reading.visible == Panel.allCells, "\(progress): \(reading.visible.count)")
      #expect(reading.problems.isEmpty, "\(progress): \(reading.problems.prefix(4))")
    }
  }
}

/// The random-cell dissolve is a function of its seed and its progress.
@MainActor
@Suite("Random-cell dissolve")
struct CellDissolveTests {
  private func cells(progress: Double, seed: UInt64, mergesRuns: Bool = true) -> Set<PanelCell> {
    let shape = CellDissolveShape(
      progress: progress, columns: Panel.columns, rows: Panel.rows, seed: seed,
      mergesRuns: mergesRuns)
    let reading = DefaultRenderer().render(PanelView().clipShape(shape)).panel()
    #expect(reading.problems.isEmpty)
    return reading.visible
  }

  @Test("the same seed gives the same cells, and another seed gives others")
  func seedDecidesTheCells() {
    let first = cells(progress: 0.5, seed: 1)
    #expect(first == cells(progress: 0.5, seed: 1))
    #expect(first.count == 216)
    let other = cells(progress: 0.5, seed: 2)
    #expect(other != first)
    // Two seeds agree on about a quarter of the panel, as two fair coins
    // both show heads: far from all of it and far from none.
    #expect((60...140).contains(first.intersection(other).count))
  }

  @Test("the count of visible cells rises with progress, and no cell leaves")
  func countRisesWithProgress() {
    var previous: Set<PanelCell> = []
    var counts: [Int] = []
    for step in 0...20 {
      let visible = cells(progress: Double(step) / 20, seed: 1)
      #expect(visible.isSuperset(of: previous), "step \(step)")
      counts.append(visible.count)
      previous = visible
    }
    #expect(counts.first == 0)
    #expect(counts.last == 400)
    // Twenty steps over 400 cells: every step adds some, about twenty.
    #expect(zip(counts, counts.dropFirst()).allSatisfy { $0 < $1 }, "\(counts)")
    #expect(zip(counts, counts.dropFirst()).allSatisfy { $1 - $0 < 45 }, "\(counts)")
  }

  @Test("one rectangle for each cell covers the cells that merged runs cover")
  func bothPathsCoverTheSameCells() {
    for progress in [0.25, 0.5, 0.75] {
      #expect(
        cells(progress: progress, seed: 1, mergesRuns: false)
          == cells(progress: progress, seed: 1, mergesRuns: true))
    }
  }

  @Test("the thresholds are SplitMix64, worked out outside this package")
  func thresholdsAreSplitMix() {
    // Computed with a third implementation, in Python, for seed 1 and 40
    // columns: the cell's index in reading order plus one, times the golden
    // gamma, added to the seed, through the two multiply-xorshift rounds.
    let known: [(column: Int, row: Int, threshold: Double)] = [
      (0, 0, 0.5665615751722809),
      (1, 0, 0.7457817572627011),
      (39, 0, 0.6685734656042366),
      (0, 1, 0.861828284658707),
      (17, 6, 0.09162433005963011),
      (39, 9, 0.5870877674617534),
    ]
    for cell in known {
      let threshold = CellDissolveShape.threshold(
        column: cell.column, row: cell.row, columns: Panel.columns, seed: 1)
      #expect(threshold == cell.threshold, "(\(cell.column),\(cell.row)): \(threshold)")
      #expect(
        Demonstration.splitMix(1, index: cell.row * Panel.columns + cell.column) == cell.threshold)
    }
    // The first row at 0.5, read off those thresholds.
    let firstRow = cells(progress: 0.5, seed: 1).filter { $0.row == 0 }.map(\.column).sorted()
    #expect(firstRow == [3, 4, 8, 10, 12, 14, 15, 20, 21, 22, 23, 24, 25, 28, 32, 33, 34])
  }
}
