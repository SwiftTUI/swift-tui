@_spi(Testing) public import SwiftTUICore

/// A shape wrapper that keeps part of its base shape's outline.
///
/// A stroke of a trimmed shape draws the part of the outline between the two
/// fractions. The outline starts where SwiftUI starts it and runs clockwise: a
/// `Rectangle` starts at its top-leading corner, and a `RoundedRectangle`, a
/// `Circle`, an `Ellipse` and a `Capsule` start at the middle of their trailing
/// edge. A fraction is a share of the outline's physical length, so a quarter
/// of a rectangle is a quarter of the way round it on screen.
///
/// A fill of a trimmed shape closes the trimmed outline with a straight line
/// and fills it, as SwiftUI does. It takes the path route, so it stretches to
/// its frame and a trimmed `Circle` fill is not aspect-corrected.
public struct TrimmedShape<Base: Shape>: Shape, ResolvableView {
  public var base: Base
  public var from: Double
  public var to: Double

  public init(base: Base, from: Double, to: Double) {
    self.base = base
    self.from = from
    self.to = to
  }

  public var geometry: ShapeGeometry {
    base.geometry
  }

  /// The trimmed outline in `rect`: the outline a fill of this shape paints,
  /// measured as the raster measures it.
  ///
  /// The outline is the one the fill trims, so a content shape built from it
  /// covers the painted cells. A trimmed `Circle` stretches to `rect` as its
  /// fill does. In a non-square `rect` this path is therefore not the trim of
  /// `Circle().path(in:)`, which is inscribed. A custom base trims its own
  /// `path(in:)`, and a trim that keeps the whole outline returns the base's
  /// outline.
  ///
  /// A vertical cell counts as the estimated cell aspect ratio
  /// (`CellPixelMetrics.estimated`, snapped to the nearest half). A path has
  /// no terminal metrics, so a terminal that reports another ratio paints
  /// its trim with that ratio, while this path keeps the estimate.
  public func path(in rect: Rect) -> Path {
    let aspectRatio = RectangleStrokeTrack.snappedAspectRatio(
      CellPixelMetrics.estimated.aspectRatio)
    switch geometry {
    case .path:
      break
    default:
      // An analytic base: trace the route the fill takes
      // (`ShapeGeometry.resolved(in:trimAspectRatio:)`), the composed fractions
      // of the untrimmed outline in the inset frame, with a `Circle` stretched
      // to that frame.
      if strokeTrim != nil {
        return fillGeometry.path(
          in: insetFrame(rect), stretchingCircle: true, trimAspectRatio: aspectRatio)
      }
    }
    // The base's path already carries the base's own trim, so this trims it by
    // this wrapper's fractions alone. A custom base's fill scales this same
    // `path(in:)` from the unit rect.
    return base.path(in: rect).physicallyTrimmedPath(
      from: from, to: to, aspectRatio: aspectRatio)
  }

  /// `rect` inset by `insetAmount`, as `InsetShape.path(in:)` insets it.
  private func insetFrame(_ rect: Rect) -> Rect {
    guard insetAmount != 0 else { return rect }
    let inset = Double(insetAmount)
    return Rect(
      origin: Point(x: rect.origin.x + inset, y: rect.origin.y + inset),
      size: Size(
        width: max(0, rect.size.width - 2 * inset), height: max(0, rect.size.height - 2 * inset)))
  }

  public var kindName: String {
    base.kindName
  }

  public var insetAmount: Int {
    base.insetAmount
  }

  // A trim of a trimmed shape keeps a share of what the first trim kept.
  public var trimStart: Double {
    let outer = StrokeTrim(from: base.trimStart, to: base.trimEnd)
    guard !outer.isEmpty else { return outer.from }
    let inner = StrokeTrim(from: from, to: to)
    return outer.from + (outer.to - outer.from) * inner.from
  }

  public var trimEnd: Double {
    let outer = StrokeTrim(from: base.trimStart, to: base.trimEnd)
    guard !outer.isEmpty else { return outer.from }
    let inner = StrokeTrim(from: from, to: to)
    return outer.from + (outer.to - outer.from) * inner.to
  }
}

extension Shape {
  /// Keeps the part of this shape's outline between two fractions of its
  /// length.
  ///
  /// ```swift
  /// Circle()
  ///   .trim(from: 0, to: progress)
  ///   .stroke(.tint)
  /// ```
  ///
  /// Both fractions are clamped to `0...1`, and nothing is drawn when `from` is
  /// not less than `to`. The interval is animatable on a stroke.
  public func trim(from startFraction: Double = 0, to endFraction: Double = 1) -> some Shape {
    TrimmedShape(base: self, from: startFraction, to: endFraction)
  }
}
