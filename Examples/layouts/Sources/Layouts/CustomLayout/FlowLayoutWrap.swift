import SwiftTUIRuntime

/// Two side-by-side `FlowLayout` containers wrapping the same eight
/// `[item N]` children — the first container is `.frame(width: 30)`,
/// the second is `.frame(width: 60)`.  ``FlowLayout`` is a custom
/// `SendableLayout` conformance that packs siblings left-to-right and wraps
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
///     .frame(width: 30).border(.separator)
///   Text("at width 60")
///   FlowLayout(spacing: 1) { ForEach(0..<8) { Text("[item \($0)]") } }
///     .frame(width: 60).border(.separator)
/// }
/// ```
///
/// Each `[item N]` cell is 8 cells wide (`[item 0]` through
/// `[item 7]`).  At width 30 a single row holds at most 3 cells
/// (`8 + 1 + 8 + 1 + 8 = 26`, with cell 4 forcing a wrap), so the
/// layout produces 3 rows of marker text.  At width 60 the layout
/// fits all 8 cells on one row (`8*8 + 7*1 = 71` exceeds 60, so the
/// algorithm wraps once around cell 7 and produces 2 rows).  The
/// behaviour test pins:
///
///   - the width-30 container produces strictly more marker rows
///     than the width-60 container (wrap is width-driven, not a
///     constant), and
///   - the width-30 container produces at least 2 marker rows
///     (the wrap actually fired).
///
/// The header `"Flow layout wrap"` is the catalog marker.
public struct FlowLayoutWrap: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Flow layout wrap").foregroundStyle(.muted)
      Text("at width 30").foregroundStyle(.muted)
      FlowLayout(spacing: 1) {
        ForEach(0..<8, id: \.self) { i in
          Text("[item \(i)]")
        }
      }
      .frame(width: 30)
      .border(.separator)
      Text("at width 60").foregroundStyle(.muted)
      FlowLayout(spacing: 1) {
        ForEach(0..<8, id: \.self) { i in
          Text("[item \(i)]")
        }
      }
      .frame(width: 60)
      .border(.separator)
    }
    .padding(1)
  }
}

/// A custom `Layout` that packs subviews left-to-right and wraps
/// onto a new row whenever the next child would push the row past
/// the proposal width.  Width-`unspecified` proposals lay every
/// child out on a single row (no wrap budget known).
struct FlowLayout: SendableLayout {
  var spacing: Int

  var measurementReuseSignature: String {
    "FlowLayout(spacing:\(spacing)).measure"
  }

  var placementReuseSignature: String {
    "FlowLayout(spacing:\(spacing)).place"
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let maxWidth = finiteWidth(proposal.width)
    var rows: [(width: Int, height: Int)] = [(0, 0)]
    for subview in subviews {
      let size = subview.sizeThatFits(.init(width: maxWidth, height: nil))
      let leading = rows[rows.count - 1].width == 0 ? 0 : spacing
      let candidate = rows[rows.count - 1].width + leading + size.width
      if let limit = maxWidth, candidate > limit, rows[rows.count - 1].width > 0 {
        rows.append((size.width, size.height))
      } else {
        rows[rows.count - 1].width += leading + size.width
        rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
      }
    }
    let totalHeight =
      rows.map(\.height).reduce(0, +) + max(0, rows.count - 1) * spacing
    let totalWidth = rows.map(\.width).max() ?? 0
    return LayoutSize(width: totalWidth, height: totalHeight)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    let maxWidth = finiteWidth(proposal.width) ?? bounds.size.width
    var x = bounds.origin.x
    var y = bounds.origin.y
    var rowHeight = 0
    var firstInRow = true
    for subview in subviews {
      let size = subview.sizeThatFits(.init(width: maxWidth, height: nil))
      let leading = firstInRow ? 0 : spacing
      if !firstInRow, x - bounds.origin.x + leading + size.width > maxWidth {
        // Wrap to a new row.
        x = bounds.origin.x
        y += rowHeight + spacing
        rowHeight = 0
        firstInRow = true
      }
      let leadingNow = firstInRow ? 0 : spacing
      subview.place(
        at: LayoutPoint(x: x + leadingNow, y: y),
        anchor: .topLeading,
        proposal: .init(width: size.width, height: size.height)
      )
      x += leadingNow + size.width
      rowHeight = max(rowHeight, size.height)
      firstInRow = false
    }
  }

  private func finiteWidth(_ dim: ProposedDimension) -> Int? {
    switch dim {
    case .finite(let value): return value
    case .unspecified, .infinity: return nil
    }
  }
}
