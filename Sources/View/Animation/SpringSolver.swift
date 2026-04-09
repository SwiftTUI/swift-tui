#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
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
  let settlingThreshold: Double

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
    settlingThreshold = 0.001
  }

  /// Creates a spring solver from physical spring parameters.
  package init(mass: Double, stiffness: Double, damping: Double) {
    let m = max(mass, 0.001)
    naturalFrequency = sqrt(stiffness / m)
    dampingRatio = damping / (2.0 * sqrt(stiffness * m))
    settlingThreshold = 0.001
  }

  /// Returns the displacement at time `t` for a unit displacement spring.
  /// Returns `nil` when the spring has settled (animation complete).
  package func value(at t: Double) -> Double? {
    guard t >= 0 else { return 1.0 }

    let decay = exp(-dampingRatio * naturalFrequency * t)
    let displacement: Double

    if dampingRatio < 1.0 {
      // Underdamped
      let dampedFrequency = naturalFrequency * sqrt(1.0 - dampingRatio * dampingRatio)
      displacement = decay * (
        cos(dampedFrequency * t)
        + (dampingRatio * naturalFrequency / dampedFrequency) * sin(dampedFrequency * t)
      )
    } else if dampingRatio > 1.0 {
      // Overdamped — solution is x(t) = a·e^(s1·t) + b·e^(s2·t)
      // with x(0)=1 and v(0)=0, so a+b=1 and a·s1+b·s2=0.
      // Solving: a = s2/(s2-s1), b = -s1/(s2-s1).
      let s1 = -naturalFrequency * (dampingRatio - sqrt(dampingRatio * dampingRatio - 1.0))
      let s2 = -naturalFrequency * (dampingRatio + sqrt(dampingRatio * dampingRatio - 1.0))
      let denom = s2 - s1
      let a = s2 / denom
      let b = -s1 / denom
      displacement = a * exp(s1 * t) + b * exp(s2 * t)
    } else {
      // Critically damped
      displacement = decay * (1.0 + naturalFrequency * t)
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
      let B = (dampingRatio * naturalFrequency) / dampedFrequency
      return decay * (
        (-dampingRatio * naturalFrequency) * (A * cosComponent + B * sinComponent)
        + dampedFrequency * (-A * sinComponent + B * cosComponent)
      )
    } else if dampingRatio > 1.0 {
      let s1 = -naturalFrequency * (dampingRatio - sqrt(dampingRatio * dampingRatio - 1.0))
      let s2 = -naturalFrequency * (dampingRatio + sqrt(dampingRatio * dampingRatio - 1.0))
      let denom = s2 - s1
      let a = s2 / denom
      let b = -s1 / denom
      return a * s1 * exp(s1 * t) + b * s2 * exp(s2 * t)
    } else {
      return decay * (-naturalFrequency * naturalFrequency * t)
    }
  }
}
