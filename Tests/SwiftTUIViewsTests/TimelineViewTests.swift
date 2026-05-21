import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite("TimelineView and TimelineSchedule")
struct TimelineViewTests {

  // MARK: - PeriodicTimelineSchedule

  @Test("PeriodicTimelineSchedule emits instants at the configured interval")
  func periodicEmitsAtInterval() {
    let start = MonotonicInstant(offset: .zero)
    let schedule = PeriodicTimelineSchedule(from: start, by: .milliseconds(500))

    let instants = Array(
      schedule.entries(from: start, mode: .normal)
        .prefix(4)
    )

    #expect(instants.count == 4)
    #expect(instants[0] == start)
    #expect(instants[1] == start.advanced(by: .milliseconds(500)))
    #expect(instants[2] == start.advanced(by: .seconds(1)))
    #expect(instants[3] == start.advanced(by: .milliseconds(1500)))
  }

  @Test("PeriodicTimelineSchedule snaps the first entry to the schedule grid")
  func periodicSnapsToGrid() {
    // Schedule starts at t=0 with a 1-second interval; the timeline
    // begins at t=2.4 s, so the first emission should be t=3.0 s (the
    // next multiple of 1 second at or after 2.4 s).
    let scheduleStart = MonotonicInstant(offset: .zero)
    let timelineStart = MonotonicInstant(offset: .milliseconds(2400))
    let schedule = PeriodicTimelineSchedule(from: scheduleStart, by: .seconds(1))

    var iter = schedule.entries(from: timelineStart, mode: .normal).makeIterator()
    let first = iter.next()

    #expect(first == MonotonicInstant(offset: .seconds(3)))
  }

  @Test("PeriodicTimelineSchedule throttles in low-frequency mode")
  func periodicLowFrequencyThrottles() {
    // Sub-second interval should be floor-clamped to 1 second under
    // reduce-motion so that low-frequency hosts don't keep redrawing.
    let start = MonotonicInstant(offset: .zero)
    let schedule = PeriodicTimelineSchedule(from: start, by: .milliseconds(100))

    let instants = Array(
      schedule.entries(from: start, mode: .lowFrequency)
        .prefix(3)
    )

    #expect(instants[0].duration(to: instants[1]) == .seconds(1))
    #expect(instants[1].duration(to: instants[2]) == .seconds(1))
  }

  @Test("PeriodicTimelineSchedule keeps an explicit interval larger than the floor")
  func periodicLowFrequencyKeepsLargerExplicitInterval() {
    let start = MonotonicInstant(offset: .zero)
    let schedule = PeriodicTimelineSchedule(from: start, by: .seconds(5))

    let instants = Array(
      schedule.entries(from: start, mode: .lowFrequency)
        .prefix(2)
    )

    #expect(instants[0].duration(to: instants[1]) == .seconds(5))
  }

  // MARK: - AnimationTimelineSchedule

  @Test("AnimationTimelineSchedule defaults to ~20 fps cadence")
  func animationDefaultCadence() {
    let start = MonotonicInstant(offset: .zero)
    let schedule = AnimationTimelineSchedule()

    let instants = Array(
      schedule.entries(from: start, mode: .normal)
        .prefix(3)
    )

    #expect(instants[0] == start)
    #expect(instants[0].duration(to: instants[1]) == .milliseconds(50))
    #expect(instants[1].duration(to: instants[2]) == .milliseconds(50))
  }

  @Test("AnimationTimelineSchedule honors an explicit minimum interval")
  func animationExplicitMinimumInterval() {
    let start = MonotonicInstant(offset: .zero)
    let schedule = AnimationTimelineSchedule(minimumInterval: .milliseconds(200))

    let instants = Array(
      schedule.entries(from: start, mode: .normal)
        .prefix(2)
    )

    #expect(instants[0].duration(to: instants[1]) == .milliseconds(200))
  }

  @Test("AnimationTimelineSchedule throttles to ~4 fps under low-frequency")
  func animationLowFrequencyCadence() {
    let start = MonotonicInstant(offset: .zero)
    let schedule = AnimationTimelineSchedule()

    let instants = Array(
      schedule.entries(from: start, mode: .lowFrequency)
        .prefix(2)
    )

    #expect(instants[0].duration(to: instants[1]) == .milliseconds(250))
  }

  @Test("AnimationTimelineSchedule respects a coarser explicit minimum under low-frequency")
  func animationLowFrequencyKeepsCoarserExplicit() {
    let start = MonotonicInstant(offset: .zero)
    let schedule = AnimationTimelineSchedule(minimumInterval: .milliseconds(500))

    let instants = Array(
      schedule.entries(from: start, mode: .lowFrequency)
        .prefix(2)
    )

    #expect(instants[0].duration(to: instants[1]) == .milliseconds(500))
  }

  @Test("AnimationTimelineSchedule paused emits exactly one frame")
  func animationPausedEmitsOnce() {
    let start = MonotonicInstant(offset: .zero)
    let schedule = AnimationTimelineSchedule(paused: true)

    let instants = Array(
      schedule.entries(from: start, mode: .normal)
        .prefix(5)
    )

    #expect(instants == [start])
  }

  // MARK: - Static factories

  @Test("Static factory .periodic produces an equivalent PeriodicTimelineSchedule")
  func staticFactoryPeriodic() {
    let start = MonotonicInstant(offset: .zero)
    let viaFactory: PeriodicTimelineSchedule = .periodic(
      from: start,
      by: .milliseconds(250)
    )
    let direct = PeriodicTimelineSchedule(from: start, by: .milliseconds(250))

    #expect(viaFactory == direct)
  }

  @Test("Static factory .animation produces a default AnimationTimelineSchedule")
  func staticFactoryAnimation() {
    let viaFactory: AnimationTimelineSchedule = .animation
    #expect(viaFactory == AnimationTimelineSchedule())
  }

  @Test("Static factory .animation(minimumInterval:paused:) wires through")
  func staticFactoryAnimationConfigured() {
    let viaFactory: AnimationTimelineSchedule = .animation(
      minimumInterval: .milliseconds(100),
      paused: true
    )
    #expect(
      viaFactory
        == AnimationTimelineSchedule(
          minimumInterval: .milliseconds(100),
          paused: true
        )
    )
  }

  // MARK: - Context

  @Test("TimelineViewContext is constructible and exposes its fields")
  func contextFields() {
    let start = MonotonicInstant(offset: .milliseconds(42))
    let context = TimelineViewContext(
      instant: start,
      cadence: .normal
    )
    #expect(context.instant == start)
    #expect(context.cadence == .normal)
  }

  // MARK: - Duration helper

  @Test("Duration.totalSeconds extracts a Double seconds value")
  func durationTotalSeconds() {
    #expect(Duration.seconds(1).totalSeconds == 1.0)
    #expect(Duration.milliseconds(500).totalSeconds == 0.5)
    #expect(Duration.milliseconds(2500).totalSeconds == 2.5)
    #expect(Duration.zero.totalSeconds == 0.0)
  }
}
