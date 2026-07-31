import Foundation
import Testing

@testable import TermUIPerf

/// WP-3: the columns the runtime has always written, finally reduced.
///
/// Every assertion here is about *not lying*: not folding a full repaint into
/// zero damage, not averaging emission over frames that emitted nothing, not
/// inventing a write latency for bytes that never reached the terminal, and not
/// failing a build because a metric was invented between two runs.
struct ScrollLatencyReductionTests {
  // MARK: - T-20 reader

  @Test("reader parses the phase, damage, emission and input-latency columns")
  func readerParsesTheWP3Columns() throws {
    let records = try PerfFrameDiagnosticsTSVReader.parse(
      """
      frame\tcauses\tresolve_ms\tmeasure_ms\tplace_ms\tsemantics_ms\tdraw_ms\traster_ms\tcommit_ms\tpipeline_ms\tcoalesced_event_batches\tanswered_inputs\tinput_to_commit_first_ms\tinput_to_commit_last_ms\tcommitted_at_ms\tpresent_bytes\tpresent_cells\tdamage_rows\tdamage_cells\ttail_job_state
      1\tinput\t4.00\t2.00\t1.00\t0.50\t0.75\t3.25\t0.40\t12.00\t2\t3\t18.50\t4.25\t1000.00\t8192\t1920\t24\t480\tcompleted
      """
    )

    let frame = try #require(records.first)
    #expect(frame.causes == "input")
    #expect(frame.phases.resolveMs == 4.00)
    #expect(frame.phases.measureMs == 2.00)
    #expect(frame.phases.placeMs == 1.00)
    #expect(frame.phases.semanticsMs == 0.50)
    #expect(frame.phases.drawMs == 0.75)
    #expect(frame.phases.rasterMs == 3.25)
    #expect(frame.phases.commitMs == 0.40)
    #expect(frame.phases.pipelineMs == 12.00)
    #expect(frame.emission.coalescedEventBatches == 2)
    #expect(frame.emission.presentBytes == 8192)
    #expect(frame.emission.presentCells == 1920)
    #expect(frame.emission.damageRows == .rows(24))
    #expect(frame.emission.damageCells == 480)
    #expect(frame.answeredInputCount == 3)
    #expect(frame.inputToCommitFirstMs == 18.50)
    #expect(frame.inputToCommitLastMs == 4.25)
    #expect(frame.committedAtMs == 1000.00)
  }

  @Test("a full-surface repaint is never parsed as zero damage rows")
  func fullRepaintIsNotZeroDamage() throws {
    // `damage_rows` prints the literal `full` for a whole-surface repaint. An
    // `Int(field) ?? 0` parse would report the most expensive frame in a scroll
    // trace as the cheapest — and scroll on current HEAD produces almost
    // nothing else, so the baseline would be inverted rather than merely noisy.
    let records = try PerfFrameDiagnosticsTSVReader.parse(
      """
      frame\tdamage_rows\ttail_job_state
      1\tfull\tcompleted
      2\t12\tcompleted
      3\t-\tcompleted
      """
    )

    #expect(records[0].emission.damageRows == .fullRepaint)
    #expect(records[0].emission.damageRows.count == nil)
    #expect(records[0].emission.damageRows.isFullRepaint)
    #expect(records[1].emission.damageRows == .rows(12))
    #expect(records[2].emission.damageRows == .unknown)
    #expect(records[2].emission.damageRows.isFullRepaint == false)
  }

  @Test("an artifact without the WP-3 columns still parses, reporting absence")
  func olderArtifactsParseWithoutTheNewColumns() throws {
    // Re-reducing an existing `.perf/runs*` directory must work: the plan's
    // acceptance gate for this stage is exactly that.
    let records = try PerfFrameDiagnosticsTSVReader.parse(
      """
      frame\ttotal_ms\ttail_job_state
      1\t10.0\tcompleted
      """
    )

    let frame = try #require(records.first)
    #expect(frame.phases.resolveMs == nil)
    #expect(frame.inputToCommitFirstMs == nil)
    #expect(frame.committedAtMs == nil)
    #expect(frame.emission.presentBytes == 0)
    #expect(frame.emission.damageRows == .unknown)
    #expect(frame.present == nil)
  }

