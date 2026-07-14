package import SwiftTUICore

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
  ///
  /// Stateless convenience overload — used by code paths that do not
  /// carry per-key ``AnimationState`` (e.g. sample-for-retargeting).
  /// Custom animations run with a fresh state buffer and therefore
  /// cannot persist bookkeeping across ticks via this path.
  package func evaluate(elapsed: Duration) -> Double? {
    var ephemeral = AnimationState()
    return evaluate(elapsed: elapsed, state: &ephemeral)
  }

  /// Stateful progress evaluation used by the controller at tick time.
  /// Built-in bezier/spring curves ignore `state`; custom curves thread
  /// it through ``CustomAnimationBox/evaluate`` so user implementations
  /// can persist bookkeeping across ticks.
  package func evaluate(
    elapsed: Duration,
    state: inout AnimationState
  ) -> Double? {
    let adjustedElapsed = adjustedTime(elapsed)
    guard adjustedElapsed >= .zero else { return 0.0 }

    guard let repeatBehavior else {
      return evaluateSingleIteration(elapsed: adjustedElapsed, state: &state)
    }

    // Repeats are modulo the iteration duration.  One iteration runs
    // the curve from 0 → 1; with autoreverse, odd iterations run 1 → 0
    // (the curve played backward).
    let iterationSecs = iterationDurationSeconds
    guard iterationSecs > 0 else {
      return evaluateSingleIteration(elapsed: adjustedElapsed, state: &state)
    }

    let totalSecs = Self.durationSeconds(adjustedElapsed)
    let rawIndex = totalSecs / iterationSecs
    let iterationIndex = Int(rawIndex.rounded(.down))
    let localTimeSecs = totalSecs - Double(iterationIndex) * iterationSecs
    let localElapsed = Self.duration(seconds: localTimeSecs)

    let autoreverses: Bool
    let terminalIndex: Int?
    switch repeatBehavior {
    case .count(let count, let ar):
      autoreverses = ar
      terminalIndex = max(count, 0)
    case .forever(let ar):
      autoreverses = ar
      terminalIndex = nil
    }

    if let terminalIndex, iterationIndex >= terminalIndex {
      return nil
    }

    guard
      let rawProgress = evaluateSingleIteration(elapsed: localElapsed, state: &state)
    else {
      // We landed past the end of the single-iteration evaluator but
      // before the next iteration starts — clamp to the endpoint the
      // curve would have reached.
      return autoreverses && !iterationIndex.isMultiple(of: 2) ? 0.0 : 1.0
    }

    if autoreverses && !iterationIndex.isMultiple(of: 2) {
      return 1.0 - rawProgress
    }
    return rawProgress
  }

  /// Evaluates a single iteration of the curve at `elapsed`.  Returns
  /// nil when the iteration has run to completion.  Repeat bookkeeping
  /// is handled by the outer ``evaluate`` wrapper.
  private func evaluateSingleIteration(
    elapsed: Duration,
    state: inout AnimationState
  ) -> Double? {
    switch curve {
    case .bezier(let solver, let duration):
      let durationSecs = Self.durationSeconds(duration)
      guard durationSecs > 0 else { return nil }
      let timeFraction = Self.durationSeconds(elapsed) / durationSecs
      if timeFraction >= 1.0 { return nil }
      return solver.progress(for: timeFraction)

    case .spring(let solver):
      let t = Self.durationSeconds(elapsed)
      guard let displacement = solver.value(at: t) else { return nil }
      // Spring returns displacement (1 -> 0), convert to progress (0 -> 1)
      return 1.0 - displacement

    case .custom(let box):
      return box.evaluate(elapsed, &state)
    }
  }

  /// The total wall-clock duration of this animation — including
  /// ``delayDuration``, ``speedMultiplier``, and any bounded repeat
  /// count.
  ///
  /// Returns `nil` for animations that repeat forever: an infinite
  /// animation has no logical completion time, and the animation
  /// controller uses `nil` as a sentinel to skip stranded-batch
  /// drains for those animations (matching SwiftUI's behavior of
  /// never firing `withAnimation` completions for `.repeatForever`
  /// scopes).
  package var totalDuration: Duration? {
    let iterationCount: Int
    switch repeatBehavior {
    case .forever:
      return nil
    case .count(let n, _):
      iterationCount = max(0, n)
    case nil:
      iterationCount = 1
    }
    let singleSecs = iterationDurationSeconds
    let adjustedSingleSecs =
      speedMultiplier > 0 ? singleSecs / speedMultiplier : singleSecs
    let totalSecs = adjustedSingleSecs * Double(iterationCount)
    let totalNanos = Int64((totalSecs * 1_000_000_000).rounded())
    return delayDuration + .nanoseconds(totalNanos)
  }

  /// The nominal duration of one full iteration, used by the repeat
  /// bookkeeping in ``evaluate(elapsed:)``.
  ///
  /// - Bezier: the explicit duration parameter.
  /// - Spring: an estimated settle time — amplitude decay of `e^(-6.9)`
  ///   ≈ 0.1% — with a floor of one natural oscillation period so very
  ///   lightly damped springs still produce a meaningful cycle.
  /// - Custom: 2 seconds, matching the linear fallback's completion
  ///   time in ``evaluateSingleIteration``.
  private var iterationDurationSeconds: Double {
    switch curve {
    case .bezier(_, let duration):
      return Self.durationSeconds(duration)
    case .spring(let solver):
      let timeConstant = solver.dampingRatio * solver.naturalFrequency
      let settle = timeConstant > 0 ? 6.9 / timeConstant : 1.0
      let period = 2.0 * .pi / max(solver.naturalFrequency, 0.001)
      return max(settle, period)
    case .custom:
      return 2.0
    }
  }

  private static func duration(seconds: Double) -> Duration {
    .milliseconds(Int64((seconds * 1000.0).rounded()))
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

  /// `true` when this animation is backed by a user ``CustomAnimation``
  /// (as opposed to a built-in bezier or spring curve).  The controller
  /// gates its retarget-handoff hooks on this so built-in retargets stay
  /// byte-for-byte unchanged.
  package var isCustomCurve: Bool {
    if case .custom = curve { return true }
    return false
  }

  /// Consults a custom curve's ``CustomAnimation/shouldMerge`` handoff
  /// policy on retarget.  Built-in bezier/spring curves have no merge
  /// policy and return `false` (the protocol default) without allocating
  /// a context.  `elapsed` is the outgoing animation's running time; the
  /// mutated ``AnimationState`` is threaded back so a policy that records
  /// bookkeeping is preserved.
  package func shouldMerge(
    previous: Animation,
    elapsed: Duration,
    state: inout AnimationState
  ) -> Bool {
    guard case .custom(let box) = curve else { return false }
    return box.shouldMerge(previous, adjustedTime(elapsed), &state)
  }

  /// Queries a custom curve's ``CustomAnimation/velocity`` hook for an
  /// interrupted handoff.  Built-in bezier/spring curves return `nil`
  /// (the protocol default) — they carry no user-defined momentum.
  package func velocity(
    elapsed: Duration,
    state: AnimationState
  ) -> Double? {
    guard case .custom(let box) = curve else { return nil }
    return box.velocity(adjustedTime(elapsed), state)
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
///
/// Retains a call-through closure so the animation controller can
/// evaluate the user's curve at tick time.  The call-through uses
/// `Double` as the `VectorArithmetic` value — the controller treats the
/// returned Double as a progress scalar and does its own interpolation
/// between `from` and `to`, so custom animations do not need to know
/// about the controller's value types.
struct CustomAnimationBox: Equatable, Hashable, Sendable {
  private let _hashValue: Int
  /// The user's concrete curve, retained so `==` can compare VALUES via a
  /// dynamic-cast open (F176). Equality previously compared stored
  /// `hashValue`s, so two distinct curves whose hashes collide compared
  /// equal — and hash-as-identity fed retarget/merge decisions.
  private let _base: any CustomAnimation
  private let _isEqual: @Sendable (CustomAnimationBox) -> Bool
  let evaluate: @Sendable (Duration, inout AnimationState) -> Double?
  /// Call-through to the user curve's ``CustomAnimation/shouldMerge``
  /// handoff policy, consulted by the controller when a mid-flight custom
  /// animation is retargeted.  Mirrors ``evaluate``: the value axis is
  /// `Double` (1.0) and the mutated context state is threaded back so a
  /// policy that records per-key bookkeeping is preserved.
  let shouldMerge: @Sendable (Animation, Duration, inout AnimationState) -> Bool
  /// Call-through to the user curve's ``CustomAnimation/velocity`` hook,
  /// queried on an interrupted handoff so momentum can carry into the
  /// replacement.  The protocol hook receives its context by value (it is
  /// non-mutating), so no state writeback occurs here.
  let velocity: @Sendable (Duration, AnimationState) -> Double?

  init<A: CustomAnimation>(_ animation: A) {
    _hashValue = animation.hashValue
    _base = animation
    _isEqual = { other in
      guard let otherAnimation = other._base as? A else {
        return false
      }
      return otherAnimation == animation
    }
    evaluate = { time, state in
      var context = AnimationContext<Double>(state: state)
      let result = animation.animate(value: 1.0, time: time, context: &context)
      state = context.state
      return result
    }
    shouldMerge = { previous, time, state in
      var context = AnimationContext<Double>(state: state)
      let result = animation.shouldMerge(
        previous: previous, value: 1.0, time: time, context: &context
      )
      state = context.state
      return result
    }
    velocity = { time, state in
      let context = AnimationContext<Double>(state: state)
      return animation.velocity(value: 1.0, time: time, context: context)
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
