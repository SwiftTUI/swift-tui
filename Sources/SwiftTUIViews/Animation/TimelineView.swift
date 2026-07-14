public import SwiftTUICore

// MARK: - TimelineSchedule

/// A schedule describing the moments at which a ``TimelineView``
/// re-evaluates its content.
///
/// Conforming types produce a sequence of ``MonotonicInstant``s; the
/// view sleeps until each successive instant and then re-resolves the
/// body with the updated context.  Schedules are free to return an
/// infinite sequence — `TimelineView` will keep walking it until the
/// view is removed from the hierarchy (the underlying `.task` cancels
/// at teardown).
///
/// Built-in schedules:
///
/// - ``PeriodicTimelineSchedule`` — fixed-interval ticks.  Use for
///   clocks, status text, and other "every N seconds" updates.
/// - ``AnimationTimelineSchedule`` — high-frequency ticks suitable
///   for shimmer/glow/marquee animations.  Honors reduce-motion via
///   the `mode:` argument.
///
/// Custom schedules can be defined by conforming a `Sendable` type
/// with a `Sendable` `Entries` sequence whose elements are
/// ``MonotonicInstant``.
public protocol TimelineSchedule: Sendable {
  /// A sequence of instants at which the timeline view should update.
  associatedtype Entries: Sequence & Sendable
  where Entries.Element == MonotonicInstant

  /// The instants this schedule wants the timeline view to fire at,
  /// starting at or after `startInstant`.
  ///
  /// - Parameters:
  ///   - startInstant: The earliest instant the caller is interested
  ///     in.  Implementations should not emit instants strictly
  ///     before this.
  ///   - mode: A cadence hint.  In ``TimelineScheduleMode/lowFrequency``
  ///     the schedule should throttle its updates — for example when
  ///     the system is in reduce-motion mode or the host has signalled
  ///     a lower preferred frame rate.
  func entries(
    from startInstant: MonotonicInstant,
    mode: TimelineScheduleMode
  ) -> Entries
}

/// Cadence hint passed to a ``TimelineSchedule``.
public enum TimelineScheduleMode: Hashable, Sendable {
  /// Normal cadence — the schedule may fire as fast as it likes.
  case normal
  /// Throttled cadence — fire less often to respect reduce-motion or
  /// other low-frequency-update signals from the host.
  case lowFrequency
}

// MARK: - PeriodicTimelineSchedule

/// A schedule that emits an infinite stream of instants spaced exactly
/// `interval` apart.
///
/// The first emitted instant is the largest multiple of `interval`
/// from `startInstant` that is at or after the timeline view's start
/// instant.  In ``TimelineScheduleMode/lowFrequency`` the effective
/// interval is rounded up to one second so that timer-driven UI
/// surfaces don't keep redrawing under reduce-motion.
public struct PeriodicTimelineSchedule: TimelineSchedule, Hashable, Sendable {
  public let startInstant: MonotonicInstant
  public let interval: Duration

  public init(
    from startInstant: MonotonicInstant = .now(),
    by interval: Duration
  ) {
    // A non-positive interval would spin the task hot — refuse it in
    // debug to flag the misuse early.
    precondition(
      interval > .zero,
      "PeriodicTimelineSchedule interval must be > 0"
    )
    self.startInstant = startInstant
    self.interval = interval
  }

  public func entries(
    from startInstant: MonotonicInstant,
    mode: TimelineScheduleMode
  ) -> Entries {
    let lowFrequencyFloor: Duration = .seconds(1)
    let effectiveInterval: Duration =
      mode == .lowFrequency && interval < lowFrequencyFloor
      ? lowFrequencyFloor
      : interval

    // Snap the first emission to the schedule's own grid so callers
    // that share a startInstant also share emission moments.
    let elapsedSeconds = self.startInstant.duration(to: startInstant)
      .totalSeconds
    let intervalSeconds = effectiveInterval.totalSeconds
    let stepsBehind =
      elapsedSeconds <= 0
      ? 0
      : Int((elapsedSeconds / intervalSeconds).rounded(.up))
    let first = self.startInstant.advanced(
      by: effectiveInterval * stepsBehind
    )
    return Entries(next: first, interval: effectiveInterval)
  }

