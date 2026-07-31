import SwiftTUICore
import SwiftTUIViews

/// The collection magnitude counters for one frame: how many rows the frame
/// realized, and how many times a list derived its visible layout.
///
/// These are the counters that let a millisecond be read. `resolve_ms` rising
/// on a scrolling collection means nothing on its own — it could be more rows
/// realized, or the same rows costing more each. Correlating the two is the
/// whole reason WP-4 exists, and it has to work in release: debug and release
/// disagree about per-cell work (the D71 lesson), so a debug-only counter can
/// only ever explain a debug-only timing.
///
/// Both probes are magnitudes, not violations, which is why they ride the
/// per-frame diagnostics assembly the way `custom_layout_fallbacks` does rather
/// than routing through `RuntimeIssues`.
package struct CollectionProbeSample: Sendable, Equatable {
  /// Rows an indexed child source realized this frame, or `nil` when the
  /// probes are disarmed.
  package var realizedRows: Int?
  /// List visible-layout derivations this frame, or `nil` when the probes are
  /// disarmed.
  package var listLayoutDerivations: Int?

  package init(realizedRows: Int?, listLayoutDerivations: Int?) {
    self.realizedRows = realizedRows
    self.listLayoutDerivations = listLayoutDerivations
  }

  /// Clears both counters at a frame head.
  ///
  /// Scoped to the head *attempt*, alongside `ElidedFrameTimingRecorder.reset()`
  /// and the fresh `FrameHeadTimingRecorder`, deliberately: a retried head
  /// re-reports from its retry, and so do the timings these counts exist to
  /// divide into. A counter and the milliseconds it explains have to cover the
  /// same work or the ratio is fiction.
  @MainActor
  package static func resetForFrameHead() {
    IndexedChildRealizationProbe.reset()
    ListLayoutDerivationProbe.reset()
  }

  /// Reads both counters at commit, after the frame tail has finished — list
  /// layout derivation happens on the worker, so an earlier read would miss it.
  @MainActor
  package static func sampleAtCommit() -> CollectionProbeSample {
    CollectionProbeSample(
      realizedRows: IndexedChildRealizationProbe.realizedChildCountIfArmed,
      listLayoutDerivations: ListLayoutDerivationProbe.derivationCountIfArmed
    )
  }
}
