@_spi(Runners) import SwiftTUIRuntime

/// Forwards per-frame diagnostics to the web surface (and on to the browser).
/// It derives the rich record from the runtime's neutral ``RuntimeFrameSample``
/// so the runtime carries no diagnostics logger of its own.
@MainActor
final class WASIFrameDiagnosticsSink: FrameDiagnosticSink {
  private let notify: @MainActor (FrameDiagnosticRecord) -> Void

  init(notify: @escaping @MainActor (FrameDiagnosticRecord) -> Void) {
    self.notify = notify
  }

  func record(_ sample: RuntimeFrameSample) {
    notify(FrameRecordDerivation.record(from: sample))
  }
}
