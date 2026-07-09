import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Coverage for the sampled-release reconciliation soundness probe.
///
/// The probe runs the framework's read-only soundness oracles (stamp coherence,
/// delta-checkpoint equality) on a sampled fraction of frames in release builds,
/// so the reconciliation-seam bug class they catch is no longer invisible in
/// release. These tests validate the gating/sampling math and the extracted
/// stamp-coherence oracle directly — including a deliberately corrupted input
/// that must trip it — without needing a release build. The wired release
/// `#else` call sites themselves are only compiled under `-c release`; the
/// org-gate CI exercises that configuration.
@MainActor
@Suite("Soundness probe")
struct SoundnessProbeConfigurationTests {
  /// Save and restore every process-global static the probe owns so a test
  /// never leaks the probe being enabled into unrelated suites (which would
  /// make them pay the oracle cost and could flake under load).
  private func withRestoredProbeState(_ body: () throws -> Void) rethrows {
    let enabled = SoundnessProbeConfiguration.isEnabled
    let sample = SoundnessProbeConfiguration.sampleEveryNFrames
    let latch = SoundnessProbeConfiguration.isSampledFrame
    let stampCount = SoundnessProbeConfiguration.stampCoherenceViolationCount
    let deltaCount = SoundnessProbeConfiguration.deltaCheckpointViolationCount
    let rasterCount = SoundnessProbeConfiguration.rasterDamageMismatchCount
    let teardownCount = SoundnessProbeConfiguration.teardownCoherenceViolationCount
    let publicationCount = SoundnessProbeConfiguration.registrationPublicationViolationCount
    let detail = SoundnessProbeConfiguration.lastViolationDetail
    defer {
      SoundnessProbeConfiguration.isEnabled = enabled
      SoundnessProbeConfiguration.sampleEveryNFrames = sample
      SoundnessProbeConfiguration.isSampledFrame = latch
      SoundnessProbeConfiguration.stampCoherenceViolationCount = stampCount
      SoundnessProbeConfiguration.deltaCheckpointViolationCount = deltaCount
      SoundnessProbeConfiguration.rasterDamageMismatchCount = rasterCount
      SoundnessProbeConfiguration.teardownCoherenceViolationCount = teardownCount
      SoundnessProbeConfiguration.registrationPublicationViolationCount = publicationCount
      SoundnessProbeConfiguration.lastViolationDetail = detail
    }
    try body()
  }

  @Test("teardown coherence violations are counted with detail")
  func teardownCoherenceViolationRecordsCountAndDetail() {
    withRestoredProbeState {
      let before = SoundnessProbeConfiguration.teardownCoherenceViolationCount
      SoundnessProbeConfiguration.recordTeardownCoherenceViolation("orphan strand")
      #expect(SoundnessProbeConfiguration.teardownCoherenceViolationCount == before + 1)
      #expect(SoundnessProbeConfiguration.lastViolationDetail == "orphan strand")
    }
  }

