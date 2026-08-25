public import SwiftTUICore

/// A function that maps a unit progress in `0...1` to an eased progress in
/// `0...1`, defined by a cubic Bézier curve.
///
/// Matches SwiftUI's `UnitCurve`. `LinearKeyframe` takes one as its
/// `timingCurve:`, and ``Animation/timingCurve(_:duration:)`` builds an
/// animation from one.
///
/// ```swift
/// LinearKeyframe(1.0, duration: .milliseconds(300), timingCurve: .easeInOut)
/// let custom = UnitCurve.bezier(
///   startControlPoint: UnitPoint(x: 0.2, y: 0.9),
///   endControlPoint: UnitPoint(x: 0.7, y: 0.1)
/// )
/// ```
public struct UnitCurve: Hashable, Sendable {
  package let solver: BezierSolver

  package init(solver: BezierSolver) {
    self.solver = solver
  }

  /// Progress advances at a constant rate.
  public static let linear = UnitCurve(solver: .linear)
  /// Progress starts slowly and accelerates.
  public static let easeIn = UnitCurve(solver: .easeIn)
  /// Progress starts quickly and decelerates.
  public static let easeOut = UnitCurve(solver: .easeOut)
  /// Progress starts and ends slowly.
  public static let easeInOut = UnitCurve(solver: .easeInOut)

  /// A cubic Bézier curve through `(0, 0)`, the two control points, and
  /// `(1, 1)`.
  public static func bezier(
    startControlPoint: UnitPoint,
    endControlPoint: UnitPoint
  ) -> UnitCurve {
    UnitCurve(
      solver: BezierSolver(
        startControlPoint.x, startControlPoint.y,
        endControlPoint.x, endControlPoint.y
      )
    )
  }

  /// The eased progress for a unit `progress`, clamped to `0...1`.
  public func value(at progress: Double) -> Double {
    if solver == .linear {
      return min(max(progress, 0), 1)
    }
    return solver.progress(for: progress)
  }

  /// The rate of change of ``value(at:)`` at `progress`: the slope of the
  /// curve in eased-progress units per unit of input progress.
  public func velocity(at progress: Double) -> Double {
    if solver == .linear {
      return 1
    }
    return solver.slope(at: progress)
  }
}
