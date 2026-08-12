import Foundation
import Testing

@testable import TermUIPerf

/// Plan 2026-08-11-005 Stage 0: deterministic work counters surfaced from
/// `frames.tsv` into the summary/aggregate/compare vocabulary.
struct DeterministicCounterTests {
  @Test("reader parses fraction numerators and branching counter columns")
  func readerParsesCounterColumns() throws {
    let records = try PerfFrameDiagnosticsTSVReader.parse(
      """
      frame\tresolved_computed\tresolved_reused\tmeasured_computed\tdraw_nodes\tbuiltin_container_measures\tbuiltin_child_measure_requests\tbuiltin_child_measure_requests_probe\tcustom_container_measures\tcustom_child_measure_requests\tcustom_child_measure_requests_probe\tcustom_placement_child_measure_requests
      1\t12/300\t288/300\t45/310\t520\t40\t95\t5\t3\t9\t2\t1
      2\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-
      """
    )

    #expect(records.count == 2)
    let counters = records[0].workCounters
    #expect(counters.resolvedComputed == 12)
    #expect(counters.resolvedReused == 288)
    #expect(counters.measuredComputed == 45)
    #expect(counters.drawNodes == 520)
    #expect(counters.builtinContainerMeasures == 40)
    #expect(counters.builtinChildMeasureRequests == 95)
    #expect(counters.builtinChildMeasureRequestsProbe == 5)
    #expect(counters.customContainerMeasures == 3)
    #expect(counters.customChildMeasureRequests == 9)
    #expect(counters.customChildMeasureRequestsProbe == 2)
    #expect(counters.customPlacementChildMeasureRequests == 1)

    // A `-` row reads as "not recorded", never zero.
    #expect(records[1].workCounters == PerfFrameWorkCounters())
  }

  @Test("reader leaves counters nil when the columns are absent")
  func readerLeavesCountersNilWhenColumnsAbsent() throws {
    let records = try PerfFrameDiagnosticsTSVReader.parse(
      """
      frame\ttotal_ms
      1\t10.00
      """
    )
    #expect(records.count == 1)
    #expect(records[0].workCounters == PerfFrameWorkCounters())
  }

  @Test("counter reduction sums all frames and splits full repaints from bounded rows")
  func counterReductionSumsFramesAndSplitsRepaints() {
    let frames = [
      PerfFrameRecord(
        frameNumber: 1,
        answeredInputCount: 1,
        emission: PerfFrameEmission(
          presentBytes: 100,
          presentCells: 40,
          damageRows: .rows(3),
          damageCells: 12
        ),
        workCounters: PerfFrameWorkCounters(
          resolvedComputed: 10,
          resolvedReused: 90,
          measuredComputed: 20,
          drawNodes: 200,
          builtinContainerMeasures: 8,
          builtinChildMeasureRequests: 21
        )
      ),
      PerfFrameRecord(
        frameNumber: 2,
        answeredInputCount: 2,
        emission: PerfFrameEmission(
          presentBytes: 50,
          presentCells: 10,
          damageRows: .fullRepaint,
          damageCells: nil
        ),
        workCounters: PerfFrameWorkCounters(
          resolvedComputed: 5,
          resolvedReused: 95,
          measuredComputed: 7,
          drawNodes: 200,
          builtinContainerMeasures: 8,
          builtinChildMeasureRequests: 21
        )
      ),
    ]

    let counters = PerfDeterministicCounters.reduce(frames: frames, committedFrameCount: 2)
    #expect(counters.committedFrames == 2)
    #expect(counters.answeredInputs == 3)
    #expect(counters.resolvedComputed == 15)
    #expect(counters.resolvedReused == 185)
    #expect(counters.measuredComputed == 27)
    #expect(counters.drawNodes == 400)
    #expect(counters.presentBytes == 150)
    #expect(counters.presentCells == 50)
    #expect(counters.damageCells == 12)
    #expect(counters.boundedDamageRows == 3)
    #expect(counters.fullRepaintFrames == 1)
    #expect(counters.builtinContainerMeasures == 16)
    #expect(counters.builtinChildMeasureRequests == 42)
    // Counters no frame carried stay nil — not zero.
    #expect(counters.customContainerMeasures == nil)
    #expect(counters.realizedRows == nil)
  }

  @Test("summary reducer attaches counters and the aggregate reports stability")
  func summaryReducerAttachesCountersAndAggregateReportsStability() {
    let metadata = PerfRunMetadata(
      gitSHA: "test",
      dirty: false,
      renderMode: .sync,
      scenario: .memoEquatableBoundary,
      iterationCount: 1,
      configuration: "debug",
      swiftVersion: "-",
      osVersion: "-",
      terminalSize: PerfTerminalSize(columns: 80, rows: 24),
      startedAt: "-"
    )
    func summary(measured: Int) -> PerfSummary {
      SummaryReducer.reduce(
        metadata: metadata,
        events: [],
        cpuSamples: [],
        frames: [
          PerfFrameRecord(
            frameNumber: 1,
            answeredInputCount: 1,
            workCounters: PerfFrameWorkCounters(measuredComputed: measured)
          )
        ]
      )
    }

    let stable = AggregateReducer.reduce([summary(measured: 27), summary(measured: 27)])
    #expect(stable.deterministicCounters?["measured_computed"]?.min == 27)
    #expect(stable.deterministicCounters?["measured_computed"]?.max == 27)
    #expect(AggregateReducer.format(stable).contains("measured_computed: 27 (stable, n=2)"))

    let drifting = AggregateReducer.reduce([summary(measured: 27), summary(measured: 29)])
    #expect(AggregateReducer.format(drifting).contains("VARIES"))
  }

