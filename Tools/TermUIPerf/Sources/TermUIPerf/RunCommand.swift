import Foundation
import SwiftTUI

/// Result of a perf run: every per-iteration result, plus one aggregate per mode.
public struct PerfRunOutcome: Sendable {
  /// All per-iteration results, ordered `modes x iterations` (i.e. the first
  /// `iterations` entries are mode[0], the next `iterations` are mode[1], ...).
  /// Read `result.metadata.renderMode` to attribute an entry to its mode.
  public var perIteration: [PerfScenarioRunResult]
  /// One aggregate per render mode, in `config.modes` order. An `--aa-check`
  /// contributes two per mode, in pass order.
  public var aggregates: [PerfAggregateSummary]
  /// One recorded A/A envelope per render mode, in `config.modes` order.
  /// Empty unless the run was an `--aa-check`.
  public var aaEnvelopes: [PerfAAEnvelope]

  public init(
    perIteration: [PerfScenarioRunResult],
    aggregates: [PerfAggregateSummary],
    aaEnvelopes: [PerfAAEnvelope] = []
  ) {
    self.perIteration = perIteration
    self.aggregates = aggregates
    self.aaEnvelopes = aaEnvelopes
  }
}

public enum RunCommand {
  @MainActor
  public static func run(_ config: PerfRunConfig) async throws -> PerfRunOutcome {
    guard let scenario = PerfScenarioRegistry.scenario(named: config.scenario) else {
      throw PerfParseError.unknownScenario(config.scenario.rawValue)
    }

    if PerfEmissionLane.isEnabled {
      // Stderr, not stdout: run output (run directories, aggregates) is
      // consumed by scripts. The fixed profile is documented here so a saved
      // log records what the bytes were counted under.
      FileHandle.standardError.write(
        Data(
          ("emission lane armed (\(PerfEmissionLane.environmentVariableName)=1): "
            + "presenting through the real terminal planner+emission builder. "
            + "Fixed profile: unicode glyphs, truecolor styling, hyperlinks on, "
            + "synchronized output ON, kitty graphics OFF, CSI-K lowering ON. "
            + "Compare lane-on runs only against lane-on runs.\n").utf8
        )
      )
    }
    let artifactRoot = URL(fileURLWithPath: config.artifactsRoot, isDirectory: true)
    if config.aaCheck {
      return try await runAACheck(config, scenario: scenario, artifactRoot: artifactRoot)
    }

    PerfScenarioRunner.configureReuseTraceArtifact(at: artifactRoot)
    var perIteration: [PerfScenarioRunResult] = []
    var aggregates: [PerfAggregateSummary] = []

    for mode in config.modes {
      let pass = try await runPass(
        config,
        scenario: scenario,
        mode: mode,
        artifactRoot: artifactRoot
      )
      perIteration.append(contentsOf: pass.results)
      aggregates.append(pass.aggregate)
      try writeAggregate(pass.aggregate, to: artifactRoot, tag: config.tag)
    }

    return PerfRunOutcome(perIteration: perIteration, aggregates: aggregates)
  }