  public struct Entries: Sequence, IteratorProtocol, Sendable {
    private var nextInstant: MonotonicInstant
    private let interval: Duration

    fileprivate init(next: MonotonicInstant, interval: Duration) {
      self.nextInstant = next
      self.interval = interval
    }

    public mutating func next() -> MonotonicInstant? {
      let current = nextInstant
      nextInstant = current.advanced(by: interval)
      return current
    }

    public func makeIterator() -> Self { self }
  }
}

// MARK: - AnimationTimelineSchedule

/// A schedule designed for driving smooth animation.  Defaults to a
/// 50 ms (~20 fps) cadence in normal mode and 250 ms (~4 fps) in
/// ``TimelineScheduleMode/lowFrequency`` (reduce-motion).
///
/// Set `paused = true` to freeze the timeline at the start instant.
public struct AnimationTimelineSchedule: TimelineSchedule, Hashable, Sendable {
  public let minimumInterval: Duration?
  public let paused: Bool

  public init(
    minimumInterval: Duration? = nil,
    paused: Bool = false
  ) {
    if let minimumInterval {
      precondition(
        minimumInterval > .zero,
        "AnimationTimelineSchedule minimumInterval must be > 0"
      )
    }
    self.minimumInterval = minimumInterval
    self.paused = paused
  }

  public func entries(
    from startInstant: MonotonicInstant,
    mode: TimelineScheduleMode
  ) -> Entries {
    if paused {
      return Entries(start: startInstant, interval: nil)
    }
    let normalDefault: Duration = .milliseconds(50)
    let lowFrequencyDefault: Duration = .milliseconds(250)
    let chosen: Duration = {
      switch mode {
      case .normal:
        return minimumInterval ?? normalDefault
      case .lowFrequency:
        // Honor an explicit minimum if it's already coarse enough,
        // otherwise enforce the reduce-motion floor.
        if let minimumInterval, minimumInterval >= lowFrequencyDefault {
          return minimumInterval
        }
        return lowFrequencyDefault
      }
    }()
    return Entries(start: startInstant, interval: chosen)
  }

  /// Lazily emits the start instant, then a tick every `interval`.
  /// When `interval` is `nil` only the start is emitted — used by
  /// the `paused` path.
  public struct Entries: Sequence, IteratorProtocol, Sendable {
    private var current: MonotonicInstant
    private let interval: Duration?
    private var didEmitStart: Bool

    fileprivate init(start: MonotonicInstant, interval: Duration?) {
      self.current = start
      self.interval = interval
      self.didEmitStart = false
    }

    public mutating func next() -> MonotonicInstant? {
      if !didEmitStart {
        didEmitStart = true
        return current
      }
      guard let interval else { return nil }
      current = current.advanced(by: interval)
      return current
    }

    public func makeIterator() -> Self { self }
  }
}

// MARK: - Static factories on the protocol

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
  /// A schedule that fires every `interval`, starting at
  /// `startInstant`.
  public static func periodic(
    from startInstant: MonotonicInstant = .now(),
    by interval: Duration
  ) -> PeriodicTimelineSchedule {
    PeriodicTimelineSchedule(from: startInstant, by: interval)
  }
}

extension TimelineSchedule where Self == AnimationTimelineSchedule {
  /// A schedule suitable for driving smooth animation; defaults to
  /// ~20 fps and throttles to ~4 fps under reduce-motion.
  public static var animation: AnimationTimelineSchedule {
    AnimationTimelineSchedule()
  }

  /// A configurable animation schedule.
  ///
  /// - Parameters:
  ///   - minimumInterval: The smallest interval the schedule will
  ///     emit at.  Passing `nil` uses the default cadence
  ///     (~50 ms / 20 fps).
  ///   - paused: When `true`, the schedule emits the start instant
  ///     and then no more entries.  The view will display a single
  ///     frame.
  public static func animation(
    minimumInterval: Duration? = nil,
    paused: Bool = false
  ) -> AnimationTimelineSchedule {
    AnimationTimelineSchedule(minimumInterval: minimumInterval, paused: paused)
  }
}

// MARK: - Tick plan (lag recovery)