  @Test("the presents join is by frame ordinal and total over a drop sequence")
  func presentsJoinIsTotalOverADropSequence() throws {
    let presents = PerfPresentsTSVReader.parse(
      """
      frame\tsubmitted_ms\twritten_ms\twrite_ms\tbytes\toutcome
      1\t1000.00\t1002.50\t2.50\t8192\twritten
      2\t1016.00\t-\t-\t7000\tsuperseded
      3\t1032.00\t1033.00\t1.00\t6000\twritten
      """
    )
    let records = try PerfFrameDiagnosticsTSVReader.parse(
      """
      frame\tanswered_inputs\tinput_to_commit_first_ms\tcommitted_at_ms\ttail_job_state
      1\t1\t10.00\t1000.00\tcompleted
      2\t1\t10.00\t1016.00\tcompleted
      3\t1\t10.00\t1032.00\tcompleted
      """,
      presents: presents
    )

    #expect(records.allSatisfy { $0.present != nil })
    #expect(records[0].present?.outcome == "written")
    #expect(records[1].present?.wasWritten == false)

    // arrival = committed_at − input_to_commit_first = 990.00;
    // write completed at 1002.50, so arrival→write is 12.50 ms. This is the
    // number `committed_at_ms` exists to make computable: without a shared
    // origin the two files could only be related by assumption.
    #expect(records[0].inputToWriteMs == 12.50)
    // Superseded bytes never reached the terminal. Reporting a write latency
    // here would attach a duration to a frame the user never saw.
    #expect(records[1].inputToWriteMs == nil)
    #expect(records[2].inputToWriteMs == 11.00)
  }

  // MARK: - T-21 reducer

  @Test("moving frames are the ones that answered input or woke on a deadline")
  func movingFrameClassification() {
    let frames = [
      frame(1, causes: "input", answered: 2, bytes: 900),
      // A momentum tick: no input, but a deadline woke it. It moves.
      frame(2, causes: "deadline", answered: 0, bytes: 600),
      // A settle repaint driven by an invalidation. It does not move.
      frame(3, causes: "invalidation", answered: 0, bytes: 30),
    ]

    let summary = reduce(frames)

    #expect(summary.movingFrameCount == 2)
    #expect(summary.presentBytesPerMovingFrame == 750)
    #expect(summary.answeredInputsPerMovingFrame == 1)
  }

  @Test("emission averages exclude the settle tail rather than being diluted by it")
  func emissionExcludesSettleFrames() {
    // The settle tail is where a scroll scenario spends most of its frames and
    // almost none of its bytes. Averaging over all frames would report a cheap
    // scroll that nobody experiences.
    let frames =
      [frame(1, causes: "input", answered: 1, bytes: 10_000)]
      + (2...20).map { frame($0, causes: "invalidation", answered: 0, bytes: 0) }

    let summary = reduce(frames)

    #expect(summary.movingFrameCount == 1)
    #expect(summary.presentBytesPerMovingFrame == 10_000)
  }

  @Test("full repaints are counted, not averaged into the damage-row mean")
  func fullRepaintsAreCountedSeparately() {
    let frames = [
      frame(1, causes: "input", answered: 1, bytes: 100, damageRows: .fullRepaint),
      frame(2, causes: "input", answered: 1, bytes: 100, damageRows: .rows(10)),
      frame(3, causes: "input", answered: 1, bytes: 100, damageRows: .rows(20)),
    ]

    let summary = reduce(frames)

    #expect(summary.fullRepaintMovingFrameCount == 1)
    // The mean covers only the two frames that reported a bounded count.
    // Substituting any number for the full repaint would understate it: a full
    // repaint is the surface height, which the reducer does not know.
    #expect(summary.damageRowsPerBoundedMovingFrame == 15)
  }

  @Test("a run with no moving frames reports nil, not zero")
  func noMovingFramesReportsNil() {
    let summary = reduce([frame(1, causes: "invalidation", answered: 0, bytes: 40)])

    #expect(summary.movingFrameCount == 0)
    // Zero would read as "this scenario emits nothing per moving frame", which
    // a gate could then certify as an improvement over a real measurement.
    #expect(summary.presentBytesPerMovingFrame == nil)
    #expect(summary.answeredInputsPerMovingFrame == nil)
    #expect(summary.damageRowsPerBoundedMovingFrame == nil)
  }

  @Test("the coalescing rate is inputs answered per moving frame")
  func coalescingRate() {
    let frames = [
      frame(1, causes: "input", answered: 3, bytes: 100),
      frame(2, causes: "input", answered: 5, bytes: 100),
    ]

    let summary = reduce(frames)

    #expect(summary.answeredInputsPerMovingFrame == 4)
    #expect(summary.inputToCommitFirstMs.count == 2)
    #expect(summary.inputToCommitLastMs.count == 2)
  }

  @Test("superseded submissions are counted over every frame")
  func supersededCount() {
    var first = frame(1, causes: "input", answered: 1, bytes: 100)
    first.present = PerfPresentRecord(frameNumber: 1, bytes: 100, outcome: "superseded")
    var second = frame(2, causes: "input", answered: 1, bytes: 100)
    second.present = PerfPresentRecord(frameNumber: 2, bytes: 100, outcome: "written")

    let summary = reduce([first, second])

    #expect(summary.supersededPresentCount == 1)
  }

  // MARK: - T-22 compare/gate across differing metric sets

