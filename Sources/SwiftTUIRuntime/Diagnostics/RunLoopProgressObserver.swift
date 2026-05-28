import SwiftTUICore

/// Receives the run loop's progress events for *perf* consumption (an
/// append-only event log), separate from the run loop's *quiescence* mechanism.
///
/// `RunLoopProgressProbe` keeps the await/quiescence role in the runtime (tests
/// synchronize on it without linking a profiling product); the runtime
/// additionally forwards every recorded event to the observer installed in
/// ``ProfilingRegistry``, which the profiling product implements as its event
/// log.
package protocol RunLoopProgressObserver: Sendable {
  @MainActor func record(_ event: RunLoopProgressEvent)
}
