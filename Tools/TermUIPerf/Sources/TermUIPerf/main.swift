import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

do {
  try await run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
  FileHandle.standardError.writeLine("error: \(error)")
  exit(64)
}

@MainActor
private func run(arguments: [String]) async throws {
  let command = try PerfCommandParser.parse(arguments)
  switch command {
  case .listScenarios:
    for scenarioName in PerfScenarioName.allNames {
      print(scenarioName)
    }
  case .run(let config):
    let outcome = try await RunCommand.run(config)
    for result in outcome.perIteration {
      print(result.runDirectory.path)
    }
    for aggregate in outcome.aggregates {
      print(AggregateReducer.format(aggregate))
    }
  case .compare(let config):
    if config.gateEnabled {
      let base = try CompareCommand.loadAggregate(from: config.baseRunDirectory)
      let candidate = try CompareCommand.loadAggregate(from: config.candidateRunDirectory)
      let comparison = CompareCommand.compareAggregates(
        base: base,
        candidate: candidate,
        sigma: config.sigma
      )
      print(CompareCommand.format(comparison))
      let outcome = CompareCommand.evaluateGate(
        comparison,
        requireImprovement: config.requireImprovement
      )
      print(CompareCommand.formatGate(outcome))
      if !outcome.passed {
        exit(1)
      }
    } else {
      let result = try CompareCommand.compare(config)
      print(CompareCommand.format(result))
    }
  }
}

extension FileHandle {
  fileprivate func writeLine(_ string: String) {
    guard let data = "\(string)\n".data(using: .utf8) else {
      return
    }
    write(data)
  }
}