  @Test("a metric only one run measured is reported and never gated")
  func oneSidedMetricsAreReportedNotGated() {
    // The realistic shape: a baseline recorded before this program existed,
    // compared against a candidate that now measures scroll latency.
    let base = aggregate(inputToCommitP95: nil, presentBytesPerMovingFrame: nil)
    let candidate = aggregate(
      inputToCommitP95: [40, 41, 42], presentBytesPerMovingFrame: [900, 950, 1000])

    let comparison = CompareCommand.compareAggregates(base: base, candidate: candidate)
    let latency = comparison.metrics.first { $0.metric == "input to commit p95 ms" }

    #expect(latency?.oneSided == true)
    #expect(latency?.verdict == .inconclusive)
    // Reported: the operator can see the metric appeared.
    #expect(CompareCommand.format(comparison).contains("input to commit p95 ms"))
    #expect(CompareCommand.format(comparison).contains("one-sided"))
    // Not gated: a metric that did not exist on the base side is not a
    // regression, however large the apparent delta.
    #expect(CompareCommand.evaluateGate(comparison).passed)
  }

  @Test("the gate refuses a one-sided metric even when its verdict says real")
  func oneSidedMetricIsSkippedEvenWhenVerdictIsReal() {
    // `evaluateGate` is public and takes a comparison, which can also arrive
    // decoded from a stored JSON file where `verdict` and `one_sided` are
    // independent fields. Going through `compareAggregates` cannot reach this
    // state — sample count forces `.inconclusive` — so the guard is only
    // provable here, at the seam that actually accepts arbitrary input.
    let comparison = AggregateComparison(
      scenario: "scroll-notch-latency",
      metrics: [
        AggregateMetricComparison(
          metric: "input to commit p95 ms",
          baseMedian: 0,
          candidateMedian: 42,
          delta: 42,
          noiseBand: 0.1,
          verdict: .real,
          oneSided: true
        )
      ]
    )

    #expect(CompareCommand.evaluateGate(comparison).passed)
  }

  @Test("a one-sided metric cannot certify a required improvement either")
  func oneSidedMetricCannotCertifyAnImprovement() {
    let base = aggregate(inputToCommitP95: nil, presentBytesPerMovingFrame: nil)
    let candidate = aggregate(
      inputToCommitP95: [1, 1, 1], presentBytesPerMovingFrame: [10, 10, 10])

    let outcome = CompareCommand.evaluateGate(
      CompareCommand.compareAggregates(base: base, candidate: candidate),
      requireImprovement: ["input to commit p95 ms"]
    )

    #expect(outcome.passed == false)
    #expect(outcome.failures.first?.reason.contains("only one run measured") == true)
  }

  @Test("a real scroll-latency regression fails the gate")
  func realLatencyRegressionFailsTheGate() {
    // Both sides measured it, the movement is well outside the noise band, and
    // it is a cost metric — this is the case the watch list exists for.
    let base = aggregate(
      inputToCommitP95: [20, 20, 20], presentBytesPerMovingFrame: [900, 900, 900])
    let candidate = aggregate(
      inputToCommitP95: [60, 60, 60],
      presentBytesPerMovingFrame: [900, 900, 900]
    )

    let outcome = CompareCommand.evaluateGate(
      CompareCommand.compareAggregates(base: base, candidate: candidate)
    )

    #expect(outcome.passed == false)
    #expect(outcome.failures.contains { $0.metric == "input to commit p95 ms" })
  }

  @Test("an emission regression fails the gate")
  func emissionRegressionFailsTheGate() {
    let base = aggregate(
      inputToCommitP95: [20, 20, 20], presentBytesPerMovingFrame: [900, 900, 900])
    let candidate = aggregate(
      inputToCommitP95: [20, 20, 20],
      presentBytesPerMovingFrame: [4000, 4000, 4000]
    )

    let outcome = CompareCommand.evaluateGate(
      CompareCommand.compareAggregates(base: base, candidate: candidate)
    )

    #expect(outcome.passed == false)
    #expect(outcome.failures.contains { $0.metric == "present bytes/moving frame" })
  }

