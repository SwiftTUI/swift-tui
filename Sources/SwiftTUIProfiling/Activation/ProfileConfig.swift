/// Selects which profiling signals run, with what cadence, and where their
/// records go. Every signal is off unless explicitly named.
public struct ProfileConfig: Sendable, Equatable {
  /// A profiling signal. `frames` is event-driven (one record per committed
  /// frame); `memory` and `cpu` are periodic with an explicit interval.
  public enum Signal: Sendable, Hashable {
    case frames
    case memory(interval: Duration)
    case cpu(interval: Duration)
  }

  /// A sink the `SWIFTTUI_PROFILE` grammar can name. The in-process handler
  /// sink used by the package's programmatic activation seam is internal and
  /// not grammar-nameable, so it has no descriptor here.
  public enum SinkDescriptor: Sendable, Equatable {
    /// Append each record as a row to a tab-separated file at `path`.
    case tsv(path: String)
    /// Append each record as a line of JSON to a file at `path`.
    case jsonl(path: String)
    /// Buffer records and emit one reduced report to stderr on
    /// ``ProfileActivation/finish()``.
    case summary
  }

  /// The signals to run. Empty means activation is a no-op.
  public var signals: Set<Signal>
  /// Where records go. Empty falls back to a stderr ``SinkDescriptor/summary``.
  public var sinks: [SinkDescriptor]

  /// Creates a config that runs `signals` and routes their records to `sinks`.
  public init(signals: Set<Signal>, sinks: [SinkDescriptor]) {
    self.signals = signals
    self.sinks = sinks
  }

  /// Default cadence for `memory` when none is given in the grammar.
  public static let defaultMemoryInterval: Duration = .seconds(1)
  /// Default cadence for `cpu` when none is given in the grammar.
  public static let defaultCPUInterval: Duration = .milliseconds(250)
}
