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
  package init(duration: Double, bounce: Double) {
    // Map bounce to damping ratio:
    // bounce 0 -> z = 1 (critically damped)
    // bounce > 0 -> z < 1 (underdamped)
    // bounce < 0 -> z > 1 (overdamped)
    dampingRatio = 1.0 - bounce
    // Natural frequency from duration: w = 2pi / duration
    naturalFrequency = 2.0 * .pi / max(duration, 0.001)
    initialVelocity = 0
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

  /// Returns the displacement at time `t` for a unit displacement spring
  /// with initial conditions x(0)=1, x'(0)=`v0`.
  /// Returns `nil` when the spring has settled (animation complete).
  package func value(at t: Double) -> Double? {
    guard t >= 0 else { return 1.0 }

    let decay = exp(-dampingRatio * naturalFrequency * t)
    let displacement: Double

    if dampingRatio < 1.0 {
      // Underdamped: x(t) = e^(-zwt)(A·cos(wd·t) + B·sin(wd·t))
      // with A = x(0) = 1 and B = (v0 + z·w)/wd from x'(0) = v0.
      let dampedFrequency = naturalFrequency * sqrt(1.0 - dampingRatio * dampingRatio)
      let b = (v0 + dampingRatio * naturalFrequency) / dampedFrequency
      displacement =
        decay
        * (cos(dampedFrequency * t) + b * sin(dampedFrequency * t))
    } else if dampingRatio > 1.0 {
      // Overdamped — solution is x(t) = a·e^(s1·t) + b·e^(s2·t)
      // with x(0)=1 and x'(0)=v0, so a+b=1 and a·s1+b·s2=v0.
      // Solving: a = (v0-s2)/(s1-s2), b = 1-a.
      let s1 = -naturalFrequency * (dampingRatio - sqrt(dampingRatio * dampingRatio - 1.0))
      let s2 = -naturalFrequency * (dampingRatio + sqrt(dampingRatio * dampingRatio - 1.0))
      let denom = s1 - s2
      let a = (v0 - s2) / denom
      let b = 1.0 - a
      displacement = a * exp(s1 * t) + b * exp(s2 * t)
    } else {
      // Critically damped: x(t) = e^(-wt)(1 + C2·t) with C2 = v0 + w.
      displacement = decay * (1.0 + (v0 + naturalFrequency) * t)
    }

    // Check if settled
    if abs(displacement) < settlingThreshold && t > 0.05 {
      return nil
    }

    return displacement
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
}
