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

  @Test("steady unbounded growth is a leak suspect")
  func steadyUnboundedGrowthIsLeakSuspect() {
    let analysis = MemoryGrowthAnalyzer.analyze(
      samples(provider: "leak", counts: [0, 10, 20, 30, 40, 50, 60, 70], step: 1.0))
    let row = analysis.rows.first { $0.provider == "leak" }!
    #expect(row.slopePerSecond > 0.5)
    #expect(row.plateaued == false)
    #expect(row.leakSuspected == true)
  }

  @Test("rises then plateaus is NOT a leak suspect (bounded cache)")
  func risesThenPlateausIsNotLeak() {
    let analysis = MemoryGrowthAnalyzer.analyze(
      samples(
        provider: "cache",
        counts: [0, 64, 128, 192, 256, 256, 256, 256, 256, 256],
        step: 1.0))
    let row = analysis.rows.first { $0.provider == "cache" }!
    #expect(row.plateaued == true)
    #expect(row.leakSuspected == false)
  }

  @Test("flat series is not a leak suspect")
  func flatSeriesIsNotLeak() {
    let analysis = MemoryGrowthAnalyzer.analyze(
      samples(provider: "flat", counts: [42, 42, 42, 42, 42], step: 1.0))
    let row = analysis.rows.first { $0.provider == "flat" }!
    #expect(approx(row.slopePerSecond, 0.0))
    #expect(row.leakSuspected == false)
  }

  @Test("tsv emits a header and one row per provider")
  func tsvEmitsHeaderAndRows() {
    let analysis = MemoryGrowthAnalyzer.analyze(
      samples(provider: "leak", counts: [0, 10, 20, 30, 40, 50, 60, 70], step: 1.0))
    let tsv = MemoryGrowthAnalyzer.tsv(analysis)

    #expect(
      tsv.hasPrefix(
        "provider\tsamples\tfirst_count\tlast_count\tslope_per_s\tplateaued\tleak_suspected\n"))
    #expect(tsv.contains("leak\t8\t0\t70\t"))
    #expect(tsv.contains("\ttrue"))
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
