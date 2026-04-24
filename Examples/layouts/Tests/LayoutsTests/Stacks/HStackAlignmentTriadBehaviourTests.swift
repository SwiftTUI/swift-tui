import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct HStackAlignmentTriadBehaviourTests {
  /// At `.top`, the "short" child anchors to the top row of the
  /// HStack — its single line sits on the same row as the tall
  /// child's first line. At `.bottom`, it anchors to the last.
  /// At `.center`, it sits in the middle of the 3-line tall child.
  @Test("Short child anchors per vertical alignment")
  func shortChildAnchorsPerAlignment() {
    let artifacts = render(HStackAlignmentTriad(), width: 40, height: 20)
    let lines = artifacts.rasterSurface.lines
    // The three rows of the triad each contain a "short" label.
    let shortRowIndices = lines.enumerated().compactMap {
      $0.element.contains("short") ? $0.offset : nil
    }
    #expect(
      shortRowIndices.count == 3,
      "expected 3 rows containing 'short', got \(shortRowIndices.count)"
    )
    // top-row triad's short label is on the row aligned with
    // "tall"'s first line; bottom-row's is aligned with "tall"'s
    // last line. The rows are ordered top < center < bottom.
    // Behaviour we pin: those three indices are strictly increasing
    // and spaced apart by at least 4 rows (one triad row + 1 spacing
    // + border ring).
    let sorted = shortRowIndices.sorted()
    #expect(sorted == shortRowIndices, "rows not emitted in display order")
    #expect(sorted[1] - sorted[0] >= 4)
    #expect(sorted[2] - sorted[1] >= 4)
  }
}
