import Foundation
import Testing

@testable import SwiftTUIGraph

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

@MainActor
@Suite("Soundness failure channel", .serialized)
struct SoundnessFailureChannelTests {
  private static let traceKinds = [
    "stamp-coherence",
    "delta-checkpoint",
    "checkpoint-store",
    "raster-damage",
    "teardown-coherence",
    "teardown-coherence-leak",
    "teardown-barrier-non-convergence",
    "resolve-lifetime-scope-unclassified",
    "registration-publication",
    "memo-unsound-skip",
    "duplicate-registration",
    "planner-targetless-frontier",
    "lifecycle-handler-skip",
    "ambient-environment-fallback",
    "state-slot-restoration-drop",
    "committed-handler-resolution",
    "handler-resolution-action",
    "handler-resolution-key",
    "handler-resolution-command",
    "handler-resolution-drop",
    "handler-resolution-gesture",
    "action-dispatch-miss",
    "stranded-listing",
  ]

  @Test("every violation recorder emits one parseable soundness line")
  func everyViolationRecorderEmitsParseableLine() throws {
    let scratch = try makeScratchDirectory()
    defer { try? FileManager.default.removeItem(at: scratch) }
    let traceFile = scratch.appendingPathComponent("all-kinds.log")
    let previousState = ProbeState.capture()
    defer { previousState.restore() }

    withEnvironmentVariable(
      SoundnessProbeConfiguration.traceFileEnvironmentVariableName,
      value: traceFile.path
    ) {
      SoundnessProbeConfiguration.isEnabled = false
      SoundnessProbeConfiguration.isTraceEnabled = true
      recordEveryViolationKind()
    }

    let contents = try String(contentsOf: traceFile, encoding: .utf8)
    let lines = contents.split(separator: "\n").map(String.init)
    let emittedKinds = lines.compactMap(Self.parseTraceKind)

    #expect(lines.count == Self.traceKinds.count)
    #expect(emittedKinds == Self.traceKinds)
  }

  @Test("scanner rejects every unquarantined violation kind")
  func scannerRejectsUnquarantinedKinds() throws {
    let fixture = try makeScannerFixture(
      lines: Self.traceKinds.map { "[SOUNDNESS] \($0): injected" },
      quarantine: "# no quarantined kinds\n"
    )
    defer { try? FileManager.default.removeItem(at: fixture.scratch) }

    let result = try runScanner(fixture)

    #expect(result.status == 1)
    for kind in Self.traceKinds {
      #expect(result.output.contains("FAIL: \(kind)"))
    }
    #expect(result.output.contains("fixture-step.log"))
  }

  @Test("scanner accepts a quarantined kind at its exact baseline")
  func scannerAcceptsExactQuarantineBaseline() throws {
    let fixture = try makeScannerFixture(
      lines: [
        "[SOUNDNESS] registration-publication: first",
        "[SOUNDNESS] registration-publication: second",
      ],
      quarantine:
        "registration-publication 2026-07-28 TEST-1 count=2 exact test baseline\n"
    )
    defer { try? FileManager.default.removeItem(at: fixture.scratch) }

    let result = try runScanner(fixture)

    #expect(result.status == 0)
    #expect(result.output.contains("WARNING: registration-publication count=2 matches baseline=2"))
  }

  @Test("scanner rejects quarantine growth")
  func scannerRejectsQuarantineGrowth() throws {
    let fixture = try makeScannerFixture(
      lines: [
        "[SOUNDNESS] teardown-coherence-leak: first",
        "[SOUNDNESS] teardown-coherence-leak: second",
      ],
      quarantine:
        "teardown-coherence-leak 2026-07-28 TEST-2 count=1 growth fixture\n"
    )
    defer { try? FileManager.default.removeItem(at: fixture.scratch) }

    let result = try runScanner(fixture)

    #expect(result.status == 1)
    #expect(result.output.contains("FAIL: teardown-coherence-leak count=2 exceeds baseline=1"))
  }