  @Test("registration publication violations are counted with detail")
  func registrationPublicationViolationRecordsCountAndDetail() {
    withRestoredProbeState {
      let before = SoundnessProbeConfiguration.registrationPublicationViolationCount
      SoundnessProbeConfiguration.recordRegistrationPublicationViolation("keys diverged")
      #expect(
        SoundnessProbeConfiguration.registrationPublicationViolationCount == before + 1
      )
      #expect(SoundnessProbeConfiguration.lastViolationDetail == "keys diverged")
    }
  }

  @Test("raster damage mismatches are counted with detail")
  func rasterDamageMismatchRecordsCountAndDetail() {
    withRestoredProbeState {
      let before = SoundnessProbeConfiguration.rasterDamageMismatchCount
      SoundnessProbeConfiguration.recordRasterDamageMismatch("rows [3] diverged")
      #expect(SoundnessProbeConfiguration.rasterDamageMismatchCount == before + 1)
      #expect(SoundnessProbeConfiguration.lastViolationDetail == "rows [3] diverged")
    }
  }

  // MARK: - Gating & sampling math (this is how the release #else logic is validated)

  @Test("every frame is sampled at period 1")
  func samplesEveryFrameAtPeriodOne() {
    withRestoredProbeState {
      SoundnessProbeConfiguration.isEnabled = true
      SoundnessProbeConfiguration.sampleEveryNFrames = 1
      for frame: UInt64 in 0...3 {
        SoundnessProbeConfiguration.beginFrame(frameID: frame)
        #expect(SoundnessProbeConfiguration.isSampledFrame)
      }
    }
  }

  @Test("1-in-N sampling latches only on multiples of N")
  func samplesEveryNthFrame() {
    withRestoredProbeState {
      SoundnessProbeConfiguration.isEnabled = true
      SoundnessProbeConfiguration.sampleEveryNFrames = 4
      let expectations: [(UInt64, Bool)] = [
        (0, true), (1, false), (2, false), (3, false), (4, true), (5, false), (8, true),
      ]
      for (frame, expected) in expectations {
        SoundnessProbeConfiguration.beginFrame(frameID: frame)
        #expect(SoundnessProbeConfiguration.isSampledFrame == expected, "frame \(frame)")
      }
    }
  }

  @Test("a zero period is clamped to 1, never a divide-by-zero")
  func zeroPeriodIsClamped() {
    withRestoredProbeState {
      SoundnessProbeConfiguration.isEnabled = true
      SoundnessProbeConfiguration.sampleEveryNFrames = 0
      SoundnessProbeConfiguration.beginFrame(frameID: 3)
      #expect(SoundnessProbeConfiguration.isSampledFrame)
    }
  }

  @Test("a disabled probe never samples")
  func disabledProbeNeverSamples() {
    withRestoredProbeState {
      SoundnessProbeConfiguration.isEnabled = false
      SoundnessProbeConfiguration.sampleEveryNFrames = 1
      SoundnessProbeConfiguration.beginFrame(frameID: 0)
      #expect(SoundnessProbeConfiguration.isSampledFrame == false)
    }
  }

  // MARK: - The extracted stamp-coherence oracle

  /// Builds a stamped two-level graph and returns its root live node + the
  /// coherently stamped committed snapshot.
  private func stampedRootAndSnapshot() throws -> (root: ViewNode, committed: ResolvedNode) {
    let graph = ViewGraph()
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: testIdentity("Root"),
        kind: .root,
        children: [
          ResolvedNode(identity: testIdentity("Root", "Leaf"), kind: .view("Leaf"))
        ]
      )
    )
    let committed = graph.snapshot()
    let rootID = try #require(committed.viewNodeID)
    let root = try #require(graph.nodeForViewNodeID(rootID))
    return (root, committed)
  }

  @Test("a coherently stamped subtree reports no violation")
  func soundSubtreeHasNoViolation() throws {
    let (root, committed) = try stampedRootAndSnapshot()
    #expect(root.resolvedStampsCoherenceViolation(committed, children: root.children) == nil)
  }

  @Test("count mismatch is tolerated, not reported as a violation")
  func countMismatchIsTolerated() throws {
    // Group splices / capture-host injections legitimately misalign child
    // counts; the oracle stops descending rather than false-positive.
    let (root, committed) = try stampedRootAndSnapshot()
    #expect(root.resolvedStampsCoherenceViolation(committed, children: []) == nil)
  }

  @Test("a divergent value stamp is detected and recorded")
  func divergentStampIsDetected() throws {
    try withRestoredProbeState {
      let (root, committed) = try stampedRootAndSnapshot()

      var corrupted = committed
      corrupted.viewNodeID = ViewNodeID(rawValue: 999_999)  // diverges from the live root

      let violation = root.resolvedStampsCoherenceViolation(corrupted, children: root.children)
      #expect(violation != nil)
      #expect(violation?.contains("diverges") == true)

      let before = SoundnessProbeConfiguration.stampCoherenceViolationCount
      SoundnessProbeConfiguration.recordStampCoherenceViolation(violation ?? "")
      #expect(SoundnessProbeConfiguration.stampCoherenceViolationCount == before + 1)
      #expect(SoundnessProbeConfiguration.lastViolationDetail != nil)
    }
  }
}
