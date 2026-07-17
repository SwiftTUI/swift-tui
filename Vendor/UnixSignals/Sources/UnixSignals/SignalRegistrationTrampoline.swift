// © GoodHatsLLC

// SwiftTUI addition to the vendored UnixSignals package.
//
// On Darwin a signal's disposition must be non-default before its kqueue
// DispatchSource can observe it (EVFILT_SIGNAL has lower precedence than
// signal/sigaction). Upstream sets `SIG_IGN` before creating each source,
// but an ignored signal that arrives while the sources are still
// registering is discarded by the kernel with no pending trace — the
// process neither terminates nor ever learns about it. The trampoline
// keeps a recording handler installed for exactly that window and replays
// recorded signals through the armed kqueue sources afterwards.

#if canImport(Darwin)
  import Darwin
  import Synchronization

  /// One bit per signal number, set from the signal handler. The handler may
  /// only perform a lock-free atomic RMW — no allocation, no locks.
  private let recordedSignalBits = Atomic<UInt64>(0)

  private func signalRegistrationRecordingHandler(_ signalNumber: Int32) {
    guard signalNumber > 0, signalNumber < 64 else { return }
    _ = recordedSignalBits.bitwiseOr(
      UInt64(1) << UInt64(signalNumber),
      ordering: .sequentiallyConsistent
    )
  }

  package enum SignalRegistrationTrampoline {
    /// Test seam: fires after the recording handlers are installed and before
    /// source registration is awaited — the window this type exists to cover.
    nonisolated(unsafe) package static var registrationGapHookForTesting: (@Sendable () -> Void)?

    /// Installs the recording handler in place of the default disposition.
    /// Called where upstream called `signal(sig, SIG_IGN)`.
    static func install(for signalNumber: Int32) {
      var action = sigaction()
      // __sigaction_u is a C union; assigning into one of its members has
      // no static type-safety guarantee, so this write is genuinely unsafe.
      unsafe action.__sigaction_u.__sa_handler = signalRegistrationRecordingHandler
      action.sa_flags = 0
      unsafe sigemptyset(&action.sa_mask)
      unsafe sigaction(signalNumber, &action, nil)
    }

    /// Swaps each recording handler for `SIG_IGN` — the registered kqueue
    /// sources own delivery from here — and replays any signal recorded
    /// while registration was in flight. Replaying with kill(2) after the
    /// swap routes the signal through EVFILT_SIGNAL, the same path live
    /// signals take. A signal that races the swap can be delivered twice;
    /// sequence consumers must treat delivery as idempotent (SIGINT/SIGTERM/
    /// SIGWINCH all are).
    static func handOffToKqueue(signalNumbers: [Int32]) {
      var mask: UInt64 = 0
      for signalNumber in signalNumbers where signalNumber > 0 && signalNumber < 64 {
        signal(signalNumber, SIG_IGN)
        mask |= UInt64(1) << UInt64(signalNumber)
      }
      // Clear only this sequence's bits; concurrent sequences trapping other
      // signals keep theirs.
      let recorded =
        recordedSignalBits.bitwiseAnd(
          ~mask,
          ordering: .sequentiallyConsistent
        ).oldValue & mask
      for signalNumber in signalNumbers
      where recorded & (UInt64(1) << UInt64(signalNumber)) != 0 {
        kill(getpid(), signalNumber)  // ignore-unacceptable-language
      }
    }

    /// Restores `SIG_IGN` for signals whose registration was cancelled,
    /// leaving the same disposition the pre-trampoline code did after a
    /// cancelled init.
    static func abandon(signalNumbers: [Int32]) {
      for signalNumber in signalNumbers {
        signal(signalNumber, SIG_IGN)
      }
    }
  }
#endif
