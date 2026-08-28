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

/// Prints the recorded envelope widest-first: the metrics this machine is
/// least able to resolve are the ones an operator most needs to see before
/// trusting a delta in them.
private func formatAAEnvelope(_ envelope: PerfAAEnvelope) -> String {
  var lines = [
    "A/A envelope: \(envelope.scenario) \(envelope.renderMode) "
      + "(\(envelope.iterations) iterations x2)"
  ]
  for (metric, relative) in envelope.relativeDeltas.sorted(by: { $0.value > $1.value }) {
    lines.append("  \(metric): ±\(String(format: "%.2f", relative * 100))%")
  }
  return lines.joined(separator: "\n")
}

@MainActor
private func run(arguments: [String]) async throws {
  let command = try PerfCommandParser.parse(arguments)
  switch command {
  case .listScenarios:
    for scenarioName in PerfScenarioName.allNames {
      print(scenarioName)
    }
  case .bench(let config):
    let outcome = try await BenchCommand.run(config)
    print(BenchCommand.format(outcome.report))
    print("report: \(outcome.reportURL.path)")
    if !outcome.report.ratchetPassed {
      exit(1)
    }
  case .run(let config):
    let outcome = try await RunCommand.run(config)
    for result in outcome.perIteration {
      print(result.runDirectory.path)
    }
    for aggregate in outcome.aggregates {
      print(AggregateReducer.format(aggregate))
    }
    for envelope in outcome.aaEnvelopes {
      print(formatAAEnvelope(envelope))
    }
  case .compare(let config):
    if config.gateEnabled {
      let base = try CompareCommand.loadAggregate(from: config.baseRunDirectory)
      let candidate = try CompareCommand.loadAggregate(from: config.candidateRunDirectory)
      try CompareCommand.requireMatchingEmissionLanes(
        base: base.emissionLane,
        candidate: candidate.emissionLane
      )
      try CompareCommand.requireMatchingBuildConfigurations(
        base: base.configuration,
        candidate: candidate.configuration
      )
      // Either side may carry the envelope; the candidate's is preferred
      // because it was recorded on the code under test.
      let envelope =
        CompareCommand.loadAAEnvelope(
          besideAggregateAt: config.candidateRunDirectory,
          scenario: candidate.scenario,
          renderMode: candidate.renderMode
        )
        ?? CompareCommand.loadAAEnvelope(
          besideAggregateAt: config.baseRunDirectory,
          scenario: base.scenario,
          renderMode: base.renderMode
        )
      let comparison = CompareCommand.compareAggregates(
        base: base,
        candidate: candidate,
        sigma: config.sigma,
        aaEnvelope: envelope
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
