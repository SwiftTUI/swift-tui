import Foundation
@_spi(Runners) import SwiftTUIRuntime

// Secondary (attachable) scenes render into a PTY, which only exists where
// the POSIX-only attach subsystem is linked (its dependency edge is
// platform-conditional).
#if os(macOS) || os(iOS) || os(Linux) || os(Android)
  import SwiftTUICLIAttach
#endif

// The sigaction-based vendor module carries CrashSignalHandler; its edge is
// platform-conditional (it can never build on Windows).
#if os(macOS) || os(iOS) || os(Linux) || os(Android)
  import SwiftTUIVendorUnixSignals
#endif

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(ucrt)
  import CRT
#endif

/// Manages the runtime for a single scene within a multi-scene app.
///
/// Each SceneRuntime owns its own TerminalHost, RunLoop, and state partitions.
/// The primary scene uses inherited stdio; secondary scenes use pty-backed hosts.
@MainActor
final class SceneRuntime {
  typealias SessionRunner =
    @MainActor (SceneRuntime, String) async throws -> RunLoopResult<SceneSessionState>

  let selection: SelectedWindowScene
  let isPrimary: Bool
  private(set) var lifecycle: SceneLifecycle
  #if os(macOS) || os(iOS) || os(Linux) || os(Android)
    private let ptyPair: ScenePty?
  #endif
  private let resources: SceneSessionResources
  private let stateContainer: StateContainer<SceneSessionState>
  private let focusTracker: FocusTracker
  private let sessionRunner: SessionRunner

  init(
    selection: SelectedWindowScene,
    isPrimary: Bool,
    configuration: RuntimeConfiguration = .default,
    resources: SceneSessionResources? = nil,
    sessionRunner: SessionRunner? = nil
  ) throws {
    self.selection = selection
    self.isPrimary = isPrimary
    self.lifecycle = SceneLifecycle(isPrimary: isPrimary)

    // Arm the session debug bundle before any sink resolves its destination,
    // so `--debug`'s default bundle directory catches every stream.
    DebugBundle.prepareIfNeeded(configuration: configuration)
    let frameSink: (any FrameDiagnosticSink)? =
      if isPrimary, let path = Self.diagnosticsFilePath(configuration: configuration) {
        FrameDiagnosticsFileSink(path: path)
      } else {
        nil
      }

    if let resources {
      #if os(macOS) || os(iOS) || os(Linux) || os(Android)
        ptyPair = nil
      #endif
      self.resources = resources
    } else if isPrimary {
      #if os(macOS) || os(iOS) || os(Linux) || os(Android)
        ptyPair = nil
      #endif
      let environment = ProcessInfo.processInfo.environment
      #if os(Windows)
        let isTTY = _isatty(STDOUT_FILENO) != 0
      #else
        let isTTY = isatty(STDOUT_FILENO) != 0
      #endif
      let capabilityProfile = TerminalCapabilityProfile.detect(
        environment: environment,
        isTTY: isTTY
      )
      .applying(configuration)
      let terminalHost = TerminalHost(capabilityProfile: capabilityProfile)
      let inputReader = InputReader()
      // The capability probes read the same input descriptor the reader's
      // dispatch source owns; the gate suspends the reader for each probe's
      // write→read cycle so the reply cannot be consumed by the reader (F42).
      terminalHost.inputSuspensionGate = inputReader
      #if canImport(ucrt)
        // Windows has no SIGWINCH: resize arrives as records in the console
        // input queue, which the reader's pump owns. Route it through the
        // injectable signal reader so the run loop's existing "SIGWINCH"
        // dispatch serves both platforms.
        let windowsSignalReader = InProcessSignalReader()
        inputReader.setWindowsResizeObserver { [windowsSignalReader] in
          windowsSignalReader.send("SIGWINCH")
        }
        let sessionSignalReader: (any SignalReading)? = windowsSignalReader
      #else
        let sessionSignalReader = defaultSignalReader()
      #endif
      let resources = SceneSessionResources(
        presentationSurface: terminalHost,
        terminalInputReader: inputReader,
        signalReader: sessionSignalReader,
        frameSink: frameSink,
        runtimeConfiguration: configuration
      )
      resources.runtimeIssueSink = .standardError
      // Windows plan Stage 6 item 9: a below-floor main-thread stack reserve
      // silently degrades the engine — debug builds must say so, loudly,
      // with the /STACK remedy. Nil everywhere else.
      if let stackFloorIssue = WindowsStackFloorDiagnostic.sessionIssue() {
        RuntimeIssueSink.standardError.report(stackFloorIssue)
      }
      self.resources = resources
    } else {
      #if os(macOS) || os(iOS) || os(Linux) || os(Android)
        let pty = try ScenePty()
        ptyPair = pty
        let environment = ProcessInfo.processInfo.environment
        let isTTY = isatty(pty.masterFD) != 0
        let capabilityProfile = TerminalCapabilityProfile.detect(
          environment: environment,
          isTTY: isTTY
        )
        .applying(configuration)
        let terminalHost = TerminalHost(
          inputFileDescriptor: pty.masterFD,
          outputFileDescriptor: pty.masterFD,
          capabilityProfile: capabilityProfile
        )
        let inputReader = InputReader(fileDescriptor: pty.masterFD)
        // Same shared-descriptor probe race as the primary path (F42).
        terminalHost.inputSuspensionGate = inputReader
        let resources = SceneSessionResources(
          presentationSurface: terminalHost,
          terminalInputReader: inputReader,
          runtimeConfiguration: configuration
        )
        resources.runtimeIssueSink = .standardError
        self.resources = resources
      #else
        // Secondary scenes are PTY-backed and only serve `--attach` clients;
        // without the attach subsystem there is nothing they could render to.
        throw SceneRuntimeError.secondaryScenesRequireAttachSubsystem
      #endif
    }

    stateContainer = StateContainer(
      initialState: SceneSessionState(),
      invalidationIdentities: [selection.rootIdentity]
    )
    focusTracker = FocusTracker(
      invalidationIdentities: [selection.rootIdentity]
    )
    self.sessionRunner =
      sessionRunner ?? { runtime, sessionName in
        try await runtime.runSceneSession(sessionName: sessionName)
      }
  }

