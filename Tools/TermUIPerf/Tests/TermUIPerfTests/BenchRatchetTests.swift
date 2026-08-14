import Foundation
import Testing

@testable import TermUIPerf

/// Plan 2026-08-11-005 Stage 3: the deterministic-counter ratchet against
/// the committed baseline.
struct BenchRatchetTests {
  @Test("baseline entries encode bare integers and round-trip tolerances")
  func baselineEntryRoundTrip() throws {
    var baseline = PerfBenchBaseline()
    baseline.setEntries(
      [
        "measured_computed": PerfBenchBaselineEntry(value: 417),
        "present_cells": PerfBenchBaselineEntry(value: 549, tolerance: 2),
      ],
      configuration: "debug",
      scenario: "bench-deep-grid",
      lane: "cold"
    )
    let data = try JSONEncoder().encode(baseline)
    let json = String(decoding: data, as: UTF8.self)
    // D4 schema: tolerance-0 entries are bare integers.
    #expect(json.contains("\"measured_computed\":417"))
    #expect(json.contains("\"tolerance\":2"))

    let decoded = try JSONDecoder().decode(PerfBenchBaseline.self, from: data)
    #expect(decoded == baseline)
    #expect(decoded.platformOverrides.isEmpty)
  }

  @Test("ratchet verdicts: ok, tolerance, regressed, improved, new, stale")
  func ratchetVerdicts() {
    let baseline: [String: PerfBenchBaselineEntry] = [
      "exact": PerfBenchBaselineEntry(value: 100),
      "banded": PerfBenchBaselineEntry(value: 100, tolerance: 5),
      "grew": PerfBenchBaselineEntry(value: 100),
      "shrank": PerfBenchBaselineEntry(value: 100),
      "gone": PerfBenchBaselineEntry(value: 7),
    ]
    let rows = BenchRatchet.evaluate(
      current: [
        "exact": 100,
        "banded": 104,
        "grew": 101,
        "shrank": 99,
        "fresh": 3,
      ],
      baseline: baseline,
      scenario: "s",
      lane: "cold"
    )
    let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.counter, $0.verdict) })
    #expect(byName["exact"] == .ok)
    #expect(byName["banded"] == .ok)
    #expect(byName["grew"] == .regressed)
    #expect(byName["shrank"] == .improved)
    #expect(byName["fresh"] == .new)
    #expect(byName["gone"] == .stale)
    // Anything but ok fails: growth is a regression, shrink is an
    // unratified improvement, coverage gaps are coverage gaps.
    #expect(rows.filter { !$0.passed }.count == 4)
  }

  @Test("warm ratchet extraction requires bit-identical iterations")
  func warmRatchetRequiresStability() {
    func aggregate(_ values: [Double], emissionLane: Bool = false) -> PerfAggregateSummary {
      PerfAggregateSummary(
        scenario: "bench-deep-grid",
        renderMode: "sync",
        emissionLane: emissionLane,
        iterationCount: values.count,
        totalCPUSeconds: PerfStat(values: values),
        committedFrameCount: PerfStat(values: values),
        diagnosticFrameCount: PerfStat(values: values),
        elidedFrameCount: PerfStat(values: []),
        cancelledFrameCount: PerfStat(values: []),
        completedDropCount: PerfStat(values: []),
        cpuSecondsPerCommittedFrame: PerfStat(values: []),
        cpuSecondsPerDiagnosticFrame: PerfStat(values: []),
        inputToPresentLatencyP95Ms: PerfStat(values: []),
        frameIntervalP50Ms: PerfStat(values: []),
        deterministicCounters: [
          "measured_computed": PerfStat(values: values),
          "present_bytes": PerfStat(values: [12, 12]),
        ]
      )
    }

    let stable = BenchRatchet.warmRatchetValues(
      from: aggregate([27, 27]),
      scenario: "bench-deep-grid"
    )
    #expect(stable.values["measured_computed"] == 27)
    // Wire bytes only ratchet with the emission lane armed (D4).
    #expect(stable.values["present_bytes"] == nil)
    #expect(stable.nondeterministic.isEmpty)

    let armed = BenchRatchet.warmRatchetValues(
      from: aggregate([27, 27], emissionLane: true),
      scenario: "bench-deep-grid"
    )
    #expect(armed.values["present_bytes"] == 12)

    let drifting = BenchRatchet.warmRatchetValues(
      from: aggregate([27, 29]),
      scenario: "bench-deep-grid"
    )
    #expect(drifting.values["measured_computed"] == nil)
    #expect(drifting.nondeterministic.map(\.verdict) == [.nondeterministic])
    #expect(drifting.nondeterministic.allSatisfy { !$0.passed })
  }

  @Test("bench parser accepts the baseline flags")
  func benchParserAcceptsBaselineFlags() throws {
    let parsed = try PerfCommandParser.parse([
      "bench", "--update-baseline", "--baseline", "/tmp/b.json",
    ])
    #expect(
      parsed
        == .bench(
          PerfBenchConfig(updateBaseline: true, baselinePath: "/tmp/b.json")
        )
    )
  }

  @Test("the committed baseline loads and covers every cold ratchet lane")
  func committedBaselineCoversRatchetLanes() throws {
    let baseline = try PerfBenchBaseline.load(from: PerfBenchBaseline.defaultLocation())
    #expect(baseline.schemaVersion == PerfBenchBaseline.currentSchemaVersion)
    for configuration in ["debug", "release"] {
      for member in BenchSuite.members {
        let cold = baseline.entries(
          configuration: configuration,
          scenario: member.scenario.rawValue,
          lane: BenchRatchet.coldLane
        )
        #expect(
          !cold.isEmpty,
          "\(configuration) cold baseline missing for \(member.scenario.rawValue)"
        )
      }
    }
  }

  /// D8's cold-lane ratchet test: the smoke-tier assertion that HEAD still
  /// reproduces the committed debug cold baseline bit for bit.
  @Test("cold lanes reproduce the committed debug baseline")
  @MainActor
  func coldLanesReproduceCommittedDebugBaseline() throws {
    let baseline = try PerfBenchBaseline.load(from: PerfBenchBaseline.defaultLocation())
    for member in BenchSuite.members {
      guard
        let scenario = PerfScenarioRegistry.scenario(named: member.scenario)
          as? any BenchColdRenderable
      else {
        Issue.record("suite member \(member.scenario.rawValue) is not cold-renderable")
        continue
      }
      // Counter identity does not depend on the iteration count, so the
      // smoke tier runs the minimum that still exercises every protocol
      // bucket (first render, discarded warm-up, measured).
      let report = try BenchColdLane.run(scenario, iterations: 4)
      let rows = BenchRatchet.evaluate(
        current: report.counters.valuesByName,
        baseline: baseline.entries(
          configuration: "debug",
          scenario: member.scenario.rawValue,
          lane: BenchRatchet.coldLane
        ),
        scenario: member.scenario.rawValue,
        lane: BenchRatchet.coldLane
      )
      for row in rows where !row.passed {
        let baselineText = row.baseline.map(String.init) ?? "-"
        let currentText = row.current.map(String.init) ?? "-"
        let heading = "\(row.scenario)/\(row.counter) [\(row.verdict.rawValue)]"
        let values = "baseline \(baselineText), current \(currentText)"
        let hint = "an intentional change reruns bench with --update-baseline"
        Issue.record("\(heading): \(values) — \(hint)")
      }
    }
  }
}
