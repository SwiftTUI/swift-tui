import SwiftTUI
import Testing

@testable import Layouts

/// A/B variant: same `HStack` shape but BOTH spacers are plain
/// `Spacer()`. With no `minLength` floor on the trailing spacer the
/// two spacers should split residual space equally — proving that the
/// primary test's "trailing gap ≥ 20" finding is caused by the
/// `minLength: 20` floor and not by some other layout quirk.
@MainActor
private struct SpacerMinLengthRespectedNoMinVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Spacer min length respected").foregroundStyle(.muted)
      HStack(spacing: 0) {
        Text("[L]")
        Spacer()
        Text("[M]")
        Spacer()
        Text("[R]")
      }
    }
  }
}

@MainActor
@Suite
struct SpacerMinLengthRespectedBehaviourTests {
  /// `Spacer(minLength: 20)` between `[M]` and `[R]` reserves at least
  /// 20 cells for that gap; the leading `Spacer()` between `[L]` and
  /// `[M]` is compressed to whatever residual remains.
  ///
  /// Pinned at width 40:
  ///   - Total content (`[L]` + `[M]` + `[R]`) = 9 cells.
  ///   - Residual = 31 cells; the trailing spacer claims ≥ 20, leaving
  ///     ≤ 11 for the leading spacer.
  ///   - Therefore: `colR - colM ≥ 20` (the right gap honours the min)
  ///     AND `colM - colL ≤ 14` (the left gap is the squeezed
  ///     remainder; allow a few cells of slack for rounding).
  @Test("Spacer(minLength: 20) reserves >= 20 cells; leading spacer compresses")
  func minLengthFloorReservesTrailingGap() {
    let raster = render(SpacerMinLengthRespected(), width: 40, height: 6).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    guard let row = raster.firstRow(containing: "[L]"),
      let line = raster.row(at: row),
      let colL = column(of: "[L]", in: line),
      let colM = column(of: "[M]", in: line),
      let colR = column(of: "[R]", in: line)
    else {
      Issue.record(
        "expected `[L]`, `[M]`, `[R]` on the same row\n\(joined)"
      )
      return
    }

    // Order check.
    #expect(
      colL < colM && colM < colR,
      "expected colL (\(colL)) < colM (\(colM)) < colR (\(colR))\nrow: '\(line)'"
    )

    // [L] anchors at the leading edge (column 0) under the leading
    // marker convention.
    #expect(
      colL == 0,
      "expected [L] at column 0; got \(colL)\nrow: '\(line)'"
    )

    // The trailing spacer's `minLength: 20` claim. `colR - colM` is
    // the distance from the LEFT bracket of `[M]` to the LEFT bracket
    // of `[R]`; subtract `[M]`'s 3-cell width to recover the gap, but
    // we use the simpler `colR - colM ≥ 20 + 3 = 23` form so the
    // assertion text matches the floor's intent.
    let trailingSpan = colR - colM
    #expect(
      trailingSpan >= 23,
      """
      expected trailing span colR - colM (\(trailingSpan)) >= 23 \
      (3 cells for [M] + 20-cell minLength floor)
      row: '\(line)'
      """
    )

    // Leading spacer is squeezed: colM - colL ≤ 14 (3 cells for [L]
    // plus ≤ 11 cells of squeezed residual).
    let leadingSpan = colM - colL
    #expect(
      leadingSpan <= 14,
      """
      expected leading span colM - colL (\(leadingSpan)) <= 14; the \
      trailing minLength floor should compress the leading spacer
      row: '\(line)'
      """
    )
  }

  /// A/B non-vacuity: removing the `minLength: 20` from the trailing
  /// spacer turns it into a plain `Spacer()`. Two equal spacers split
  /// residual space evenly, so `colR - colM` should DROP below the
  /// `>= 23` threshold the primary test pins. Without this A/B the
  /// primary assertion could plausibly pass for an unrelated reason
  /// (e.g. the trailing spacer always took the lion's share for some
  /// other layout reason).
  @Test("Without minLength, two plain Spacers split evenly: trailing span drops")
  func plainSpacersSplitEvenlyWithoutMinLength() {
    let pinnedRaster = render(
      SpacerMinLengthRespected(),
      width: 40,
      height: 6,
      id: "pinned"
    ).rasterSurface
    let plainRaster = render(
      SpacerMinLengthRespectedNoMinVariant(),
      width: 40,
      height: 6,
      id: "plain"
    ).rasterSurface

    func trailingSpan(_ raster: RasterSurface) -> Int? {
      guard let row = raster.firstRow(containing: "[L]"),
        let line = raster.row(at: row),
        let colM = column(of: "[M]", in: line),
        let colR = column(of: "[R]", in: line)
      else { return nil }
      return colR - colM
    }

    guard let pinnedSpan = trailingSpan(pinnedRaster),
      let plainSpan = trailingSpan(plainRaster)
    else {
      Issue.record(
        """
        could not measure trailing span in one of the rasters
        PINNED:
        \(pinnedRaster.lines.joined(separator: "\n"))
        PLAIN:
        \(plainRaster.lines.joined(separator: "\n"))
        """
      )
      return
    }

    // The pinned (minLength-bearing) variant's trailing span MUST be
    // strictly larger than the plain-spacer variant's trailing span.
    // If they are equal, `minLength` is not influencing layout —
    // primary test would be a false green.
    #expect(
      pinnedSpan > plainSpan,
      """
      expected pinned trailing span (\(pinnedSpan)) > plain trailing \
      span (\(plainSpan)); minLength must produce a measurably wider \
      trailing gap than two plain spacers splitting evenly.
      """
    )
  }
}
