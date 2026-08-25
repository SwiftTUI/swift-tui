public import SwiftTUICore

/// A view that drives its content with a value interpolated along keyframes.
///
/// Matches SwiftUI's `KeyframeAnimator`. Two modes:
///
/// ### Trigger mode
///
/// `init(initialValue:trigger:content:keyframes:)` runs the keyframes once
/// each time `trigger` changes. The initial appearance is not a change: the
/// content renders at `initialValue` until the first trigger change. A change
/// mid-flight restarts the keyframes from the *current* interpolated value
/// (and carries its velocity into a leading cubic or spring keyframe), so a
/// quick double trigger never jumps back to the start.
///
/// ```swift
/// struct Marker { var y = 0.0; var opacity = 1.0 }
///
/// @State private var taps = 0
/// KeyframeAnimator(initialValue: Marker(), trigger: taps) { marker in
///   Text("★")
///     .offset(x: 0, y: Int(marker.y.rounded()))
///     .opacity(marker.opacity)
/// } keyframes: { _ in
///   KeyframeTrack(\.y) {
///     CubicKeyframe(-3, duration: .milliseconds(400))
///     SpringKeyframe(0, spring: .bouncy)
///   }
///   KeyframeTrack(\.opacity) {
///     LinearKeyframe(0.4, duration: .milliseconds(200))
///     LinearKeyframe(1, duration: .milliseconds(600))
///   }
/// }
/// Button("bounce") { taps += 1 }
/// ```
///
/// ### Repeating mode
///
/// `init(initialValue:repeating:content:keyframes:)` starts on appearance;
/// with `repeating: true` (the default) the keyframes loop from
/// `initialValue` for as long as the view is on screen.
///
/// ### How it animates
///
/// The animator re-evaluates `content` on the ``AnimationTimelineSchedule``
/// cadence (about 20 updates per second) with a fresh value each time, the
/// way ``TimelineView`` does, and every state write it makes snaps. The
/// content subtree does not take part in implicit animation: an enclosing
/// `withAnimation` scope or ``View/animation(_:value:)`` cannot layer a
/// curve on top of the keyframe-driven values, and transitions inside the
/// content are suppressed. Keep `content` cheap; it runs on every tick.
///
/// `Int` properties step (``VectorArithmetic`` scaling truncates); prefer
/// `Double` tracks and round in `content`.
///
/// ### Reduce motion
///
/// Under reduce motion a trigger change writes the keyframes' end value at
/// once, and repeating mode rests at `initialValue` without starting a task.
public struct KeyframeAnimator<Value: Sendable, KeyframePath: Keyframes, Content: View>: View
where KeyframePath.Value == Value {
  private enum Mode {
    case trigger(KeyframeTriggerKey)
    case onAppear(repeating: Bool)
  }

  private let initialValue: Value
  private let mode: Mode
  private let content: @MainActor (Value) -> Content
  private let keyframes: @MainActor (Value) -> KeyframePath

  @State private var value: Value
  /// The trigger the last run started for. Archived with the view, so a
  /// dormant-tab re-mount whose trigger did not change does not replay.
  @State private var lastRunTrigger: KeyframeTriggerKey?
  /// The timeline in flight, for retrigger continuity.
  @State private var flight: KeyframeFlight<Value>?

  /// Creates an animator that runs its keyframes once per `trigger` change.
  public init(
    initialValue: Value,
    trigger: some Equatable,
    @ViewBuilder content: @escaping @MainActor (Value) -> Content,
    @KeyframesBuilder<Value> keyframes: @escaping @MainActor (Value) -> KeyframePath
  ) {
    self.initialValue = initialValue
    mode = .trigger(KeyframeTriggerKey(trigger))
    self.content = content
    self.keyframes = keyframes
    _value = State(wrappedValue: initialValue)
  }

  /// Creates an animator that starts on appearance and, when `repeating`,
  /// loops for as long as the view is on screen.
  public init(
    initialValue: Value,
    repeating: Bool = true,
    @ViewBuilder content: @escaping @MainActor (Value) -> Content,
    @KeyframesBuilder<Value> keyframes: @escaping @MainActor (Value) -> KeyframePath
  ) {
    self.initialValue = initialValue
    mode = .onAppear(repeating: repeating)
    self.content = content
    self.keyframes = keyframes
    _value = State(wrappedValue: initialValue)
  }

  public var body: some View {
    EnvironmentReader(\.renderingReduceMotion) { reduceMotion in
      animatorBody(reduceMotion: reduceMotion)
    }
  }

  @ViewBuilder
  private func animatorBody(reduceMotion: Bool) -> some View {
    // Touch the task-written state in body so each slot binds to this
    // instance during body evaluation (the PhaseAnimator/TimelineView
    // trick): a first access from inside `.task` would land on the seed.
    _ = lastRunTrigger
    _ = flight
    switch mode {
    case .trigger(let trigger):
      keyframeContent
        .task(id: KeyframeTriggerTaskKey(trigger: trigger, reduceMotion: reduceMotion)) {
          @MainActor in
          await runTriggered(trigger, reduceMotion: reduceMotion)
        }
    case .onAppear(let repeating):
      if reduceMotion {
        keyframeContent
      } else {
        keyframeContent
          .task { @MainActor in
            await runFromAppearance(repeating: repeating)
          }
      }
    }
  }

  /// The content under an authored `disablesAnimations` transaction: every
  /// node below carries a `.disabled` snapshot the controller consults before
  /// any frame segment, so keyframe-driven slots never pick up an ancestor's
  /// animation.
  private var keyframeContent: some View {
    content(value)
      .transaction { $0.disablesAnimations = true }
  }

  // MARK: - Drivers

  @MainActor
  private func runTriggered(_ trigger: KeyframeTriggerKey, reduceMotion: Bool) async {
    guard let previous = lastRunTrigger else {
      // The initial appearance records the trigger and does not animate.
      lastRunTrigger = trigger
      return
    }
    guard previous != trigger else {
      // An unchanged trigger is a `.task` replay (dormant-tab re-mount).
      return
    }
    lastRunTrigger = trigger

    let start = MonotonicInstant.now()
    var timeline = KeyframeTimeline(initialValue: value, keyframes: keyframes(value))
    if let inFlight = flight {
      // Retrigger mid-flight: start from the current value with its velocity.
      timeline = timeline.continuing(
        from: inFlight.timeline,
        at: inFlight.start.duration(to: start)
      )
    }
    if reduceMotion {
      flight = nil
      value = timeline.value(time: timeline.duration)
      return
    }
    flight = KeyframeFlight(timeline: timeline, start: start)
    await drive(timeline, from: start, repeating: false)
  }

  @MainActor
  private func runFromAppearance(repeating: Bool) async {
    let start = MonotonicInstant.now()
    let timeline = KeyframeTimeline(
      initialValue: initialValue,
      keyframes: keyframes(initialValue)
    )
    flight = KeyframeFlight(timeline: timeline, start: start)
    await drive(timeline, from: start, repeating: repeating)
  }

  /// Ticks `timeline` on the animation schedule from `start`, writing the
  /// sampled value each tick and, when not repeating, the end value exactly
  /// once. Lag recovery follows ``TimelineView``: a tick that is already due
  /// renders now and re-anchors the grid so the loop always suspends before
  /// its next write.
  @MainActor
  private func drive(
    _ timeline: KeyframeTimeline<Value>,
    from start: MonotonicInstant,
    repeating: Bool
  ) async {
    let duration = timeline.duration
    guard duration > .zero else {
      value = timeline.value(time: .zero)
      flight = nil
      return
    }
    let cycleSeconds = duration.totalSeconds
    let schedule = AnimationTimelineSchedule()
    var iterator = schedule.entries(from: start, mode: .normal).makeIterator()
    // The start instant itself carries the value already on screen.
    _ = iterator.next()

    while !Task.isCancelled {
      guard let next = iterator.next() else { return }
      let now = MonotonicInstant.now()
      let tick: MonotonicInstant
      switch timelineTickPlan(delay: now.duration(to: next)) {
      case .sleep(let delay):
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        tick = next
      case .renderNowAndReanchor:
        tick = now
        iterator = schedule.entries(from: now, mode: .normal).makeIterator()
        _ = iterator.next()
      }

      var elapsed = start.duration(to: tick)
      if repeating {
        elapsed = .seconds(elapsed.totalSeconds.truncatingRemainder(dividingBy: cycleSeconds))
      } else if elapsed >= duration {
        value = timeline.value(time: duration)
        flight = nil
        return
      }
      value = timeline.value(time: elapsed)
    }
  }
}

// MARK: - Support types

/// A timeline in flight and the instant it started, kept in view state so a
/// retrigger can sample the outgoing velocity.
struct KeyframeFlight<Value> {
  var timeline: KeyframeTimeline<Value>
  var start: MonotonicInstant
}

/// Value-equality key over an opened `Equatable` trigger (the
/// `TimelineView.TaskKey` shape): the trigger keeps SwiftUI's `some Equatable`
/// bound, and comparison opens the concrete type so distinct values never
/// alias. A changed trigger type compares unequal.
struct KeyframeTriggerKey: Equatable {
  let base: any Equatable

  init(_ base: some Equatable) {
    self.base = base
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    func open<T: Equatable>(_ lhsBase: T) -> Bool {
      guard let rhsBase = rhs.base as? T else {
        return false
      }
      return lhsBase == rhsBase
    }
    return open(lhs.base)
  }
}

/// The `.task(id:)` key for trigger mode: the trigger plus the reduce-motion
/// arm, so a motion-policy flip restarts the driver with the right behavior.
struct KeyframeTriggerTaskKey: Equatable {
  let trigger: KeyframeTriggerKey
  let reduceMotion: Bool
}
