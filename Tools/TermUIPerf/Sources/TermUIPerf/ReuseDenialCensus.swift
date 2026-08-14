import Foundation

/// Run-level census reduced from the opt-in `[REUSE-TRACE]` stream.
///
/// Totals show the overall denial population; per-reason and all-reason peaks
/// preserve the full-tree-walk signal that a total alone can hide when frame
/// counts change. `RunCommand` writes this beside its aggregates whenever
/// `SWIFTTUI_REUSE_TRACE` is armed.
public struct PerfReuseDenialCensus: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public var schemaVersion: Int
  public var frameCount: Int
  public var totalDenials: Int
  public var peakDenialsPerFrame: Int
  public var reasonTotals: [String: Int]
  public var reasonPeaks: [String: Int]

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    frameCount: Int,
    totalDenials: Int,
    peakDenialsPerFrame: Int,
    reasonTotals: [String: Int],
    reasonPeaks: [String: Int]
  ) {
    self.schemaVersion = schemaVersion
    self.frameCount = frameCount
    self.totalDenials = totalDenials
    self.peakDenialsPerFrame = peakDenialsPerFrame
    self.reasonTotals = reasonTotals
    self.reasonPeaks = reasonPeaks
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case frameCount = "frame_count"
    case totalDenials = "total_denials"
    case peakDenialsPerFrame = "peak_denials_per_frame"
    case reasonTotals = "reason_totals"
    case reasonPeaks = "reason_peaks"
  }

  public static func parse(_ trace: String) -> PerfReuseDenialCensus {
    var frameCount = 0
    var totalDenials = 0
    var peakDenialsPerFrame = 0
    var reasonTotals: [String: Int] = [:]
    var reasonPeaks: [String: Int] = [:]

    for line in trace.split(separator: "\n") {
      guard line.hasPrefix("[REUSE-TRACE] "),
        let reasonsStart = line.range(of: "recompute-reasons:")
      else {
        continue
      }
      frameCount += 1
      let suffix = line[reasonsStart.upperBound...]
      let reasonSegment = suffix.split(separator: "|", maxSplits: 1).first ?? suffix[...]
      var frameTotal = 0

      for token in reasonSegment.split(whereSeparator: \.isWhitespace) {
        let pair = token.split(separator: "=", maxSplits: 1)
        guard pair.count == 2, let count = Int(pair[1]), count >= 0 else {
          continue
        }
        let reason = String(pair[0])
        reasonTotals[reason, default: 0] += count
        reasonPeaks[reason] = max(reasonPeaks[reason, default: 0], count)
        frameTotal += count
      }

      totalDenials += frameTotal
      peakDenialsPerFrame = max(peakDenialsPerFrame, frameTotal)
    }

    return PerfReuseDenialCensus(
      frameCount: frameCount,
      totalDenials: totalDenials,
      peakDenialsPerFrame: peakDenialsPerFrame,
      reasonTotals: reasonTotals,
      reasonPeaks: reasonPeaks
    )
  }

  /// Writes nothing when the trace produced no file. A present-but-empty trace
  /// still writes a zero census so an armed yet vacuous diagnostic is visible.
  public static func writeIfPresent(traceURL: URL, to outputURL: URL) throws {
    guard FileManager.default.fileExists(atPath: traceURL.path) else {
      return
    }
    let trace = try String(contentsOf: traceURL, encoding: .utf8)
    let census = parse(trace)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try (try encoder.encode(census) + Data("\n".utf8)).write(to: outputURL)
  }
}
