#if os(macOS) || os(iOS) || os(Linux) || os(Android)
  @_exported public import SwiftTUIPlatformIO
  import SwiftTUIVendorUnixSignals
  import Synchronization
  import SwiftTUIRuntime

  /// Reads Unix signals and exposes them as strings for the runtime.
  public final class SignalReader: SignalReading {
    private let signals: [TerminalSignal]
    // Sources installed ahead of run-loop startup by armSignalSources();
    // consumed by the next events() call. Signals delivered in between are
    // buffered by the sequence's own stream.
    private let armedSequence = Mutex<UnixSignalsSequence?>(nil)

    /// Creates a signal reader for the supplied signals.
    public init(signals: [TerminalSignal]? = nil) {
      var defaults: [TerminalSignal] = [.sigint, .sigterm, .sigwinch]
      #if DEBUG && (os(macOS) || os(Linux))
        if let spool = FeatureFlags.environmentValue(.hotReloadSpool),
          !spool.isEmpty
        {
          defaults.append(.sigusr1)
        }
      #endif
      self.signals = signals ?? defaults
    }

    public func events() -> AsyncStream<String> { stream { $0.description } }
    public func runtimeSignals() -> AsyncStream<RuntimeSignal> { stream { $0.runtimeSignal } }

    private func stream<Element: Sendable>(
      _ transform: @escaping @Sendable (TerminalSignal) -> Element
    ) -> AsyncStream<Element> {
      let armed = armedSequence.withLock { sequence in
        let taken = sequence
        sequence = nil
        return taken
      }
      let signals = self.signals
      return makeTaskBackedAsyncStream { continuation in
        let sequence: UnixSignalsSequence
        if let armed {
          sequence = armed
        } else {
          sequence = await UnixSignalsSequence(trapping: signals)
        }
        for await signal in sequence { continuation.yield(transform(signal)) }
        continuation.finish()
      }
    }

  }

  extension TerminalSignal {
    fileprivate var runtimeSignal: RuntimeSignal {
      switch self {
      case .sigabrt: .abort
      case .sighup: .hangup
      case .sigill: .illegalInstruction
      case .sigint: .interrupt
      case .sigsegv: .segmentationFault
      case .sigterm: .terminate
      case .sigusr1: .user1
      case .sigusr2: .user2
      case .sigalrm: .alarm
      case .sigquit: .quit
      case .sigwinch: .windowChange
      case .sigbus: .busError
      case .sigfpe: .floatingPointException
      case .sigtrap: .trap
      case .sigcont: .resume
      case .sigpipe: .brokenPipe
      default: .other(description)
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
  #if os(macOS) || os(iOS) || os(Linux) || os(Android)
    SignalReader()
  #else
    nil
  #endif
}
