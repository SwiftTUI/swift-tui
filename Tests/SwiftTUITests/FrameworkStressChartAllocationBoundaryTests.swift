import Testing

@testable import SwiftTUICharts
@testable import SwiftTUICore

@Suite("SwiftTUI chart allocation boundary stress behavior", .serialized)
struct FrameworkStressChartAllocationBoundaryTests {
  @Test("stress chart allocation 001 three positive segments never overbook two cells")
  func threePositiveSegmentsNeverOverbookTwoCells() {
    // Hypothesis: minimum-width promotion can allocate more cells than the track owns.
    let widths = stackedBarWidths(
      entries: [
        .init("A", value: 1),
        .init("B", value: 1),
        .init("C", value: 1),
      ],
      total: 3,
      barWidth: 2
    )

    #expect(widths == [1, 1, 0])
    #expect(widths.reduce(0, +) == 2)
  }

  @Test("stress chart allocation 002 zero-weight neighbors do not steal width")
  func zeroWeightNeighborsDoNotStealWidth() {
    // Hypothesis: largest-remainder distribution can award cells to zero-weight entries.
    let widths = stackedBarWidths(
      entries: [
        .init("zero-leading", value: 0),
        .init("only-value", value: 5),
        .init("zero-trailing", value: 0),
      ],
      total: 5,
      barWidth: 7
    )

    #expect(widths == [0, 7, 0])
  }

  @Test("stress chart allocation 003 negative stacked values use magnitude")
  func negativeStackedValuesUseMagnitude() {
    // Hypothesis: a negative value can be discarded instead of receiving magnitude-based width.
    let widths = stackedBarWidths(
      entries: [.init("negative", value: -3), .init("positive", value: 3)],
      total: 6,
      barWidth: 4
    )

    #expect(widths == [2, 2])
  }

  @Test("stress chart allocation 004 explicit headroom stays unassigned")
  func explicitHeadroomStaysUnassigned() {
    // Hypothesis: remainder distribution can incorrectly fill capacity reserved by an explicit total.
    let widths = stackedBarWidths(
      entries: [.init("A", value: 2), .init("B", value: 2)],
      total: 8,
      barWidth: 8
    )

    #expect(widths == [3, 3])
    #expect(widths.reduce(0, +) == 6)
  }

  @Test("stress chart allocation 005 undersized total cannot distort proportions")
  func undersizedTotalCannotDistortProportions() {
    // Hypothesis: an explicit total smaller than the weight sum can overbook the bar.
    let widths = stackedBarWidths(
      entries: [.init("quarter", value: 1), .init("three-quarters", value: 3)],
      total: 1,
      barWidth: 4
    )

    #expect(widths == [1, 3])
  }

  @Test("stress chart allocation 006 all-zero weights remain empty")
  func allZeroWeightsRemainEmpty() {
    // Hypothesis: remainder distribution can invent a visible segment for an all-zero dataset.
    let widths = stackedBarWidths(
      entries: [.init("A", value: 0), .init("B", value: 0)],
      total: 10,
      barWidth: 6
    )

    #expect(widths == [0, 0])
  }

  @Test("stress chart allocation 007 negative width normalizes to one cell")
  func negativeWidthNormalizesToOneCell() {
    // Hypothesis: a negative authored width can leak a negative allocation into rendering.
    let widths = stackedBarWidths(
      entries: [.init("dominant", value: 4), .init("minor", value: 1)],
      total: 5,
      barWidth: -8
    )

    #expect(widths == [1, 0])
  }

  @Test("stress chart allocation 008 more segments than cells preserve the capacity bound")
  func moreSegmentsThanCellsPreserveCapacityBound() {
    // Hypothesis: repeated minimum-width promotion can exceed a one-cell capacity.
    let widths = stackedBarWidths(
      entries: [
        .init("A", value: 1),
        .init("B", value: 1),
        .init("C", value: 1),
        .init("D", value: 1),
      ],
      total: 4,
      barWidth: 1
    )

    #expect(widths == [1, 0, 0, 0])
    #expect(widths.reduce(0, +) == 1)
  }

  @Test("stress chart allocation 009 largest fractional remainder receives the spare cell")
  func largestFractionalRemainderReceivesSpareCell() {
    // Hypothesis: the spare cell can be awarded by entry order instead of fractional remainder.
    let widths = stackedBarWidths(
      entries: [.init("one", value: 1), .init("two", value: 2)],
      total: 3,
      barWidth: 5
    )

    #expect(widths == [2, 3])
  }

  @Test("stress chart allocation 010 empty thresholds synthesize a terminal band")
  func emptyThresholdsSynthesizeTerminalBand() {
    // Hypothesis: an empty threshold list can leave the gauge without a total-covering band.
    let bands = thresholdBandsSorted([], total: 12)

    #expect(bands.count == 1)
    #expect(bands[0].upperBound == 12)
    #expect(bands[0].tone == .info)
  }

  @Test("stress chart allocation 011 threshold bounds clamp into the effective domain")
  func thresholdBoundsClampIntoEffectiveDomain() {
    // Hypothesis: negative and oversized band bounds can escape the gauge's normalized domain.
    let bands = thresholdBandsSorted(
      [.init(upTo: -4, tone: .warning), .init(upTo: 20, tone: .critical)],
      total: 10
    )

    #expect(bands.map(\.upperBound) == [0, 10])
  }

