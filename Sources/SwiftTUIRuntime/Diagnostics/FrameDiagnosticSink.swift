import SwiftTUICore

/// Neutral per-frame emit contract between the runtime and the profiling
/// product.
///
/// The runtime calls ``record(_:)`` once per committed, cancelled, or dropped
/// frame and passes a flat ``RuntimeFrameSample``.
/// The sink (the profiling product) owns all derivation, formatting, and persistence.
/// Thus, the runtime gathers only the raw inputs.
/// It does no diagnostic work when no sink is installed.
@_spi(Runners) public protocol FrameDiagnosticSink: Sendable {
  @MainActor func record(_ sample: RuntimeFrameSample)
}
