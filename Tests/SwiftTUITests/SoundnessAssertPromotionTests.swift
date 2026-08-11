import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@MainActor
@Suite("Soundness assert promotions", .serialized)
struct SoundnessAssertPromotionTests {
  @Test("promoted recorders retain their counter channel when assertions are disabled")
  func promotedRecordersRemainObservableWithProbeDisabled() {
    let probeEnabled = SoundnessProbeConfiguration.isEnabled
    let traceEnabled = SoundnessProbeConfiguration.isTraceEnabled
    let before = SoundnessCounterSnapshot.current()
    let lastDetail = SoundnessProbeConfiguration.lastViolationDetail
    defer {
      SoundnessProbeConfiguration.isEnabled = probeEnabled
      SoundnessProbeConfiguration.isTraceEnabled = traceEnabled
      SoundnessProbeConfiguration.deltaCheckpointViolationCount =
        before.deltaCheckpointViolationCount
      SoundnessProbeConfiguration.checkpointStoreViolationCount =
        before.checkpointStoreViolationCount
      SoundnessProbeConfiguration.memoUnsoundSkipCount = before.memoUnsoundSkipCount
      SoundnessProbeConfiguration.stateSlotRestorationDropCount =
        before.stateSlotRestorationDropCount
      SoundnessProbeConfiguration.committedHandlerResolutionViolationCount =
        before.committedHandlerResolutionViolationCount
      SoundnessProbeConfiguration.rasterDamageMismatchCount =
        before.rasterDamageMismatchCount
      SoundnessProbeConfiguration.layoutShadowDivergenceCount =
        before.layoutShadowDivergenceCount
      SoundnessProbeConfiguration.layoutShadowWindowedExclusionCount =
        before.layoutShadowWindowedExclusionCount
      SoundnessProbeConfiguration.lastViolationDetail = lastDetail
      SoundnessProbeConfiguration.lastViolationDetailByKind =
        before.lastViolationDetailByKind
    }

    SoundnessProbeConfiguration.isEnabled = false
    SoundnessProbeConfiguration.isTraceEnabled = false
    SoundnessProbeConfiguration.recordDeltaCheckpointViolation("delta promotion")
    SoundnessProbeConfiguration.recordCheckpointStoreViolation("store promotion")
    SoundnessProbeConfiguration.recordMemoUnsoundSkip("memo promotion")
    SoundnessProbeConfiguration.recordStateSlotRestorationDrop("slot promotion")
    SoundnessProbeConfiguration.recordCommittedHandlerResolutionViolation(
      "handler promotion"
    )
    DefaultRendererFrameTailCoordinator.recordIncrementalRasterMismatchIfCaught(
      .init(mismatchedRows: [2])
    )
    var layoutShadowSummary = LayoutShadowComparisonSummary()
    layoutShadowSummary.measureDivergenceCount = 1
    layoutShadowSummary.windowedExclusionCount = 2
    layoutShadowSummary.firstDivergenceDetail = "injected measure divergence"
    DefaultRendererFrameTailCoordinator.recordLayoutShadowDivergenceIfCaught(
      layoutShadowSummary
    )

    let after = SoundnessCounterSnapshot.current()
    #expect(
      after.deltaCheckpointViolationCount == before.deltaCheckpointViolationCount + 1
    )
    #expect(
      after.checkpointStoreViolationCount == before.checkpointStoreViolationCount + 1
    )
    #expect(after.memoUnsoundSkipCount == before.memoUnsoundSkipCount + 1)
    #expect(
      after.stateSlotRestorationDropCount == before.stateSlotRestorationDropCount + 1
    )
    #expect(
      after.committedHandlerResolutionViolationCount
        == before.committedHandlerResolutionViolationCount + 1
    )
    #expect(after.rasterDamageMismatchCount == before.rasterDamageMismatchCount + 1)
    #expect(after.lastViolationDetailByKind["raster-damage"]?.contains("rows [2]") == true)
    #expect(after.layoutShadowDivergenceCount == before.layoutShadowDivergenceCount + 1)
    #expect(
      after.layoutShadowWindowedExclusionCount
        == before.layoutShadowWindowedExclusionCount + 2
    )
    #expect(
      after.lastViolationDetailByKind["layout-shadow-divergence"]?
        .contains("injected measure divergence") == true
    )
  }
}
