import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIPrimitives
@_spi(Runners) @testable import SwiftTUIProfiling
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetAProfilingBoundaryTests {
  @Test func setA776JSONLinesEscapeEveryControlScalarInProviderNames() throws {
    // Hypothesis: hand-written JSON escaping iterates Characters and misses CRLF clusters and other control scalars.
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let sink = try #require(FileProfileSink(path: url.path, format: .jsonl))
    let name = "cache\r\nnext\u{0000}\u{0008}\\\"\tend"
    sink.emit(.memory([.init(name: name, count: 3)]))
    let data = try Data(contentsOf: url)
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    withKnownIssue("STUI-1002: JSONL escaping leaves control scalars raw") {
      #expect(object != nil)
    }
    if let object {
      let providers = try #require(object["providers"] as? [[String: Any]])
      #expect(providers.first?["name"] as? String == name)
    }
  }

  @Test func setA777TSVIdentityFieldsCannotInjectColumnsOrRows() {
    // Hypothesis: arbitrary authored identity text bypasses the field sanitizer and destroys the diagnostic row schema.
    var record = FrameDiagnosticRecord(frameNumber: 1, causeSummary: "ordinary")
    record.firstCustomLayoutFallbackIdentity = "Root/row\tpart\r\nnext"
    let fields = FrameDiagnosticsTSVFormatting.fields(for: record)
    let encoded = fields.joined(separator: "\t")
    withKnownIssue("STUI-1003: arbitrary identity fields bypass TSV sanitization") {
      #expect(
        encoded.split(separator: "\t", omittingEmptySubsequences: false).count
          == FrameDiagnosticsTSVFormatting.headerFields.count)
      #expect(!encoded.unicodeScalars.contains { $0.value == 10 || $0.value == 13 })
    }
  }

  @Test func setA778PresentationSidecarCannotOverwriteAnAuthoredFramesPath() throws {
    // Hypothesis: a frames file named presents.tsv aliases the fixed-name sidecar, whose independent descriptor overwrites its header.
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("presents.tsv").path
    try withSavedProfilingRegistry {
      let activation = ProfileActivation()
      defer { activation.finish() }
      activation.activateIfNeeded(config: .init(signals: [.frames], sinks: [.tsv(path: path)]))
      let frameSink = try #require(ProfilingRegistry.shared.frameSink)
      frameSink.record(sample(7))
      let before = try String(contentsOfFile: path, encoding: .utf8)
      #expect(before.hasPrefix(FrameDiagnosticsTSVFormatting.headerFields.joined(separator: "\t")))
      ProfilingRegistry.shared.presentationWriteSink?.record(presentation(7))
      let after = try String(contentsOfFile: path, encoding: .utf8)
      withKnownIssue(
        "STUI-1004: fixed sidecar name aliases and overwrites the authored frames file"
      ) {
        #expect(after.hasPrefix(FrameDiagnosticsTSVFormatting.headerFields.joined(separator: "\t")))
      }
    }
  }

  @Test func setA779EveryConfiguredFramesDestinationReceivesItsWriteSidecar() throws {
    // Hypothesis: completion fan-out selects only the first TSV descriptor even though frame records reach every configured destination.
    let a = try temporaryDirectory()
    let b = try temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: a)
      try? FileManager.default.removeItem(at: b)
    }
    try withSavedProfilingRegistry {
      let activation = ProfileActivation()
      defer { activation.finish() }
      activation.activateIfNeeded(
        config: .init(
          signals: [.frames],
          sinks: [
            .tsv(path: a.appendingPathComponent("frames.tsv").path),
            .tsv(path: b.appendingPathComponent("frames.tsv").path),
          ]))
      try #require(ProfilingRegistry.shared.frameSink).record(sample(8))
      try #require(ProfilingRegistry.shared.presentationWriteSink).record(presentation(8))
      for directory in [a, b] {
        #expect(
          try String(contentsOf: directory.appendingPathComponent("frames.tsv"), encoding: .utf8)
            .contains("\n8\t"))
      }
      let first = try String(contentsOf: a.appendingPathComponent("presents.tsv"), encoding: .utf8)
      let second = try? String(
        contentsOf: b.appendingPathComponent("presents.tsv"), encoding: .utf8)
      withKnownIssue("STUI-1005: presentation completion routing uses only the first TSV sink") {
        #expect(second == first)
      }
    }
  }

  @Test func setA780SecondActivationCannotReplaceTheFirstSessionsSinks() {
    // Hypothesis: idempotent activation rebuilds the bridge or appends sinks, duplicating or redirecting observations.
    withSavedProfilingRegistry {
      let a = SetAProfileRecords()
      let b = SetAProfileRecords()
      let activation = ProfileActivation()
      defer { activation.finish() }
      activation.activate(signals: [.frames], sinks: [HandlerSink { a.records.append($0) }])
      activation.activate(signals: [.frames], sinks: [HandlerSink { b.records.append($0) }])
      ProfilingRegistry.shared.frameSink?.record(sample(3))
      activation.collectMemory()
      #expect(a.records.count == 2)
      #expect(b.records.isEmpty)
    }
  }

  @Test func setA781EmptyConfigurationDoesNotConsumeTheActivationLatch() {
    // Hypothesis: attempting disabled profiling prevents a later explicit configuration from activating in the same session.
    withSavedProfilingRegistry {
      let records = SetAProfileRecords()
      let activation = ProfileActivation()
      defer { activation.finish() }
      activation.activateIfNeeded(config: .init(signals: [], sinks: [.summary]))
      #expect(ProfilingRegistry.shared.frameSink == nil)
      activation.activate(signals: [.frames], sinks: [HandlerSink { records.records.append($0) }])
      ProfilingRegistry.shared.frameSink?.record(sample(1))
      #expect(records.records.count == 1)
    }
  }

  @Test func setA782MemorySnapshotCanRegisterAProviderWithoutChangingItsCurrentCohort() {
    // Hypothesis: provider callbacks run under the registry mutex or iterate live storage, deadlocking or including a newly registered provider mid-snapshot.
    let registry = MemoryMetricRegistry()
    let state = SetAProfileProviderState()
    let token = registry.register(
      ClosureMemoryMetricProvider {
        if state.token == nil {
          state.token = registry.register(
            ClosureMemoryMetricProvider { .init(name: "late", count: 2) })
        }
        return .init(name: "first", count: 1)
      })
    defer {
      withExtendedLifetime(token) {}
      state.token = nil
    }
    #expect(registry.snapshotAll().map(\.name) == ["first"])
    #expect(Set(registry.snapshotAll().map(\.name)) == ["first", "late"])
  }

  @Test func setA783EqualNamedProvidersHaveIndependentRegistrationLifetimes() {
    // Hypothesis: provider names act as registry keys, so retiring one same-named store removes another's occupancy signal.
    let registry = MemoryMetricRegistry()
    var first: MemoryMetricRegistry.Token? = registry.register(
      ClosureMemoryMetricProvider { .init(name: "same", count: 1) })
    let second = registry.register(ClosureMemoryMetricProvider { .init(name: "same", count: 2) })
    #expect(registry.snapshotAll().map(\.count).sorted() == [1, 2])
    withExtendedLifetime(first) {}
    first = nil
    #expect(registry.snapshotAll().map(\.count) == [2])
    withExtendedLifetime(second) {}
  }

  @Test func setA784WeakOccupancyProviderDoesNotExtendItsStoresLifetime() {
    // Hypothesis: registering a weak provider accidentally retains its source through type erasure or snapshot currency.
    let registry = MemoryMetricRegistry()
    var owner: SetAProfileOwner? = SetAProfileOwner()
    weak let observed = owner
    let token = registry.register(
      ClosureMemoryMetricProvider { [weak owner] in .init(name: "owner", count: owner?.value ?? 0) }
    )
    #expect(registry.snapshotAll().first?.count == 7)
    owner = nil
    #expect(observed == nil)
    #expect(registry.snapshotAll().first?.count == 0)
    withExtendedLifetime(token) {}
  }

  @Test func setA785ResettingOneCPUCounterDoesNotEraseTheOtherCountersWork() {
    // Hypothesis: clamping the combined CPU delta lets a reset in one counter cancel valid work in its independent peer.
    let start = reading(time: 10, user: 20, system: 3)
    let end = reading(time: 11, user: 1, system: 7)
    let sample = CPUSampler.sampleDelta(from: start, to: end)
    #expect(sample.userCPUSeconds == 0 && sample.systemCPUSeconds == 4)
    #expect(sample.totalCPUSeconds == 4 && sample.estimatedCPUPercent == 400)
    #expect(sample.maxResidentBytes == end.maxResidentBytes)
  }

  @Test func setA786CPUSamplingPreservesTheOperationsOriginalThrownError() async {
    // Hypothesis: sampler teardown replaces an application error or keeps its task running after exceptional completion.
    await #expect(throws: SetAProfileFailure.operation) {
      _ = try await CPUSampler.collect(interval: .seconds(3600)) {
        throw SetAProfileFailure.operation
      }
    }
  }

  @Test func setA787SummaryClearsAnUnknownCurrentByteEstimateButKeepsTheOccupancyPeak() {
    // Hypothesis: a later nil estimate accidentally retains an old byte count, misreporting current occupancy after shrink.
    let sink = SummarySink()
    sink.emit(.memory([.init(name: "cache", count: 20, approxBytes: 4096)]))
    sink.emit(.memory([.init(name: "cache", count: 3)]))
    let report = sink.report()
    #expect(report.contains("cache: 3 / 20"))
    #expect(!report.contains("4KB") && !report.contains("[at peak]"))
  }

  @Test func setA788SummaryKeepsIndependentCPUPeaksAcrossSparseMemoryRecords() {
    // Hypothesis: interleaving signals replaces the CPU peak tuple wholesale or clears it when a later signal omits CPU.
    let sink = SummarySink()
    sink.emit(.cpu(cpu(percent: 250, rss: 1024)))
    sink.emit(.memory([]))
    sink.emit(.cpu(cpu(percent: 20, rss: 4096)))
    #expect(sink.report().contains("cpu: peak 250%, rss peak 4KB"))
  }

  @Test func setA789JSONLSignalSwitchingPreservesAnEmptyMemoryObservation() throws {
    // Hypothesis: an empty provider collection is dropped or inherits the preceding CPU record in the shared file sink.
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let sink = try #require(FileProfileSink(path: url.path, format: .jsonl))
    sink.emit(.cpu(cpu(percent: 10, rss: 12)))
    sink.emit(.memory([]))
    sink.emit(.frame(.init(frameNumber: 19, causeSummary: "next")))
    let rows = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    let objects = try rows.map {
      try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
    }
    try #require(objects.count == 3)
    #expect(objects.compactMap { $0?["signal"] as? String } == ["cpu", "memory", "frame"])
    #expect((objects[1]?["providers"] as? [Any])?.isEmpty == true)
  }

  @Test func setA790ConcurrentIngressProducersCannotLoseCounterUpdates() async {
    // Hypothesis: read/pull/pump accounting races across ingress producers, losing increments or lowering the peak depth.
    let diagnostics = IngressDiagnostics()
    await withTaskGroup(of: Void.self) { group in
      for value in 1...128 {
        group.addTask {
          diagnostics.recordSourceRead(bytes: value, events: 1)
          diagnostics.recordPullDelivered(2)
          diagnostics.recordPumpEnqueue(depth: value)
        }
      }
    }
    let counters = diagnostics.drainCounters()
    #expect(counters.sourceBytes == 128 * 129 / 2)
    #expect(counters.sourceReads == 128 && counters.sourceEvents == 128)
    #expect(
      counters.pullEvents == 256 && counters.pumpEnqueues == 128 && counters.pumpHighWater == 128)
  }

  @Test func setA791DrainingIngressResetsThePeakWithoutRecountingOldEvents() {
    // Hypothesis: a frame drain resets counts but retains the previous peak, attributing old backlog to a quiet next frame.
    let diagnostics = IngressDiagnostics()
    diagnostics.recordSourceRead(bytes: 7, events: 2)
    diagnostics.recordPumpEnqueue(depth: 30)
    let first = diagnostics.drainCounters()
    #expect(first.sourceBytes == 7 && first.pumpHighWater == 30)
    #expect(diagnostics.drainCounters() == .init())
    diagnostics.recordPumpEnqueue(depth: 1)
    diagnostics.recordPullDelivered(0)
    diagnostics.recordPullDelivered(-1)
    #expect(diagnostics.drainCounters() == .init(pumpEnqueues: 1, pumpHighWater: 1))
  }

  @Test func setA792BoundedClockReadsCannotConsumeStepsOrRewindAcquiredTime() {
    // Hypothesis: readiness reads advance the animation clock without an acquisition, or a regressing wall source rewinds it.
    let wall = SetAProfileClock()
    let clock = BoundedStepFrameClock(maximumStep: .milliseconds(10), wallClock: { wall.now })
    #expect(clock.now() == .zero)
    wall.now = .init(offset: .seconds(1))
    #expect(clock.now().offset == .milliseconds(10))
    #expect(clock.now().offset == .milliseconds(10))
    clock.recordAcquisition(clock.now())
    #expect(clock.now().offset == .milliseconds(20))
    wall.now = .zero
    #expect(clock.now().offset == .milliseconds(10))
    clock.recordAcquisition(.zero)
    #expect(clock.now().offset == .milliseconds(10))
  }

  @Test func setA793VirtualClockRetainsSubmicrosecondStepsWithoutFloatingPointDrift() {
    // Hypothesis: clock arithmetic quantizes each fractional step before accumulation and loses an entire later deadline interval.
    let clock = VirtualFrameClock()
    for _ in 0..<1001 { clock.advance(by: .nanoseconds(1)) }
    #expect(clock.now.offset == .nanoseconds(1001))
    #expect(MonotonicInstant.zero.duration(to: clock.now) == .nanoseconds(1001))
  }

  @Test func setA794FiniteHostDimensionsCannotTrapDuringCellCountConversion() async {
    // Hypothesis: individually finite proposal and cell dimensions produce an infinite quotient that is converted to Int unchecked.
    await withKnownIssue("STUI-1006: finite host operands overflow before unchecked Int conversion")
    {
      await #expect(processExitsWith: .success) {
        let negotiator = HostedSurfaceSizeNegotiator(
          cellSize: .init(width: 1e-200, height: 2), preferredGridSize: .init(width: 4, height: 3))
        let result = negotiator.negotiate(proposedWidth: 1e200, proposedHeight: 8)
        #expect(result.size.width.isFinite && result.size.height == 6)
        #expect(result.size.width > 0)
      }
    }
  }

  @Test func setA795ConcurrentPresentationWritersKeepOneHeaderAndWholeRows() async throws {
    // Hypothesis: completion and supersession writers race the lazy header or interleave partial rows in their shared output descriptor.
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let sink = try #require(PresentationWriteTSVSink(path: url.path))
    await withTaskGroup(of: Void.self) { group in
      for number in 1...64 {
        group.addTask {
          sink.record(
            .init(
              frame: number, submittedAt: .zero,
              writtenAt: number.isMultiple(of: 2) ? .init(offset: .milliseconds(1)) : nil,
              bytes: number, outcome: number.isMultiple(of: 2) ? .written : .superseded))
        }
      }
    }
    let rows = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    try #require(rows.count == 65)
    #expect(rows.first == PresentationWriteTSVSink.headerFields.joined(separator: "\t"))
    let fields = rows.dropFirst().map {
      $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
    #expect(fields.allSatisfy { $0.count == 6 })
    #expect(Set(fields.compactMap { $0.first.flatMap(Int.init) }) == Set(1...64))
    for row in fields where row.count == 6 {
      let number = try #require(Int(row[0]))
      #expect(row[4] == String(number))
      #expect(row[5] == (number.isMultiple(of: 2) ? "written" : "superseded"))
    }
  }

  @Test func setA796OneConstrainedHostAxisDoesNotTurnAnUnconstrainedPeerIntoAProbe() {
    // Hypothesis: constructing a two-axis probe drops the peer's fallback or treats an unspecified proposal as zero.
    let negotiator = HostedSurfaceSizeNegotiator(
      cellSize: .init(width: 2.5, height: 3), fallbackGridSize: .init(width: 80, height: 7))
    let result = negotiator.negotiate(proposedWidth: 26, proposedHeight: nil)
    #expect(result.size == .init(width: 2.5, height: 21))
    #expect(result.probeGridSize == .init(width: 10, height: 7))
  }

  @Test func setA797IntrinsicHostSizeKeepsFractionalPitchAndNormalizesEmptyGridAxes() {
    // Hypothesis: grid normalization happens after host-unit conversion, replacing fractional pitch with an integer host-unit minimum.
    let negotiator = HostedSurfaceSizeNegotiator(
      cellSize: .init(width: 0.75, height: 1.25), preferredGridSize: .init(width: 0, height: -2))
    #expect(
      negotiator.intrinsicContentSize(noIntrinsicMetric: -1) == .init(width: 0.75, height: 1.25))
    var unknown = negotiator
    unknown.preferredGridSize = nil
    #expect(unknown.intrinsicContentSize(noIntrinsicMetric: -17) == .init(width: -17, height: -17))
  }

  @Test func setA798DiagnosticOptionalBooleanDistinguishesFalseFromUnobserved() throws {
    // Hypothesis: optional truth-value formatting collapses a measured false into the sentinel for an unavailable measurement.
    var record = FrameDiagnosticRecord(frameNumber: 1, causeSummary: "optional")
    let header = FrameDiagnosticsTSVFormatting.headerFields
    let index = try #require(header.firstIndex(of: "runtime_publication_portal_root_queued"))
    #expect(FrameDiagnosticsTSVFormatting.fields(for: record)[index] == "-")
    record.runtimePublicationPresentationPortalRootQueued = false
    #expect(FrameDiagnosticsTSVFormatting.fields(for: record)[index] == "0")
    record.runtimePublicationPresentationPortalRootQueued = true
    #expect(FrameDiagnosticsTSVFormatting.fields(for: record)[index] == "1")
  }

  @Test func setA799JSONLOccupancyDoesNotRoundLargeIntegerCountsThroughDouble() throws {
    // Hypothesis: diagnostic numeric serialization loses integer currency above the binary64 exact-integer boundary.
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let value = 9_007_199_254_740_993
    let sink = try #require(FileProfileSink(path: url.path, format: .jsonl))
    sink.emit(.memory([.init(name: "large", count: value, approxBytes: Int.max)]))
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("\"count\":9007199254740993"))
    let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    let providers = try #require(object["providers"] as? [[String: Any]])
    #expect((providers.first?["count"] as? NSNumber)?.int64Value == Int64(value))
    #expect((providers.first?["approxBytes"] as? NSNumber)?.int64Value == Int64.max)
  }

  @Test func setA800LiveRunLoopsKeepTheirDiagnosticBridgesSessionLocal() throws {
    // Hypothesis: alternating frame emission consults a shared last-installed sink and attributes one runtime's committed frames to another.
    let a = SetAProfileRecords()
    let b = SetAProfileRecords()
    let h1 = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetA800a"), size: .init(width: 24, height: 3)
    ) { SetAProfileButton() }
    let h2 = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetA800b"), size: .init(width: 24, height: 3)
    ) { SetAProfileButton() }
    defer {
      h1.shutdown()
      h2.shutdown()
    }
    h1.runLoop.frameSink = ProfileFrameBridge(sinks: [HandlerSink { a.records.append($0) }])
    h2.runLoop.frameSink = ProfileFrameBridge(sinks: [HandlerSink { b.records.append($0) }])
    try h1.clickText("Tick")
    #expect(!a.records.isEmpty && b.records.isEmpty)
    let firstCount = a.records.count
    try h2.clickText("Tick")
    #expect(a.records.count == firstCount && !b.records.isEmpty)
    let secondCount = b.records.count
    try h1.clickText("Tick")
    #expect(a.records.count > firstCount && b.records.count == secondCount)
    #expect(h1.frame.contains("value2") && h2.frame.contains("value1"))
  }

  private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "set-a-profile-\(UUID().uuidString)")
  }
  private func temporaryDirectory() throws -> URL {
    let result = temporaryURL()
    try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
    return result
  }
  private func withSavedProfilingRegistry(_ operation: () throws -> Void) rethrows {
    let oldFrame = ProfilingRegistry.shared.frameSink
    let oldWrites = ProfilingRegistry.shared.presentationWriteSink
    ProfilingRegistry.shared.frameSink = nil
    ProfilingRegistry.shared.presentationWriteSink = nil
    defer {
      ProfilingRegistry.shared.frameSink = oldFrame
      ProfilingRegistry.shared.presentationWriteSink = oldWrites
    }
    try operation()
  }
  private func sample(_ number: Int) -> RuntimeFrameSample {
    .elided(
      .init(
        frameNumber: number,
        scheduledFrame: .init(
          causes: [], invalidatedIdentities: [], signalNames: [], externalReasons: [],
          triggeredDeadline: nil, nextDeadline: nil),
        desiredGeneration: 1, coalescedEventBatches: 0, coalescedWakeCauses: [],
        intentRequestCount: 0,
        animationControllerActiveAnimationCount: 0, animationControllerHasPendingWork: false,
        cancelledRenderCount: 0))
  }
  private func presentation(_ number: Int) -> PresentationWriteSample {
    .init(
      frame: number, submittedAt: .zero, writtenAt: .init(offset: .milliseconds(1)), bytes: 10,
      outcome: .written)
  }
  private func reading(time: Double, user: Double, system: Double) -> ProcessCPUReading {
    .init(
      timestampSeconds: time, userCPUSeconds: user, systemCPUSeconds: system, maxResidentBytes: 4096
    )
  }
  private func cpu(percent: Double, rss: Int) -> CPUSample {
    .init(
      timestampSeconds: 1, userCPUSeconds: 0, systemCPUSeconds: 0, totalCPUSeconds: 0,
      wallDeltaSeconds: 1, estimatedCPUPercent: percent, maxResidentBytes: rss)
  }
}

@MainActor private final class SetAProfileRecords { var records: [ProfileRecord] = [] }
@MainActor private final class SetAProfileProviderState { var token: MemoryMetricRegistry.Token? }
@MainActor private final class SetAProfileOwner { var value = 7 }
@MainActor private final class SetAProfileClock { var now = MonotonicInstant.zero }
private enum SetAProfileFailure: Error, Equatable { case operation }
private struct SetAProfileButton: View {
  @State private var value = 0
  var body: some View {
    VStack {
      Button("Tick") { value += 1 }
      Text("value\(value)")
    }
  }
}
