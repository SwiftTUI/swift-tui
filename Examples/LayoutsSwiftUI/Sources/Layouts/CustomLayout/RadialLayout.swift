import SwiftUI

/// A custom `Layout` that places its children around a ring at the
/// cardinal compass directions (East, South, West, North) — the
/// simplest exposition of "compute child position from index" that
/// any radial layout (planet/clock/rosette) builds on.
///
/// The demo wires four `Text` children — `[E]`, `[S]`, `[W]`, `[N]` —
/// in source order so the behaviour test can pin which marker lands
/// where: `[E]` to the right of center, `[W]` to the left, `[N]`
/// above (smaller row), `[S]` below (larger row).  The layout is
/// wrapped in a `.frame(width: 24, height: 16)` so the cardinals
/// have room to spread.
///
/// Layout shape:
///
/// ```
/// VStack(alignment: .leading) {
///   Text("Radial layout")
///   RingLayout(radius: 6) { Text("[E]"); Text("[S]"); Text("[W]"); Text("[N]") }
///     .frame(width: 24, height: 16).border(Color.gray)
/// }
/// ```
///
/// The header `"Radial layout"` is the catalog marker.
public struct RadialLayout: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Radial layout").foregroundStyle(.secondary)
      RingLayout(radius: cell(6)) {
        Text("[E]")  // east  — 0°
        Text("[S]")  // south — 90°
        Text("[W]")  // west  — 180°
        Text("[N]")  // north — 270°
      }
      .frame(width: cell(24), height: cell(16))
      .border(Color.gray)
    }
    .padding(cell(1))
  }
}

/// A custom `Layout` that places exactly four children at the
/// cardinal compass directions on a ring of `radius` cells around
/// the center of the proposed bounds.  Children are placed in the
/// order `[East, South, West, North]`.  Passing more (or fewer)
/// children still works — extra children stack at the center.
///
/// The simplest possible custom radial layout: cardinal-only, no
/// trigonometry, no Foundation dependency.  The behaviour-tested
/// invariant is the spatial relationship between the four cardinals
/// and the center, not the precise pixel coordinates.
struct RingLayout: Layout {
  var radius: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews _: Subviews,
    cache _: inout Void
  ) -> CGSize {
    // The layout fills the proposed bounds.  Fall back to a size
    // sufficient to contain the ring when proposed dimensions are
    // unspecified.
    let diameter = max(cell(1), 2 * radius + cell(1))
    let width = unwrap(proposal.width, fallback: diameter)
    let height = unwrap(proposal.height, fallback: diameter)
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal _: ProposedViewSize,
    subviews: Subviews,
    cache _: inout Void
  ) {
    let centerX = bounds.origin.x + bounds.size.width / 2
    let centerY = bounds.origin.y + bounds.size.height / 2
    let cardinals: [(dx: CGFloat, dy: CGFloat)] = [
      (radius, 0),  // East  — 0°
      (0, radius),  // South — 90°
      (-radius, 0),  // West  — 180°
      (0, -radius),  // North — 270°
    ]
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      let cardinal: (dx: CGFloat, dy: CGFloat) =
        index < cardinals.count ? cardinals[index] : (dx: 0, dy: 0)
      let x = centerX + cardinal.dx
      let y = centerY + cardinal.dy
      subview.place(
        at: CGPoint(x: x, y: y),
        anchor: .center,
        proposal: ProposedViewSize(width: size.width, height: size.height)
      )
    }
  }

  private func unwrap(_ dim: CGFloat?, fallback: CGFloat) -> CGFloat {
    guard let dim, dim.isFinite else { return fallback }
    return dim
  }
}
