#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(ucrt)
  import CRT
#endif

// Positive host test, not "not WASI": the terminal-control family compiles
// exactly where a real terminal host exists (Stage 3.5 of the Windows plan).
#if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(ucrt)
  /// An opaque snapshot of the terminal's pre-raw-mode state, captured by
  /// ``TerminalControlling/enterRawMode(input:output:)`` and consumed only by
  /// ``TerminalControlling/restore(_:input:output:)``.
  ///
  /// Nothing outside a platform controller inspects its fields — what "raw
  /// mode" means (and therefore what must be saved to undo it) is owned by
  /// each platform: termios attributes plus file-status flags on POSIX,
  /// console modes plus code pages on Windows.
  package struct TerminalModeSnapshot: Sendable {
    #if canImport(ucrt)
      var consoleInputMode: UInt32
      var consoleOutputMode: UInt32
      var inputCodePage: UInt32
      var outputCodePage: UInt32

      init(
        consoleInputMode: UInt32,
        consoleOutputMode: UInt32,
        inputCodePage: UInt32,
        outputCodePage: UInt32
      ) {
        self.consoleInputMode = consoleInputMode
        self.consoleOutputMode = consoleOutputMode
        self.inputCodePage = inputCodePage
        self.outputCodePage = outputCodePage
      }

      /// A neutral snapshot for test controllers; restoring it is a no-op
      /// shape, never a real console state.
      package init() {
        self.init(consoleInputMode: 0, consoleOutputMode: 0, inputCodePage: 0, outputCodePage: 0)
      }
    #else
      var attributes: termios
      var inputFileStatusFlags: Int32

      init(attributes: termios, inputFileStatusFlags: Int32) {
        self.attributes = attributes
        self.inputFileStatusFlags = inputFileStatusFlags
      }

      /// A neutral snapshot for test controllers; restoring it is a no-op
      /// shape, never a real terminal state.
      package init() {
        self.init(attributes: termios(), inputFileStatusFlags: 0)
      }
    #endif
  }
#endif
