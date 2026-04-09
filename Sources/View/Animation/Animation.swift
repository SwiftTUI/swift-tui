package import Core

/// An animation that can be applied to state changes.
public struct Animation: Equatable, Hashable, Sendable {
  let curve: AnimationCurve
  let delayDuration: Duration
  let speedMultiplier: Double
  let repeatBehavior: RepeatBehavior?

  init(
    curve: AnimationCurve,
    delay: Duration = .zero,
    speed: Double = 1.0,
    repeatBehavior: RepeatBehavior? = nil
  ) {
    self.curve = curve
    delayDuration = delay
    speedMultiplier = speed
    self.repeatBehavior = repeatBehavior
  }

  // MARK: - Timing Curves

  public static let `default`: Animation = .easeInOut

  public static func linear(duration: Duration = .milliseconds(200)) -> Animation {
    Animation(curve: .bezier(.linear, duration))
  }

  public static func easeIn(duration: Duration = .milliseconds(200)) -> Animation {
    Animation(curve: .bezier(.easeIn, duration))
  }

  public static func easeOut(duration: Duration = .milliseconds(200)) -> Animation {
    Animation(curve: .bezier(.easeOut, duration))
  }

  public static func easeInOut(duration: Duration = .milliseconds(200)) -> Animation {
    Animation(curve: .bezier(.easeInOut, duration))
  }

  public static var easeInOut: Animation {
    easeInOut()
  }

  public static func timingCurve(
    _ c0x: Double, _ c0y: Double,
    _ c1x: Double, _ c1y: Double,
    duration: Duration = .milliseconds(200)
  ) -> Animation {
    Animation(curve: .bezier(.init(c0x, c0y, c1x, c1y), duration))
  }

  // MARK: - Springs

  public static func spring(
    duration: Duration = .milliseconds(500),
    bounce: Double = 0.0
  ) -> Animation {
    Animation(
      curve: .spring(
        .init(
          duration: durationSeconds(duration),
          bounce: bounce
        )))
  }

  public static var smooth: Animation { spring(bounce: 0.0) }
  public static var snappy: Animation { spring(bounce: 0.15) }
  public static var bouncy: Animation { spring(bounce: 0.3) }

  public static func smooth(
    duration: Duration,
    extraBounce: Double = 0.0
  ) -> Animation {
    spring(duration: duration, bounce: 0.0 + extraBounce)
  }

  public static func snappy(
    duration: Duration,
    extraBounce: Double = 0.0
  ) -> Animation {
    spring(duration: duration, bounce: 0.15 + extraBounce)
  }

  public static func bouncy(
    duration: Duration,
    extraBounce: Double = 0.0
  ) -> Animation {
    spring(duration: duration, bounce: 0.3 + extraBounce)
  }

  public static func interpolatingSpring(
    mass: Double = 1.0,
    stiffness: Double,
    damping: Double,
    initialVelocity: Double = 0.0
  ) -> Animation {
    Animation(
      curve: .spring(
        .init(
          mass: mass, stiffness: stiffness, damping: damping
        )))
  }

  // MARK: - Custom

  public init<A: CustomAnimation>(_ base: A) {
    self.init(curve: .custom(CustomAnimationBox(base)))
  }

  // MARK: - Modifiers

  public func delay(_ delay: Duration) -> Animation {
    Animation(
      curve: curve,
      delay: delayDuration + delay,
      speed: speedMultiplier,
      repeatBehavior: repeatBehavior
    )
  }

  public func speed(_ speed: Double) -> Animation {
    Animation(
      curve: curve,
      delay: delayDuration,
      speed: speedMultiplier * speed,
      repeatBehavior: repeatBehavior
    )
  }

  public func repeatCount(
    _ count: Int,
    autoreverses: Bool = true
  ) -> Animation {
    Animation(
      curve: curve,
      delay: delayDuration,
      speed: speedMultiplier,
      repeatBehavior: .count(count, autoreverses: autoreverses)
    )
  }

  public func repeatForever(
    autoreverses: Bool = true
  ) -> Animation {
    Animation(
      curve: curve,
      delay: delayDuration,
      speed: speedMultiplier,
      repeatBehavior: .forever(autoreverses: autoreverses)
    )
  }

  // MARK: - Evaluation

  /// Returns the progress value at elapsed time, or nil if complete.
  package func evaluate(elapsed: Duration) -> Double? {
    let adjustedElapsed = adjustedTime(elapsed)
    guard adjustedElapsed >= .zero else { return 0.0 }

    switch curve {
    case .bezier(let solver, let duration):
      let durationSecs = Self.durationSeconds(duration)
      guard durationSecs > 0 else { return nil }
      let timeFraction = Self.durationSeconds(adjustedElapsed) / durationSecs
      if timeFraction >= 1.0 { return nil }
      return solver.progress(for: timeFraction)

    case .spring(let solver):
      let t = Self.durationSeconds(adjustedElapsed)
      guard let displacement = solver.value(at: t) else { return nil }
      // Spring returns displacement (1 -> 0), convert to progress (0 -> 1)
      return 1.0 - displacement

    case .custom:
      // Custom animations evaluated via the CustomAnimation protocol
      // at the controller level. Return linear fallback here.
      let t = Self.durationSeconds(adjustedElapsed)
      if t >= 2.0 { return nil }
      return min(t / 0.5, 1.0)
    }
  }

  private func adjustedTime(_ elapsed: Duration) -> Duration {
    let delayed = elapsed - delayDuration
    guard speedMultiplier != 1.0 else { return delayed }
    let seconds = Self.durationSeconds(delayed) * speedMultiplier
    return .milliseconds(Int64(seconds * 1000))
  }

  static func durationSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
  }

  /// Wraps this animation for transport through Core's AnimationBox.
  package var animationBox: AnimationBox {
    AnimationBox(self)
  }
}

// MARK: - Internal Types

enum AnimationCurve: Equatable, Hashable, Sendable {
  case bezier(BezierSolver, Duration)
  case spring(SpringSolver)
  case custom(CustomAnimationBox)
}

enum RepeatBehavior: Equatable, Hashable, Sendable {
  case count(Int, autoreverses: Bool)
  case forever(autoreverses: Bool)
}

/// Type-erased wrapper for CustomAnimation conformances.
struct CustomAnimationBox: Equatable, Hashable, Sendable {
  private let _hashValue: Int
  private let _isEqual: @Sendable (CustomAnimationBox) -> Bool

  init<A: CustomAnimation>(_ animation: A) {
    _hashValue = animation.hashValue
    _isEqual = { other in
      other._hashValue == animation.hashValue
    }
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs._isEqual(rhs)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(_hashValue)
  }
}

// Make BezierSolver and SpringSolver Equatable + Hashable for AnimationCurve
extension BezierSolver: Equatable {
  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.c0x == rhs.c0x && lhs.c0y == rhs.c0y
      && lhs.c1x == rhs.c1x && lhs.c1y == rhs.c1y
  }
}

extension BezierSolver: Hashable {
  package func hash(into hasher: inout Hasher) {
    hasher.combine(c0x)
    hasher.combine(c0y)
    hasher.combine(c1x)
    hasher.combine(c1y)
  }
}

extension SpringSolver: Equatable {
  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.dampingRatio == rhs.dampingRatio
      && lhs.naturalFrequency == rhs.naturalFrequency
  }
}

extension SpringSolver: Hashable {
  package func hash(into hasher: inout Hasher) {
    hasher.combine(dampingRatio)
    hasher.combine(naturalFrequency)
  }
}
