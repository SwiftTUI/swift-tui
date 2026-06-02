package struct ElidedFrameTimings: Equatable, Sendable {
  package var headTotal: Duration?
  package var graphCheckpointCreate: Duration?
  package var graphCheckpointRestore: Duration?
  package var resolveCheckpointRestore: Duration?
  package var animationTick: Duration?
  package var commitRuntimeRegistrations: Duration?
  package var animationCommit: Duration?
  package var commit: Duration?

  package init(
    headTotal: Duration? = nil,
    graphCheckpointCreate: Duration? = nil,
    graphCheckpointRestore: Duration? = nil,
    resolveCheckpointRestore: Duration? = nil,
    animationTick: Duration? = nil,
    commitRuntimeRegistrations: Duration? = nil,
    animationCommit: Duration? = nil,
    commit: Duration? = nil
  ) {
    self.headTotal = headTotal
    self.graphCheckpointCreate = graphCheckpointCreate
    self.graphCheckpointRestore = graphCheckpointRestore
    self.resolveCheckpointRestore = resolveCheckpointRestore
    self.animationTick = animationTick
    self.commitRuntimeRegistrations = commitRuntimeRegistrations
    self.animationCommit = animationCommit
    self.commit = commit
  }

  package static let empty = ElidedFrameTimings()

  package mutating func add(_ duration: Duration, for field: Field) {
    switch field {
    case .headTotal:
      headTotal = (headTotal ?? .zero) + duration
    case .graphCheckpointCreate:
      graphCheckpointCreate = (graphCheckpointCreate ?? .zero) + duration
    case .graphCheckpointRestore:
      graphCheckpointRestore = (graphCheckpointRestore ?? .zero) + duration
    case .resolveCheckpointRestore:
      resolveCheckpointRestore = (resolveCheckpointRestore ?? .zero) + duration
    case .animationTick:
      animationTick = (animationTick ?? .zero) + duration
    case .commitRuntimeRegistrations:
      commitRuntimeRegistrations = (commitRuntimeRegistrations ?? .zero) + duration
    case .animationCommit:
      animationCommit = (animationCommit ?? .zero) + duration
    case .commit:
      commit = (commit ?? .zero) + duration
    }
  }

  package enum Field {
    case headTotal
    case graphCheckpointCreate
    case graphCheckpointRestore
    case resolveCheckpointRestore
    case animationTick
    case commitRuntimeRegistrations
    case animationCommit
    case commit
  }
}

@MainActor
package final class ElidedFrameTimingRecorder {
  package var isEnabled = false
  private let clock = ContinuousClock()
  private var timings = ElidedFrameTimings.empty

  package init() {}

  package func reset() {
    timings = .empty
  }

  package var snapshot: ElidedFrameTimings {
    isEnabled ? timings : .empty
  }

  package func measure<Value>(
    _ field: ElidedFrameTimings.Field,
    _ operation: () -> Value
  ) -> Value {
    guard isEnabled else {
      return operation()
    }
    let start = clock.now
    let value = operation()
    timings.add(start.duration(to: clock.now), for: field)
    return value
  }

  package func start() -> ContinuousClock.Instant? {
    guard isEnabled else {
      return nil
    }
    return clock.now
  }

  package func record(
    _ field: ElidedFrameTimings.Field,
    since start: ContinuousClock.Instant?
  ) {
    guard isEnabled, let start else {
      return
    }
    timings.add(start.duration(to: clock.now), for: field)
  }
}
