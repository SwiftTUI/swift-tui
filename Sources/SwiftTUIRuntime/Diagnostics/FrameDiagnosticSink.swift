import SwiftTUICore

/// Neutral per-frame emit contract between the runtime and the profiling
/// product.
///
/// The runtime calls ``record(_:)`` once per committed, cancelled, or dropped
/// frame, passing a flat ``RuntimeFrameSample``. All derivation, formatting,
/// and persistence belong to the sink (the profiling product), so the runtime
/// pays only for gathering raw inputs — and nothing at all when no sink is
/// installed.
@_spi(Runners) public protocol FrameDiagnosticSink: Sendable {
  @MainActor func record(_ sample: RuntimeFrameSample)
}