/// What a ``TimelineView`` run loop should do for the next scheduled instant,
/// given how far ahead/behind wall-clock it is. Extracted as a pure function so
/// the lag-recovery decision is unit-testable without driving the async loop.
package enum TimelineTickPlan: Equatable, Sendable {
  /// The instant is in the future: sleep this long, then render it.
  case sleep(Duration)
  /// The instant is already due/past — the loop fell behind (e.g. its driver
  /// task was starved while the MainActor re-rendered). Render the *current*
  /// instant now and re-anchor the schedule grid to now, so the **next**
  /// instant is in the future and the loop suspends again before the next
  /// write. This caps the cadence at the achievable frame rate (one render per
  /// sleep) instead of replaying the backlog of past grid instants flat-out — a
  /// frame storm that never recovers, because each re-render keeps the grid
  /// behind.
  ///
  /// Re-anchoring on *any* lag (not only "more than a tick") is deliberate: the
  /// normal path stays in ``sleep(_:)`` and self-corrects small wake jitter
  /// against the grid, so this case only fires under real lag — and emitting
  /// even a single backlogged instant without first suspending is what lets a
  /// frame whose cost exceeds the interval spiral into a burst.
  case renderNowAndReanchor
}

/// Decides the next ``TimelineView`` tick action from the delay until the next
/// scheduled instant (`> 0` future, `<= 0` due/past). See ``TimelineTickPlan``.
package func timelineTickPlan(delay: Duration) -> TimelineTickPlan {
  delay > .zero ? .sleep(delay) : .renderNowAndReanchor
}

// MARK: - TimelineView

/// The per-tick context handed to a ``TimelineView``'s content
/// builder.
///
/// Lives outside `TimelineView` so that callers using trailing-closure
/// syntax don't trip Swift's generic-inference resolution — a closure
/// parameter typed `(TimelineView<...>.Context) -> Content` requires
/// the generics to be known before the closure can be type-checked,
/// which defeats the trailing-closure call site.
public struct TimelineViewContext: Sendable, Hashable {
  /// The schedule's fire instant currently being displayed.
  public let instant: MonotonicInstant
  /// The cadence hint the schedule was last asked to honor.
  public let cadence: TimelineScheduleMode

  public init(instant: MonotonicInstant, cadence: TimelineScheduleMode) {
    self.instant = instant
    self.cadence = cadence
  }
}

/// A view that re-evaluates its content at the instants supplied by a
/// ``TimelineSchedule``.
///
/// `TimelineView` is the SwiftTUI analogue of SwiftUI's `TimelineView`
/// — it lets a view compute its body from "the current time" without
/// hand-rolling a tick loop in `@State`.  Combine it with
/// ``LinearGradient`` and `Color/interpolated(to:progress:method:)` to
/// build shimmer/marquee/clock surfaces that pause cleanly when the
/// view leaves the hierarchy (the underlying `.task` cancels on
/// teardown).
///
///     TimelineView(.periodic(by: .seconds(1))) { context in
///       // Use context.instant.duration(to: .now()) for elapsed math.
///       Text("tick")
///     }
///
///     TimelineView(.animation) { context in
///       // Animation phase derived from elapsed-since-start:
///       let t = startInstant.duration(to: context.instant).totalSeconds
///       Text("hello")
///         .foregroundStyle(
///           Color.red.interpolated(
///             to: .blue,
///             progress: 0.5 + 0.5 * sin(t * 2)
///           )
///         )
///     }
///
/// The schedule's `entries(from:mode:)` is called when the view first
/// appears and after the schedule itself changes.  Under reduce-motion
/// the schedule receives ``TimelineScheduleMode/lowFrequency`` so it
/// can throttle its emissions.
public struct TimelineView<Schedule: TimelineSchedule, Content: View>: View {
  /// The schedule driving updates.
  public let schedule: Schedule
  /// The closure that produces the content for a given context.
  public let content: @MainActor (TimelineViewContext) -> Content

  // Current instant being shown.  Seeded to `.now()` at construction
  // so the first body evaluation is meaningful even before the task
  // has had a chance to run.
  @State private var currentInstant: MonotonicInstant = .now()
  // True once the .task has had a chance to advance the instant at
  // least once.  Used purely as a debug signal in tests; not exposed.
  @State private var hasAdvanced: Bool = false

