import Foundation

/// Cross-iteration summary statistics for a single scalar metric.
public struct PerfStat: Codable, Equatable, Sendable {
  public var sampleCount: Int
  public var median: Double
  public var mean: Double
  public var stddev: Double
  public var min: Double
  public var max: Double
  public var coefficientOfVariation: Double

  public init(
    sampleCount: Int,
    median: Double,
    mean: Double,
    stddev: Double,
    min: Double,
    max: Double,
    coefficientOfVariation: Double
  ) {
    self.sampleCount = sampleCount
    self.median = median
    self.mean = mean
    self.stddev = stddev
    self.min = min
    self.max = max
    self.coefficientOfVariation = coefficientOfVariation
  }

  /// Builds a stat from raw samples. Sample stddev (Bessel's correction) for
  /// `count > 1`, else `0`. CV is `0` when the mean is `0`.
  public init(values: [Double]) {
    let count = values.count
    guard count > 0 else {
      self.init(
        sampleCount: 0, median: 0, mean: 0, stddev: 0, min: 0, max: 0,
        coefficientOfVariation: 0)
      return
    }
    let sorted = values.sorted()
    let mean = values.reduce(0, +) / Double(count)
    let median: Double
    if count % 2 == 1 {
      median = sorted[count / 2]
    } else {
      median = (sorted[count / 2 - 1] + sorted[count / 2]) / 2
    }
    let stddev: Double
    if count > 1 {
      let sumSquares = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
      stddev = (sumSquares / Double(count - 1)).squareRoot()
    } else {
      stddev = 0
    }
    let cv = mean == 0 ? 0 : stddev / mean
    self.init(
      sampleCount: count,
      median: median,
      mean: mean,
      stddev: stddev,
      min: sorted.first ?? 0,
      max: sorted.last ?? 0,
      coefficientOfVariation: cv)
  }

  private enum CodingKeys: String, CodingKey {
    case sampleCount = "sample_count"
    case median
    case mean
    case stddev
    case min
    case max
    case coefficientOfVariation = "coefficient_of_variation"
  }
}
