import TerminalUI

/// HStack of four children with layout priorities `0/1/0/2`. Under
/// a tight width proposal the priority-2 child survives first, the
/// priority-1 child survives next, and the two priority-0 children
/// yield earliest. Under a generous proposal all four fit in full.
///
/// Markers are chosen so NONE of the four child strings share any
/// character with the header `"Layout priority cascade"` (whose chars
/// are `{L, ' ', a, y, o, u, t, p, r, i, c, s, d, e}`). This prevents
/// behaviour tests from matching the header row by accident —
/// without header-proof markers, `rows(containing: "d")` would return
/// the header row ("cascade" contains `d`) regardless of whether the
/// priority-2 child actually survived the squeeze. See:
/// `Examples/layouts/Tests/LayoutsTests/Frames/LayoutPriorityCascadeBehaviourTests.swift`.
///
/// - Priority-0 outer strings are intentionally long so their
///   truncation under a tight proposal is visible.
/// - Priority-1 child: `"K"` (single cell, unique vs header).
/// - Priority-2 child: `"Z"` (single cell, unique vs header).
///
/// The header `"Layout priority cascade"` is the catalog marker.
public struct LayoutPriorityCascade: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Layout priority cascade").foregroundStyle(.muted)
      HStack(spacing: 1) {
        Text("XXXXXXXXXXXX").layoutPriority(0)
        Text("K").layoutPriority(1)
        Text("YYYYYYYYYYYY").layoutPriority(0)
        Text("Z").layoutPriority(2)
      }
    }
    .padding(1)
  }
}
