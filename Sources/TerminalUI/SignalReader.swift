#if canImport(UnixSignals)
  public import UnixSignals

  /// Reads Unix signals and exposes them as strings for the runtime.
  public final class SignalReader: SignalReading {
    private let signals: [UnixSignal]

    /// Creates a signal reader for the supplied signals.
    public init(signals: [UnixSignal]? = nil) {
      self.signals = signals ?? [.sigint, .sigterm, .sigwinch]
    }

    public func events() -> AsyncStream<String> {
      UnixSignalsSequence.stream(for: signals)
    }
  }
#endif

package func defaultSignalReader() -> (any SignalReading)? {
  #if canImport(UnixSignals)
    SignalReader()
  #else
    nil
  #endif
}
