#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(WASILibc)
  import WASILibc
#elseif canImport(ucrt)
  import ucrt
#endif

/// Solves the damped harmonic oscillator equation for spring animations.
///
/// x(t) = e^(-zt) * (A*cos(wd*t) + B*sin(wd*t))
///
/// Where z = damping ratio, w = natural frequency, wd = damped frequency.
package struct SpringSolver: Sendable {
  let dampingRatio: Double  // z
  let naturalFrequency: Double  // w
  /// Initial velocity in toward-target units, matching SwiftUI's
  /// `interpolatingSpring(initialVelocity:)`: positive values start the
  /// spring already moving toward its target, so the remaining displacement
  /// begins with slope `-initialVelocity`.
  let initialVelocity: Double
  let settlingThreshold: Double

  /// The initial slope of the remaining displacement (solver space).
  private var v0: Double { -initialVelocity }

  /// Creates a spring solver from duration and bounce parameters.
  ///
  /// - Parameters:
  ///   - duration: Response duration. Maps to natural frequency.
  ///   - bounce: 0 = critically damped, >0 = underdamped (bouncy), <0 = overdamped.
  ///   - initialVelocity: Toward-target initial velocity (see
  ///     ``initialVelocity``); zero starts the spring at rest.
  package init(duration: Double, bounce: Double, initialVelocity: Double = 0) {
    // Map bounce to damping ratio:
    // bounce 0 -> z = 1 (critically damped)
    // bounce > 0 -> z < 1 (underdamped)
    // bounce < 0 -> z > 1 (overdamped)
    dampingRatio = max(0, 1.0 - bounce)
    // Natural frequency from duration: w = 2pi / duration
    naturalFrequency = 2.0 * .pi / max(duration, 0.001)
    self.initialVelocity = initialVelocity
    settlingThreshold = 0.001
  }

  /// Creates a spring solver from physical spring parameters.
  package init(
    mass: Double,
    stiffness: Double,
    damping: Double,
    initialVelocity: Double = 0
  ) {
    let m = max(mass, 0.001)
    naturalFrequency = sqrt(stiffness / m)
    dampingRatio = damping / (2.0 * sqrt(stiffness * m))
    self.initialVelocity = initialVelocity
    settlingThreshold = 0.001
  }

  private init(
    dampingRatio: Double,
    naturalFrequency: Double,
    initialVelocity: Double,
    settlingThreshold: Double
  ) {
    self.dampingRatio = dampingRatio
    self.naturalFrequency = naturalFrequency
    self.initialVelocity = initialVelocity
    self.settlingThreshold = settlingThreshold
  }

  /// The same spring released with a different toward-target initial
  /// velocity. The registered `Animation` that owns a solver is never
  /// mutated; velocity continuity rebuilds the solver per evaluation through
  /// this copy instead.
  package func with(initialVelocity: Double) -> SpringSolver {
    SpringSolver(
      dampingRatio: dampingRatio,
      naturalFrequency: naturalFrequency,
      initialVelocity: initialVelocity,
      settlingThreshold: settlingThreshold
    )
  }

  /// Returns the displacement at time `t` for a unit displacement spring
  /// with initial conditions x(0)=1, x'(0)=`v0`.
  /// Returns `nil` when the spring has settled (animation complete).
  package func value(at t: Double) -> Double? {
    guard t >= 0 else { return 1.0 }
    let displacement = displacement(at: t)

    // Settled once both the displacement and the velocity are inside the
    // threshold (velocity scaled by the natural frequency, the solver's
    // own rate unit). Displacement alone would report a spring settled at
    // a zero crossing it is still moving through: an underdamped bounce,
    // or a spring released with a velocity toward its target.
    if abs(displacement) < settlingThreshold
      && abs(velocity(at: t)) < settlingThreshold * max(naturalFrequency, 1)
      && t > 0.05
    {
      return nil
    }

    return displacement
  }

  /// The displacement at time `t` for x(0)=1, x'(0)=`v0`, with no settling
  /// check: the raw oscillator solution, defined for every `t >= 0`.
  package func displacement(at t: Double) -> Double {
    guard t >= 0 else { return 1.0 }

    let decay = exp(-dampingRatio * naturalFrequency * t)

    if dampingRatio < 1.0 {
      // Underdamped: x(t) = e^(-zwt)(A·cos(wd·t) + B·sin(wd·t))
      // with A = x(0) = 1 and B = (v0 + z·w)/wd from x'(0) = v0.
      let dampedFrequency = naturalFrequency * sqrt(1.0 - dampingRatio * dampingRatio)
      let b = (v0 + dampingRatio * naturalFrequency) / dampedFrequency
      return decay * (cos(dampedFrequency * t) + b * sin(dampedFrequency * t))
    } else if dampingRatio > 1.0 {
      // Overdamped — solution is x(t) = a·e^(s1·t) + b·e^(s2·t)
      // with x(0)=1 and x'(0)=v0, so a+b=1 and a·s1+b·s2=v0.
      // Solving: a = (v0-s2)/(s1-s2), b = 1-a.
      let (s1, s2) = overdampedRoots
      let denom = s1 - s2
      let a = (v0 - s2) / denom
      let b = 1.0 - a
      return a * exp(s1 * t) + b * exp(s2 * t)
    } else {
      // Critically damped: x(t) = e^(-wt)(1 + C2·t) with C2 = v0 + w.
      return decay * (1.0 + (v0 + naturalFrequency) * t)
    }
  }

  /// Returns the velocity at time `t`.
  package func velocity(at t: Double) -> Double {
    guard t >= 0 else { return 0.0 }

    let decay = exp(-dampingRatio * naturalFrequency * t)

    if dampingRatio < 1.0 {
      let dampedFrequency = naturalFrequency * sqrt(1.0 - dampingRatio * dampingRatio)
      let cosComponent = cos(dampedFrequency * t)
      let sinComponent = sin(dampedFrequency * t)
      let A = 1.0
      let B = (v0 + dampingRatio * naturalFrequency) / dampedFrequency
      return decay
        * ((-dampingRatio * naturalFrequency) * (A * cosComponent + B * sinComponent)
          + dampedFrequency * (-A * sinComponent + B * cosComponent))
    } else if dampingRatio > 1.0 {
      let (s1, s2) = overdampedRoots
      let denom = s1 - s2
      let a = (v0 - s2) / denom
      let b = 1.0 - a
      return a * s1 * exp(s1 * t) + b * s2 * exp(s2 * t)
    } else {
      let c2 = v0 + naturalFrequency
      return decay * (c2 - naturalFrequency - naturalFrequency * c2 * t)
    }
  }

  // MARK: - Unit-velocity response

  /// The oscillator's response to x(0)=0, x'(0)=1: the second fundamental
  /// solution. A spring released from displacement `d` with velocity `v`
  /// follows `d · displacement(at:) + v · unitVelocityResponse(at:)` when
  /// this solver's own ``initialVelocity`` is zero, which is how the public
  /// `Spring` value type evaluates vector-valued initial velocities.
  package func unitVelocityResponse(at t: Double) -> Double {
    guard t >= 0 else { return 0 }
    let decay = exp(-dampingRatio * naturalFrequency * t)
    if dampingRatio < 1.0 {
      let dampedFrequency = naturalFrequency * sqrt(1.0 - dampingRatio * dampingRatio)
      return decay * sin(dampedFrequency * t) / dampedFrequency
    } else if dampingRatio > 1.0 {
      let (s1, s2) = overdampedRoots
      return (exp(s1 * t) - exp(s2 * t)) / (s1 - s2)
    } else {
      return t * decay
    }
  }

  /// The derivative of ``unitVelocityResponse(at:)``.
  package func unitVelocityResponseDerivative(at t: Double) -> Double {
    guard t >= 0 else { return 0 }
    let decay = exp(-dampingRatio * naturalFrequency * t)
    if dampingRatio < 1.0 {
      let dampedFrequency = naturalFrequency * sqrt(1.0 - dampingRatio * dampingRatio)
      return decay
        * (cos(dampedFrequency * t)
          - (dampingRatio * naturalFrequency / dampedFrequency) * sin(dampedFrequency * t))
    } else if dampingRatio > 1.0 {
      let (s1, s2) = overdampedRoots
      return (s1 * exp(s1 * t) - s2 * exp(s2 * t)) / (s1 - s2)
    } else {
      return decay * (1.0 - naturalFrequency * t)
    }
  }

  /// Rationalizing the slow root avoids subtracting nearly equal numbers.
  /// The scaled square root also avoids overflowing z² for heavy damping.
  private var overdampedRoots: (Double, Double) {
    let radical = sqrt(1 - 1 / dampingRatio) * sqrt(1 + 1 / dampingRatio)
    let reciprocalSum = (1 / dampingRatio) / (1 + radical)
    return (-naturalFrequency * reciprocalSum, -naturalFrequency / reciprocalSum)
  }

  // MARK: - Settling

  /// Bounds both displacement and velocity for this release. For critical
  /// damping the polynomial envelopes decrease after one natural time unit;
  /// other envelopes are sums of decaying exponentials.
  private func settlingEnvelope(at t: Double) -> Double {
    let w = naturalFrequency
    let velocityUnit = max(w, 1)
    if dampingRatio < 1 {
      let wd = w * sqrt(1 - dampingRatio * dampingRatio)
      let b = (v0 + dampingRatio * w) / wd
      let positionAmplitude = hypot(1, b)
      let velocityAmplitude = hypot(v0, -dampingRatio * w * b - wd)
      return exp(-dampingRatio * w * t)
        * max(positionAmplitude, velocityAmplitude / velocityUnit)
    } else if dampingRatio > 1 {
      let (s1, s2) = overdampedRoots
      let a = (v0 - s2) / (s1 - s2)
      let b = 1 - a
      let slow = abs(a) * exp(s1 * t)
      let fast = abs(b) * exp(s2 * t)
      return max(slow + fast, (slow * abs(s1) + fast * abs(s2)) / velocityUnit)
    } else {
      let c = v0 + w
      let decay = exp(-w * t)
      return max(
        decay * (1 + abs(c) * t),
        decay * (abs(v0) + abs(w * c) * t) / velocityUnit)
    }
  }

  /// A conservative completion time for this release, using the same
  /// position/velocity thresholds as evaluation. Undamped motion has no end.
  package var completionDuration: Double? {
    guard dampingRatio > 0, naturalFrequency > 0 else { return nil }
    let floor = max(0.05 + 1e-6, dampingRatio == 1 ? 1 / naturalFrequency : 0)
    let target = settlingThreshold * 0.999
    var lo = floor
    var hi = floor
    while settlingEnvelope(at: hi) >= target {
      hi *= 2
      guard hi.isFinite else { return nil }
    }
    for _ in 0..<64 {
      let mid = lo + (hi - lo) / 2
      if settlingEnvelope(at: mid) < target { hi = mid } else { lo = mid }
    }
    return hi
  }

  /// Finite segment duration for keyframes. An undamped or very slow spring
  /// is capped at 60 seconds; Animation reports its uncapped completion time.
  package var settlingDuration: Double {
    min(completionDuration ?? 60, 60)
  }
}