  @Test("stress chart allocation 012 unsorted thresholds become monotonic")
  func unsortedThresholdsBecomeMonotonic() {
    // Hypothesis: lookup can preserve authoring order and choose a wider band too early.
    let bands = thresholdBandsSorted(
      [
        .init(upTo: 90, tone: .critical),
        .init(upTo: 25, tone: .success),
        .init(upTo: 60, tone: .warning),
      ],
      total: 100
    )

    #expect(bands.map(\.upperBound) == [25, 60, 90])
  }

  @Test("stress chart allocation 013 negative gauge values choose the first band")
  func negativeGaugeValuesChooseFirstBand() {
    // Hypothesis: a negative value can bypass every band rather than clamp to zero.
    let tone = thresholdBandTone(
      for: -100,
      total: 100,
      bands: [.init(upTo: 20, tone: .success), .init(upTo: 100, tone: .critical)]
    )

    #expect(tone == .success)
  }

  @Test("stress chart allocation 014 oversized gauge values choose the final band")
  func oversizedGaugeValuesChooseFinalBand() {
    // Hypothesis: a value above total can miss the terminal band after normalization.
    let tone = thresholdBandTone(
      for: 1_000,
      total: 100,
      bands: [.init(upTo: 20, tone: .success), .init(upTo: 100, tone: .critical)]
    )

    #expect(tone == .critical)
  }

  @Test("stress chart allocation 015 negative columns use magnitude")
  func negativeColumnsUseMagnitude() {
    // Hypothesis: negative column values can collapse even when their magnitude is maximal.
    #expect(columnChartFilledHeight(value: -10, maximumValue: 10, chartHeight: 6) == 6)
  }

  @Test("stress chart allocation 016 tiny nonzero columns remain visible")
  func tinyNonzeroColumnsRemainVisible() {
    // Hypothesis: rounding can erase a nonzero column below half a cell.
    #expect(columnChartFilledHeight(value: 0.000_1, maximumValue: 10, chartHeight: 8) == 1)
  }

  @Test("stress chart allocation 017 zero columns stay empty")
  func zeroColumnsStayEmpty() {
    // Hypothesis: minimum visibility can accidentally promote an exact zero to one cell.
    #expect(columnChartFilledHeight(value: 0, maximumValue: 10, chartHeight: 8) == 0)
  }

  @Test("stress chart allocation 018 oversized columns clamp to chart height")
  func oversizedColumnsClampToChartHeight() {
    // Hypothesis: values above the maximum can allocate beyond the chart's row count.
    #expect(columnChartFilledHeight(value: 500, maximumValue: 10, chartHeight: 7) == 7)
  }

  @Test("stress chart allocation 019 negative chart height never produces negative fill")
  func negativeChartHeightNeverProducesNegativeFill() {
    // Hypothesis: a negative authored height can leak through the fill-height clamp.
    #expect(columnChartFilledHeight(value: 5, maximumValue: 10, chartHeight: -3) == 0)
  }

  @Test("stress chart allocation 020 negative heat values use magnitude")
  func negativeHeatValuesUseMagnitude() {
    // Hypothesis: a negative heat value can select a different intensity than its magnitude peer.
    #expect(
      heatStripGlyph(value: -5, maximumValue: 10) == heatStripGlyph(value: 5, maximumValue: 10))
  }

  @Test("stress chart allocation 021 zero heat stays visually empty")
  func zeroHeatStaysVisuallyEmpty() {
    // Hypothesis: ramp thresholding can render an exact zero as the faintest activity glyph.
    #expect(heatStripGlyph(value: 0, maximumValue: 10) == " ")
  }

  @Test("stress chart allocation 022 nonpositive heat maximum suppresses output")
  func nonpositiveHeatMaximumSuppressesOutput() {
    // Hypothesis: division by a nonpositive maximum can produce a spurious full-intensity cell.
    #expect(heatStripGlyph(value: 8, maximumValue: -1) == " ")
  }

  @Test("stress chart allocation 023 ramp quarter boundary advances exactly once")
  func rampQuarterBoundaryAdvancesExactlyOnce() {
    // Hypothesis: the first closed threshold can classify exactly 0.25 into the lower bucket.
    #expect(intensityRampGlyph(fraction: 0.249_999) == "░")
    #expect(intensityRampGlyph(fraction: 0.25) == "▒")
  }

  @Test("stress chart allocation 024 comparison maximum uses negative magnitudes")
  func comparisonMaximumUsesNegativeMagnitudes() {
    // Hypothesis: all-negative comparison data can collapse to the fallback maximum of one.
    let maximum = comparisonChartMaximumValue([
      .init("A", current: -8, baseline: -13),
      .init("B", current: -21, baseline: -3),
    ])

    #expect(maximum == 21)
  }

  @Test("stress chart allocation 025 fractional plot coordinates preserve subcell precision")
  func fractionalPlotCoordinatesPreserveSubcellPrecision() {
    // Hypothesis: chart coordinate conversion can truncate a fractional pointer location to a cell.
    let plot = CellRect(origin: .init(x: 10, y: 4), size: .init(width: 5, height: 3))
    let fraction = chartFraction(at: Point(x: 11.5, y: 4), in: plot, axis: .horizontal)
    let value = chartDomainValue(
      at: Point(x: 11.5, y: 4),
      in: plot,
      domain: 100...200,
      axis: .horizontal
    )

    #expect(fraction == 0.375)
    #expect(value == 137.5)
  }
}
