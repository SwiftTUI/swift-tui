import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct GeometryReaderTakesProposalBehaviourTests {
  /// Observed raster at 80×28 (bordered reader is 40 wide × 10 tall,
  /// centred at terminal top):
  ///
  /// ```
  /// [1]  Geometry reader takes proposal|
  /// [2]  ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|
  /// [7]  ▌               w=80 h=28                ▐|
  /// [13] ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
  /// ```
  ///
  /// A SwiftUI-faithful implementation would report the tightened
  /// `.frame(width: 40, height: 10)` proposal, so the label would
  /// read `"w=40 h=10"`.  The library reports the full terminal
  /// `(80, 28)` — see `BEHAVIOUR_FINDINGS.md` finding #4.
  ///
  /// This test pins the OBSERVED behaviour.  When finding #4 is
  /// closed, flip the assertions to expect `"w=40 h=10"`.
  @Test("GeometryReader reports the terminal size, not the .frame proposal (finding #4)")
  func proxyReportsTerminalSize() {
    let raster = render(GeometryReaderTakesProposal(), width: 80, height: 28).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    // The reader currently reports `terminalSize` directly — see
    // `BEHAVIOUR_FINDINGS.md` finding #4. When that is fixed, this
    // should read `"w=40 h=10"`.
    #expect(
      joined.contains("w=80 h=28"),
      """
      expected GeometryReader to report w=80 h=28 (observed library \
      behaviour); see BEHAVIOUR_FINDINGS.md finding #4. \
      When the library is fixed to honour proposal tightening for \
      GeometryReader proxies, flip this to `"w=40 h=10"`.
      \(joined)
      """
    )
    #expect(
      !joined.contains("w=40 h=10"),
      """
      `w=40 h=10` found in raster — finding #4 may be fixed. \
      Close the finding and flip the assertion to expect \
      `"w=40 h=10"` as the SwiftUI-faithful value.
      \(joined)
      """
    )
  }

  /// Vacuity check: removing the inner `GeometryReader` (replacing it
  /// with a static `Text`) visibly changes the raster.  Without this,
  /// the primary assertion could false-green against a hard-coded
  /// `"w=80 h=28"` literal.
  @Test("removing the GeometryReader visibly changes the raster")
  func geometryReaderIsNonVacuous() {
    let withReader = render(
      GeometryReaderTakesProposal(),
      width: 80,
      height: 28,
      id: "with-reader"
    ).rasterSurface
    let withoutReader = render(
      WithoutGeometryReaderVariant(),
      width: 80,
      height: 28,
      id: "without-reader"
    ).rasterSurface

    let withDump = withReader.lines.joined(separator: "\n")
    let withoutDump = withoutReader.lines.joined(separator: "\n")

    #expect(
      withDump.contains("w=80 h=28"),
      "WITH variant should contain live-proxy text\n\(withDump)"
    )
    #expect(
      !withoutDump.contains("w=80 h=28"),
      "WITHOUT variant should not contain the live-proxy text\n\(withoutDump)"
    )
    #expect(
      withoutDump.contains("no-geom"),
      "WITHOUT variant should contain the static replacement text\n\(withoutDump)"
    )
  }
}

/// Identical to `GeometryReaderTakesProposal` except the inner body
/// is a static `Text` instead of a `GeometryReader`.  Used by the A/B
/// vacuity assertion.
private struct WithoutGeometryReaderVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Geometry reader takes proposal").foregroundStyle(.muted)
      Text("no-geom")
        .frame(width: 40, height: 10)
        .border(.separator)
    }
    .padding(1)
  }
}
