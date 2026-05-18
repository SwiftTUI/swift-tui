import SwiftTUI
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
  /// `GeometryReader` previously read `terminalSize` from the
  /// environment and missed fixed-frame tightening. The fix tightens
  /// the terminal-size environment on explicit-axis frames and lowers
  /// `GeometryReader`'s content into a flexible top-leading
  /// proposal-filling frame.
  @Test("GeometryReader reports the tightened frame width")
  func proxyReportsTerminalWidth() {
    let raster = render(ProposalTightening(), width: 80, height: 10).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    #expect(
      joined.contains("w=30"),
      "expected GeometryReader to report the tightened .frame(width:30)\n\(joined)"
    )
    #expect(
      !joined.contains("w=80"),
      "GeometryReader should not report the full terminal width once the frame tightens it\n\(joined)"
    )
  }
}
