import TerminalUI

@testable import Layouts

/// Single-shot render helper used by every behaviour test file.
///
/// The default `id` is `#fileID + "." + #function` so identities stay
/// unique across behaviour-test files even when two unrelated tests
/// happen to share a function name. (Swift Testing doesn't run the
/// same `@Test` function concurrently with itself; the real concern
/// here is cross-file collision, not parallel invocation.)
@MainActor
func render(
  _ view: some View,
  width: Int,
  height: Int,
  id: String = "\(#fileID).\(#function)"
) -> FrameArtifacts {
  var env = EnvironmentValues()
  env.terminalSize = Size(width: width, height: height)
  return DefaultRenderer().render(
    view,
    context: ResolveContext(
      identity: Identity(components: ["layouts.behaviour.\(id)"]),
      environmentValues: env
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}

extension RasterSurface {
  /// The 0-indexed row indices whose text contains `needle`, in ascending order.
  func rows(containing needle: String) -> [Int] {
    lines.enumerated().compactMap { $0.element.contains(needle) ? $0.offset : nil }
  }

  /// The first row whose text contains `needle`, or nil.
  func firstRow(containing needle: String) -> Int? {
    rows(containing: needle).first
  }

  /// The last row whose text contains `needle`, or nil.
  func lastRow(containing needle: String) -> Int? {
    rows(containing: needle).last
  }

  /// The text of the row at `y`, or nil if out of range.
  func row(at y: Int) -> String? {
    (0..<lines.count).contains(y) ? lines[y] : nil
  }
}
