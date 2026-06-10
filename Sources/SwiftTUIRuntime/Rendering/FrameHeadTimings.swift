import SwiftTUICore

package enum FrameHeadTimingField {
  case prepare
  case graphCheckpointCreate
  case graphCheckpointRestore
  case resolveCheckpointRestore
  case animationProcessResolvedTree
  case animationApplyInterpolations
}

@MainActor
package final class FrameHeadTimingRecorder {
  private let clock = ContinuousClock()
  private var timings = FrameHeadTimings()

  package init() {}

  package var snapshot: FrameHeadTimings {
    timings
  }

  package func measure<Value>(
    _ field: FrameHeadTimingField,
    _ operation: () -> Value
  ) -> Value {
    let start = clock.now
    let value = operation()
    add(start.duration(to: clock.now), to: field)
    return value
  }

  package func start() -> ContinuousClock.Instant {
    clock.now
  }

  package func record(
    _ field: FrameHeadTimingField,
    since start: ContinuousClock.Instant
  ) {
    add(start.duration(to: clock.now), to: field)
  }

  private func add(
    _ duration: Duration,
    to field: FrameHeadTimingField
  ) {
    switch field {
    case .prepare:
      timings.prepare += duration
    case .graphCheckpointCreate:
      timings.graphCheckpointCreate += duration
    case .graphCheckpointRestore:
      timings.graphCheckpointRestore += duration
    case .resolveCheckpointRestore:
      timings.resolveCheckpointRestore += duration
    case .animationProcessResolvedTree:
      timings.animationProcessResolvedTree += duration
    case .animationApplyInterpolations:
      timings.animationApplyInterpolations += duration
    }
  }
}
