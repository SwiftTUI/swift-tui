import Foundation
import SwiftTUI
import SwiftTUICLI
import Testing

@testable import SwiftTUIWebHost
@testable import SwiftTUIWebHostCLI

@Suite
@MainActor
struct WebHostCLIRunnerTests {
  @Test("combined runner parses standard SwiftTUI web arguments")
  func combinedRunnerParsesStandardSwiftTUIWebArguments() throws {
    let configuration = try WebHostCLIRunner.runtimeConfiguration(
      arguments: ["--web", "--port", "4567", "--bind", "127.0.0.1", "--open"],
      environment: [:],
      isStdoutTTY: true
    )

    #expect(configuration.web?.port == 4567)
    #expect(configuration.web?.bind == "127.0.0.1")
    #expect(configuration.web?.openBrowser == true)
  }

  @Test("combined runner routes web configuration to WebHost runner")
  func combinedRunnerRoutesWebConfigurationToWebHostRunner() async throws {
    var route: RunnerRoute?

    try await WebHostCLIRunner.run(
      SingleSceneApp(),
      configuration: .init(web: .init()),
      webRunner: { _, configuration in
        route = .web(configuration)
      },
      terminalRunner: { _, configuration in
        route = .terminal(configuration)
      }
    )

    #expect(route?.isWeb == true)
  }

  @Test("combined runner routes terminal configuration to TerminalRunner")
  func combinedRunnerRoutesTerminalConfigurationToTerminalRunner() async throws {
    var route: RunnerRoute?

    try await WebHostCLIRunner.run(
      SingleSceneApp(),
      configuration: .default,
      webRunner: { _, configuration in
        route = .web(configuration)
      },
      terminalRunner: { _, configuration in
        route = .terminal(configuration)
      }
    )

    #expect(route?.isTerminal == true)
  }

  @Test("terminal-only runner still rejects web configuration")
  func terminalOnlyRunnerStillRejectsWebConfiguration() async throws {
    do {
      try await TerminalRunner.run(SingleSceneApp(), configuration: .init(web: .init()))
      Issue.record("Expected terminal-only runner to reject web configuration.")
    } catch let error as TerminalRunnerError {
      #expect(error == .webHostNotLinked)
    } catch {
      Issue.record("Expected TerminalRunnerError.webHostNotLinked, got \(error).")
    }
  }

  @Test("SwiftTUICLI package graph remains server-free")
  func swiftTUICLIPackageGraphRemainsServerFree() throws {
    let packageURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Platforms/CLI/Package.swift")
    let source = try String(contentsOf: packageURL, encoding: .utf8)

    #expect(!source.contains("SwiftTUIWebHost"))
    #expect(!source.contains("FlyingFox"))
  }
}

@MainActor
private struct SingleSceneApp: App {
  var body: some Scene {
    WindowGroup("Primary", id: WindowIdentifier("primary")) {
      Text("Primary")
    }
  }
}

private enum RunnerRoute: Equatable {
  case web(RuntimeConfiguration)
  case terminal(RuntimeConfiguration)

  var isWeb: Bool {
    if case .web = self {
      return true
    }
    return false
  }

  var isTerminal: Bool {
    if case .terminal = self {
      return true
    }
    return false
  }
}
