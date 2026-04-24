import TerminalUI

/// HStack of four children with layout priorities `0/1/0/2`. Under
/// a tight width proposal the priority-2 child survives first, the
/// priority-1 child survives next, and the two priority-0 children
/// yield earliest. Under a generous proposal all four fit in full.
///
/// Outer priority-0 strings are intentionally long so truncation is
/// visible. The priority-1 child is the single letter "b"; the
/// priority-2 child is the single letter "d".
///
/// The header `"Layout priority cascade"` is the catalog marker.
public struct LayoutPriorityCascade: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Layout priority cascade").foregroundStyle(.muted)
      HStack(spacing: 1) {
        Text("aaaaaaaaaa").layoutPriority(0)
        Text("b").layoutPriority(1)
        Text("cccccccccc").layoutPriority(0)
        Text("d").layoutPriority(2)
      }
    }
    .padding(1)
  }
}
