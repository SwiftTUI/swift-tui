import Foundation
import SwiftTUI

/// Configuration for the `bench` subcommand (plan 2026-08-11-005).
public struct PerfBenchConfig: Equatable, Sendable {
  public static let defaultArtifactsRoot = ".perf/bench"
  public static let defaultWarmIterations = PerfRunConfig.defaultIterations
  /// D3's cold-lane protocol: 30 one-shot renders per configuration.
  public static let defaultColdIterations = 30

  public var artifactsRoot: String
  public var configuration: String
  public var warmIterations: Int
  public var coldIterations: Int
  /// Suite subset to run; `nil` runs every member. A focused-rerun and
  /// smoke-test seam — the suite itself is defined only by `BenchSuite`.
  public var members: [PerfScenarioName]?
  /// Skip the warm lanes and run only the cold lane per member — the
  /// `bench-ratchet` shape: the ratchet is cold-only (see
  /// `BenchSuite.members`), so a ratchet check need not pay for warm
  /// drives whose counters it will not gate.
  public var skipWarm: Bool
  /// Rewrite the committed baseline from this run's counters instead of
  /// failing on a mismatch. The only sanctioned way to change the baseline;
  /// the diff is reviewed and committed with the cause named (D4).
  public var updateBaseline: Bool
  /// Baseline file override; `nil` uses the committed
  /// `Baselines/bench-counters.json` beside the tool's sources.
  public var baselinePath: String?

  public init(
    artifactsRoot: String = defaultArtifactsRoot,
    configuration: String = PerfRunConfig.defaultConfiguration,
    warmIterations: Int = defaultWarmIterations,
    coldIterations: Int = defaultColdIterations,
    members: [PerfScenarioName]? = nil,
    skipWarm: Bool = false,
    updateBaseline: Bool = false,
    baselinePath: String? = nil
  ) {
    self.artifactsRoot = artifactsRoot
    self.configuration = configuration
    self.warmIterations = warmIterations
    self.coldIterations = coldIterations
    self.members = members
    self.skipWarm = skipWarm
    self.updateBaseline = updateBaseline
    self.baselinePath = baselinePath
  }
}

public struct PerfBenchLaneReport: Codable, Equatable, Sendable {
  /// `warm-sync`, `warm-async`, ... (`cold` lands in Stage 1).
  public var lane: String
  public var aggregate: PerfAggregateSummary

  public init(lane: String, aggregate: PerfAggregateSummary) {
    self.lane = lane
    self.aggregate = aggregate
  }
}

public struct PerfBenchMemberReport: Codable, Equatable, Sendable {
  public var scenario: String
  public var lanes: [PerfBenchLaneReport]
  /// The cold one-shot lane (Stage 1). Present for every member — a suite
  /// member that cannot cold-render fails the run rather than omitting the
  /// lane silently.
  public var cold: PerfBenchColdReport?

  public init(
    scenario: String,
    lanes: [PerfBenchLaneReport],
    cold: PerfBenchColdReport? = nil
  ) {
    self.scenario = scenario
    self.lanes = lanes
    self.cold = cold
  }
}

/// The one-file result of a `bench` run (D6): suite manifest, per-member
/// per-lane aggregates, and run provenance.
public struct PerfBenchReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public var schemaVersion: Int
  public var generatedAt: String
  public var configuration: String
  /// The full suite's member names — recorded even when `--member` narrowed
  /// the run, so a partial report is legible as partial.
  public var suite: [String]
  public var members: [PerfBenchMemberReport]
  /// Provenance from the first executed run (git SHA, dirty flag, toolchain,
  /// host). `nil` only if the member filter selected nothing.
  public var provenance: PerfRunMetadata?
  /// The D4 ratchet verdicts, one row per (scenario, lane, counter) in the
  /// ratchet scope: cold for every member, warm-sync for the closed-loop
  /// click members.
  public var ratchet: [PerfBenchRatchetRow]
  public var ratchetPassed: Bool
  /// Whether this run rewrote the baseline (`--update-baseline`).
  public var baselineUpdated: Bool

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    generatedAt: String,
    configuration: String,
    suite: [String],
    members: [PerfBenchMemberReport],
    provenance: PerfRunMetadata? = nil,
    ratchet: [PerfBenchRatchetRow] = [],
    ratchetPassed: Bool = true,
    baselineUpdated: Bool = false
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.configuration = configuration
    self.suite = suite
    self.members = members
    self.provenance = provenance
    self.ratchet = ratchet
    self.ratchetPassed = ratchetPassed
    self.baselineUpdated = baselineUpdated
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case generatedAt = "generated_at"
    case configuration
    case suite
    case members
    case provenance
    case ratchet
    case ratchetPassed = "ratchet_passed"
    case baselineUpdated = "baseline_updated"
  }
}

