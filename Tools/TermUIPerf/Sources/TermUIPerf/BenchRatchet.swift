import Foundation

/// One committed baseline entry: an exact counter value with an optional
/// tolerance (default 0). Encoded as a bare integer when the tolerance is 0
/// — the D4 schema — and as `{"value": N, "tolerance": T}` otherwise.
public struct PerfBenchBaselineEntry: Codable, Equatable, Sendable {
  public var value: Int
  public var tolerance: Int

  public init(value: Int, tolerance: Int = 0) {
    self.value = value
    self.tolerance = tolerance
  }

  private enum CodingKeys: String, CodingKey {
    case value
    case tolerance
  }

  public init(from decoder: Decoder) throws {
    if let bare = try? decoder.singleValueContainer().decode(Int.self) {
      self.init(value: bare)
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      value: try container.decode(Int.self, forKey: .value),
      tolerance: try container.decodeIfPresent(Int.self, forKey: .tolerance) ?? 0
    )
  }

  public func encode(to encoder: Encoder) throws {
    if tolerance == 0 {
      var container = encoder.singleValueContainer()
      try container.encode(value)
      return
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(value, forKey: .value)
    try container.encode(tolerance, forKey: .tolerance)
  }
}

/// `configuration -> scenario -> lane -> counter -> entry`.
public typealias PerfBenchBaselineCounters =
  [String: [String: [String: [String: PerfBenchBaselineEntry]]]]

/// The committed counter baseline (plan 2026-08-11-005 D4):
/// `Tools/TermUIPerf/Baselines/bench-counters.json`. Growth fails the
/// ratchet; an intentional change reruns with `--update-baseline` and
/// commits the diff in the same landing with the cause named; an
/// unexplained shrink prompts tightening, not silence — which is why a
/// shrink also fails until the baseline is updated.
public struct PerfBenchBaseline: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public var schemaVersion: Int
  public var configurations: PerfBenchBaselineCounters
  /// Platform-keyed override sections (e.g. `linux-x86_64`), same nested
  /// shape. Empty by default; a populated entry requires a register-worthy
  /// justification (D7).
  public var platformOverrides: [String: PerfBenchBaselineCounters]

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    configurations: PerfBenchBaselineCounters = [:],
    platformOverrides: [String: PerfBenchBaselineCounters] = [:]
  ) {
    self.schemaVersion = schemaVersion
    self.configurations = configurations
    self.platformOverrides = platformOverrides
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case configurations
    case platformOverrides = "platform_overrides"
  }

  /// The committed baseline's location, resolved from this source file so
  /// `bench` finds it regardless of the invoking working directory. The
  /// tool only ever runs from a checkout, where `#filePath` is real.
  public static func defaultLocation() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // TermUIPerf
      .deletingLastPathComponent()  // Sources
      .deletingLastPathComponent()  // package root
      .appendingPathComponent("Baselines", isDirectory: true)
      .appendingPathComponent("bench-counters.json")
  }

  public static func load(from url: URL) throws -> PerfBenchBaseline {
    try JSONDecoder().decode(PerfBenchBaseline.self, from: Data(contentsOf: url))
  }

  public func write(to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try (try encoder.encode(self) + Data("\n".utf8)).write(to: url)
  }

  public func entries(
    configuration: String,
    scenario: String,
    lane: String
  ) -> [String: PerfBenchBaselineEntry] {
    configurations[configuration]?[scenario]?[lane] ?? [:]
  }

  public mutating func setEntries(
    _ entries: [String: PerfBenchBaselineEntry],
    configuration: String,
    scenario: String,
    lane: String
  ) {
    var scenarios = configurations[configuration] ?? [:]
    var lanes = scenarios[scenario] ?? [:]
    lanes[lane] = entries
    scenarios[scenario] = lanes
    configurations[configuration] = scenarios
  }
}

public enum PerfBenchRatchetVerdict: String, Codable, Equatable, Sendable {
  case ok
  /// Beyond tolerance in the growth direction — a work regression.
  case regressed
  /// Beyond tolerance in the shrink direction. Still a failure: an
  /// improvement is ratified by tightening the baseline in the same
  /// landing, not by silently drifting under it.
  case improved
  /// The run recorded a counter the baseline has no entry for.
  case new
  /// The baseline pins a counter the run no longer records.
  case stale
  /// A warm ratchet lane whose iterations disagreed — D3's identity
  /// requirement violated, so there is no single value to compare.
  case nondeterministic
}

/// One `counter | baseline | current | delta | verdict` row (D6).
public struct PerfBenchRatchetRow: Codable, Equatable, Sendable {
  public var scenario: String
  public var lane: String
  public var counter: String
  public var baseline: Int?
  public var current: Int?
  public var tolerance: Int
  public var verdict: PerfBenchRatchetVerdict

  public init(
    scenario: String,
    lane: String,
    counter: String,
    baseline: Int?,
    current: Int?,
    tolerance: Int = 0,
    verdict: PerfBenchRatchetVerdict
  ) {
    self.scenario = scenario
    self.lane = lane
    self.counter = counter
    self.baseline = baseline
    self.current = current
    self.tolerance = tolerance
    self.verdict = verdict
  }