  #if os(macOS) || os(iOS) || os(Linux) || os(Android)
    /// The slave path of the PTY an attach client would connect to, or `nil`
    /// for the primary scene (which owns the real tty).
    var attachPtyPath: String? {
      ptyPair?.slavePath
    }
  #endif

  func run(
    sessionName: String,
    onAttachmentChanged: @escaping @Sendable (Bool) -> Void = { _ in }
  ) async throws -> RunLoopResult<SceneSessionState> {
    if isPrimary {
      installCrashGuard()
      defer {
        #if os(macOS) || os(iOS) || os(Linux) || os(Android)
          CrashSignalHandler.uninstall()
        #endif
      }
      // Arm the OS signal sources before the session renders its first
      // frame: when registration instead rides the run loop's lazy startup
      // path it races the initial render, and a SIGTERM/SIGINT landing in
      // that window is discarded by the kernel.
      if let armableSignalReader = resources.signalReader as? any SignalSourceArming {
        await armableSignalReader.armSignalSources()
      }
      return try await sessionRunner(self, sessionName)
    }

    while !Task.isCancelled {
      guard await waitForClient(onAttachmentChanged: onAttachmentChanged) else {
        break
      }

      let result = try await sessionRunner(self, sessionName)
      if Task.isCancelled {
        return result
      }

      if result.exitReason == .inputEnded {
        if lifecycle.clientDetached() {
          onAttachmentChanged(false)
        }
        continue
      }

      return result
    }

    return RunLoopResult(
      finalState: stateContainer.state,
      renderedFrames: 0,
      exitReason: .inputEnded
    )
  }

  func shutdown() {
    #if os(macOS) || os(iOS) || os(Linux) || os(Android)
      guard let ptyPair else { return }
      Task {
        await ptyPair.close()
      }
    #endif
  }

  // ---------------------------------------------------------------------------
  // MARK: - Crash guard
  // ---------------------------------------------------------------------------

  /// Installs the crash signal handler so that fatal signals (SIGABRT, SIGSEGV,
  /// etc.) reset the terminal before the process dies.
  ///
  /// Only meaningful for the primary scene, which owns the real tty via stdio.
  private func installCrashGuard() {
    #if os(macOS) || os(iOS) || os(Linux) || os(Android)
      installPOSIXCrashGuard()
    #else
      // No POSIX fatal-signal delivery without the sigaction-based vendor
      // module (Windows); console-mode restoration on the normal exit paths
      // is Stage 4 of the Windows plan.
    #endif
  }

