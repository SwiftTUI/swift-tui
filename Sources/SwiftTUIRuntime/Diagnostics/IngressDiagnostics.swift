import SwiftTUICore
import Synchronization

/// Ingress counters for the `frames.tsv` `ingress_*` columns (plan
/// 2026-09-24-001 §4A/§4D, STUI-618): how much input crossed each hop between
/// the source and the run loop since the previous committed frame, so a
/// backlog can be located at the source, in the reader, or in the pump rather
/// than inferred from an empty ring.
///
/// Recorded by the pull-delivery sink and the pump buffer, drained by the
/// committed-frame emit. Counting is a mutex increment per source read and
/// per pump enqueue — hundreds per second at most — so it is unconditional;
/// emission is gated by the frame sink like every other column.
package final class IngressDiagnostics: Sendable {
  private struct State: Sendable {
    var sourceBytes = 0
    var sourceReads = 0
    var sourceEvents = 0
    var pullEvents = 0
    var pumpEnqueues = 0
    var pumpHighWater = 0
  }

  private let state = Mutex(State())

  package init() {}

  /// One source read that returned data.
  package func recordSourceRead(bytes: Int, events: Int) {
    state.withLock { state in
      state.sourceBytes += bytes
      state.sourceReads += 1
      state.sourceEvents += events
    }
  }

  /// Events delivered by a run-loop turn-boundary pull (as opposed to the
  /// reader's idle poll or the stream adapter).
  package func recordPullDelivered(_ count: Int) {
    guard count > 0 else { return }
    state.withLock { $0.pullEvents += count }
  }

  /// One event enqueued into the pump buffer, with the batch depth after it.
  package func recordPumpEnqueue(depth: Int) {
    state.withLock { state in
      state.pumpEnqueues += 1
      state.pumpHighWater = max(state.pumpHighWater, depth)
    }
  }

  /// Returns the counters accumulated since the previous drain and resets
  /// them.
  package func drainCounters() -> IngressFrameCounters {
    state.withLock { state in
      let counters = IngressFrameCounters(
        sourceBytes: state.sourceBytes,
        sourceReads: state.sourceReads,
        sourceEvents: state.sourceEvents,
        pullEvents: state.pullEvents,
        pumpEnqueues: state.pumpEnqueues,
        pumpHighWater: state.pumpHighWater
      )
      state = State()
      return counters
    }
  }
}

/// Ingress counters accumulated between two committed frames.
package struct IngressFrameCounters: Sendable, Equatable {
  package var sourceBytes = 0
  package var sourceReads = 0
  package var sourceEvents = 0
  package var pullEvents = 0
  package var pumpEnqueues = 0
  package var pumpHighWater = 0

  package init(
    sourceBytes: Int = 0,
    sourceReads: Int = 0,
    sourceEvents: Int = 0,
    pullEvents: Int = 0,
    pumpEnqueues: Int = 0,
    pumpHighWater: Int = 0
  ) {
    self.sourceBytes = sourceBytes
    self.sourceReads = sourceReads
    self.sourceEvents = sourceEvents
    self.pullEvents = pullEvents
    self.pumpEnqueues = pumpEnqueues
    self.pumpHighWater = pumpHighWater
  }
}

/// What the run loop saw at one frame acquisition: the pump's depth and the
/// age of its oldest entry, and where the acquisition sat in its drain pass.
package struct IngressAcquisitionSnapshot: Sendable, Equatable {
  /// Batches waiting in the pump buffer when the frame was acquired.
  package var pumpBatches: Int
  /// Age of the oldest pending pump entry at acquisition; `nil` when the
  /// pump was empty (or no pump is attached).
  package var oldestPendingAge: Duration?
  /// 1-based index of this acquisition within its drain pass.
  package var drainPassFrameIndex: Int
  /// Frame-clock time elapsed in the drain pass at acquisition.
  package var drainPassElapsed: Duration

  package init(
    pumpBatches: Int = 0,
    oldestPendingAge: Duration? = nil,
    drainPassFrameIndex: Int = 1,
    drainPassElapsed: Duration = .zero
  ) {
    self.pumpBatches = pumpBatches
    self.oldestPendingAge = oldestPendingAge
    self.drainPassFrameIndex = drainPassFrameIndex
    self.drainPassElapsed = drainPassElapsed
  }
}

/// The ingress fields of one committed frame's sample.
package struct IngressFrameSample: Sendable, Equatable {
  package var counters: IngressFrameCounters
  package var acquisition: IngressAcquisitionSnapshot

  package init(
    counters: IngressFrameCounters = .init(),
    acquisition: IngressAcquisitionSnapshot = .init()
  ) {
    self.counters = counters
    self.acquisition = acquisition
  }
}
