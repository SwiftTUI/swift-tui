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
  try run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
  FileHandle.standardError.writeLine("error: \(error)")
  exit(64)
}

private func run(arguments: [String]) throws {
  let command = try PerfCommandParser.parse(arguments)
  switch command {
  case .listScenarios:
    for scenarioName in PerfScenarioName.allNames {
      print(scenarioName)
    }
  case .run(let config):
    let modes = config.modes.map(\.rawValue).joined(separator: ",")
    print(
      """
      run command parsed
      scenario: \(config.scenario.rawValue)
      modes: \(modes)
      iterations: \(config.iterations)
      artifacts-root: \(config.artifactsRoot)
      configuration: \(config.configuration)
      """
    )
  case .compare(let config):
    print(
      """
      compare command parsed
      base: \(config.baseRunDirectory)
      candidate: \(config.candidateRunDirectory)
      """
    )
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
