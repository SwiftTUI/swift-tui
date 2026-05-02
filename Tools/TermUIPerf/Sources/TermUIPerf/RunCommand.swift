import Foundation

public enum RunCommand {
  @MainActor
  public static func run(_ config: PerfRunConfig) async throws -> [PerfScenarioRunResult] {
    guard let scenario = PerfScenarioRegistry.scenario(named: config.scenario) else {
      throw PerfParseError.unknownScenario(config.scenario.rawValue)
    }

    var results: [PerfScenarioRunResult] = []
    let artifactRoot = URL(fileURLWithPath: config.artifactsRoot, isDirectory: true)
    for mode in config.modes {
      let result = try await scenario.run(
        options: PerfScenarioRunOptions(
          renderMode: mode,
          iterations: config.iterations,
          artifactRoot: artifactRoot,
          configuration: config.configuration
        ))
      results.append(result)
    }
    return results
  }
}
