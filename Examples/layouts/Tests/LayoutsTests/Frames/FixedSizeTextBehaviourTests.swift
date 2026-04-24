import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct FixedSizeTextBehaviourTests {
  /// The layout renders the marker `"thelongerstring"` (15 cells
  /// wide) inside a `.frame(width: 10)`. With `.fixedSize()` on the
  /// Text, the view requests its intrinsic width and the parent
  /// lays it out at that size regardless of the 10-cell proposal —
  /// the full substring should therefore appear somewhere in the
  /// raster.
  @Test("fixedSize text escapes its 10-wide frame at intrinsic width")
  func fullStringSurvivesNarrowFrame() {
    let raster = render(FixedSizeText(), width: 80, height: 10).rasterSurface
    let joined = raster.lines.joined(separator: "\n")
    #expect(
      joined.contains("thelongerstring"),
      "fixedSize Text should render full intrinsic string 'thelongerstring' in raster:\n\(joined)"
    )
  }
}