public enum PerfBenchError: Error, Equatable, CustomStringConvertible {
  case notASuiteMember(String)
  case memberNotColdRenderable(String)

  public var description: String {
    switch self {
    case .notASuiteMember(let name):
      let known = BenchSuite.members.map(\.scenario.rawValue).joined(separator: ", ")
      return "'\(name)' is not a benchmark suite member. Suite: \(known)."
    case .memberNotColdRenderable(let name):
      return
        "suite member '\(name)' does not conform to BenchColdRenderable — every "
        + "member must support the cold lane (plan 2026-08-11-005 D3)."
    }
  }
}

public enum BenchCommand {
  public struct Outcome: Sendable {
    public var report: PerfBenchReport
    public var reportURL: URL
  }

  @MainActor
  public static func run(_ config: PerfBenchConfig) async throws -> Outcome {
    let selected = try selectedMembers(config)
    let benchRoot = URL(fileURLWithPath: config.artifactsRoot, isDirectory: true)
      .appendingPathComponent("bench-\(directoryTimestamp())", isDirectory: true)
    try FileManager.default.createDirectory(
      at: benchRoot, withIntermediateDirectories: true)

    let baselineURL =
      config.baselinePath.map { URL(fileURLWithPath: $0) }
      ?? PerfBenchBaseline.defaultLocation()
    // A missing baseline file is an empty baseline: every ratcheted counter
    // reads `new` and the run fails until `--update-baseline` seeds it.
    var baseline =
      (try? PerfBenchBaseline.load(from: baselineURL)) ?? PerfBenchBaseline()

    var memberReports: [PerfBenchMemberReport] = []
    var provenance: PerfRunMetadata?
    var ratchetRows: [PerfBenchRatchetRow] = []
    for member in selected {
      // Cold lane first: it is cheap, and its determinism check failing
      // should abort before the member's multi-minute warm lanes run.
      guard
        let coldRenderable = PerfScenarioRegistry.scenario(named: member.scenario)
          as? any BenchColdRenderable
      else {
        throw PerfBenchError.memberNotColdRenderable(member.scenario.rawValue)
      }
      let cold = try BenchColdLane.run(coldRenderable, iterations: config.coldIterations)

      var lanes: [PerfBenchLaneReport] = []
      for mode in member.warmModes where !config.skipWarm {
        let laneRoot =
          benchRoot
          .appendingPathComponent(member.scenario.rawValue, isDirectory: true)
          .appendingPathComponent("warm-\(mode.rawValue)", isDirectory: true)
        let outcome = try await RunCommand.run(
          PerfRunConfig(
            scenario: member.scenario,
            modes: [mode],
            iterations: config.warmIterations,
            artifactsRoot: laneRoot.path,
            configuration: config.configuration
          )
        )
        if provenance == nil {
          provenance = outcome.perIteration.first?.metadata
        }
        for aggregate in outcome.aggregates {
          lanes.append(
            PerfBenchLaneReport(lane: "warm-\(mode.rawValue)", aggregate: aggregate)
          )
        }
      }
      memberReports.append(
        PerfBenchMemberReport(
          scenario: member.scenario.rawValue,
          lanes: lanes,
          cold: cold
        )
      )

      // Ratchet scope (D4): the cold lane for every member, plus the warm
      // sync lane for the click-driven closed-loop members.
      var ratchetLanes: [(lane: String, values: [String: Int])] = [
        (BenchRatchet.coldLane, cold.counters.valuesByName)
      ]
      if member.warmSyncRatchets,
        let syncAggregate = lanes.first(where: { $0.lane == "warm-sync" })?.aggregate
      {
        let warm = BenchRatchet.warmRatchetValues(
          from: syncAggregate,
          scenario: member.scenario.rawValue
        )
        ratchetRows.append(contentsOf: warm.nondeterministic)
        ratchetLanes.append((BenchRatchet.warmSyncLane, warm.values))
      }
      for (lane, values) in ratchetLanes {
        if config.updateBaseline {
          // New value, preserved tolerance: a tolerance is a reviewed
          // decision and does not reset just because the value moved.
          let previous = baseline.entries(
            configuration: config.configuration,
            scenario: member.scenario.rawValue,
            lane: lane
          )
          baseline.setEntries(
            Dictionary(
              uniqueKeysWithValues: values.map { name, value in
                (
                  name,
                  PerfBenchBaselineEntry(
                    value: value,
                    tolerance: previous[name]?.tolerance ?? 0
                  )
                )
              }
            ),
            configuration: config.configuration,
            scenario: member.scenario.rawValue,
            lane: lane
          )
        }
        ratchetRows.append(
          contentsOf: BenchRatchet.evaluate(
            current: values,
            baseline: baseline.entries(
              configuration: config.configuration,
              scenario: member.scenario.rawValue,
              lane: lane
            ),
            scenario: member.scenario.rawValue,
            lane: lane
          )
        )
      }
    }

    if config.updateBaseline {
      try baseline.write(to: baselineURL)
    }

    let report = PerfBenchReport(
      generatedAt: isoTimestamp(),
      configuration: config.configuration,
      suite: BenchSuite.members.map(\.scenario.rawValue),
      members: memberReports,
      provenance: provenance,
      ratchet: ratchetRows,
      ratchetPassed: ratchetRows.allSatisfy(\.passed),
      baselineUpdated: config.updateBaseline
    )
    let reportURL = benchRoot.appendingPathComponent("report.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try encoder.encode(report).write(to: reportURL)
    return Outcome(report: report, reportURL: reportURL)
  }

  public static func format(_ report: PerfBenchReport) -> String {
    var lines = [
      "bench suite (\(report.configuration)): "
        + report.suite.joined(separator: ", ")
    ]
    for member in report.members {
      if let cold = member.cold {
        lines.append("")
        lines.append("=== \(member.scenario) [cold] ===")
        lines.append(formatCold(cold))
      }
      for lane in member.lanes {
        lines.append("")
        lines.append("=== \(member.scenario) [\(lane.lane)] ===")
        lines.append(AggregateReducer.format(lane.aggregate))
      }
    }
    if !report.ratchet.isEmpty {
      lines.append("")
      lines.append(BenchRatchet.format(report.ratchet))
    }
    if report.baselineUpdated {
      lines.append("baseline: UPDATED — review and commit the diff with the cause named")
    } else {
      lines.append(report.ratchetPassed ? "ratchet: PASS" : "ratchet: FAIL")
      if !report.ratchetPassed {
        for row in report.ratchet where !row.passed {
          lines.append(
            "  - \(row.scenario)/\(row.lane)/\(row.counter): \(row.verdict.rawValue)"
          )
        }
        lines.append(
          "an intentional change reruns with --update-baseline and commits the diff"
        )
      }
    }
    return lines.joined(separator: "\n")
  }

  private static func formatCold(_ cold: PerfBenchColdReport) -> String {
    var lines = [
      "iterations: \(cold.iterations) "
        + "(1 = first render, 2-3 discarded, \(cold.renderMs.sampleCount) measured)",
      "first render ms: \(String(format: "%.3f", cold.firstRenderMs))",
      statLine("render ms", cold.renderMs),
      statLine("resolve ms", cold.resolveMs),
      statLine("measure ms", cold.measureMs),
      statLine("place ms", cold.placeMs),
      statLine("draw ms", cold.drawMs),
      statLine("raster ms", cold.rasterMs),
      "deterministic counters (bit-identical across all iterations):",
    ]
    for (name, value) in cold.counters.orderedEntries {
      lines.append("  \(name): \(value)")
    }
    return lines.joined(separator: "\n")
  }

  private static func statLine(_ label: String, _ stat: PerfStat) -> String {
    guard stat.sampleCount > 0 else {
      return "\(label): n/a (0 samples)"
    }
    return "\(label): \(String(format: "%.3f", stat.median)) "
      + "+/- \(String(format: "%.3f", stat.stddev)) (n=\(stat.sampleCount))"
  }

  private static func selectedMembers(_ config: PerfBenchConfig) throws -> [BenchMember] {
    guard let requested = config.members else {
      return BenchSuite.members
    }
    return try requested.map { name in
      guard let member = BenchSuite.member(named: name) else {
        throw PerfBenchError.notASuiteMember(name.rawValue)
      }
      return member
    }
  }

  /// Filesystem-safe run-directory stamp (local time, second resolution).
  private static func directoryTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
  }

  private static func isoTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: Date())
  }
}
