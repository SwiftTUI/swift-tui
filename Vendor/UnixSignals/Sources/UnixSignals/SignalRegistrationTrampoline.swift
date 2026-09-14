// © OPTIONAL.DEV

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

  /// One bit per signal number. The handler uses lock-free atomics and
  /// async-signal-safe POSIX calls only — no allocation, no locks.
  private let recordedSignalBits = Atomic<UInt64>(0)
  private let armedSignalBits = Atomic<UInt64>(0)

  private func signalRegistrationRecordingHandler(_ signalNumber: Int32) {
    guard signalNumber > 0, signalNumber < 64 else { return }
    let savedErrno = errno
    defer { errno = savedErrno }
    _ = recordedSignalBits.bitwiseOr(
      UInt64(1) << UInt64(signalNumber),
      ordering: .sequentiallyConsistent
    )
    if armedSignalBits.load(ordering: .sequentiallyConsistent)
      & (UInt64(1) << UInt64(signalNumber)) != 0
    {
      replayRecordedSignal(signalNumber)
    }
  }

  private func replayRecordedSignal(_ signalNumber: Int32) {
    let bit = UInt64(1) << UInt64(signalNumber)
    guard
      recordedSignalBits.bitwiseAnd(~bit, ordering: .sequentiallyConsistent).oldValue
        & bit != 0
    else { return }

    var action = sigaction()
    unsafe action.__sigaction_u.__sa_handler = SIG_IGN
    unsafe sigemptyset(&action.sa_mask)
    unsafe sigaction(signalNumber, &action, nil)
    kill(getpid(), signalNumber)  // ignore-unacceptable-language
  }

  package enum SignalRegistrationTrampoline {
    /// Test seam: fires after the recording handlers are installed and before
    /// source registration is awaited — the window this type exists to cover.
    nonisolated(unsafe) package static var registrationGapHookForTesting: (@Sendable () -> Void)?

    /// Installs the recording handler in place of the default disposition.
    /// Called where upstream called `signal(sig, SIG_IGN)`.
    static func install(for signalNumber: Int32) {
      let bit = UInt64(1) << UInt64(signalNumber)
      // Initialize/reset both atomics before a signal can enter the handler.
      _ = armedSignalBits.bitwiseAnd(~bit, ordering: .sequentiallyConsistent)
      _ = recordedSignalBits.bitwiseAnd(~bit, ordering: .sequentiallyConsistent)
      var action = sigaction()
      // __sigaction_u is a C union; assigning into one of its members has
      // no static type-safety guarantee, so this write is genuinely unsafe.
      unsafe action.__sigaction_u.__sa_handler = signalRegistrationRecordingHandler
      action.sa_flags = 0
      unsafe sigemptyset(&action.sa_mask)
      unsafe sigaction(signalNumber, &action, nil)
    }

    /// Arms replay before checking recorded receipts. A queued signal may not
    /// have entered its handler yet: switching it to SIG_IGN now would discard
    /// it. Leave the recording handler installed until either this handoff or
    /// the delayed handler claims a receipt and replays it through kqueue.
    /// A signal observed by both mechanisms may be delivered twice; consumers
    /// must treat delivery as idempotent (SIGINT/SIGTERM/SIGWINCH all are).
    static func handOffToKqueue(signalNumbers: [Int32]) {
      var mask: UInt64 = 0
      for signalNumber in signalNumbers where signalNumber > 0 && signalNumber < 64 {
        mask |= UInt64(1) << UInt64(signalNumber)
      }
      _ = armedSignalBits.bitwiseOr(mask, ordering: .sequentiallyConsistent)
      for signalNumber in signalNumbers where signalNumber > 0 && signalNumber < 64 {
        replayRecordedSignal(signalNumber)
      }
    }

    /// Restores `SIG_IGN` for signals whose registration was cancelled,
    /// leaving the same disposition the pre-trampoline code did after a
    /// cancelled init.
    static func abandon(signalNumbers: [Int32]) {
      for signalNumber in signalNumbers {
        signal(signalNumber, SIG_IGN)
        let bit = UInt64(1) << UInt64(signalNumber)
        _ = armedSignalBits.bitwiseAnd(~bit, ordering: .sequentiallyConsistent)
        _ = recordedSignalBits.bitwiseAnd(~bit, ordering: .sequentiallyConsistent)
      }
    }
  }
#endif
