import SwiftUI

/// A `Circle` filled with red inside a deliberately non-square
/// `.frame(width: 12, height: 5)` container.
///
/// The point: `Circle` always inscribes itself in the **shortest** axis
/// of its frame, so a 12×5 frame produces a 5×5 disc centred (well —
/// flushed leading by the parent VStack, but inscribed in the smaller
/// axis), and the wide frame's left/right corners are NOT painted by
/// the circle. The framed border traces the full 12×5 rectangle so
/// the empty corners are visible relative to the border.
///
/// Layout shape: a `VStack(alignment: .leading)` carrying the catalog
/// marker header on top of `Circle().fill(Color.red)
/// .frame(width: 12, height: 5).border(Color.gray)`.
///
/// Observable invariant pinned by the behaviour test:
///   - At least one cell **inside** the inscribed disc carries a red
///     foreground (e.g. the centre column row of the disc bounding box).
///   - At least one cell in the wide frame's empty-corner band (a
///     column outside the inscribed 5×5 disc but inside the 12-cell
///     border) does NOT carry a red foreground, proving the disc
///     inscribes in the shortest axis rather than stretching to fit.
public struct CircleInNonSquareFrame: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Circle in non square frame").foregroundStyle(.secondary)
      Circle()
        .fill(Color.red)
        .frame(width: cell(12), height: cell(5))
        .border(Color.gray)
    }
    .padding(cell(1))
  }
}
