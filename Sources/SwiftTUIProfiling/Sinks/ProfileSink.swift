package import SwiftTUICore
package import SwiftTUIRuntime

/// One profiling observation, tagged by signal. `frame` is the derived
/// per-frame record; `memory` is a full occupancy snapshot set; `cpu` is one
/// CPU/RSS sample.
package enum ProfileRecord: Sendable {
  case frame(FrameDiagnosticRecord)
  case memory([MemoryMetricSnapshot])
  case cpu(CPUSample)
}

/// A multi-signal profiling sink. Activation fans every emitted record out to
/// the configured sinks and calls ``finish()`` once at process exit so buffered
/// sinks can flush a reduced report.
package protocol ProfileSink: Sendable {
  @MainActor func emit(_ record: ProfileRecord)
  @MainActor func finish()
}

extension ProfileSink {
  @MainActor package func finish() {}
}
