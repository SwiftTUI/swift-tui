import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct ProposalTighteningBehaviourTests {
  /// The GeometryReader is wrapped in `.frame(width: 30, height: 3)`
  /// while the outer terminal is 80 cells wide. A SwiftUI-faithful
  /// implementation would tighten the proposal that reaches the
  /// reader so `proxy.size.width` reports `30`.
  ///
  /// Observed behaviour (raster at 80×10): the GeometryReader reports
  /// the full terminal width (`w=80`), not the tightened
  /// `.frame(width: 30)` proposal. The `GeometryReader` implementation
  /// reads `context.environmentValues.terminalSize` directly rather
  /// than the locally-proposed size.
  ///
  /// See `BEHAVIOUR_FINDINGS.md` finding #4. This test pins the
  /// OBSERVED behaviour (`w=80`).
  @Test("GeometryReader reports the full terminal width, not the tightened frame")
  func proxyReportsTerminalWidth() {
    let raster = render(ProposalTightening(), width: 80, height: 10).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    // SwiftUI-faithful would be `w=30` (the .frame width). Observed
    // is `w=80`. Pin the observed value; if the library is fixed to
    // honour proposal tightening, this test will flip and the
    // finding can be closed.
    #expect(
      joined.contains("w=80"),
      "expected GeometryReader to report w=80 (observed library behaviour); see BEHAVIOUR_FINDINGS.md finding #4\n\(joined)"
    )
    #expect(
      !joined.contains("w=30"),
      "if GeometryReader started honouring the .frame(width:30), close finding #4 and flip this assertion to expect w=30\n\(joined)"
    )
  }
}