  public init(
    _ schedule: Schedule,
    @ViewBuilder content:
      @escaping @MainActor (TimelineViewContext) -> Content
  ) {
    self.schedule = schedule
    self.content = content
  }

  public var body: some View {
    EnvironmentReader(\.accessibilityReduceMotion) { reduceMotion in
      timelineBody(reduceMotion: reduceMotion)
    }
  }

  @ViewBuilder
  private func timelineBody(reduceMotion: Bool) -> some View {
    let mode: TimelineScheduleMode = reduceMotion ? .lowFrequency : .normal
    let context = TimelineViewContext(instant: currentInstant, cadence: mode)
    // Touch `hasAdvanced` in body so its State slot is reliably bound
    // to this view's identity — same trick PhaseAnimator uses to make
    // sure writes from inside `.task` persist on this instance rather
    // than the global seed.
    _ = hasAdvanced
    content(context)
      .task(id: TaskKey(schedule: schedule, mode: mode)) {
        await run(mode: mode)
      }
  }

  @MainActor
  private func run(mode: TimelineScheduleMode) async {
    // The schedule produces an infinite-ish stream of fire instants.
    // We walk them in order, sleeping until each, and updating the
    // @State so the body re-resolves.
    var iterator =
      schedule
      .entries(from: .now(), mode: mode)
      .makeIterator()
    while !Task.isCancelled {
      guard let next = iterator.next() else { return }
      let now = MonotonicInstant.now()
      switch timelineTickPlan(delay: now.duration(to: next)) {
      case .sleep(let interval):
        try? await Task.sleep(for: interval)
        guard !Task.isCancelled else { return }
        currentInstant = next
      case .renderNowAndReanchor:
        // The loop fell behind (its task was starved while the MainActor
        // re-rendered). Render the current instant once, then drop the backlog
        // and re-anchor the grid to now so the next instant is in the future —
        // guaranteeing the next iteration suspends before writing again. This
        // caps the cadence at the achievable frame rate instead of replaying
        // every missed grid instant flat-out (a frame storm that never recovers
        // under render contention).
        guard !Task.isCancelled else { return }
        currentInstant = now
        iterator = schedule.entries(from: now, mode: mode).makeIterator()
        // Discard the immediate re-anchored "now" entry so the next iteration
        // resumes at `now + interval` (a future instant the loop sleeps until).
        _ = iterator.next()
      }
      hasAdvanced = true
    }
  }

  /// Stable identity for the `.task(id:)` so changing the schedule
  /// (or the cadence mode) cleanly cancels the prior loop.
  ///
  /// The key compares schedules by their own value equality rather than a
  /// hashed `Int`: a hash conflates distinct values (a constant/colliding
  /// `hash(into:)`), so a replacement schedule could silently keep the
  /// original task. `.task(id:)` requires only `Equatable`, so the key holds
  /// the schedule value and opens `Equatable` directly — an Equatable but
  /// non-Hashable schedule compares by value and SURVIVES unrelated
  /// re-resolves (F176; the previous `as? any Hashable` comparison treated
  /// every such re-resolve as a schedule change and restarted the driver).
  struct TaskKey: Equatable, Sendable {
    let schedule: Schedule
    let mode: TimelineScheduleMode

    static func == (lhs: TaskKey, rhs: TaskKey) -> Bool {
      guard lhs.mode == rhs.mode else {
        return false
      }
      guard let lhsEquatable = lhs.schedule as? any Equatable else {
        // A schedule with no Equatable conformance has no basis for value
        // comparison; treat every re-resolution as a change so a replacement
        // restarts the driver task instead of silently retaining the
        // original schedule's loop.
        return false
      }
      func open<T: Equatable>(_ lhsBase: T) -> Bool {
        guard let rhsBase = rhs.schedule as? T else {
          return false
        }
        return lhsBase == rhsBase
      }
      return open(lhsEquatable)
    }
  }
}

// MARK: - Duration → seconds helper

extension Duration {
  /// Total elapsed time expressed as a Double number of seconds.
  /// Useful for animation-phase math where Double trig/modulo is
  /// natural.  Loses sub-attosecond precision but is exact for any
  /// duration shorter than ~285 years.
  public var totalSeconds: Double {
    Double(components.seconds)
      + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }
}
