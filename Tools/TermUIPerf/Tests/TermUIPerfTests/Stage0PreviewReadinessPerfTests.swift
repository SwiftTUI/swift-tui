import Foundation
import Testing

@testable import TermUIPerf

/// Preview-readiness Stage-0 controls. Exact counter values live in the
/// committed bench baseline; these checks prove the new instruments cannot go
/// green while measuring an empty tree, an unresolved image, or an empty trace.
struct Stage0PreviewReadinessPerfTests {
  @Test("focused cold scenarios are non-vacuous")
  @MainActor
  func focusedColdScenariosAreNonVacuous() throws {
    let dynamic = try BenchColdLane.run(DynamicPropertyHeavyScenario(), iterations: 4)
    #expect((dynamic.counters.resolvedComputed ?? 0) >= 64)
    #expect((dynamic.counters.drawNodes ?? 0) >= 64)

    let tabs = try BenchColdLane.run(GalleryTabSwitchScenario(), iterations: 4)
    #expect((tabs.counters.resolvedComputed ?? 0) >= 32)
    #expect((tabs.counters.drawNodes ?? 0) >= 24)

    let image = try BenchColdLane.run(StillImagePresentationScenario(), iterations: 4)
    #expect(image.counters.rasterImageAttachments == 1)
    #expect((image.counters.presentCells ?? 0) > 0)
  }

  @Test("reuse-denial census preserves totals and per-frame peaks")
  func reuseDenialCensusIsNonVacuous() {
    let census = PerfReuseDenialCensus.parse(
      """
      unrelated diagnostic
      [REUSE-TRACE] frame=7 recompute-reasons: dirty=3 no-node=2 | invalidated: App/Root
      [REUSE-TRACE] frame=8 recompute-reasons: dirty=1 suppressed=9 | scope: focus
      """
    )

    #expect(census.frameCount == 2)
    #expect(census.totalDenials == 15)
    #expect(census.peakDenialsPerFrame == 10)
    #expect(census.reasonTotals == ["dirty": 4, "no-node": 2, "suppressed": 9])
    #expect(census.reasonPeaks == ["dirty": 3, "no-node": 2, "suppressed": 9])
  }

  @Test("reuse-denial census preserves DynamicProperty update-result reasons")
  func dynamicPropertyReuseDenialsAreNonVacuous() {
    let census = PerfReuseDenialCensus.parse(
      """
      [REUSE-TRACE] frame=11 recompute-reasons: dynamic-property-changed=2 dynamic-property-uncertified=1
      """
    )

    #expect(census.frameCount == 1)
    #expect(census.totalDenials == 3)
    #expect(census.peakDenialsPerFrame == 3)
    #expect(
      census.reasonTotals == [
        "dynamic-property-changed": 2,
        "dynamic-property-uncertified": 1,
      ]
    )
    #expect(census.reasonPeaks == census.reasonTotals)
  }
}