  /// Runs the scenario twice back-to-back per mode and records what identical
  /// runs disagree by — this machine's noise, measured rather than assumed.
  ///
  /// The two passes write into `aa-1/` and `aa-2/` subdirectories rather than
  /// into the root. `loadAggregate` requires a directory to hold exactly one
  /// `aggregate-*.json`, so dropping two more at the root would break every
  /// later `--gate <root>` on it; the subdirectories keep both passes' data
  /// fully inspectable — an A/A pair *is* evidence — while leaving the root's
  /// single-aggregate shape intact for the real run that follows.
  @MainActor
  private static func runAACheck(
    _ config: PerfRunConfig,
    scenario: any PerfScenario,
    artifactRoot: URL
  ) async throws -> PerfRunOutcome {
    var perIteration: [PerfScenarioRunResult] = []
    var aggregates: [PerfAggregateSummary] = []
    var envelopes: [PerfAAEnvelope] = []

    for mode in config.modes {
      var passAggregates: [PerfAggregateSummary] = []
      for passIndex in 1...2 {
        let passRoot = artifactRoot.appendingPathComponent("aa-\(passIndex)", isDirectory: true)
        try FileManager.default.createDirectory(
          at: passRoot, withIntermediateDirectories: true)
        PerfScenarioRunner.configureReuseTraceArtifact(at: passRoot)
        let pass = try await runPass(
          config,
          scenario: scenario,
          mode: mode,
          artifactRoot: passRoot
        )
        perIteration.append(contentsOf: pass.results)
        passAggregates.append(pass.aggregate)
        try writeAggregate(pass.aggregate, to: passRoot, tag: config.tag)
      }

      let envelope = PerfAAEnvelope.record(
        runA: passAggregates[0],
        runB: passAggregates[1],
        iterations: config.iterations,
        generatedAt: timestamp()
      )
      try writeAAEnvelope(envelope, to: artifactRoot)
      aggregates.append(contentsOf: passAggregates)
      envelopes.append(envelope)
    }

    return PerfRunOutcome(
      perIteration: perIteration,
      aggregates: aggregates,
      aaEnvelopes: envelopes
    )
  }

  @MainActor
  private static func runPass(
    _ config: PerfRunConfig,
    scenario: any PerfScenario,
    mode: RuntimeRenderMode,
    artifactRoot: URL
  ) async throws -> (results: [PerfScenarioRunResult], aggregate: PerfAggregateSummary) {
    var results: [PerfScenarioRunResult] = []
    var summaries: [PerfSummary] = []
    for _ in 0..<config.iterations {
      let result = try await scenario.run(
        options: PerfScenarioRunOptions(
          renderMode: mode,
          iterations: 1,
          artifactRoot: artifactRoot,
          configuration: config.configuration,
          terminalSize: config.terminalSize
        ))
      summaries.append(result.summary)
      results.append(result)
    }
    var aggregate = AggregateReducer.reduce(summaries)
    aggregate.generatedAt = timestamp()
    return (results, aggregate)
  }

  /// Writes `aggregate-<scenario>-<mode>[-<tag>].json` at the artifact root so
  /// `CompareCommand.compareAggregates` can load it later. Untagged, the
  /// filename is stable (no timestamp) and repeated runs into the SAME
  /// `--artifacts-root` overwrite it; the per-iteration run directories are
  /// timestamped and are never clobbered.
  ///
  /// `--tag` exists because that overwrite is silent, and an A/B whose base was
  /// quietly replaced by its own candidate reports no difference — a passing
  /// result that means nothing. The embedded `generated_at` covers the same
  /// hazard for files already on disk. Filenames stay unchanged without a tag:
  /// always-timestamped names would be a flag day for every existing script.
  private static func writeAggregate(
    _ aggregate: PerfAggregateSummary,
    to artifactRoot: URL,
    tag: String?
  ) throws {
    try FileManager.default.createDirectory(
      at: artifactRoot, withIntermediateDirectories: true)
    let suffix = tag.map { "-\($0)" } ?? ""
    let name = "aggregate-\(aggregate.scenario)-\(aggregate.renderMode)\(suffix).json"
    try write(aggregate, to: artifactRoot.appendingPathComponent(name))
  }

  private static func writeAAEnvelope(
    _ envelope: PerfAAEnvelope,
    to artifactRoot: URL
  ) throws {
    try FileManager.default.createDirectory(
      at: artifactRoot, withIntermediateDirectories: true)
    let name = PerfAAEnvelope.fileName(
      scenario: envelope.scenario,
      renderMode: envelope.renderMode
    )
    try write(envelope, to: artifactRoot.appendingPathComponent(name))
  }

  private static func write(_ value: some Encodable, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try encoder.encode(value).write(to: url)
  }

  private static func timestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: Date())
  }
}
