/// Selects which profiling signals run, with what cadence, and where their
/// records go. Every signal is off unless explicitly named.
package struct ProfileConfig: Sendable, Equatable {
  /// A profiling signal. `frames` is event-driven (one record per committed
  /// frame); `memory` and `cpu` are periodic with an explicit interval.
  package enum Signal: Sendable, Hashable {
    case frames
    case memory(interval: Duration)
    case cpu(interval: Duration)
  }

  /// A sink the `SWIFTTUI_PROFILE` grammar can name. The in-process `handler`
  /// sink is programmatic-only and is therefore not represented here.
  package enum SinkDescriptor: Sendable, Equatable {
    case tsv(path: String)
    case jsonl(path: String)
    case summary
  }

  package var signals: Set<Signal>
  package var sinks: [SinkDescriptor]

  package init(signals: Set<Signal>, sinks: [SinkDescriptor]) {
    self.signals = signals
    self.sinks = sinks
  }

  /// Default cadence for `memory` when none is given in the grammar.
  package static let defaultMemoryInterval: Duration = .seconds(1)
  /// Default cadence for `cpu` when none is given in the grammar.
  package static let defaultCPUInterval: Duration = .milliseconds(250)
}