  public var passed: Bool {
    verdict == .ok
  }
}

public enum BenchRatchet {
  /// The warm-lane name whose counters ratchet (D4): sync closed-loop only.
  public static let warmSyncLane = "warm-sync"
  public static let coldLane = "cold"

  /// The warm counters that ratchet: the per-INPUT work census — values that
  /// are a function of the scripted drive, not of how many frames the
  /// session happened to commit.
  ///
  /// This is the D4 kill-condition retreat, exercised: recording the debug
  /// baseline showed the session frame census varies by an idle/settle frame
  /// between identical fresh sessions even in sync closed-loop, and every
  /// per-frame-summed repaint counter (`committed_frames`, `draw_nodes`,
  /// `present_cells`, damage, `resolved_computed`/`reused`,
  /// `custom_placement_child_measure_requests`) inherits that variance.
  /// Those stay report-only in the warm lanes — and fully ratcheted in the
  /// cold lane, which has exactly one frame by construction.
  public static let warmRatchetCounters: Set<String> = [
    "answered_inputs",
    "measured_computed",
    "builtin_container_measures",
    "builtin_child_measure_requests",
    "builtin_child_measure_requests_probe",
    "custom_container_measures",
    "custom_child_measure_requests",
    "custom_child_measure_requests_probe",
    "realized_rows",
    "list_layout_derivations",
    "present_bytes",
  ]

  /// Evaluates one lane's recorded counters against the baseline section.
  ///
  /// Every comparison is two-sided at its tolerance: growth is a
  /// regression, shrink is an unratified improvement, and both fail until
  /// `--update-baseline` commits the new truth. Counters and baseline
  /// entries must also cover each other exactly (`new`/`stale` otherwise) —
  /// a ratchet that ignores unknown rows can be starved into silence.
  public static func evaluate(
    current: [String: Int],
    baseline: [String: PerfBenchBaselineEntry],
    scenario: String,
    lane: String
  ) -> [PerfBenchRatchetRow] {
    Set(current.keys)
      .union(baseline.keys)
      .sorted()
      .map { counter in
        let entry = baseline[counter]
        let value = current[counter]
        let verdict: PerfBenchRatchetVerdict
        switch (entry, value) {
        case (nil, _):
          verdict = .new
        case (_, nil):
          verdict = .stale
        case (let entry?, let value?):
          if abs(value - entry.value) <= entry.tolerance {
            verdict = .ok
          } else {
            verdict = value > entry.value ? .regressed : .improved
          }
        }
        return PerfBenchRatchetRow(
          scenario: scenario,
          lane: lane,
          counter: counter,
          baseline: entry?.value,
          current: value,
          tolerance: entry?.tolerance ?? 0,
          verdict: verdict
        )
      }
  }

  /// Extracts the single deterministic per-iteration value for each counter
  /// of a warm ratchet lane from its aggregate. A counter whose iterations
  /// disagreed yields a `.nondeterministic` row instead of a value —
  /// there is nothing sound to compare, and hiding that would certify a
  /// flaky census.
  public static func warmRatchetValues(
    from aggregate: PerfAggregateSummary,
    scenario: String
  ) -> (values: [String: Int], nondeterministic: [PerfBenchRatchetRow]) {
    guard let counters = aggregate.deterministicCounters else {
      return ([:], [])
    }
    var values: [String: Int] = [:]
    var unstable: [PerfBenchRatchetRow] = []
    for (name, stat) in counters {
      guard warmRatchetCounters.contains(name) else {
        continue
      }
      // Wire bytes only ratchet with the emission lane armed (D4): without
      // it the in-process host writes nothing and a pinned 0 would freeze
      // the lane-off accident into the baseline.
      if name == "present_bytes", !aggregate.emissionLane {
        continue
      }
      guard stat.sampleCount > 0 else {
        continue
      }
      if stat.min == stat.max {
        values[name] = Int(stat.min)
      } else {
        unstable.append(
          PerfBenchRatchetRow(
            scenario: scenario,
            lane: warmSyncLane,
            counter: name,
            baseline: nil,
            current: nil,
            verdict: .nondeterministic
          )
        )
      }
    }
    return (values, unstable)
  }

  public static func format(_ rows: [PerfBenchRatchetRow]) -> String {
    var lines = ["ratchet (counter | baseline | current | delta | verdict):"]
    for row in rows {
      let baseline = row.baseline.map(String.init) ?? "-"
      let current = row.current.map(String.init) ?? "-"
      let delta: String
      if let b = row.baseline, let c = row.current {
        let d = c - b
        delta = d >= 0 ? "+\(d)" : "\(d)"
      } else {
        delta = "-"
      }
      let tolerance = row.tolerance > 0 ? " (tolerance \(row.tolerance))" : ""
      lines.append(
        "  \(row.scenario)/\(row.lane)/\(row.counter): "
          + "\(baseline) | \(current) | \(delta) | \(row.verdict.rawValue)\(tolerance)"
      )
    }
    return lines.joined(separator: "\n")
  }
}