  #if os(macOS) || os(iOS) || os(Linux) || os(Android)
    private func installPOSIXCrashGuard() {
      // Read the current terminal attributes before the session enters raw mode.
      // These are the attributes we want to restore on crash.
      var savedTermios = termios()
      let hasTermios = unsafe tcgetattr(STDIN_FILENO, &savedTermios) == 0

      // Build the reset sequence: disable mouse reporting, show cursor,
      // reset style, exit alternate screen.
      let resetSequence =
        "\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1016l\u{1B}[?1006l"  // disable mouse reporting
        + "\u{1B}[?25h"  // show cursor
        + "\u{1B}[0m"  // reset style
        + "\u{1B}[?1049l"  // exit alternate screen
      let resetBytes = Array(resetSequence.utf8)

      let resetAction = CrashSignalHandler.ResetAction(
        outputFileDescriptor: STDOUT_FILENO,
        resetBytes: resetBytes,
        termiosFileDescriptor: hasTermios ? STDIN_FILENO : nil,
        savedTermios: hasTermios ? savedTermios : nil
      )
      CrashSignalHandler.install(
        for: CrashSignalHandler.fatalSignals,
        reset: resetAction
      )
    }
  #endif

  private func runSceneSession(
    sessionName: String
  ) async throws -> RunLoopResult<SceneSessionState> {
    try await selection.run(
      sessionName: sessionName,
      resources: resources,
      stateContainer: stateContainer,
      focusTracker: focusTracker
    )
  }

  /// Returns a diagnostics output file path when debug instrumentation or the
  /// `SWIFTTUI_DIAGNOSTICS` environment variable is enabled.
  ///
  /// A value of `1` or `true` writes the debug bundle's `diagnostics.tsv`
  /// when a bundle directory is active (`SWIFTTUI_DEBUG_DIR`, or the default
  /// bundle `--debug` installs), else `/tmp/termui-diagnostics.tsv`; any
  /// other truthy value is treated as a custom file path. `--debug` /
  /// `SWIFTTUI_DEBUG=1` follows the same bundle-then-default resolution when
  /// no custom diagnostics path is present.
  @MainActor
  static func diagnosticsFilePath(
    configuration: RuntimeConfiguration,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String? {
    if let string = environment["SWIFTTUI_DIAGNOSTICS"],
      let path = diagnosticsFilePath(from: string)
    {
      return path
    }
    return configuration.debug ? bundleOrDefaultDiagnosticsFilePath() : nil
  }

  private static let defaultDiagnosticsFilePath = "/tmp/termui-diagnostics.tsv"

  @MainActor
  private static func bundleOrDefaultDiagnosticsFilePath() -> String {
    DebugBundle.bundleFilePath(named: "diagnostics.tsv") ?? defaultDiagnosticsFilePath
  }

  @MainActor
  private static func diagnosticsFilePath(from string: String) -> String? {
    switch string.lowercased() {
    case "", "0", "false", "no":
      return nil
    case "1", "true", "yes":
      return bundleOrDefaultDiagnosticsFilePath()
    default:
      return string
    }
  }

  private func waitForClient(
    onAttachmentChanged: @escaping @Sendable (Bool) -> Void
  ) async -> Bool {
    #if os(macOS) || os(iOS) || os(Linux) || os(Android)
      guard let pty = ptyPair else { return true }

      while !Task.isCancelled {
        if await pty.hasAttachedClient() {
          if lifecycle.clientAttached() {
            onAttachmentChanged(true)
          }
          return true
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
      }

      return false
    #else
      // Secondary scenes cannot construct without the attach subsystem, so
      // this path is unreachable; primaries never wait.
      return true
    #endif
  }
}

enum SceneRuntimeError: Error, Equatable, Sendable, CustomStringConvertible {
  case secondaryScenesRequireAttachSubsystem

  var description: String {
    switch self {
    case .secondaryScenesRequireAttachSubsystem:
      return "Secondary scenes are PTY-backed and require the POSIX-only attach subsystem; "
        + "this platform supports single-scene apps only."
    }
  }
}
