import SwiftUI

/// Two side-by-side `FlowLayout` containers wrapping the same eight
/// `[item N]` children — the first container is `.frame(width: 30)`,
/// the second is `.frame(width: 60)`.  ``FlowLayout`` is a custom
/// `Layout` conformance that packs siblings left-to-right and wraps
/// onto a new row whenever the next child would exceed the proposed
/// width.
///
/// Layout shape:
///
/// ```
/// VStack(alignment: .leading) {
///   Text("Flow layout wrap")
///   Text("at width 30")
///   FlowLayout(spacing: 1) { ForEach(0..<8) { Text("[item \($0)]") } }
///     .frame(width: 30).border(Color.gray)
///   Text("at width 60")
///   FlowLayout(spacing: 1) { ForEach(0..<8) { Text("[item \($0)]") } }
///     .frame(width: 60).border(Color.gray)
/// }
/// ```
public struct FlowLayoutWrap: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Flow layout wrap").foregroundStyle(.secondary)
      Text("at width 30").foregroundStyle(.secondary)
      FlowLayout(spacing: cell(1)) {
        ForEach(0..<8, id: \.self) { i in
          Text("[item \(i)]")
        }
      }
      .frame(width: cell(30))
      .border(Color.gray)
      Text("at width 60").foregroundStyle(.secondary)
      FlowLayout(spacing: cell(1)) {
        ForEach(0..<8, id: \.self) { i in
          Text("[item \(i)]")
        }
      }
      .frame(width: cell(60))
      .border(Color.gray)
    }
    .padding(cell(1))
  }
}

/// A custom `Layout` that packs subviews left-to-right and wraps
/// onto a new row whenever the next child would push the row past
/// the proposal width.  Width-`unspecified` proposals lay every
/// child out on a single row (no wrap budget known).
struct FlowLayout: Layout {
  var spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache _: inout Void
  ) -> CGSize {
    let maxWidth = finiteWidth(proposal.width)
    var rows: [(width: CGFloat, height: CGFloat)] = [(0, 0)]
    for subview in subviews {
      let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
      let leading: CGFloat = rows[rows.count - 1].width == 0 ? 0 : spacing
      let candidate = rows[rows.count - 1].width + leading + size.width
      if let limit = maxWidth, candidate > limit, rows[rows.count - 1].width > 0 {
        rows.append((size.width, size.height))
      } else {
        rows[rows.count - 1].width += leading + size.width
        rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
      }
    }
    let totalHeight =
      rows.map(\.height).reduce(0, +) + max(0, CGFloat(rows.count - 1)) * spacing
    let totalWidth = rows.map(\.width).max() ?? 0
    return CGSize(width: totalWidth, height: totalHeight)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache _: inout Void
  ) {
    let maxWidth = finiteWidth(proposal.width) ?? bounds.size.width
    var x = bounds.origin.x
    var y = bounds.origin.y
    var rowHeight: CGFloat = 0
    var firstInRow = true
    for subview in subviews {
      let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
      let leading: CGFloat = firstInRow ? 0 : spacing
      if !firstInRow, x - bounds.origin.x + leading + size.width > maxWidth {
        // Wrap to a new row.
        x = bounds.origin.x
        y += rowHeight + spacing
        rowHeight = 0
        firstInRow = true
      }
      let leadingNow: CGFloat = firstInRow ? 0 : spacing
      subview.place(
        at: CGPoint(x: x + leadingNow, y: y),
        anchor: .topLeading,
        proposal: ProposedViewSize(width: size.width, height: size.height)
      )
      x += leadingNow + size.width
      rowHeight = max(rowHeight, size.height)
      firstInRow = false
    }
  }

  private func finiteWidth(_ dim: CGFloat?) -> CGFloat? {
    guard let dim, dim.isFinite else { return nil }
    return dim
  }
}
