import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct GeometryReaderTakesProposalBehaviourTests {
  /// Bordered reader is 40 wide × 10 tall:
  ///
  /// ```
  /// [1]  Geometry reader takes proposal|
  /// [2]  ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|
  /// [3]  ▌w=40 h=10                               ▐|
  /// [13] ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
  /// ```
  ///
  /// The reader reports the tightened `.frame(width: 40, height: 10)`
  /// proposal rather than the full terminal size.
  @Test("GeometryReader reports the .frame proposal")
  func proxyReportsTerminalSize() {
    let raster = render(GeometryReaderTakesProposal(), width: 80, height: 28).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    #expect(
      joined.contains("w=40 h=10"),
      "expected GeometryReader to report the tightened .frame(width:40,height:10)\n\(joined)"
    )
    #expect(
      !joined.contains("w=80 h=28"),
      "GeometryReader should not report the full terminal size\n\(joined)"
    )
  }

  /// Vacuity check: removing the inner `GeometryReader` (replacing it
  /// with a static `Text`) visibly changes the raster.  Without this,
  /// the primary assertion could false-green against a hard-coded
  /// `"w=40 h=10"` literal.
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
      withDump.contains("w=40 h=10"),
      "WITH variant should contain live-proxy text\n\(withDump)"
    )
    #expect(
      !withoutDump.contains("w=40 h=10"),
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
