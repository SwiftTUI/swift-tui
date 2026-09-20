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

  public func path(in rect: Rect) -> Path {
    // The base's path already carries the base's own trim, so this trims it by
    // this wrapper's fractions alone. `trimStart` and `trimEnd` are the composed
    // fractions of the untrimmed outline, which a stroke uses.
    base.path(in: rect).trimmedPath(from: from, to: to)
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
    let inner = StrokeTrim(from: from, to: to)
    return outer.from + (outer.to - outer.from) * inner.from
  }

  public var trimEnd: Double {
    let outer = StrokeTrim(from: base.trimStart, to: base.trimEnd)
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
