// © GoodHatsLLC
//
// Synchronous crash signal handler for terminal reset on fatal signals.
// Unlike UnixSignalsSequence (which uses Dispatch for async delivery),
// this installs raw sigaction handlers that fire synchronously when
// the process is dying — the only way to clean up terminal state on
// crashes like SIGABRT, SIGSEGV, etc.

#if canImport(Darwin)
  public import Darwin
#elseif canImport(Glibc)
  public import Glibc
#elseif canImport(Musl)
  public import Musl
#elseif canImport(Android)
  public import Android
#endif

#if !os(Windows) && !os(WASI)

  // ---------------------------------------------------------------------------
  // MARK: - Global state for the signal handler
  // ---------------------------------------------------------------------------
  //
  // Signal handlers are C function pointers — they cannot capture context.
  // All state must be file-scope globals. This is safe because:
  //   - Writes happen only from install()/uninstall() on the calling thread
  //   - The signal handler only reads, and runs after the writing thread has
  //     completed installation (the sigaction call is the barrier)
  //   - SA_RESETHAND ensures the handler fires at most once

  /// Maximum number of reset bytes we can store (more than enough for
  /// any terminal escape sequence combination).
  private let crashResetMaxBytes = 256

  /// Maximum number of signals we track for save/restore of previous handlers.
  private let crashMaxSignals = 16

  /// The fd to write the reset sequence to.
  nonisolated(unsafe) private var crashResetFD: Int32 = -1

  /// Pre-encoded reset escape sequence bytes.
  nonisolated(unsafe) private var crashResetBuffer =
    UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 256)

  /// Number of valid bytes in crashResetBuffer.
  nonisolated(unsafe) private var crashResetByteCount: Int = 0

  /// Whether to attempt termios restoration.
  nonisolated(unsafe) private var crashRestoreTermios = false

  /// The termios to restore (only meaningful when crashRestoreTermios is true).
  nonisolated(unsafe) private var crashSavedTermios = termios()

  /// The fd to restore termios on (may differ from the output fd).
  nonisolated(unsafe) private var crashTermiosFD: Int32 = -1

  /// Whether the crash guard is currently installed.
  nonisolated(unsafe) private var crashGuardActive = false

  /// Signal numbers we installed handlers for, so we can restore them.
  nonisolated(unsafe) private var crashHandledSignals =
    UnsafeMutableBufferPointer<Int32>.allocate(capacity: 16)

  /// Previous sigaction values, parallel to crashHandledSignals.
  nonisolated(unsafe) private var crashPreviousActions =
    UnsafeMutableBufferPointer<sigaction>.allocate(capacity: 16)

  /// Number of signals currently handled.
  nonisolated(unsafe) private var crashHandledSignalCount: Int = 0

  /// Alternate signal stack buffer (allocated once, freed on uninstall).
  nonisolated(unsafe) private var crashAltStackBuffer: UnsafeMutableRawPointer? = nil
  private let crashAltStackSize = Int(SIGSTKSZ) * 2

  // ---------------------------------------------------------------------------
  // MARK: - The signal handler (async-signal-safe only)
  // ---------------------------------------------------------------------------

  /// The actual signal handler invoked by the kernel.
  ///
  /// Only async-signal-safe functions may be called here:
  /// write(2), tcsetattr(3) (practically safe), signal(2), raise(2).
  private func crashSignalHandler(_ sig: Int32) {
    // Write the terminal reset sequence.
    if unsafe crashResetByteCount > 0, unsafe crashResetFD >= 0 {
      _ = unsafe crashResetBuffer.withMemoryRebound(to: UInt8.self) { buffer in
        unsafe write(crashResetFD, buffer.baseAddress, crashResetByteCount)
      }
    }

    // Attempt to restore termios.
    if unsafe crashRestoreTermios, unsafe crashTermiosFD >= 0 {
      unsafe withUnsafePointer(to: &crashSavedTermios) { ptr in
        // tcsetattr is not officially async-signal-safe per POSIX, but it is
        // practically safe on Darwin and Linux. This is a crash path — the
        // small theoretical risk is acceptable.
        _ = unsafe tcsetattr(crashTermiosFD, TCSANOW, ptr)
      }
    }

    // Re-raise with the default handler so the process terminates normally
    // (producing a core dump if applicable).
    signal(sig, SIG_DFL)
    raise(sig)
  }

  // ---------------------------------------------------------------------------
  // MARK: - Public API
  // ---------------------------------------------------------------------------

  /// Installs synchronous signal handlers that reset terminal state on fatal
  /// signals.
  ///
  /// This is designed for crash recovery: when a process dies from SIGABRT
  /// (Swift fatalError, precondition failure), SIGSEGV (null pointer, stack
  /// overflow), SIGBUS, SIGILL, SIGFPE, or SIGTRAP, the handler writes a
  /// terminal reset sequence and optionally restores termios before the
  /// process terminates.
  ///
  /// The handler is process-global. Calling `install` again replaces the
  /// previous registration.
  ///
  /// - Important: The signal handler only uses async-signal-safe functions.
  ///   `tcsetattr` is not officially async-signal-safe but is practically safe
  ///   on Darwin and Linux.
  public enum CrashSignalHandler {

    /// Describes the terminal reset to perform when a crash signal fires.
    public struct ResetAction: Sendable {
      /// The file descriptor to write the reset escape sequence to.
      public var outputFileDescriptor: Int32

      /// The pre-encoded bytes of the terminal reset escape sequence.
      public var resetBytes: [UInt8]

      /// The file descriptor to restore termios on, if any.
      public var termiosFileDescriptor: Int32?

      /// The saved termios to restore, if any.
      public var savedTermios: termios?

      public init(
        outputFileDescriptor: Int32,
        resetBytes: [UInt8],
        termiosFileDescriptor: Int32? = nil,
        savedTermios: termios? = nil
      ) {
        self.outputFileDescriptor = outputFileDescriptor
        self.resetBytes = resetBytes
        self.termiosFileDescriptor = termiosFileDescriptor
        self.savedTermios = savedTermios
      }
    }

    /// Installs crash signal handlers for the given signals.
    ///
    /// - Parameters:
    ///   - signals: The signals to handle (e.g. `.sigabrt`, `.sigsegv`).
    ///   - reset: The terminal reset action to perform in the handler.
    public static func install(
      for signals: [UnixSignal],
      reset: ResetAction
    ) {
      // If already active, uninstall first to restore previous handlers.
      if unsafe crashGuardActive {
        uninstall()
      }

      unsafe installImpl(for: signals, reset: reset)
    }

    @unsafe
    private static func installImpl(
      for signals: [UnixSignal],
      reset: ResetAction
    ) {
      // Store reset state in globals.
      unsafe crashResetFD = reset.outputFileDescriptor
      let byteCount = min(reset.resetBytes.count, crashResetMaxBytes)
      for i in 0..<byteCount {
        (unsafe crashResetBuffer)[i] = reset.resetBytes[i]
      }
      unsafe crashResetByteCount = byteCount

      if let savedTermios = reset.savedTermios,
        let termiosFD = reset.termiosFileDescriptor
      {
        unsafe crashSavedTermios = savedTermios
        unsafe crashTermiosFD = termiosFD
        unsafe crashRestoreTermios = true
      } else {
        unsafe crashRestoreTermios = false
        unsafe crashTermiosFD = -1
      }

      // Set up alternate signal stack for SIGSEGV from stack overflow.
      unsafe installAlternateStack()

      // Install sigaction handlers.
      let uniqueSignals = Array(Set(signals.map(\.rawValue)))
      let signalCount = min(uniqueSignals.count, crashMaxSignals)
      unsafe crashHandledSignalCount = signalCount

      for i in 0..<signalCount {
        let sig = uniqueSignals[i]
        (unsafe crashHandledSignals)[i] = sig

        var action = sigaction()
        #if canImport(Darwin)
          unsafe action.__sigaction_u.__sa_handler = crashSignalHandler
        #elseif canImport(Glibc) || canImport(Musl) || canImport(Android)
          unsafe action.__sigaction_handler = .init(sa_handler: crashSignalHandler)
        #endif
        action.sa_flags = Int32(SA_RESETHAND | SA_ONSTACK)
        unsafe sigemptyset(&action.sa_mask)

        var previousAction = sigaction()
        unsafe sigaction(sig, &action, &previousAction)
        (unsafe crashPreviousActions)[i] = previousAction
      }

      unsafe crashGuardActive = true
    }

    /// Removes the crash signal handlers and restores the previous handlers.
    public static func uninstall() {
      guard unsafe crashGuardActive else {
        return
      }

      unsafe uninstallImpl()
    }

    @unsafe
    private static func uninstallImpl() {
      // Restore previous signal handlers.
      for i in 0..<(unsafe crashHandledSignalCount) {
        let sig = (unsafe crashHandledSignals)[i]
        var previousAction = (unsafe crashPreviousActions)[i]
        unsafe sigaction(sig, &previousAction, nil)
      }
      unsafe crashHandledSignalCount = 0

      // Tear down alternate stack.
      unsafe uninstallAlternateStack()

      // Clear global state.
      unsafe crashResetFD = -1
      unsafe crashResetByteCount = 0
      unsafe crashRestoreTermios = false
      unsafe crashTermiosFD = -1
      unsafe crashGuardActive = false
    }

    /// Whether the crash guard is currently installed.
    public static var isInstalled: Bool {
      unsafe crashGuardActive
    }

    // -------------------------------------------------------------------------
    // MARK: - Alternate signal stack
    // -------------------------------------------------------------------------

    @unsafe
    private static func installAlternateStack() {
      guard unsafe crashAltStackBuffer == nil else {
        return
      }

      let buffer = UnsafeMutableRawPointer.allocate(
        byteCount: crashAltStackSize,
        alignment: 16
      )
      unsafe crashAltStackBuffer = unsafe buffer

      var stack = unsafe stack_t()
      unsafe stack.ss_sp = unsafe buffer
      unsafe stack.ss_size = crashAltStackSize
      unsafe stack.ss_flags = 0
      unsafe sigaltstack(&stack, nil)
    }

    @unsafe
    private static func uninstallAlternateStack() {
      guard let buffer = unsafe crashAltStackBuffer else {
        return
      }

      var stack = unsafe stack_t()
      unsafe stack.ss_flags = Int32(SS_DISABLE)
      unsafe stack.ss_size = crashAltStackSize
      unsafe stack.ss_sp = unsafe buffer
      unsafe sigaltstack(&stack, nil)

      unsafe buffer.deallocate()
      unsafe crashAltStackBuffer = nil
    }
  }

  // ---------------------------------------------------------------------------
  // MARK: - Convenience: default fatal signals
  // ---------------------------------------------------------------------------

  extension CrashSignalHandler {
    /// The default set of fatal signals that should trigger terminal reset.
    public static let fatalSignals: [UnixSignal] = [
      .sigabrt,
      .sigsegv,
      .sigbus,
      .sigill,
      .sigfpe,
      .sigtrap,
    ]
  }

#endif
