// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises a
// POSIX-only subsystem whose modules build empty (or not at all) on Windows.
#if !os(Windows)

  // © OPTIONAL.DEV

  #if canImport(Darwin)
    import Darwin
    import Dispatch
    import Foundation
    @testable import SwiftTUIVendorUnixSignals
    import Testing

    // Joins UnixSignalTests so the shared `.serialized` trait keeps this raise
    // from racing the other suites' process-global signal traps.
    extension UnixSignalTests {
      @Test
      func signalPendingUntilAfterRegistrationIsDelivered() async {
        // Darwin rejects pthread_kill on cooperative-pool threads. Keep the
        // thread-specific mask and pending signal on one dedicated thread.
        let failures: [String] = await withCheckedContinuation { continuation in
          Thread.detachNewThread {
            continuation.resume(returning: Self.checkPendingSignalHandoff())
          }
        }
        #expect(failures.isEmpty, "\(failures)")
      }

      private static func checkPendingSignalHandoff() -> [String] {
        var failures: [String] = []
        let signalNumber = SIGUSR2
        var blocked = sigset_t()
        var previousMask = sigset_t()
        unsafe sigemptyset(&blocked)
        unsafe sigaddset(&blocked, signalNumber)
        guard unsafe pthread_sigmask(SIG_BLOCK, &blocked, &previousMask) == 0 else {
          return ["could not block signal"]
        }
        defer { _ = unsafe pthread_sigmask(SIG_SETMASK, &previousMask, nil) }

        SignalRegistrationTrampoline.install(for: signalNumber)
        // Thread-directed delivery stays pending on this synchronous test's thread.
        // No handler can record it before the registration handoff below.
        guard unsafe pthread_kill(pthread_self(), signalNumber) == 0 else {
          return ["could not queue signal"]
        }
        var pending = sigset_t()
        if unsafe sigpending(&pending) != 0 || sigismember(&pending, signalNumber) != 1 {
          failures.append("signal was not pending before registration")
        }

        let registered = DispatchSemaphore(value: 0)
        let received = DispatchSemaphore(value: 0)
        let source = DispatchSource.makeSignalSource(
          signal: signalNumber, queue: DispatchQueue.global())
        source.setRegistrationHandler { registered.signal() }
        source.setEventHandler { received.signal() }
        source.resume()
        defer { source.cancel() }
        if registered.wait(timeout: .now() + 5) != .success {
          failures.append("source did not register")
        }
        if received.wait(timeout: .now()) != .timedOut {
          failures.append("source received signal before handoff")
        }

        SignalRegistrationTrampoline.handOffToKqueue(signalNumbers: [signalNumber])
        if unsafe pthread_sigmask(SIG_UNBLOCK, &blocked, nil) != 0 {
          failures.append("could not unblock signal")
        }
        if received.wait(timeout: .now() + 5) != .success {
          failures.append("pending signal was lost during handoff")
        }
        return failures
      }

      /// Raises a signal inside the registration window — after the recording
      /// trampoline replaces the default disposition, before the kqueue
      /// sources finish registering — and expects the sequence to deliver it.
      ///
      /// Pre-trampoline code installed `SIG_IGN` for that window, so the
      /// kernel discarded the signal: the process neither terminated nor ever
      /// observed it, and this test would hang until the time limit.
      @Test(.timeLimit(.minutes(1)))
      func signalRaisedDuringRegistrationWindowIsDelivered() async {
        let signal = UnixSignal.sigusr2
        let pid = getpid()
        unsafe SignalRegistrationTrampoline.registrationGapHookForTesting = {
          kill(pid, signal.rawValue)  // ignore-unacceptable-language
        }
        defer {
          unsafe SignalRegistrationTrampoline.registrationGapHookForTesting = nil
        }

        let signals = await UnixSignalsSequence(trapping: signal)
        var signalIterator = signals.makeAsyncIterator()
        let caught = await signalIterator.next()
        #expect(caught == signal)
      }
    }
  #endif

#endif
