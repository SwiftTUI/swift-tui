public import SwiftTUIViews

// Demonstration 2 of 6: an iris (STUI-1546).
//
// What it shows: the view appears through an ellipse that opens from its
// centre until it covers the corners, and leaves as the ellipse closes.
//
// What it proves: stage 4a inside stages 2 and 3. `IrisShape` is a shape
// that conforms to `Animatable`, used as a `clipShape` in a custom
// `Transition` body. Its `path(in:)` runs with interpolated `open` on every
// frame of the insertion and of the removal, and no view is evaluated for a
// frame.
//
// Known limits:
// - A clip has a hard edge: a cell is drawn or it is not.
// - `path(in:)` gets the unit rectangle, and the path is stretched to the
//   frame. The shape cannot learn the size of the frame in cells, so the
//   iris has the proportions of the view and is round only on a view that
//   is as wide as it is tall on screen.

/// An ellipse round the centre of the frame. `open` runs from 0 (nothing)
/// to 1 (the whole frame).
public struct IrisShape: Shape, Animatable {
  public var open: Double

  public init(open: Double) {
    self.open = open
  }

  public nonisolated var animatableData: Double {
    get { open }
    set { open = newValue }
  }

  /// The radius on each axis, as a fraction of the frame's extent on that
  /// axis. The corners are 0.7071 from the centre in these units, so 0.75
  /// covers them. A spring takes `open` outside 0...1; the radius stays in
  /// range.
  public nonisolated var radius: Double {
    0.75 * min(1, max(0, open))
  }

  public func path(in rect: Rect) -> Path {
    let radius = radius
    guard radius > 0 else {
      return Path()
    }
    return Path(
      ellipseIn: Rect(
        origin: Point(
          x: rect.origin.x + rect.size.width * (0.5 - radius),
          y: rect.origin.y + rect.size.height * (0.5 - radius)),
        size: Size(width: rect.size.width * 2 * radius, height: rect.size.height * 2 * radius)))
  }
}

/// An iris that opens from the centre of the view.
public struct Iris: Transition {
  public init() {}

  public func body(content: Content, phase: TransitionPhase) -> some View {
    content.clipShape(IrisShape(open: phase.isIdentity ? 1 : 0))
  }
}
