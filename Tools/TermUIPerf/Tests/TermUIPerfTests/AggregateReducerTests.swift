import Foundation
import Testing

@testable import TermUIPerf

struct AggregateReducerTests {
  @Test("PerfStat computes median, mean, sample stddev, min/max, CV")
  func perfStatComputesSummaryStatistics() {
    let stat = PerfStat(values: [2, 4, 4, 4, 5, 5, 7, 9])

    #expect(stat.sampleCount == 8)
    #expect(approx(stat.mean, 5.0))
    #expect(approx(stat.median, 4.5))
    #expect(approx(stat.stddev, 2.138_089_935))  // sample stddev (n-1)
    #expect(approx(stat.min, 2.0))
    #expect(approx(stat.max, 9.0))
    #expect(approx(stat.coefficientOfVariation, 0.427_617_987))
  }

  @Test("PerfStat with one value has zero stddev and zero CV")
  func perfStatSingleValueIsZeroSpread() {
    let stat = PerfStat(values: [3.5])

    #expect(stat.sampleCount == 1)
    #expect(approx(stat.median, 3.5))
    #expect(approx(stat.mean, 3.5))
    #expect(approx(stat.stddev, 0.0))
    #expect(approx(stat.coefficientOfVariation, 0.0))
  }

  @Test("PerfStat with zero mean reports zero CV, not NaN")
  func perfStatZeroMeanReportsZeroCV() {
    let stat = PerfStat(values: [0, 0, 0])

    #expect(approx(stat.mean, 0.0))
    #expect(approx(stat.stddev, 0.0))
    #expect(approx(stat.coefficientOfVariation, 0.0))
  }

  @Test("PerfStat with no values is all zeros")
  func perfStatEmptyInputIsAllZeros() {
    let stat = PerfStat(values: [])

    #expect(stat.sampleCount == 0)
    #expect(approx(stat.median, 0.0))
    #expect(approx(stat.mean, 0.0))
    #expect(approx(stat.stddev, 0.0))
    #expect(approx(stat.min, 0.0))
    #expect(approx(stat.max, 0.0))
    #expect(approx(stat.coefficientOfVariation, 0.0))
  }

  private func approx(_ actual: Double, _ expected: Double) -> Bool {
    abs(actual - expected) < 0.000_001
  }
}
