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
    dampingRatio = 1.0 - bounce
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

    // Check if settled
    if abs(displacement) < settlingThreshold && t > 0.05 {
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
      let s1 = -naturalFrequency * (dampingRatio - sqrt(dampingRatio * dampingRatio - 1.0))
      let s2 = -naturalFrequency * (dampingRatio + sqrt(dampingRatio * dampingRatio - 1.0))
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
      let s1 = -naturalFrequency * (dampingRatio - sqrt(dampingRatio * dampingRatio - 1.0))
      let s2 = -naturalFrequency * (dampingRatio + sqrt(dampingRatio * dampingRatio - 1.0))
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
      let s1 = -naturalFrequency * (dampingRatio - sqrt(dampingRatio * dampingRatio - 1.0))
      let s2 = -naturalFrequency * (dampingRatio + sqrt(dampingRatio * dampingRatio - 1.0))
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
      let s1 = -naturalFrequency * (dampingRatio - sqrt(dampingRatio * dampingRatio - 1.0))
      let s2 = -naturalFrequency * (dampingRatio + sqrt(dampingRatio * dampingRatio - 1.0))
      return (s1 * exp(s1 * t) - s2 * exp(s2 * t)) / (s1 - s2)
    } else {
      return decay * (1.0 - naturalFrequency * t)
    }
  }

  // MARK: - Settling

  /// Seconds after which a spring released from rest (unit displacement,
  /// zero velocity) stays inside ``settlingThreshold`` for good — the same
  /// criterion ``value(at:)`` uses to report completion, applied to the
  /// decay envelope rather than to one sample, so an underdamped spring's
  /// zero crossings never count as settled.
  ///
  /// Capped at 60 seconds: an undamped spring (damping ratio zero) never
  /// settles, and the cap keeps a keyframe segment sized by this value
  /// finite.
  package var settlingDuration: Double {
    let floor = 0.05 + 1e-6
    let cap = 60.0
    // Aim slightly inside the threshold so the instant reported here is
    // strictly settled by `value(at:)`'s `<` comparison.
    let target = settlingThreshold * 0.999
    let timeConstant = dampingRatio * naturalFrequency
    guard timeConstant > 0 else { return cap }

    if dampingRatio < 1.0 {
      // |x(t)| <= e^(-z·w·t) / sqrt(1 - z²) for the rest release.
      let amplitude = 1.0 / sqrt(1.0 - dampingRatio * dampingRatio)
      let settle = log(amplitude / target) / timeConstant
      return min(max(settle, floor), cap)
    }

    // Critically damped and overdamped rest releases decay monotonically:
    // bisect the raw solution for the threshold crossing.
    let rest = with(initialVelocity: 0)
    var lo = 0.0
    var hi = cap
    guard abs(rest.displacement(at: hi)) < target else { return cap }
    for _ in 0..<80 {
      let mid = (lo + hi) / 2
      if abs(rest.displacement(at: mid)) < target {
        hi = mid
      } else {
        lo = mid
      }
      if hi - lo < 1e-9 { break }
    }
    return min(max(hi, floor), cap)
  }
}
