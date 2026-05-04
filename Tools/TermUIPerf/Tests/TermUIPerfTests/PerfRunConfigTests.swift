import SwiftTUI
import Testing

@testable import TermUIPerf

struct PerfRunConfigTests {
  @Test("run command parses required scenario")
  func runCommandParsesRequiredScenario() throws {
    let command = try PerfCommandParser.parse([
      "run",
      "--scenario",
      "gallery-animation-click",
    ])

    #expect(
      command
        == .run(
          PerfRunConfig(
            scenario: .galleryAnimationClick,
            modes: [.async],
            iterations: 20,
            artifactsRoot: ".perf/runs",
            configuration: "release"
          )))
  }

  @Test("run command parses singular mode option")
  func runCommandParsesSingularModeOption() throws {
    let command = try PerfCommandParser.parse([
      "run",
      "--scenario",
      "gallery-animation-click",
      "--mode",
      "sync",
    ])

    #expect(
      command
        == .run(
          PerfRunConfig(
            scenario: .galleryAnimationClick,
            modes: [.sync]
          )))
  }

  @Test("run command parses comma separated mode list")
  func runCommandParsesCommaSeparatedModeList() throws {
    let command = try PerfCommandParser.parse([
      "run",
      "--scenario",
      "layout-scroll-burst",
      "--modes",
      "sync,async,async-no-cancel,async-no-drop",
      "--iterations",
      "7",
      "--artifacts-root",
      ".perf/custom",
      "--configuration",
      "debug",
    ])

    #expect(
      command
        == .run(
          PerfRunConfig(
            scenario: .layoutScrollBurst,
            modes: [.sync, .async, .asyncNoCancel, .asyncNoDrop],
            iterations: 7,
            artifactsRoot: ".perf/custom",
            configuration: "debug"
          )))
  }

  @Test("run command rejects unknown scenario with known names")
  func runCommandRejectsUnknownScenarioWithKnownNames() throws {
    let error = #expect(throws: PerfParseError.self) {
      try PerfCommandParser.parse([
        "run",
        "--scenario",
        "missing-scenario",
      ])
    }

    #expect(
      error?.description
        == "unknown scenario 'missing-scenario'. Known scenarios: gallery-animation-click, layout-scroll-burst."
    )
  }

  @Test("run command rejects invalid iterations")
  func runCommandRejectsInvalidIterations() throws {
    let error = #expect(throws: PerfParseError.self) {
      try PerfCommandParser.parse([
        "run",
        "--scenario",
        "gallery-animation-click",
        "--iterations",
        "0",
      ])
    }

    #expect(error?.description == "invalid iterations '0'. Use a positive integer.")
  }

  @Test("run command rejects unknown mode with known names")
  func runCommandRejectsUnknownModeWithKnownNames() throws {
    let error = #expect(throws: PerfParseError.self) {
      try PerfCommandParser.parse([
        "run",
        "--scenario",
        "gallery-animation-click",
        "--mode",
        "main-thread",
      ])
    }

    #expect(
      error?.description
        == "unknown render mode 'main-thread'. Known modes: sync, async, async-no-cancel, async-no-drop."
    )
  }

  @Test("compare command parses run directories")
  func compareCommandParsesRunDirectories() throws {
    let command = try PerfCommandParser.parse([
      "compare",
      ".perf/runs/base",
      ".perf/runs/candidate",
    ])

    #expect(
      command
        == .compare(
          PerfCompareConfig(
            baseRunDirectory: ".perf/runs/base",
            candidateRunDirectory: ".perf/runs/candidate"
          )))
  }

  @Test("list scenarios command parses without arguments")
  func listScenariosCommandParsesWithoutArguments() throws {
    let command = try PerfCommandParser.parse(["list-scenarios"])

    #expect(command == .listScenarios)
  }
}
