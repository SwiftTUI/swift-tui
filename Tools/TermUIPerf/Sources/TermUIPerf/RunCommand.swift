import Foundation

/// Result of a perf run: every per-iteration result, plus one aggregate per mode.
public struct PerfRunOutcome: Sendable {
  /// All per-iteration results, ordered `modes x iterations` (i.e. the first
  /// `iterations` entries are mode[0], the next `iterations` are mode[1], ...).
  /// Read `result.metadata.renderMode` to attribute an entry to its mode.
  public var perIteration: [PerfScenarioRunResult]
  /// One aggregate per render mode, in `config.modes` order.
  public var aggregates: [PerfAggregateSummary]

  public init(perIteration: [PerfScenarioRunResult], aggregates: [PerfAggregateSummary]) {
    self.perIteration = perIteration
    self.aggregates = aggregates
  }
}

public enum RunCommand {
  @MainActor
  public static func run(_ config: PerfRunConfig) async throws -> PerfRunOutcome {
    guard let scenario = PerfScenarioRegistry.scenario(named: config.scenario) else {
      throw PerfParseError.unknownScenario(config.scenario.rawValue)
    }

    let artifactRoot = URL(fileURLWithPath: config.artifactsRoot, isDirectory: true)
    PerfScenarioRunner.configureReuseTraceArtifact(at: artifactRoot)
    var perIteration: [PerfScenarioRunResult] = []
    var aggregates: [PerfAggregateSummary] = []

    for mode in config.modes {
      var modeSummaries: [PerfSummary] = []
      for _ in 0..<config.iterations {
        let result = try await scenario.run(
          options: PerfScenarioRunOptions(
            renderMode: mode,
            iterations: 1,
            artifactRoot: artifactRoot,
            configuration: config.configuration
          ))
        modeSummaries.append(result.summary)
        perIteration.append(result)
      }
      let aggregate = AggregateReducer.reduce(modeSummaries)
      aggregates.append(aggregate)
      try writeAggregate(aggregate, to: artifactRoot)
    }

    return PerfRunOutcome(perIteration: perIteration, aggregates: aggregates)
  }

  /// Writes `aggregate-<scenario>-<mode>.json` at the artifact root so
  /// `CompareCommand.compareAggregates` can load it later. The filename is
  /// stable (no timestamp), so repeated runs into the SAME `--artifacts-root`
  /// overwrite it; the per-iteration run directories are timestamped and are
  /// never clobbered. For a baseline-vs-candidate comparison, run the two into
  /// distinct artifact roots (or copy the aggregate aside) before comparing.
  private static func writeAggregate(
    _ aggregate: PerfAggregateSummary,
    to artifactRoot: URL
  ) throws {
    try FileManager.default.createDirectory(
      at: artifactRoot, withIntermediateDirectories: true)
    let name = "aggregate-\(aggregate.scenario)-\(aggregate.renderMode).json"
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let data = try encoder.encode(aggregate)
    try data.write(to: artifactRoot.appendingPathComponent(name))
  }
}
