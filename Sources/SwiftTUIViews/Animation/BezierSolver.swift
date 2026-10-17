/// Evaluates a cubic bezier timing curve.
///
/// Given control points (0,0), (c0x,c0y), (c1x,c1y), (1,1), finds
/// the `y` value for a given `x` (time fraction).
package struct BezierSolver: Sendable {
  let c0x: Double
  let c0y: Double
  let c1x: Double
  let c1y: Double

  package init(_ c0x: Double, _ c0y: Double, _ c1x: Double, _ c1y: Double) {
    self.c0x = min(max(c0x, 0), 1)
    self.c0y = c0y
    self.c1x = min(max(c1x, 0), 1)
    self.c1y = c1y
  }

  /// Standard curves
  package static let linear = BezierSolver(0, 0, 1, 1)
  package static let easeIn = BezierSolver(0.42, 0, 1, 1)
  package static let easeOut = BezierSolver(0, 0, 0.58, 1)
  package static let easeInOut = BezierSolver(0.42, 0, 0.58, 1)

  /// Returns the progress (y) for a given time fraction (x) in [0,1].
  package func progress(for timeFraction: Double) -> Double {
    let x = min(max(timeFraction, 0), 1)
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }

    // Find t parameter for the given x using Newton-Raphson
    let t = solveTForX(x)
    return evaluateY(at: t)
  }

  /// Returns the slope `dy/dx` of the progress curve at a time fraction —
  /// the analytic velocity behind `UnitCurve.velocity(at:)`.
  ///
  /// Where the parametric tangent degenerates (both derivatives vanish at
  /// an endpoint whose control point sits on the origin or the far corner,
  /// as the linear curve's do) the slope falls back to a central finite
  /// difference of ``progress(for:)`` so the result stays finite.
  package func slope(at timeFraction: Double) -> Double {
    let x = min(max(timeFraction, 0), 1)
    let t = solveTForX(x)
    let dx = derivativeX(at: t)
    let dy = derivativeY(at: t)
    if abs(dx) > 1e-9 {
      return dy / dx
    }
    let h = 1e-4
    let lo = max(x - h, 0)
    let hi = min(x + h, 1)
    guard hi > lo else { return 0 }
    return (progress(for: hi) - progress(for: lo)) / (hi - lo)
  }

  private func evaluateX(at t: Double) -> Double {
    let mt = 1.0 - t
    return 3.0 * mt * mt * t * c0x + 3.0 * mt * t * t * c1x + t * t * t
  }

  private func evaluateY(at t: Double) -> Double {
    let mt = 1.0 - t
    return 3.0 * mt * mt * t * c0y + 3.0 * mt * t * t * c1y + t * t * t
  }

  private func derivativeX(at t: Double) -> Double {
    let mt = 1.0 - t
    return 3.0 * mt * mt * c0x + 6.0 * mt * t * (c1x - c0x) + 3.0 * t * t * (1.0 - c1x)
  }

  private func derivativeY(at t: Double) -> Double {
    let mt = 1.0 - t
    return 3.0 * mt * mt * c0y + 6.0 * mt * t * (c1y - c0y) + 3.0 * t * t * (1.0 - c1y)
  }

  private func solveTForX(_ x: Double) -> Double {
    // The x curve is monotone after clamping its control points. Keep a
    // parameter-space bracket: a small x residual says nothing about the
    // accuracy of t near a stationary tangent (for example x = 1/2 + 4u³).
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    var lo = 0.0
    var hi = 1.0
    for _ in 0..<48 {
      let t = (lo + hi) / 2
      let sample = evaluateX(at: t)
      if sample == x { return t }
      if sample < x { lo = t } else { hi = t }
    }
    return (lo + hi) / 2
  }
}
