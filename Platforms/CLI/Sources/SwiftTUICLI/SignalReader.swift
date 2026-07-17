#if canImport(SwiftTUIVendorUnixSignals)
  public import SwiftTUIVendorUnixSignals
  import Synchronization

  /// Reads Unix signals and exposes them as strings for the runtime.
  public final class SignalReader: SignalReading {
    private let signals: [UnixSignal]
    // Sources installed ahead of run-loop startup by armSignalSources();
    // consumed by the next events() call. Signals delivered in between are
    // buffered by the sequence's own stream.
    private let armedSequence = Mutex<UnixSignalsSequence?>(nil)

    /// Creates a signal reader for the supplied signals.
    public init(signals: [UnixSignal]? = nil) {
      self.signals = signals ?? [.sigint, .sigterm, .sigwinch]
    }

    public func events() -> AsyncStream<String> {
      let armed = armedSequence.withLock { sequence -> UnixSignalsSequence? in
        let taken = sequence
        sequence = nil
        return taken
      }
      guard let armed else {
        return UnixSignalsSequence.stream(for: signals)
      }
      return AsyncStream { continuation in
        let task = Task {
          for await signal in armed {
            continuation.yield(signal.description)
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in
          task.cancel()
        }
      }
    }
  }

  extension SignalReader: SignalSourceArming {
    package func armSignalSources() async {
      if armedSequence.withLock({ $0 != nil }) {
        return
      }
      let sequence = await UnixSignalsSequence(trapping: signals)
      armedSequence.withLock { armed in
        if armed == nil {
          armed = sequence
        }
      }
    }
  }
#endif

@_spi(Runners) public func defaultSignalReader() -> (any SignalReading)? {
  #if canImport(SwiftTUIVendorUnixSignals)
    SignalReader()
  #else
    nil
  #endif
}
