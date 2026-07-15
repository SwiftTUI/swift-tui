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
        == "unknown scenario 'missing-scenario'. Known scenarios: canvas-partial-reuse, example-app-shell-workflow, file-browser-selection, gallery-animation-click, gallery-tab-switch, gif-playback, layout-scroll-burst, lazy-list-1k, memo-equatable-boundary, sheet-open-latency, synthetic-continuous-animation, synthetic-narrow-invalidation, synthetic-observable-fanout, synthetic-offscreen-phase-animator, synthetic-text-shimmer, table-1kx4, text-input-editing."
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

  @Test("compare command parses the gate flags")
  func compareCommandParsesGateFlags() throws {
    let command = try PerfCommandParser.parse([
      "compare",
      "base.json",
      "candidate.json",
      "--gate",
      "--require-improvement", "total CPU seconds,CPU seconds/frame",
      "--sigma", "3",
    ])

    #expect(
      command
        == .compare(
          PerfCompareConfig(
            baseRunDirectory: "base.json",
            candidateRunDirectory: "candidate.json",
            gate: true,
            requireImprovement: ["total CPU seconds", "CPU seconds/frame"],
            sigma: 3
          )))
  }

  @Test("compare gate is enabled by --require-improvement alone")
  func compareGateEnabledByRequireImprovement() throws {
    let command = try PerfCommandParser.parse([
      "compare", "base.json", "candidate.json",
      "--require-improvement", "total CPU seconds",
    ])

    guard case .compare(let config) = command else {
      Issue.record("expected a compare command")
      return
    }
    #expect(config.gateEnabled)
    #expect(!config.gate)
  }

  @Test("compare rejects an invalid sigma")
  func compareRejectsInvalidSigma() throws {
    #expect(throws: PerfParseError.invalidSigma("nope")) {
      try PerfCommandParser.parse([
        "compare", "base.json", "candidate.json", "--sigma", "nope",
      ])
    }
  }

  @Test("compare still rejects a wrong positional count alongside flags")
  func compareRejectsWrongPositionalCount() throws {
    #expect(throws: PerfParseError.compareArgumentCount(1)) {
      try PerfCommandParser.parse(["compare", "only-one.json", "--gate"])
    }
  }

  @Test("list scenarios command parses without arguments")
  func listScenariosCommandParsesWithoutArguments() throws {
    let command = try PerfCommandParser.parse(["list-scenarios"])

    #expect(command == .listScenarios)
  }
}
