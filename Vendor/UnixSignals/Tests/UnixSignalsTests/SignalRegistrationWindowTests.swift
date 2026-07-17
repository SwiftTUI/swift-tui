// © GoodHatsLLC

#if canImport(Darwin)
  import Darwin
  import SwiftTUIVendorUnixSignals
  import Testing

  // Joins UnixSignalTests so the shared `.serialized` trait keeps this raise
  // from racing the other suites' process-global signal traps.
  extension UnixSignalTests {
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
