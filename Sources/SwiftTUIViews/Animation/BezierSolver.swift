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
    self.c0x = c0x
    self.c0y = c0y
    self.c1x = c1x
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

  private func solveTForX(_ x: Double) -> Double {
    // Newton-Raphson with fallback to bisection
    var t = x  // Initial guess

    // Newton-Raphson iterations
    for _ in 0..<8 {
      let currentX = evaluateX(at: t) - x
      let dx = derivativeX(at: t)
      guard abs(dx) > 1e-12 else { break }
      let nextT = t - currentX / dx
      if abs(nextT - t) < 1e-7 { return nextT }
      t = nextT
    }

    // Bisection fallback
    var lo = 0.0
    var hi = 1.0
    t = x
    for _ in 0..<20 {
      let currentX = evaluateX(at: t)
      if abs(currentX - x) < 1e-7 { return t }
      if currentX < x {
        lo = t
      } else {
        hi = t
      }
      t = (lo + hi) / 2.0
    }
    return t
  }
}
