// © GoodHatsLLC

#if !os(Windows) && !os(WASI)

  import Testing
  import SwiftTUIVendorUnixSignals

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Musl)
    import Musl
  #elseif canImport(Android)
    import Android
  #endif

  @Suite(.serialized)
  struct CrashSignalHandlerTests {

    // MARK: - New signal cases

    @Test func newSignalRawValues() {
      #expect(UnixSignal.sigbus.rawValue == SIGBUS)
      #expect(UnixSignal.sigfpe.rawValue == SIGFPE)
      #expect(UnixSignal.sigtrap.rawValue == SIGTRAP)
    }

    @Test func newSignalDescriptions() {
      #expect(String(describing: UnixSignal.sigbus) == "SIGBUS")
      #expect(String(describing: UnixSignal.sigfpe) == "SIGFPE")
      #expect(String(describing: UnixSignal.sigtrap) == "SIGTRAP")
    }

    // MARK: - Install / uninstall lifecycle

    @Test func installSetsIsInstalled() {
      let action = CrashSignalHandler.ResetAction(
        outputFileDescriptor: STDOUT_FILENO,
        resetBytes: Array("\u{1B}[?1049l".utf8)
      )
      CrashSignalHandler.install(for: [.sigabrt], reset: action)
      #expect(CrashSignalHandler.isInstalled)

      CrashSignalHandler.uninstall()
      #expect(!CrashSignalHandler.isInstalled)
    }

    @Test func uninstallWhenNotInstalledIsNoOp() {
      #expect(!CrashSignalHandler.isInstalled)
      CrashSignalHandler.uninstall()
      #expect(!CrashSignalHandler.isInstalled)
    }

    @Test func doubleInstallReplacesCleanly() {
      let action1 = CrashSignalHandler.ResetAction(
        outputFileDescriptor: STDOUT_FILENO,
        resetBytes: Array("\u{1B}[?1049l".utf8)
      )
      CrashSignalHandler.install(for: [.sigabrt], reset: action1)
      #expect(CrashSignalHandler.isInstalled)

      let action2 = CrashSignalHandler.ResetAction(
        outputFileDescriptor: STDERR_FILENO,
        resetBytes: Array("\u{1B}[0m".utf8)
      )
      CrashSignalHandler.install(for: [.sigsegv], reset: action2)
      #expect(CrashSignalHandler.isInstalled)

      CrashSignalHandler.uninstall()
      #expect(!CrashSignalHandler.isInstalled)
    }

    @Test func installWithAllFatalSignals() {
      let action = CrashSignalHandler.ResetAction(
        outputFileDescriptor: STDOUT_FILENO,
        resetBytes: Array(
          "\u{1B}[?1002l\u{1B}[?1006l\u{1B}[?25h\u{1B}[0m\u{1B}[?1049l".utf8
        )
      )
      CrashSignalHandler.install(
        for: CrashSignalHandler.fatalSignals,
        reset: action
      )
      #expect(CrashSignalHandler.isInstalled)

      CrashSignalHandler.uninstall()
      #expect(!CrashSignalHandler.isInstalled)
    }

    @Test func installWithTermiosRestore() {
      let attributes = termios()
      CrashSignalHandler.install(
        for: [.sigabrt],
        reset: CrashSignalHandler.ResetAction(
          outputFileDescriptor: STDOUT_FILENO,
          resetBytes: Array("\u{1B}[?1049l".utf8),
          termiosFileDescriptor: STDIN_FILENO,
          savedTermios: attributes
        )
      )
      #expect(CrashSignalHandler.isInstalled)

      CrashSignalHandler.uninstall()
      #expect(!CrashSignalHandler.isInstalled)
    }

    @Test func fatalSignalsContainsExpectedSignals() {
      let rawValues = Set(CrashSignalHandler.fatalSignals.map(\.rawValue))
      #expect(rawValues.contains(SIGABRT))
      #expect(rawValues.contains(SIGSEGV))
      #expect(rawValues.contains(SIGBUS))
      #expect(rawValues.contains(SIGILL))
      #expect(rawValues.contains(SIGFPE))
      #expect(rawValues.contains(SIGTRAP))
    }

    @Test func previousHandlersRestoredOnUninstall() {
      var customAction = sigaction()
      #if canImport(Darwin)
        unsafe customAction.__sigaction_u.__sa_handler = { _ in }
      #elseif canImport(Glibc) || canImport(Musl) || canImport(Android)
        customAction.__sigaction_handler = .init(sa_handler: { _ in })
      #endif
      unsafe sigemptyset(&customAction.sa_mask)
      customAction.sa_flags = 0

      var savedAction = sigaction()
      unsafe sigaction(SIGUSR1, &customAction, &savedAction)

      CrashSignalHandler.install(
        for: [.sigusr1],
        reset: CrashSignalHandler.ResetAction(
          outputFileDescriptor: STDOUT_FILENO,
          resetBytes: []
        )
      )

      CrashSignalHandler.uninstall()

      var restoredAction = sigaction()
      unsafe sigaction(SIGUSR1, nil, &restoredAction)

      #if canImport(Darwin)
        let restoredHandler = unsafe unsafeBitCast(
          restoredAction.__sigaction_u.__sa_handler, to: Int.self
        )
        let customHandler = unsafe unsafeBitCast(
          customAction.__sigaction_u.__sa_handler, to: Int.self
        )
        #expect(restoredHandler == customHandler)
      #endif

      unsafe sigaction(SIGUSR1, &savedAction, nil)
    }
  }

#endif
