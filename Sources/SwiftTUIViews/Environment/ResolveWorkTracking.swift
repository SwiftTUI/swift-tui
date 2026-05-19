package import SwiftTUICore
import Synchronization

// Bookkeeping objects threaded through a resolve pass.
//
// A `ResolveContext` carries these reference types so resolution can record
// how much work it did and route invalidation requests back to the runtime.
// They are split out of `Environment.swift` so that file stays focused on the
// environment values and `ResolveContext` itself.

/// Thread-safe counter for resolved-node computation vs. reuse during a
/// resolve pass; the totals feed frame diagnostics.
package final class ResolveWorkTracker: Sendable {
  private let workMetrics: Mutex<ResolveWorkMetrics>

  package init(
    workMetrics: ResolveWorkMetrics = .init()
  ) {
    self.workMetrics = Mutex(workMetrics)
  }

  package func recordResolvedComputation(
    count: Int = 1
  ) {
    workMetrics.withLock { workMetrics in
      workMetrics.resolvedNodesComputed += max(0, count)
    }
  }

  package func recordResolvedReuse(
    count: Int = 1
  ) {
    workMetrics.withLock { workMetrics in
      workMetrics.resolvedNodesReused += max(0, count)
    }
  }

  package var snapshot: ResolveWorkMetrics {
    workMetrics.withLock { $0 }
  }
}

/// Weak handle to the runtime invalidator, so resolution can request a
/// re-render without retaining the run loop.
@MainActor
package final class ResolveInvalidationProxy {
  package weak var invalidator: (any Invalidating)?

  package init(
    invalidator: (any Invalidating)? = nil
  ) {
    self.invalidator = invalidator
  }
}
