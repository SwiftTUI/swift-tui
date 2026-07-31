import Synchronization

/// Process-wide hand-off point between the runtime and the profiling product.
///
/// The product's `.profiling()` activation installs a ``FrameDiagnosticSink``
/// here before the first session is built; the runtime consults the registry
/// when constructing each `SceneSession` and wires the installed sink onto the
/// run loop. When nothing is installed the registry holds `nil`, the run loop's
/// per-frame emit stays a single branch, and no profiling work runs.
package final class ProfilingRegistry: Sendable {
  package static let shared = ProfilingRegistry()

  private struct State {
    var frameSink: (any FrameDiagnosticSink)?
    var progressObserver: (any RunLoopProgressObserver)?
    var presentationWriteSink: (any PresentationWriteSink)?
  }

  private let state = Mutex(State())

  package init() {}

  package var frameSink: (any FrameDiagnosticSink)? {
    get { state.withLock { $0.frameSink } }
    set { state.withLock { $0.frameSink = newValue } }
  }

  package var progressObserver: (any RunLoopProgressObserver)? {
    get { state.withLock { $0.progressObserver } }
    set { state.withLock { $0.progressObserver = newValue } }
  }

  /// Sink for per-submission terminal write records (`presents.tsv`).
  /// Read once by each ``TerminalPresentationWriter`` at construction, so it
  /// must be installed before the first frame is presented — which the
  /// profiling product's activation guarantees.
  package var presentationWriteSink: (any PresentationWriteSink)? {
    get { state.withLock { $0.presentationWriteSink } }
    set { state.withLock { $0.presentationWriteSink = newValue } }
  }
}
