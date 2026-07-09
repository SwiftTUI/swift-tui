import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Coverage for the memo-soundness alarm (F90): the shadow oracle's unsound
/// class splits into per-resolve entity bookkeeping (histogram-only) and
/// *content* divergence (a comparator false-equal — the class that would have
/// served stale UI had the production gate skipped the node). Only a no-reads
/// content divergence raises the cumulative alarm on
/// `SoundnessProbeConfiguration`, which the run loop routes to the host as a
/// `RuntimeIssue` alongside the other F34 soundness counters.
@MainActor
@Suite("Memo soundness alarm")
struct MemoSoundnessAlarmTests {
  /// Save and restore every process-global static this suite touches so an
  /// enabled trace or a synthetic alarm never leaks into unrelated suites.
  private func withRestoredTraceAndAlarmState(_ body: () throws -> Void) rethrows {
    let enabled = MemoSkipTrace.isEnabled
    let sample = MemoSkipTrace.sampleEveryNFrames
    let latch = MemoSkipTrace.isSampledFrame
    let alarmCount = SoundnessProbeConfiguration.memoUnsoundSkipCount
    let detail = SoundnessProbeConfiguration.lastViolationDetail
    defer {
      MemoSkipTrace.isEnabled = enabled
      MemoSkipTrace.sampleEveryNFrames = sample
      MemoSkipTrace.isSampledFrame = latch
      MemoSkipTrace.reset()
      SoundnessProbeConfiguration.memoUnsoundSkipCount = alarmCount
      SoundnessProbeConfiguration.lastViolationDetail = detail
    }
    try body()
  }

  private func beginObservedFrame() {
    MemoSkipTrace.isEnabled = true
    MemoSkipTrace.sampleEveryNFrames = 1
    MemoSkipTrace.isSampledFrame = true
    MemoSkipTrace.reset()
  }

  private func leafPair() -> (ResolvedNode, ResolvedNode) {
    let node = ResolvedNode(identity: testIdentity("Root"), kind: .view("Leaf"))
    return (node, node)
  }

  // MARK: - Content-vs-bookkeeping classification

  @Test("entity bookkeeping divergence alone is not a content divergence")
  func bookkeepingOnlyDivergenceIsNotContent() {
    var (current, committed) = leafPair()
    current.entityIdentity = EntityIdentity("entity", occurrence: 0)
    committed.entityIdentity = EntityIdentity("entity", occurrence: 1)

    #expect(!current.memoReuseEquivalent(to: committed))
    #expect(current.memoUnsoundContentDivergence(from: committed) == nil)
    #expect(current.memoFirstDifferingField(from: committed) == "entityIdentity")
  }

  @Test("a content divergence is never masked by a coincident bookkeeping diff")
  func contentDivergenceIsNotMaskedByBookkeeping() {
    var (current, committed) = leafPair()
    // Both a bookkeeping diff (entity occurrence) and a content diff (kind):
    // the classifier and the histogram must both surface the content field.
    current.entityIdentity = EntityIdentity("entity", occurrence: 0)
    committed.entityIdentity = EntityIdentity("entity", occurrence: 1)
    committed.kind = .view("Renamed")

    #expect(current.memoUnsoundContentDivergence(from: committed) == "kind")
    #expect(current.memoFirstDifferingField(from: committed) == "kind")
  }

  @Test("a child content divergence surfaces with its path")
  func childContentDivergenceSurfaces() {
    let child = ResolvedNode(identity: testIdentity("Root", "Leaf"), kind: .view("Leaf"))
    var changedChild = child
    changedChild.kind = .view("Renamed")
    let current = ResolvedNode(
      identity: testIdentity("Root"), kind: .root, children: [child]
    )
    let committed = ResolvedNode(
      identity: testIdentity("Root"), kind: .root, children: [changedChild]
    )

    #expect(current.memoUnsoundContentDivergence(from: committed) == "child.kind")
  }

  @Test("oracle-equivalent nodes report no differing field")
  func equivalentNodesReportNoField() {
    let (current, committed) = leafPair()
    #expect(current.memoReuseEquivalent(to: committed))
    #expect(current.memoUnsoundContentDivergence(from: committed) == nil)
    #expect(current.memoFirstDifferingField(from: committed) == nil)
  }

  // MARK: - Alarm intake

  @Test("a no-reads content divergence raises the memo-soundness alarm")
  func noReadsContentDivergenceRaisesAlarm() {
    withRestoredTraceAndAlarmState {
      beginObservedFrame()
      let before = SoundnessProbeConfiguration.memoUnsoundSkipCount
      MemoSkipTrace.recordUnsoundSkip(
        hadReads: false,
        contentDivergenceField: "drawPayload",
        firstDifferingField: "drawPayload"
      )
      #expect(SoundnessProbeConfiguration.memoUnsoundSkipCount == before + 1)
      #expect(MemoSkipTrace.unsoundContentNoReads == 1)
      #expect(SoundnessProbeConfiguration.lastViolationDetail?.contains("drawPayload") == true)
    }
  }

  @Test("a with-reads divergence never alarms (dependency-explained re-run)")
  func withReadsDivergenceDoesNotAlarm() {
    withRestoredTraceAndAlarmState {
      beginObservedFrame()
      let before = SoundnessProbeConfiguration.memoUnsoundSkipCount
      MemoSkipTrace.recordUnsoundSkip(
        hadReads: true,
        contentDivergenceField: "drawPayload",
        firstDifferingField: "drawPayload"
      )
      #expect(SoundnessProbeConfiguration.memoUnsoundSkipCount == before)
      #expect(MemoSkipTrace.unsoundWithReads == 1)
      #expect(MemoSkipTrace.unsoundContentNoReads == 0)
    }
  }

  @Test("a bookkeeping-only no-reads divergence never alarms")
  func bookkeepingOnlyDivergenceDoesNotAlarm() {
    withRestoredTraceAndAlarmState {
      beginObservedFrame()
      let before = SoundnessProbeConfiguration.memoUnsoundSkipCount
      MemoSkipTrace.recordUnsoundSkip(
        hadReads: false,
        contentDivergenceField: nil,
        firstDifferingField: "entityIdentity"
      )
      #expect(SoundnessProbeConfiguration.memoUnsoundSkipCount == before)
      #expect(MemoSkipTrace.unsoundNoReads == 1)
      #expect(MemoSkipTrace.unsoundContentNoReads == 0)
      #expect(MemoSkipTrace.unsoundFieldCounts["entityIdentity"] == 1)
    }
  }

  @Test("an unobserved frame records nothing and never alarms")
  func unobservedFrameRecordsNothing() {
    withRestoredTraceAndAlarmState {
      beginObservedFrame()
      MemoSkipTrace.isSampledFrame = false
      let before = SoundnessProbeConfiguration.memoUnsoundSkipCount
      MemoSkipTrace.recordUnsoundSkip(
        hadReads: false,
        contentDivergenceField: "drawPayload",
        firstDifferingField: "drawPayload"
      )
      #expect(SoundnessProbeConfiguration.memoUnsoundSkipCount == before)
      #expect(MemoSkipTrace.unsoundSkip == 0)
    }
  }
}
