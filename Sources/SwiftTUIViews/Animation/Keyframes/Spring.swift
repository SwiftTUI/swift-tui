public import SwiftTUICore

/// The physical parameters of a spring, evaluable at any time and for any
/// ``VectorArithmetic`` value.
///
/// Matches SwiftUI's `Spring`. `SpringKeyframe` takes one, and
/// ``Animation/spring(_:)`` builds an animation from one. The
/// `duration`/`bounce` parameterization is the same one
/// ``Animation/spring(duration:bounce:)`` uses, so a keyframe spring and a
/// `withAnimation` spring with the same parameters move and settle alike.
///
/// ```swift
/// SpringKeyframe(0.0, spring: .bouncy)
/// SpringKeyframe(1.0, spring: Spring(duration: .milliseconds(800), bounce: 0.4))
/// ```
public struct Spring: Hashable, Sendable {
  package let solver: SpringSolver
  /// The perceptual duration of the spring, which defines its pace.
  public let duration: Duration
  /// How bouncy the spring is: `0` is critically damped, positive values
  /// overshoot, negative values are overdamped.
  public let bounce: Double
  /// The spring's mass.
  public let mass: Double
  /// The spring's stiffness.
  public let stiffness: Double
  /// The spring's damping coefficient.
  public let damping: Double

  /// Creates a spring from a perceptual duration and a bounce.
  ///
  /// - Parameters:
  ///   - duration: The perceptual duration, which defines the pace.
  ///   - bounce: How bouncy the spring is; `0` settles without overshoot.
  public init(duration: Duration = .milliseconds(500), bounce: Double = 0) {
    let seconds = max(duration.totalSeconds, 0.001)
    let solver = SpringSolver(duration: seconds, bounce: bounce)
    self.solver = solver
    self.duration = duration
    self.bounce = bounce
    mass = 1
    stiffness = solver.naturalFrequency * solver.naturalFrequency
    damping = 2 * solver.dampingRatio * solver.naturalFrequency
  }

  /// Creates a spring from physical parameters.
  public init(mass: Double = 1, stiffness: Double, damping: Double) {
    let solver = SpringSolver(mass: mass, stiffness: stiffness, damping: damping)
    self.solver = solver
    self.mass = mass
    self.stiffness = stiffness
    self.damping = damping
    bounce = 1 - solver.dampingRatio
    let seconds = 2 * Double.pi / max(solver.naturalFrequency, 1e-9)
    duration = .microseconds(Int64((seconds * 1_000_000).rounded()))
  }

  /// A smooth spring with no bounce.
  public static let smooth = Spring(bounce: 0)
  /// A spring with a small amount of bounce.
  public static let snappy = Spring(bounce: 0.15)
  /// A spring with a higher amount of bounce.
  public static let bouncy = Spring(bounce: 0.3)

  /// A smooth spring with a given duration and, optionally, extra bounce.
  public static func smooth(duration: Duration, extraBounce: Double = 0) -> Spring {
    Spring(duration: duration, bounce: extraBounce)
  }

  /// A snappy spring with a given duration and, optionally, extra bounce.
  public static func snappy(duration: Duration, extraBounce: Double = 0) -> Spring {
    Spring(duration: duration, bounce: 0.15 + extraBounce)
  }

  /// A bouncy spring with a given duration and, optionally, extra bounce.
  public static func bouncy(duration: Duration, extraBounce: Double = 0) -> Spring {
    Spring(duration: duration, bounce: 0.3 + extraBounce)
  }

  /// The damping ratio: `1` is critically damped, less than `1` oscillates.
  public var dampingRatio: Double {
    solver.dampingRatio
  }

  /// How long the spring takes to come to rest from a unit displacement at
  /// zero velocity, by the same criterion ``Animation/spring(duration:bounce:)``
  /// completes on.
  public var settlingDuration: Duration {
    .microseconds(Int64((solver.settlingDuration * 1_000_000).rounded()))
  }

  // MARK: - Evaluation

  /// The spring's value at `time`, moving from `fromValue` toward `toValue`
  /// with an initial velocity in value units per second.
  public func value<V: VectorArithmetic>(
    fromValue: V,
    toValue: V,
    initialVelocity: V,
    time: Duration
  ) -> V {
    let t = max(time.totalSeconds, 0)
    var displacement = (fromValue - toValue).scaled(by: solver.displacement(at: t))
    displacement += initialVelocity.scaled(by: solver.unitVelocityResponse(at: t))
    return toValue + displacement
  }

  /// The spring's value at `time`, moving from zero toward `target`.
  public func value<V: VectorArithmetic>(
    target: V,
    initialVelocity: V = .zero,
    time: Duration
  ) -> V {
    value(fromValue: .zero, toValue: target, initialVelocity: initialVelocity, time: time)
  }

  /// The spring's velocity at `time` in value units per second, moving from
  /// `fromValue` toward `toValue` with an initial velocity.
  public func velocity<V: VectorArithmetic>(
    fromValue: V,
    toValue: V,
    initialVelocity: V,
    time: Duration
  ) -> V {
    let t = max(time.totalSeconds, 0)
    var velocity = (fromValue - toValue).scaled(by: solver.velocity(at: t))
    velocity += initialVelocity.scaled(by: solver.unitVelocityResponseDerivative(at: t))
    return velocity
  }

  /// The spring's velocity at `time`, moving from zero toward `target`.
  public func velocity<V: VectorArithmetic>(
    target: V,
    initialVelocity: V = .zero,
    time: Duration
  ) -> V {
    velocity(fromValue: .zero, toValue: target, initialVelocity: initialVelocity, time: time)
  }
}
