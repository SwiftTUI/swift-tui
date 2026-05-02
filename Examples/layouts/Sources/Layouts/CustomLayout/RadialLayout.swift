import SwiftTUI

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
///     .frame(width: 24, height: 16).border(.separator)
/// }
/// ```
///
/// The header `"Radial layout"` is the catalog marker.
public struct RadialLayout: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Radial layout").foregroundStyle(.muted)
      RingLayout(radius: 6) {
        Text("[E]")  // east  — 0°
        Text("[S]")  // south — 90°
        Text("[W]")  // west  — 180°
        Text("[N]")  // north — 270°
      }
      .frame(width: 24, height: 16)
      .border(.separator)
    }
    .padding(1)
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
struct RingLayout: SendableLayout {
  var radius: Int

  var measurementReuseSignature: String {
    "RingLayout(radius:\(radius)).measure"
  }

  var placementReuseSignature: String {
    "RingLayout(radius:\(radius)).place"
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    // The layout fills the proposed bounds.  Fall back to a size
    // sufficient to contain the ring when proposed dimensions are
    // unspecified.
    let diameter = max(1, 2 * radius + 1)
    let width = unwrap(proposal.width, fallback: diameter)
    let height = unwrap(proposal.height, fallback: diameter)
    return LayoutSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    let centerX = bounds.origin.x + bounds.size.width / 2
    let centerY = bounds.origin.y + bounds.size.height / 2
    let cardinals: [(dx: Int, dy: Int)] = [
      (radius, 0),  // East  — 0°
      (0, radius),  // South — 90°
      (-radius, 0),  // West  — 180°
      (0, -radius),  // North — 270°
    ]
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      let cardinal: (dx: Int, dy: Int) =
        index < cardinals.count ? cardinals[index] : (dx: 0, dy: 0)
      let x = centerX + cardinal.dx
      let y = centerY + cardinal.dy
      subview.place(
        at: LayoutPoint(x: x, y: y),
        anchor: .center,
        proposal: .init(width: size.width, height: size.height)
      )
    }
  }

  private func unwrap(_ dim: ProposedDimension, fallback: Int) -> Int {
    switch dim {
    case .finite(let value): return value
    case .unspecified, .infinity: return fallback
    }
  }
}
