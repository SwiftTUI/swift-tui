import TerminalUI

/// `.fixedSize(horizontal: false, vertical: true)` asks the view to use
/// the parent's proposed width (so text still wraps horizontally) while
/// taking its intrinsic height (no vertical stretching).
///
/// The layout wraps a multi-word `Text` inside an 8-cell-wide frame;
/// the behaviour test pins that the text wraps across multiple rows.
///
/// The header `"FixedSize one axis"` is the catalog marker.
public struct FixedSizeOneAxis: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("FixedSize one axis").foregroundStyle(.muted)
      Text("abc def ghi jkl mno pqr")
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 8)
        .border(.separator)
    }
    .padding(1)
  }
}
