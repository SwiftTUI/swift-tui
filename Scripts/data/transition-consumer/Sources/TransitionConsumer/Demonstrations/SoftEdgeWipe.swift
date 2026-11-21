public import SwiftTUIViews

// Demonstration 1 of 6: a wipe with a soft edge (STUI-1546).
//
// What it shows: the view appears from its leading edge. A front travels
// across it; the cells behind the front are drawn, and the ink fades to
// nothing over the last `softness` of the width before the front.
//
// What it proves: stage 4b. `SoftEdgeWipeEffect` is a view modifier that
// conforms to `Animatable`, placed in a custom `Transition` body. Its body
// runs with interpolated `progress` on every frame of the insertion and of
// the removal. It also proves stages 2 and 3 for a style: the foreground
// style the body writes for `content` reaches the live view on insertion and
// the view as it was last drawn on removal.
//
// Known limits:
// - The soft edge is a foreground gradient, because a clip has a hard edge
//   and there is no `mask`. The transition therefore paints every view that
//   inherits the foreground in `ink`, also while the view is at rest, and it
//   does not fade a view that sets its own style, or a background.
// - A gradient is sampled in the frame of each view that draws with it, so
//   the fade lines up only across views of the same horizontal extent.

/// The modifier of ``SoftEdgeWipe``: everything it draws is a function of
/// `progress`, from 0 (nothing) to 1 (the whole view in `ink`).
public struct SoftEdgeWipeEffect: ViewModifier, Animatable {
  public var progress: Double
  public var ink: Color
  /// The width of the fade, as a fraction of the view's width.
  public var softness: Double

  public init(progress: Double, ink: Color = .white, softness: Double = 0.25) {
    self.progress = progress
    self.ink = ink
    self.softness = softness
  }

  public nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  /// The position of the front, as a fraction of the width. It runs from 0
  /// to `1 + fade`, so that the whole view is opaque when it arrives. A
  /// spring takes `progress` outside 0...1; the front stays in range.
  public nonisolated var front: Double {
    min(1, max(0, progress)) * (1 + fade)
  }

  /// The opacity of the ink at `x`, a fraction of the width: 1 behind the
  /// fade, falling in a straight line to 0 at the front.
  public nonisolated func inkOpacity(at x: Double) -> Double {
    min(1, max(0, (front - x) / fade))
  }

  private nonisolated var fade: Double {
    max(0.001, softness)
  }

  public func body(content: Content) -> some View {
    content
      .foregroundStyle(
        LinearGradient(
          gradient: Gradient(stops: stops), startPoint: .leading, endPoint: .trailing)
      )
      .clipShape(WipeFront(extent: front))
  }

  /// The ramp as gradient stops. A stop cannot lie outside 0...1, so the
  /// ramp is cut at both ends of the view, with a stop at each of its bends
  /// that falls inside.
  private var stops: [Gradient.Stop] {
    let bends = [0, min(1, max(0, front - fade)), min(1, max(0, front)), 1]
    return bends.map { location in
      Gradient.Stop(color: ink.opacity(inkOpacity(at: location)), location: location)
    }
  }
}

/// The part of the frame behind the front. It cuts what the gradient cannot
/// hide: a view that sets its own style, and a background.
private struct WipeFront: Shape {
  var extent: Double

  func path(in rect: Rect) -> Path {
    let width = rect.size.width * min(1, max(0, extent))
    guard width > 0 else {
      return Path()
    }
    return Path(Rect(origin: rect.origin, size: Size(width: width, height: rect.size.height)))
  }
}

/// A wipe from the leading edge with a soft front.
public struct SoftEdgeWipe: Transition {
  public var ink: Color
  public var softness: Double

  public init(ink: Color = .white, softness: Double = 0.25) {
    self.ink = ink
    self.softness = softness
  }

  public func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(
      SoftEdgeWipeEffect(progress: phase.isIdentity ? 1 : 0, ink: ink, softness: softness))
  }
}
