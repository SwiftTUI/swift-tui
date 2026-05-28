import SwiftTUICore

/// Temporary bridge that lets the legacy ``FrameDiagnosticsLogger`` satisfy the
/// new ``FrameDiagnosticSink`` contract: it derives a record from the raw
/// sample and forwards it to the logger. Removed in phase 2 once record
/// derivation and the TSV logger move into `SwiftTUIProfiling`.
@MainActor
final class FrameDiagnosticsLoggerSink: FrameDiagnosticSink {
  private let logger: FrameDiagnosticsLogger

  init(_ logger: FrameDiagnosticsLogger) {
    self.logger = logger
  }

  func record(_ sample: RuntimeFrameSample) {
    logger.log(FrameRecordDerivation.record(from: sample))
  }
}
