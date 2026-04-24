import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct IntrinsicTextUnderZeroProposalBehaviourTests {
  /// The layout renders two copies of `Text("intrinsic content")`:
  ///
  ///   1. plain (no frame modifier)
  ///   2. wrapped in `.frame(width: 0, height: 0)`
  ///
  /// Observed raster (60×10):
  ///
  /// ```
  /// [1] | Intrinsic text under zero proposal|
  /// [3] | plain copy:|
  /// [5] | intrinsic content|
  /// [7] | zero-frame copy:|
  /// ```
  ///
  /// Only the plain copy appears: the `.frame(width: 0, height: 0)`
  /// copy is fully clipped out of the raster. The zero proposal
  /// effectively removes the text from the visible surface, leaving
  /// the layout slot empty.
  ///
  /// See `BEHAVIOUR_FINDINGS.md` finding #5. This test pins the
  /// observed behaviour: exactly ONE row contains "intrinsic
  /// content".
  @Test(".frame(width: 0, height: 0) clips the text out of the raster")
  func zeroFrameCopyVanishes() {
    let raster = render(IntrinsicTextUnderZeroProposal(), width: 60, height: 10).rasterSurface
    let occurrences = raster.rows(containing: "intrinsic content")

    #expect(
      occurrences.count == 1,
      "expected exactly 1 visible 'intrinsic content' row (zero-frame copy clipped); observed at rows \(occurrences)\n\(raster.lines.joined(separator: "\n"))"
    )
  }
}
