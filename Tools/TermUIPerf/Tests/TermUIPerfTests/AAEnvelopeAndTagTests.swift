import Foundation
import Testing

@testable import TermUIPerf

/// WP-6: aggregate identity (`--tag`, `generated_at`) and the recorded A/A
/// envelope (`--aa-check`) that annotates compare verdicts.
///
/// Both features exist because of the same failure: a perf result that looks
/// like evidence and is not. A silently overwritten aggregate compares a run
/// against itself; a delta read without knowing the machine's own spread is a
/// guess with a decimal point on it.
struct AAEnvelopeAndTagTests {
  // MARK: - T-51 aggregate identity

  @Test("--tag suffixes the aggregate filename and untagged output is unchanged")
  @MainActor
  func tagSuffixesAggregateFilenameAndUntaggedIsUnchanged() async throws {
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-perf-tag-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: artifactRoot) }

    let untagged = try await RunCommand.run(
      PerfRunConfig(
        scenario: .galleryAnimationClick,
        modes: [.sync],
        iterations: 1,
        artifactsRoot: artifactRoot.path,
        configuration: "debug"))
    let scenario = untagged.aggregates[0].scenario
    let mode = untagged.aggregates[0].renderMode
    // Written aggregates carry their write instant, so a file left on disk by a
    // previous session is identifiable as one.
    #expect(untagged.aggregates[0].generatedAt != nil)

    // Byte-for-byte the historical name: every committed compare invocation and
    // script resolves this path, so an always-timestamped filename would have
    // been a flag day rather than a feature.
    #expect(
      FileManager.default.fileExists(
        atPath: artifactRoot.appendingPathComponent(
          "aggregate-\(scenario)-\(mode).json"
        ).path))

    _ = try await RunCommand.run(
      PerfRunConfig(
        scenario: .galleryAnimationClick,
        modes: [.sync],
        iterations: 1,
        artifactsRoot: artifactRoot.path,
        configuration: "debug",
        tag: "candidate"))

    // Both survive in one root — which is the whole point. Untagged, the second
    // run would have overwritten the first, and an A/B against the overwritten
    // base compares a run to itself and reports no difference.
    #expect(
      FileManager.default.fileExists(
        atPath: artifactRoot.appendingPathComponent(
          "aggregate-\(scenario)-\(mode).json"
        ).path))
    #expect(
      FileManager.default.fileExists(
        atPath: artifactRoot.appendingPathComponent(
          "aggregate-\(scenario)-\(mode)-candidate.json"
        ).path))
  }

  @Test("generated_at is opt-in, round-trips, and older aggregates still decode")
  func generatedAtIsOptInAndBackwardCompatible() throws {
    // Unstamped by default: `AggregateReducer` stays clock-free so its own
    // tests are deterministic, and the stamp is applied where the file is
    // written. The run-side stamp is asserted by the `--tag` test above.
    #expect(aggregate(cpuPerFrame: [1], pipelineP50: [1]).generatedAt == nil)

    let stamped = PerfAggregateSummary(
      scenario: "s", renderMode: "async", iterationCount: 1,
      generatedAt: "2026-07-31T12:00:00Z",
      totalCPUSeconds: PerfStat(values: [1]),
      committedFrameCount: PerfStat(values: [1]),
      diagnosticFrameCount: PerfStat(values: [1]),
      elidedFrameCount: PerfStat(values: [1]),
      cancelledFrameCount: PerfStat(values: [1]),
      completedDropCount: PerfStat(values: [1]),
      cpuSecondsPerCommittedFrame: PerfStat(values: [1]),
      cpuSecondsPerDiagnosticFrame: PerfStat(values: [1]),
      inputToPresentLatencyP95Ms: PerfStat(values: [1]),
      frameIntervalP50Ms: PerfStat(values: [1]))
    let encoded = try JSONEncoder().encode(stamped)
    let decoded = try JSONDecoder().decode(PerfAggregateSummary.self, from: encoded)
    #expect(decoded.generatedAt == "2026-07-31T12:00:00Z")
    #expect(String(data: encoded, encoding: .utf8)?.contains("generated_at") == true)

    // An aggregate written before the field existed still decodes.
    let legacy = try JSONDecoder().decode(
      PerfAggregateSummary.self,
      from: try JSONSerialization.data(withJSONObject: legacyAggregateJSON()))
    #expect(legacy.generatedAt == nil)
  }

  @Test("a tag that would escape the artifact root is rejected at the boundary")
  func invalidTagsAreRejected() throws {
    for bad in ["../escape", "with space", "", "a/b"] {
      #expect(throws: PerfParseError.self) {
        _ = try PerfCommandParser.parse(
          ["run", "--scenario", "gallery-animation-click", "--tag", bad])
      }
    }
    let parsed = try PerfCommandParser.parse(
      ["run", "--scenario", "gallery-animation-click", "--tag", "wp4.base-1"])
    guard case .run(let config) = parsed else {
      Issue.record("expected a run command")
      return
    }
    #expect(config.tag == "wp4.base-1")
    #expect(config.aaCheck == false)
  }

  // MARK: - T-50 A/A envelope

  @Test("--aa-check runs twice and writes the envelope beside the aggregates")
  @MainActor
  func aaCheckWritesTheEnvelopeFile() async throws {
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-perf-aa-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: artifactRoot) }

    let outcome = try await RunCommand.run(
      PerfRunConfig(
        scenario: .galleryAnimationClick,
        modes: [.sync],
        iterations: 1,
        artifactsRoot: artifactRoot.path,
        configuration: "debug",
        aaCheck: true))

    #expect(outcome.perIteration.count == 2)
    #expect(outcome.aggregates.count == 2)
    let envelope = try #require(outcome.aaEnvelopes.first)
    #expect(outcome.aaEnvelopes.count == 1)
    #expect(!envelope.relativeDeltas.isEmpty)

    let envelopeURL = artifactRoot.appendingPathComponent(
      PerfAAEnvelope.fileName(
        scenario: envelope.scenario,
        renderMode: envelope.renderMode))
    #expect(FileManager.default.fileExists(atPath: envelopeURL.path))
    let decoded = try JSONDecoder().decode(
      PerfAAEnvelope.self, from: try Data(contentsOf: envelopeURL))
    #expect(decoded.relativeDeltas == envelope.relativeDeltas)

    // The two passes land in subdirectories, keeping the root loadable as the
    // single-aggregate shape `loadAggregate` requires — an --aa-check followed
    // by a real run into the same root must still gate.
    for pass in ["aa-1", "aa-2"] {
      let passRoot = artifactRoot.appendingPathComponent(pass, isDirectory: true)
      #expect(FileManager.default.fileExists(atPath: passRoot.path), "missing \(pass)")
      _ = try CompareCommand.loadAggregate(from: passRoot.path)
    }
    // Nothing extra was dropped at the root, so a later `--gate <root>` is
    // still unambiguous once a real run writes its aggregate there.
    let rootAggregates = try FileManager.default
      .contentsOfDirectory(atPath: artifactRoot.path)
      .filter { $0.hasPrefix("aggregate-") && $0.hasSuffix(".json") }
    #expect(rootAggregates.isEmpty)
  }

  @Test("the envelope is what compare reports when nothing changed")
  func envelopeIsRecordedFromTheComparatorItself() {
    let runA = aggregate(cpuPerFrame: [1.00, 1.00, 1.00], pipelineP50: [10.0, 10.0, 10.0])
    let runB = aggregate(cpuPerFrame: [1.02, 1.02, 1.02], pipelineP50: [10.5, 10.5, 10.5])

    let envelope = PerfAAEnvelope.record(runA: runA, runB: runB, iterations: 3)

    // Metric names come from the comparator, not from a parallel list that
    // could drift: a name mismatch would read as "no envelope recorded", which
    // is exactly the silent failure this construction rules out.
    #expect(abs((envelope.envelope(for: "CPU seconds/frame") ?? -1) - 0.02) < 1e-9)
    #expect(abs((envelope.envelope(for: "pipeline p50 ms") ?? -1) - 0.05) < 1e-9)
  }

  @Test("compare annotates each metric against the recorded envelope")
  func compareAnnotatesAgainstTheRecordedEnvelope() {
    let base = aggregate(cpuPerFrame: [1.00, 1.00, 1.00], pipelineP50: [10.0, 10.0, 10.0])
    // A 1 % CPU move (inside a 2 % envelope) and a 20 % pipeline move
    // (far outside a 5 % one).
    let candidate = aggregate(cpuPerFrame: [1.01, 1.01, 1.01], pipelineP50: [12.0, 12.0, 12.0])
    let envelope = PerfAAEnvelope(
      scenario: "gallery-animation-click",
      renderMode: "async",
      iterations: 3,
      relativeDeltas: ["CPU seconds/frame": 0.02, "pipeline p50 ms": 0.05])

    let comparison = CompareCommand.compareAggregates(
      base: base, candidate: candidate, aaEnvelope: envelope)

    let cpu = comparison.metrics.first { $0.metric == "CPU seconds/frame" }
    let pipeline = comparison.metrics.first { $0.metric == "pipeline p50 ms" }
    #expect(cpu?.withinRecordedAA == true)
    #expect(pipeline?.withinRecordedAA == false)
    // A metric the envelope never covered stays unannotated rather than
    // defaulting to "inside".
    #expect(comparison.metrics.first { $0.metric == "elided frames" }?.withinRecordedAA == nil)

    // A recorded envelope of exactly 0 — two A/A passes that produced identical
    // medians — resolves nothing, and must not turn every later delta into an
    // "outside" verdict. Observed live during the WP-4 M-AA pair, where a
    // +0.19% pipeline p50 move was flagged outside a ±0.00% envelope.
    let zeroEnvelope = PerfAAEnvelope(
      scenario: "gallery-animation-click",
      renderMode: "async",
      iterations: 3,
      relativeDeltas: ["pipeline p50 ms": 0])
    let zeroAnnotated = CompareCommand.compareAggregates(
      base: base, candidate: candidate, aaEnvelope: zeroEnvelope)
    #expect(
      zeroAnnotated.metrics.first { $0.metric == "pipeline p50 ms" }?.withinRecordedAA == nil)
    #expect(!CompareCommand.format(zeroAnnotated).contains("recorded A/A"))

    let text = CompareCommand.format(comparison)
    #expect(text.contains("[inside recorded A/A ±2.00%]"))
    #expect(text.contains("[OUTSIDE recorded A/A ±5.00%]"))

    // Without an envelope the output is unchanged.
    let bare = CompareCommand.format(
      CompareCommand.compareAggregates(base: base, candidate: candidate))
    #expect(!bare.contains("recorded A/A"))
  }

  @Test("the envelope never changes a gate verdict")
  func envelopeDoesNotGate() {
    let base = aggregate(cpuPerFrame: [1.00, 1.00, 1.00], pipelineP50: [10.0, 10.0, 10.0])
    let candidate = aggregate(cpuPerFrame: [2.00, 2.00, 2.00], pipelineP50: [10.0, 10.0, 10.0])
    // An envelope wide enough to call a doubling "inside A/A". The gate must
    // still fail it: how noisy this machine is and whether a 2x CPU regression
    // is acceptable are different questions, and only the second is a policy.
    let envelope = PerfAAEnvelope(
      scenario: "gallery-animation-click",
      renderMode: "async",
      iterations: 3,
      relativeDeltas: ["CPU seconds/frame": 5.0])

    let annotated = CompareCommand.compareAggregates(
      base: base, candidate: candidate, aaEnvelope: envelope)
    let bare = CompareCommand.compareAggregates(base: base, candidate: candidate)

    #expect(annotated.metrics.first { $0.metric == "CPU seconds/frame" }?.withinRecordedAA == true)
    #expect(
      CompareCommand.evaluateGate(annotated, requireImprovement: []).passed
        == CompareCommand.evaluateGate(bare, requireImprovement: []).passed)
    #expect(!CompareCommand.evaluateGate(annotated, requireImprovement: []).passed)
  }

  // MARK: - Helpers

  private func aggregate(
    cpuPerFrame: [Double],
    pipelineP50: [Double]
  ) -> PerfAggregateSummary {
    let flat = PerfStat(values: [1, 1, 1])
    return PerfAggregateSummary(
      scenario: "gallery-animation-click",
      renderMode: "async",
      iterationCount: 3,
      totalCPUSeconds: flat,
      committedFrameCount: flat,
      diagnosticFrameCount: flat,
      elidedFrameCount: flat,
      cancelledFrameCount: flat,
      completedDropCount: flat,
      cpuSecondsPerCommittedFrame: PerfStat(values: cpuPerFrame),
      cpuSecondsPerDiagnosticFrame: flat,
      inputToPresentLatencyP95Ms: flat,
      frameIntervalP50Ms: flat,
      pipelineP50Ms: PerfStat(values: pipelineP50))
  }

  private func legacyAggregateJSON() -> [String: Any] {
    let stat: [String: Any] = [
      "sample_count": 1, "median": 1.0, "mean": 1.0, "stddev": 0.0,
      "min": 1.0, "max": 1.0, "coefficient_of_variation": 0.0,
    ]
    return [
      "scenario": "gallery-animation-click",
      "render_mode": "async",
      "iteration_count": 1,
      "total_cpu_seconds": stat,
      "committed_frame_count": stat,
      "diagnostic_frame_count": stat,
      "elided_frame_count": stat,
      "cancelled_frame_count": stat,
      "completed_drop_count": stat,
      "cpu_seconds_per_committed_frame": stat,
      "cpu_seconds_per_diagnostic_frame": stat,
      "input_to_present_latency_p95_ms": stat,
      "frame_interval_p50_ms": stat,
    ]
  }
}