  @Test("scanner reports quarantine shrink without failing")
  func scannerReportsQuarantineShrink() throws {
    let fixture = try makeScannerFixture(
      lines: ["[SOUNDNESS] registration-publication: remaining"],
      quarantine:
        "registration-publication 2026-07-28 TEST-3 count=2 shrink fixture\n"
    )
    defer { try? FileManager.default.removeItem(at: fixture.scratch) }

    let result = try runScanner(fixture)

    #expect(result.status == 0)
    #expect(
      result.output.contains(
        "WARNING: registration-publication count=1 is below baseline=2; reduce the ledger"
      )
    )
  }

  private func recordEveryViolationKind() {
    SoundnessProbeConfiguration.recordStampCoherenceViolation("test")
    SoundnessProbeConfiguration.recordDeltaCheckpointViolation("test")
    SoundnessProbeConfiguration.recordCheckpointStoreViolation("test")
    SoundnessProbeConfiguration.recordRasterDamageMismatch("test")
    SoundnessProbeConfiguration.recordTeardownCoherenceViolation("test")
    SoundnessProbeConfiguration.recordTeardownCoherenceLeak("test", unreachableCount: 1)
    SoundnessProbeConfiguration.recordBarrierNonConvergence("test")
    SoundnessProbeConfiguration.recordUnclassifiedResolvedNode("test")
    SoundnessProbeConfiguration.recordRegistrationPublicationViolation("test")
    SoundnessProbeConfiguration.recordMemoUnsoundSkip("test")
    SoundnessProbeConfiguration.recordDuplicateRegistrationOverwrite("test")
    SoundnessProbeConfiguration.recordPlannerTargetlessFrontierEscalation("test")
    SoundnessProbeConfiguration.recordLifecycleHandlerSkip("test")
    SoundnessProbeConfiguration.recordAmbientEnvironmentFallbackRead("test")
    SoundnessProbeConfiguration.recordStateSlotRestorationDrop("test")
    SoundnessProbeConfiguration.recordCommittedHandlerResolutionViolation("test")
    SoundnessProbeConfiguration.recordInteractiveHandlerResolutionViolation(
      family: .action,
      detail: "test"
    )
    SoundnessProbeConfiguration.recordInteractiveHandlerResolutionViolation(
      family: .key,
      detail: "test"
    )
    SoundnessProbeConfiguration.recordInteractiveHandlerResolutionViolation(
      family: .command,
      detail: "test"
    )
    SoundnessProbeConfiguration.recordInteractiveHandlerResolutionViolation(
      family: .drop,
      detail: "test"
    )
    SoundnessProbeConfiguration.recordInteractiveHandlerResolutionViolation(
      family: .gesture,
      detail: "test"
    )
    SoundnessProbeConfiguration.recordActionDispatchMiss("test")
    SoundnessProbeConfiguration.recordStrandedListingViolation("test")
  }

  private static func parseTraceKind(_ line: String) -> String? {
    let prefix = "[SOUNDNESS] "
    guard line.hasPrefix(prefix) else {
      return nil
    }
    let remainder = line.dropFirst(prefix.count)
    guard let colon = remainder.firstIndex(of: ":") else {
      return nil
    }
    let kind = remainder[..<colon]
    guard !kind.isEmpty,
      kind.allSatisfy({ $0.isLowercase || $0 == "-" })
    else {
      return nil
    }
    return String(kind)
  }

  private func makeScannerFixture(
    lines: [String],
    quarantine: String
  ) throws -> ScannerFixture {
    let scratch = try makeScratchDirectory()
    let traceRoot = scratch.appendingPathComponent("traces")
    try FileManager.default.createDirectory(
      at: traceRoot,
      withIntermediateDirectories: true
    )
    try (lines.joined(separator: "\n") + "\n").write(
      to: traceRoot.appendingPathComponent("fixture-step.log"),
      atomically: true,
      encoding: .utf8
    )
    let quarantineFile = scratch.appendingPathComponent("quarantine.txt")
    try quarantine.write(to: quarantineFile, atomically: true, encoding: .utf8)
    return ScannerFixture(
      scratch: scratch,
      traceRoot: traceRoot,
      quarantineFile: quarantineFile
    )
  }

  private func runScanner(_ fixture: ScannerFixture) throws -> ScannerResult {
    let repositoryRoot = try SourceParsingTestSupport.repositoryRoot()
    let scanner = repositoryRoot.appendingPathComponent("Scripts/scan_soundness_traces.sh")
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [scanner.path, fixture.traceRoot.path, fixture.quarantineFile.path]
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    return ScannerResult(
      status: process.terminationStatus,
      output: String(decoding: data, as: UTF8.self)
    )
  }

  private func makeScratchDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("soundness-channel-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func withEnvironmentVariable<Result>(
    _ name: String,
    value: String,
    _ body: () throws -> Result
  ) rethrows -> Result {
    let previousValue = ProcessInfo.processInfo.environment[name]
    setEnvironmentVariable(name, value: value)
    defer { setEnvironmentVariable(name, value: previousValue) }
    return try body()
  }

  private func setEnvironmentVariable(_ name: String, value: String?) {
    unsafe name.withCString { namePointer in
      if let value {
        unsafe value.withCString { valuePointer in
          _ = unsafe setenv(namePointer, valuePointer, 1)
        }
      } else {
        _ = unsafe unsetenv(namePointer)
      }
    }
  }
}

