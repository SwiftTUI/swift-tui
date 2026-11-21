public import SwiftTUIViews

// Demonstration 3 of 6: blinds (STUI-1546).
//
// What it shows: the view is cut into vertical slats, and every slat opens
// from its leading edge at the same time.
//
// What it proves: stage 4a inside stages 2 and 3, for a path of several
// subpaths. `BlindsShape` conforms to `Animatable`, so each frame is the
// path the shape builds for that frame's `open`, and not a point-by-point
// morph between two outlines.
//
// Known limits:
// - A clip has a hard edge, so a slat opens one cell at a time. Vertical
//   slats have more steps than horizontal ones would: a view is many more
//   cells wide than it is tall.
// - A slat boundary falls between two cells only when the width of the view
//   is a multiple of the number of slats.

/// `slats` vertical bands, each drawn over the leading `open` of its width.
/// `open` runs from 0 (nothing) to 1 (the whole frame).
public struct BlindsShape: Shape, Animatable {
  public var open: Double
  public var slats: Int

  public init(open: Double, slats: Int = 8) {
    self.open = open
    self.slats = slats
  }

  public nonisolated var animatableData: Double {
    get { open }
    set { open = newValue }
  }

  public func path(in rect: Rect) -> Path {
    let count = max(1, slats)
    // A spring takes `open` outside 0...1; a slat stays inside its band.
    let share = min(1, max(0, open))
    guard share > 0 else {
      return Path()
    }
    let band = rect.size.width / Double(count)
    return Path { path in
      for slat in 0..<count {
        path.addRect(
          Rect(
            origin: Point(x: rect.origin.x + Double(slat) * band, y: rect.origin.y),
            size: Size(width: band * share, height: rect.size.height)))
      }
    }
  }
}

/// Vertical blinds that open across the view.
public struct Blinds: Transition {
  public var slats: Int

  public init(slats: Int = 8) {
    self.slats = slats
  }

  public func body(content: Content, phase: TransitionPhase) -> some View {
    content.clipShape(BlindsShape(open: phase.isIdentity ? 1 : 0, slats: slats))
  }
}
