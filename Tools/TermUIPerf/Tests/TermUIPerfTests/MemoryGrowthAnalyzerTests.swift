import Foundation
@_spi(Runners) import SwiftTUIProfiling
import Testing

@testable import TermUIPerf

struct MemoryGrowthAnalyzerTests {
  @Test("linear growth yields a positive count/second slope")
  func linearGrowthYieldsPositiveSlope() {
    let analysis = MemoryGrowthAnalyzer.analyze(
      samples(provider: "g", counts: [0, 2, 4, 6, 8], step: 1.0))

    let row = analysis.rows.first { $0.provider == "g" }!
    #expect(row.sampleCount == 5)
    #expect(row.firstCount == 0)
    #expect(row.lastCount == 8)
    #expect(approx(row.slopePerSecond, 2.0))
  }

  @Test("a single sample yields zero slope and no leak")
  func singleSampleYieldsZeroSlope() {
    let analysis = MemoryGrowthAnalyzer.analyze(samples(provider: "g", counts: [5], step: 1.0))
    let row = analysis.rows.first { $0.provider == "g" }!
    #expect(approx(row.slopePerSecond, 0.0))
    #expect(row.leakSuspected == false)
  }

  func samples(provider: String, counts: [Int], step: Double) -> [PerfMemorySampler.Sample] {
    counts.enumerated().map { index, count in
      PerfMemorySampler.Sample(
        elapsedSeconds: Double(index) * step,
        snapshots: [ProfiledMemorySnapshot(name: provider, count: count, approxBytes: nil)])
    }
  }

  func approx(_ actual: Double, _ expected: Double) -> Bool {
    abs(actual - expected) < 0.000_001
  }
}