private struct ScannerFixture {
  let scratch: URL
  let traceRoot: URL
  let quarantineFile: URL
}

private struct ScannerResult {
  let status: Int32
  let output: String
}

@MainActor
private struct ProbeState {
  let isEnabled: Bool
  let sampleEveryNFrames: Int
  let isSampledFrame: Bool
  let isTraceEnabled: Bool
  let stampCoherenceViolationCount: Int
  let deltaCheckpointViolationCount: Int
  let checkpointStoreViolationCount: Int
  let rasterDamageMismatchCount: Int
  let teardownCoherenceViolationCount: Int
  let teardownCoherenceLeakCount: Int
  let barrierNonConvergenceCount: Int
  let automaticLifetimeAnchorCount: Int
  let unclassifiedResolvedNodeCount: Int
  let lastTeardownLeakUnreachableCount: Int
  let registrationPublicationViolationCount: Int
  let memoUnsoundSkipCount: Int
  let duplicateRegistrationOverwriteCount: Int
  let stateSlotRestorationDropCount: Int
  let plannerTargetlessFrontierEscalationCount: Int
  let lifecycleHandlerSkipCount: Int
  let ambientEnvironmentFallbackReadCount: Int
  let committedHandlerResolutionViolationCount: Int
  let actionResolutionViolationCount: Int
  let keyHandlerResolutionViolationCount: Int
  let commandScopeResolutionViolationCount: Int
  let dropScopeResolutionViolationCount: Int
  let gestureRouteResolutionViolationCount: Int
  let actionDispatchMissCount: Int
  let strandedListingViolationCount: Int
  let lastViolationDetail: String?
  let lastViolationDetailByKind: [String: String]

  static func capture() -> Self {
    Self(
      isEnabled: SoundnessProbeConfiguration.isEnabled,
      sampleEveryNFrames: SoundnessProbeConfiguration.sampleEveryNFrames,
      isSampledFrame: SoundnessProbeConfiguration.isSampledFrame,
      isTraceEnabled: SoundnessProbeConfiguration.isTraceEnabled,
      stampCoherenceViolationCount: SoundnessProbeConfiguration.stampCoherenceViolationCount,
      deltaCheckpointViolationCount: SoundnessProbeConfiguration.deltaCheckpointViolationCount,
      checkpointStoreViolationCount: SoundnessProbeConfiguration.checkpointStoreViolationCount,
      rasterDamageMismatchCount: SoundnessProbeConfiguration.rasterDamageMismatchCount,
      teardownCoherenceViolationCount:
        SoundnessProbeConfiguration.teardownCoherenceViolationCount,
      teardownCoherenceLeakCount: SoundnessProbeConfiguration.teardownCoherenceLeakCount,
      barrierNonConvergenceCount: SoundnessProbeConfiguration.barrierNonConvergenceCount,
      automaticLifetimeAnchorCount: SoundnessProbeConfiguration.automaticLifetimeAnchorCount,
      unclassifiedResolvedNodeCount: SoundnessProbeConfiguration.unclassifiedResolvedNodeCount,
      lastTeardownLeakUnreachableCount:
        SoundnessProbeConfiguration.lastTeardownLeakUnreachableCount,
      registrationPublicationViolationCount:
        SoundnessProbeConfiguration.registrationPublicationViolationCount,
      memoUnsoundSkipCount: SoundnessProbeConfiguration.memoUnsoundSkipCount,
      duplicateRegistrationOverwriteCount:
        SoundnessProbeConfiguration.duplicateRegistrationOverwriteCount,
      stateSlotRestorationDropCount:
        SoundnessProbeConfiguration.stateSlotRestorationDropCount,
      plannerTargetlessFrontierEscalationCount:
        SoundnessProbeConfiguration.plannerTargetlessFrontierEscalationCount,
      lifecycleHandlerSkipCount: SoundnessProbeConfiguration.lifecycleHandlerSkipCount,
      ambientEnvironmentFallbackReadCount:
        SoundnessProbeConfiguration.ambientEnvironmentFallbackReadCount,
      committedHandlerResolutionViolationCount:
        SoundnessProbeConfiguration.committedHandlerResolutionViolationCount,
      actionResolutionViolationCount:
        SoundnessProbeConfiguration.actionResolutionViolationCount,
      keyHandlerResolutionViolationCount:
        SoundnessProbeConfiguration.keyHandlerResolutionViolationCount,
      commandScopeResolutionViolationCount:
        SoundnessProbeConfiguration.commandScopeResolutionViolationCount,
      dropScopeResolutionViolationCount:
        SoundnessProbeConfiguration.dropScopeResolutionViolationCount,
      gestureRouteResolutionViolationCount:
        SoundnessProbeConfiguration.gestureRouteResolutionViolationCount,
      actionDispatchMissCount: SoundnessProbeConfiguration.actionDispatchMissCount,
      strandedListingViolationCount:
        SoundnessProbeConfiguration.strandedListingViolationCount,
      lastViolationDetail: SoundnessProbeConfiguration.lastViolationDetail,
      lastViolationDetailByKind: SoundnessProbeConfiguration.lastViolationDetailByKind
    )
  }