  @Test("summary JSON without deterministic counters still decodes")
  func summaryDecodesWithoutCounters() throws {
    let metadata = PerfRunMetadata(
      gitSHA: "test",
      dirty: false,
      renderMode: .sync,
      scenario: .memoEquatableBoundary,
      iterationCount: 1,
      configuration: "debug",
      swiftVersion: "-",
      osVersion: "-",
      terminalSize: PerfTerminalSize(columns: 80, rows: 24),
      startedAt: "-"
    )
    let summary = SummaryReducer.reduce(
      metadata: metadata, events: [], cpuSamples: [], frames: [])
    #expect(summary.deterministicCounters != nil)

    var json = try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(summary)) as! [String: Any]
    json.removeValue(forKey: "deterministic_counters")
    let stripped = try JSONSerialization.data(withJSONObject: json)
    let decoded = try JSONDecoder().decode(PerfSummary.self, from: stripped)
    #expect(decoded.deterministicCounters == nil)
  }

  @Test("aggregate compare reports counters without gating them")
  func aggregateCompareReportsCountersWithoutGating() {
    func aggregate(measured: Double) -> PerfAggregateSummary {
      PerfAggregateSummary(
        scenario: "memo-equatable-boundary",
        renderMode: "sync",
        iterationCount: 2,
        totalCPUSeconds: PerfStat(values: [1, 1]),
        committedFrameCount: PerfStat(values: [8, 8]),
        diagnosticFrameCount: PerfStat(values: [9, 9]),
        elidedFrameCount: PerfStat(values: [0, 0]),
        cancelledFrameCount: PerfStat(values: [0, 0]),
        completedDropCount: PerfStat(values: [0, 0]),
        cpuSecondsPerCommittedFrame: PerfStat(values: [0.1, 0.1]),
        cpuSecondsPerDiagnosticFrame: PerfStat(values: [0.1, 0.1]),
        inputToPresentLatencyP95Ms: PerfStat(values: [5, 5]),
        frameIntervalP50Ms: PerfStat(values: [16, 16]),
        deterministicCounters: [
          "measured_computed": PerfStat(values: [measured, measured])
        ]
      )
    }

    // A counter regression is reported `real` but must NOT fail the
    // wall-clock gate — the hard gate on counters is the bench ratchet.
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(measured: 100),
      candidate: aggregate(measured: 150)
    )
    let counterRow = comparison.metrics.first { $0.metric == "counter measured_computed" }
    #expect(counterRow?.verdict == .real)
    #expect(counterRow?.delta == 50)
    #expect(CompareCommand.evaluateGate(comparison).passed)

    // But a required improvement can name it explicitly.
    let requiring = CompareCommand.evaluateGate(
      comparison,
      requireImprovement: ["counter-measured-computed"]
    )
    #expect(!requiring.passed)
  }

  @Test("summary compare prints counter deltas and one-sided rows")
  func summaryComparePrintsCounterDeltas() {
    let metadata = PerfRunMetadata(
      gitSHA: "test",
      dirty: false,
      renderMode: .sync,
      scenario: .memoEquatableBoundary,
      iterationCount: 1,
      configuration: "debug",
      swiftVersion: "-",
      osVersion: "-",
      terminalSize: PerfTerminalSize(columns: 80, rows: 24),
      startedAt: "-"
    )
    func summary(measured: Int?, realized: Int?) -> PerfSummary {
      SummaryReducer.reduce(
        metadata: metadata,
        events: [],
        cpuSamples: [],
        frames: [
          PerfFrameRecord(
            frameNumber: 1,
            realizedRows: realized,
            workCounters: PerfFrameWorkCounters(measuredComputed: measured)
          )
        ]
      )
    }

    let comparison = CompareCommand.compare(
      base: summary(measured: 100, realized: nil),
      candidate: summary(measured: 80, realized: 24)
    )
    let formatted = CompareCommand.format(comparison)
    #expect(formatted.contains("measured_computed: 100 -> 80 (-20)"))
    #expect(formatted.contains("realized_rows: - -> 24 (one-sided"))
  }

  @Test("bench parser applies defaults and options")
  func benchParserAppliesDefaultsAndOptions() throws {
    let defaulted = try PerfCommandParser.parse(["bench"])
    #expect(
      defaulted
        == .bench(PerfBenchConfig())
    )

    let configured = try PerfCommandParser.parse([
      "bench",
      "--iterations", "3",
      "--configuration", "debug",
      "--artifacts-root", "/tmp/bench",
      "--member", "memo-equatable-boundary",
    ])
    #expect(
      configured
        == .bench(
          PerfBenchConfig(
            artifactsRoot: "/tmp/bench",
            configuration: "debug",
            warmIterations: 3,
            members: [.memoEquatableBoundary]
          )
        )
    )

    #expect(throws: PerfParseError.unknownScenario("nope")) {
      _ = try PerfCommandParser.parse(["bench", "--member", "nope"])
    }
  }

  @Test("bench rejects a scenario that is not a suite member")
  func benchRejectsNonSuiteMember() async {
    // Parse accepts any scenario name; suite membership is enforced at run
    // time so the parser stays a pure name check.
    await #expect(throws: PerfBenchError.notASuiteMember("scroll-jump")) {
      _ = try await BenchCommand.run(
        PerfBenchConfig(members: [.scrollJump])
      )
    }
  }
}
