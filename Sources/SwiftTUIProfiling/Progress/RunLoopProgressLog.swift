@_spi(Runners) package import SwiftTUIRuntime

/// The profiling product's run-loop progress event log. This is the perf half
/// of the old probe: it conforms to the runtime's ``RunLoopProgressObserver``
/// and retains every forwarded event. Install it into
/// `ProfilingRegistry.shared.progressObserver` to begin capturing; the runtime
/// keeps its own quiescence/await mechanism independently.
@MainActor
package final class RunLoopProgressLog: RunLoopProgressObserver {
  private var recorded: [RunLoopProgressEvent] = []

  package init() {}

  package var events: [RunLoopProgressEvent] {
    recorded
  }

  package func record(_ event: RunLoopProgressEvent) {
    recorded.append(event)
  }

  package func clear() {
    recorded.removeAll(keepingCapacity: true)
  }

  /// Installs this log as the active progress observer and returns it for
  /// convenience.
  @discardableResult
  package static func install() -> RunLoopProgressLog {
    let log = RunLoopProgressLog()
    ProfilingRegistry.shared.progressObserver = log
    return log
  }
}