  @Test("an aggregate written before these metrics existed still decodes")
  func legacyAggregateDecodes() throws {
    let json = """
      {
        "scenario": "lazy-vstack-scroll",
        "render_mode": "async",
        "iteration_count": 3,
        "total_cpu_seconds": {"sample_count": 3, "median": 1.0, "mean": 1.0, "stddev": 0.0,
          "min": 1.0, "max": 1.0, "coefficient_of_variation": 0.0},
        "committed_frame_count": {"sample_count": 3, "median": 10.0, "mean": 10.0,
          "stddev": 0.0, "min": 10.0, "max": 10.0, "coefficient_of_variation": 0.0},
        "diagnostic_frame_count": {"sample_count": 3, "median": 10.0, "mean": 10.0,
          "stddev": 0.0, "min": 10.0, "max": 10.0, "coefficient_of_variation": 0.0},
        "elided_frame_count": {"sample_count": 3, "median": 0.0, "mean": 0.0, "stddev": 0.0,
          "min": 0.0, "max": 0.0, "coefficient_of_variation": 0.0},
        "cancelled_frame_count": {"sample_count": 3, "median": 0.0, "mean": 0.0,
          "stddev": 0.0, "min": 0.0, "max": 0.0, "coefficient_of_variation": 0.0},
        "completed_drop_count": {"sample_count": 3, "median": 0.0, "mean": 0.0,
          "stddev": 0.0, "min": 0.0, "max": 0.0, "coefficient_of_variation": 0.0},
        "cpu_seconds_per_committed_frame": {"sample_count": 3, "median": 0.1, "mean": 0.1,
          "stddev": 0.0, "min": 0.1, "max": 0.1, "coefficient_of_variation": 0.0},
        "cpu_seconds_per_diagnostic_frame": {"sample_count": 3, "median": 0.1, "mean": 0.1,
          "stddev": 0.0, "min": 0.1, "max": 0.1, "coefficient_of_variation": 0.0},
        "input_to_present_latency_p95_ms": {"sample_count": 3, "median": 5.0, "mean": 5.0,
          "stddev": 0.0, "min": 5.0, "max": 5.0, "coefficient_of_variation": 0.0},
        "frame_interval_p50_ms": {"sample_count": 3, "median": 16.0, "mean": 16.0,
          "stddev": 0.0, "min": 16.0, "max": 16.0, "coefficient_of_variation": 0.0}
      }
      """

    let decoded = try JSONDecoder().decode(
      PerfAggregateSummary.self,
      from: Data(json.utf8)
    )

    #expect(decoded.scenario == "lazy-vstack-scroll")
    #expect(decoded.inputToCommitP95Ms.sampleCount == 0)
    #expect(decoded.presentBytesPerMovingFrameMedian.sampleCount == 0)
    #expect(decoded.pipelineP50Ms.sampleCount == 0)
  }

  // MARK: - fixtures

  private func frame(
    _ number: Int,
    causes: String,
    answered: Int,
    bytes: Int,
    damageRows: PerfDamageRows = .unknown
  ) -> PerfFrameRecord {
    PerfFrameRecord(
      frameNumber: number,
      tailJobState: "completed",
      causes: causes,
      emission: PerfFrameEmission(presentBytes: bytes, damageRows: damageRows),
      inputToCommitFirstMs: answered > 0 ? 20.0 : nil,
      inputToCommitLastMs: answered > 0 ? 5.0 : nil,
      committedAtMs: Double(number) * 16.0
    )
    .answering(answered)
  }

  private func reduce(_ frames: [PerfFrameRecord]) -> PerfSummary {
    SummaryReducer.reduce(
      metadata: PerfRunMetadata(
        gitSHA: "abc123",
        dirty: false,
        renderMode: .async,
        scenario: .scrollNotchLatency,
        iterationCount: 1,
        configuration: "release",
        swiftVersion: "Swift 6.3",
        osVersion: "macOS 15",
        terminalSize: PerfTerminalSize(columns: 80, rows: 24),
        startedAt: "2026-07-31T00:00:00Z"
      ),
      events: [],
      cpuSamples: [],
      frames: frames
    )
  }

  private func aggregate(
    inputToCommitP95: [Double]?,
    presentBytesPerMovingFrame: [Double]?
  ) -> PerfAggregateSummary {
    let flat = PerfStat(values: [1, 1, 1])
    return PerfAggregateSummary(
      scenario: "scroll-notch-latency",
      renderMode: "async",
      iterationCount: 3,
      totalCPUSeconds: flat,
      committedFrameCount: flat,
      diagnosticFrameCount: flat,
      elidedFrameCount: flat,
      cancelledFrameCount: flat,
      completedDropCount: flat,
      cpuSecondsPerCommittedFrame: flat,
      cpuSecondsPerDiagnosticFrame: flat,
      inputToPresentLatencyP95Ms: flat,
      frameIntervalP50Ms: flat,
      inputToCommitP95Ms: PerfStat(values: inputToCommitP95 ?? []),
      presentBytesPerMovingFrameMedian: PerfStat(values: presentBytesPerMovingFrame ?? [])
    )
  }
}

extension PerfFrameRecord {
  /// `answeredInputCount` sits ahead of the WP-3 parameters in the memberwise
  /// initializer, so setting it inline in the fixtures above would mean
  /// restating every argument between them.
  fileprivate func answering(_ count: Int) -> PerfFrameRecord {
    var copy = self
    copy.answeredInputCount = count
    return copy
  }
}
