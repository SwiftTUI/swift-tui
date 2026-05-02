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
    let results = try await RunCommand.run(config)
    for result in results {
      print(result.runDirectory.path)
    }
  case .compare(let config):
    let result = try CompareCommand.compare(config)
    print(CompareCommand.format(result))
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
