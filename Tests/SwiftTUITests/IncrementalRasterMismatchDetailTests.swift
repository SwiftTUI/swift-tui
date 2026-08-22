import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// The incremental-raster mismatch recorder folds the rasterizer's evidence
/// and the opt-out hint into the probe's per-kind detail, which is also the
/// DEBUG trap's message — the only artifact a consumer's crash report carries
/// (GitHub issue SwiftTUI/swift-tui#5 arrived with the rows alone).
@MainActor
@Suite("Incremental raster mismatch detail", .serialized)
struct IncrementalRasterMismatchDetailTests {
  @Test("the recorded detail carries the evidence and the opt-out hint")
  func recordedDetailCarriesEvidenceAndHint() {
    let probeEnabled = SoundnessProbeConfiguration.isEnabled
    let traceEnabled = SoundnessProbeConfiguration.isTraceEnabled
    let before = SoundnessCounterSnapshot.current()
    let lastDetail = SoundnessProbeConfiguration.lastViolationDetail
    defer {
      SoundnessProbeConfiguration.isEnabled = probeEnabled
      SoundnessProbeConfiguration.isTraceEnabled = traceEnabled
      SoundnessProbeConfiguration.rasterDamageMismatchCount = before.rasterDamageMismatchCount
      SoundnessProbeConfiguration.lastViolationDetail = lastDetail
      SoundnessProbeConfiguration.lastViolationDetailByKind = before.lastViolationDetailByKind
    }
    SoundnessProbeConfiguration.isEnabled = false
    SoundnessProbeConfiguration.isTraceEnabled = false

    DefaultRendererFrameTailCoordinator.recordIncrementalRasterMismatchIfCaught(
      .init(
        mismatchedRows: [2],
        evidence: "trusted damage rows [1, 2]; row 2 incremental=\" ● \" fresh=\"[●]\""
      )
    )

    let detail = SoundnessProbeConfiguration.lastViolationDetailByKind["raster-damage"] ?? ""
    #expect(detail.contains("rows [2] diverged from fresh raster"), "detail: \(detail)")
    #expect(detail.contains("trusted damage rows [1, 2]"), "detail: \(detail)")
    #expect(detail.contains("row 2 incremental=\" ● \" fresh=\"[●]\""), "detail: \(detail)")
    #expect(detail.contains("SWIFTTUI_SOUNDNESS_PROBE=0"), "detail: \(detail)")
    #expect(
      SoundnessProbeConfiguration.rasterDamageMismatchCount == before.rasterDamageMismatchCount + 1
    )
  }

  @Test("a mismatch without evidence still names the rows and the hint")
  func recordedDetailWithoutEvidence() {
    let probeEnabled = SoundnessProbeConfiguration.isEnabled
    let traceEnabled = SoundnessProbeConfiguration.isTraceEnabled
    let before = SoundnessCounterSnapshot.current()
    let lastDetail = SoundnessProbeConfiguration.lastViolationDetail
    defer {
      SoundnessProbeConfiguration.isEnabled = probeEnabled
      SoundnessProbeConfiguration.isTraceEnabled = traceEnabled
      SoundnessProbeConfiguration.rasterDamageMismatchCount = before.rasterDamageMismatchCount
      SoundnessProbeConfiguration.lastViolationDetail = lastDetail
      SoundnessProbeConfiguration.lastViolationDetailByKind = before.lastViolationDetailByKind
    }
    SoundnessProbeConfiguration.isEnabled = false
    SoundnessProbeConfiguration.isTraceEnabled = false

    DefaultRendererFrameTailCoordinator.recordIncrementalRasterMismatchIfCaught(
      .init(mismatchedRows: [])
    )

    let detail = SoundnessProbeConfiguration.lastViolationDetailByKind["raster-damage"] ?? ""
    #expect(
      detail.hasPrefix(
        "incremental raster mismatch: non-cell surface state diverged from fresh raster (the frame"
      ),
      "no evidence clause without evidence: \(detail)"
    )
    #expect(detail.contains("SWIFTTUI_SOUNDNESS_PROBE=0"), "detail: \(detail)")
  }
}