  func restore() {
    SoundnessProbeConfiguration.isEnabled = isEnabled
    SoundnessProbeConfiguration.sampleEveryNFrames = sampleEveryNFrames
    SoundnessProbeConfiguration.isSampledFrame = isSampledFrame
    SoundnessProbeConfiguration.isTraceEnabled = isTraceEnabled
    SoundnessProbeConfiguration.stampCoherenceViolationCount = stampCoherenceViolationCount
    SoundnessProbeConfiguration.deltaCheckpointViolationCount = deltaCheckpointViolationCount
    SoundnessProbeConfiguration.checkpointStoreViolationCount = checkpointStoreViolationCount
    SoundnessProbeConfiguration.rasterDamageMismatchCount = rasterDamageMismatchCount
    SoundnessProbeConfiguration.teardownCoherenceViolationCount =
      teardownCoherenceViolationCount
    SoundnessProbeConfiguration.teardownCoherenceLeakCount = teardownCoherenceLeakCount
    SoundnessProbeConfiguration.barrierNonConvergenceCount = barrierNonConvergenceCount
    SoundnessProbeConfiguration.automaticLifetimeAnchorCount = automaticLifetimeAnchorCount
    SoundnessProbeConfiguration.unclassifiedResolvedNodeCount = unclassifiedResolvedNodeCount
    SoundnessProbeConfiguration.lastTeardownLeakUnreachableCount =
      lastTeardownLeakUnreachableCount
    SoundnessProbeConfiguration.registrationPublicationViolationCount =
      registrationPublicationViolationCount
    SoundnessProbeConfiguration.memoUnsoundSkipCount = memoUnsoundSkipCount
    SoundnessProbeConfiguration.duplicateRegistrationOverwriteCount =
      duplicateRegistrationOverwriteCount
    SoundnessProbeConfiguration.stateSlotRestorationDropCount =
      stateSlotRestorationDropCount
    SoundnessProbeConfiguration.plannerTargetlessFrontierEscalationCount =
      plannerTargetlessFrontierEscalationCount
    SoundnessProbeConfiguration.lifecycleHandlerSkipCount = lifecycleHandlerSkipCount
    SoundnessProbeConfiguration.ambientEnvironmentFallbackReadCount =
      ambientEnvironmentFallbackReadCount
    SoundnessProbeConfiguration.committedHandlerResolutionViolationCount =
      committedHandlerResolutionViolationCount
    SoundnessProbeConfiguration.actionResolutionViolationCount =
      actionResolutionViolationCount
    SoundnessProbeConfiguration.keyHandlerResolutionViolationCount =
      keyHandlerResolutionViolationCount
    SoundnessProbeConfiguration.commandScopeResolutionViolationCount =
      commandScopeResolutionViolationCount
    SoundnessProbeConfiguration.dropScopeResolutionViolationCount =
      dropScopeResolutionViolationCount
    SoundnessProbeConfiguration.gestureRouteResolutionViolationCount =
      gestureRouteResolutionViolationCount
    SoundnessProbeConfiguration.actionDispatchMissCount = actionDispatchMissCount
    SoundnessProbeConfiguration.strandedListingViolationCount =
      strandedListingViolationCount
    SoundnessProbeConfiguration.lastViolationDetail = lastViolationDetail
    SoundnessProbeConfiguration.lastViolationDetailByKind = lastViolationDetailByKind
  }
}
