import Foundation
@_spi(Runners) import SwiftTUIProfiling

/// Per-provider growth summary over a run's memory time-series.
public struct MemoryGrowthRow: Codable, Equatable, Sendable {
  public var provider: String
  public var sampleCount: Int
  public var firstCount: Int
  public var lastCount: Int
  public var slopePerSecond: Double
  public var plateaued: Bool
  public var leakSuspected: Bool

  public init(
    provider: String,
    sampleCount: Int,
    firstCount: Int,
    lastCount: Int,
    slopePerSecond: Double,
    plateaued: Bool,
    leakSuspected: Bool
  ) {
    self.provider = provider
    self.sampleCount = sampleCount
    self.firstCount = firstCount
    self.lastCount = lastCount
    self.slopePerSecond = slopePerSecond
    self.plateaued = plateaued
    self.leakSuspected = leakSuspected
  }

  private enum CodingKeys: String, CodingKey {
    case provider
    case sampleCount = "sample_count"
    case firstCount = "first_count"
    case lastCount = "last_count"
    case slopePerSecond = "slope_per_second"
    case plateaued
    case leakSuspected = "leak_suspected"
  }
}

public struct MemoryGrowthAnalysis: Codable, Equatable, Sendable {
  public var rows: [MemoryGrowthRow]

  public init(rows: [MemoryGrowthRow]) {
    self.rows = rows
  }
}

public enum MemoryGrowthAnalyzer {
  public static let defaultSlopeThresholdPerSecond = 0.5
  public static let defaultPlateauTailFraction = 0.5
  public static let defaultPlateauTolerance = 0.05

  static func analyze(
    _ samples: [PerfMemorySampler.Sample],
    slopeThresholdPerSecond: Double = defaultSlopeThresholdPerSecond,
    plateauTailFraction: Double = defaultPlateauTailFraction,
    plateauTolerance: Double = defaultPlateauTolerance
  ) -> MemoryGrowthAnalysis {
    var series: [String: [(t: Double, count: Int)]] = [:]
    var order: [String] = []
    for sample in samples {
      for snapshot in sample.snapshots {
        if series[snapshot.name] == nil {
          order.append(snapshot.name)
        }
        series[snapshot.name, default: []].append((sample.elapsedSeconds, snapshot.count))
      }
    }
    let rows = order.map { name -> MemoryGrowthRow in
      let points = series[name] ?? []
      let slope = leastSquaresSlope(points)
      let plateaued = isPlateaued(
        points, tailFraction: plateauTailFraction, tolerance: plateauTolerance)
      let leak = slope > slopeThresholdPerSecond && !plateaued
      return MemoryGrowthRow(
        provider: name,
        sampleCount: points.count,
        firstCount: points.first?.count ?? 0,
        lastCount: points.last?.count ?? 0,
        slopePerSecond: slope,
        plateaued: plateaued,
        leakSuspected: leak)
    }
    return MemoryGrowthAnalysis(rows: rows)
  }

  static func tsv(_ analysis: MemoryGrowthAnalysis) -> String {
    var lines = [
      "provider\tsamples\tfirst_count\tlast_count\tslope_per_s\tplateaued\tleak_suspected"
    ]
    for row in analysis.rows {
      let slope = String(format: "%.4f", row.slopePerSecond)
      lines.append(
        "\(row.provider)\t\(row.sampleCount)\t\(row.firstCount)\t\(row.lastCount)\t"
          + "\(slope)\t\(row.plateaued)\t\(row.leakSuspected)")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func leastSquaresSlope(_ points: [(t: Double, count: Int)]) -> Double {
    let n = Double(points.count)
    guard points.count > 1 else {
      return 0
    }
    let sumT = points.reduce(0.0) { $0 + $1.t }
    let sumY = points.reduce(0.0) { $0 + Double($1.count) }
    let sumTT = points.reduce(0.0) { $0 + $1.t * $1.t }
    let sumTY = points.reduce(0.0) { $0 + $1.t * Double($1.count) }
    let denominator = n * sumTT - sumT * sumT
    guard abs(denominator) > 0.000_000_1 else {
      return 0
    }
    return (n * sumTY - sumT * sumY) / denominator
  }

  private static func isPlateaued(
    _ points: [(t: Double, count: Int)],
    tailFraction: Double,
    tolerance: Double
  ) -> Bool {
    guard points.count >= 4 else {
      return false
    }
    let tailStart = Int(Double(points.count) * (1 - tailFraction))
    let tail = points[tailStart...].map { $0.count }
    guard let maxCount = tail.max(), let minCount = tail.min() else {
      return false
    }
    if maxCount == 0 {
      return true
    }
    return Double(maxCount - minCount) <= tolerance * Double(maxCount)
  }
}
